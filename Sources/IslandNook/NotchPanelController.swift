import SwiftUI
import AppKit
import QuartzCore

@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private let model: AppModel
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var hoverTimer: Timer?
    private var hoverExitStartedAt: Date?
    private var activationEntryArmed = true

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.contentView = EdgeToEdgeHostingView(
            rootView: NotchRootView()
                .environment(model)
                .ignoresSafeArea(.all)
        )
        configurePanelBackingLayer(expanded: false)
        model.expansionChanged = { [weak self] expanded in
            self?.updatePanelFrame(expanded: expanded, animated: true)
        }
        model.compactPresentationChanged = { [weak self] in
            guard let self, !self.model.isExpanded else { return }
            self.updatePanelFrame(expanded: false, animated: true)
        }
        model.modalPresentationChanged = { [weak self] presenting in
            guard let self else { return }
            if presenting {
                self.panel.orderOut(nil)
            } else {
                self.positionPanel()
                self.panel.orderFrontRegardless()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.positionPanel() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.isExpanded else { return }
                self.updatePanelFrame(expanded: false, animated: false)
            }
        }
        startHoverMonitoring()
    }

    func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    func expandTemporarily() {
        model.isExpanded = true
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        updatePanelFrame(expanded: model.isExpanded, animated: false)
    }

    private func updatePanelFrame(expanded: Bool, animated: Bool) {
        guard let screen = targetScreen else { return }
        configurePanelBackingLayer(expanded: expanded)
        let frame = screen.frame
        let compactSize = compactPresentationSize(on: screen)
        model.compactHeight = compactSize.height
        let size: NSSize
        if expanded {
            size = NSSize(width: 590, height: 390)
        } else {
            model.compactWidth = compactSize.width
            size = compactSize
        }
        let newFrame = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = expanded ? 0.18 : 0.12
                context.timingFunction = CAMediaTimingFunction(name: expanded ? .easeOut : .easeInEaseOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    private func configurePanelBackingLayer(expanded: Bool) {
        guard let contentView = panel.contentView else { return }
        contentView.wantsLayer = true
        contentView.canDrawSubviewsIntoLayer = true
        guard let layer = contentView.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = NSColor.black.cgColor
        layer.isOpaque = true
        layer.masksToBounds = true
        // NSView's layer is flipped relative to the screen coordinate system here:
        // maxY maps to the visible bottom edge of the top-anchored panel.
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.cornerRadius = expanded ? 28 : 13
        CATransaction.commit()
    }

    private func startHoverMonitoring() {
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHoverState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func updateHoverState() {
        guard panel.isVisible,
              (UserDefaults.standard.object(forKey: "expandOnHover") as? Bool ?? true),
              let screen = targetScreen else {
            hoverExitStartedAt = nil
            activationEntryArmed = true
            return
        }

        let pointer = NSEvent.mouseLocation
        let expandedFrame = targetFrame(size: NSSize(width: 590, height: 390), on: screen)
        let isInsideActivationArea = activationFrame(on: screen)?.contains(pointer) == true

        if !isInsideActivationArea {
            activationEntryArmed = true
        }

        if model.isExpanded {
            if isInsideActivationArea { activationEntryArmed = false }
            if expandedFrame.contains(pointer) || model.isFileDropTargeted {
                hoverExitStartedAt = nil
                return
            }

            let now = Date()
            guard let exitStartedAt = hoverExitStartedAt else {
                hoverExitStartedAt = now
                return
            }
            guard now.timeIntervalSince(exitStartedAt) >= 0.08 else { return }

            hoverExitStartedAt = nil
            model.collapseTask?.cancel()
            withAnimation(.spring(response: 0.16, dampingFraction: 0.9, blendDuration: 0.02)) {
                model.isExpanded = false
            }
        } else {
            hoverExitStartedAt = nil
            guard isInsideActivationArea, activationEntryArmed else { return }

            activationEntryArmed = false
            model.collapseTask?.cancel()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.84, blendDuration: 0.03)) {
                model.isExpanded = true
            }
        }
    }

    private func compactPresentationSize(on screen: NSScreen) -> NSSize {
        let systemNotchWidth = measuredNotchWidth(on: screen) ?? 0
        let restingWidth = max(systemNotchWidth, 210)
        // Overlay windows do not make macOS reflow menu-bar extras like a physical
        // notch does. Keep music mode within roughly one status-item slot on each
        // side of the real notch so adjacent icons remain wholly visible.
        let preferredMediaWidth: CGFloat = 300
        let menuBarSafeWidth = systemNotchWidth > 0 ? systemNotchWidth + 96 : 320
        let mediaWidth = max(restingWidth, min(preferredMediaWidth, menuBarSafeWidth))
        let width = model.media.isPlaying ? max(restingWidth, mediaWidth) : restingWidth
        return NSSize(width: width, height: measuredCompactHeight(on: screen))
    }

    private func activationFrame(on screen: NSScreen) -> NSRect? {
        if model.media.isPlaying {
            return targetFrame(size: compactPresentationSize(on: screen), on: screen)
        }
        return physicalNotchFrame(on: screen)
    }

    private func physicalNotchFrame(on screen: NSScreen) -> NSRect? {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              !leftArea.isEmpty,
              !rightArea.isEmpty else { return nil }

        let triggerWidth = rightArea.minX - leftArea.maxX
        guard triggerWidth > 80 else { return nil }
        let height = measuredCompactHeight(on: screen)

        return NSRect(
            x: screen.frame.midX - triggerWidth / 2,
            y: screen.frame.maxY - height,
            width: triggerWidth,
            height: height
        )
    }

    private func targetFrame(size: NSSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private var targetScreen: NSScreen? {
        if let current = panel.screen { return current }
        return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
    }

    private func measuredCompactHeight(on screen: NSScreen) -> CGFloat {
        let safeAreaHeight = screen.safeAreaInsets.top
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        return min(max(max(safeAreaHeight, menuBarHeight), 30), 44)
    }

    private func measuredNotchWidth(on screen: NSScreen) -> CGFloat? {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return nil }
        guard !leftArea.isEmpty, !rightArea.isEmpty else { return nil }
        let width = rightArea.minX - leftArea.maxX
        return width > 80 ? width : nil
    }
}

private final class EdgeToEdgeHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}
