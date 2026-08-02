import SwiftUI
import AppKit
import QuartzCore

@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private let model: AppModel
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

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
        model.isPointerInsidePanel = { [weak self] in
            guard let self, self.panel.isVisible else { return false }
            return self.panel.frame.contains(NSEvent.mouseLocation)
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.positionPanel() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.isExpanded else { return }
                self.updatePanelFrame(expanded: false, animated: true)
            }
        }
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
        let frame = screen.frame
        let compactHeight = measuredCompactHeight(on: screen)
        model.compactHeight = compactHeight
        let size: NSSize
        if expanded {
            size = NSSize(width: 590, height: 390)
        } else {
            let storedWidth = UserDefaults.standard.object(forKey: "nookWidth") as? Double ?? 210
            let configuredWidth = min(max(storedWidth, 170), 280)
            let systemNotchWidth = measuredNotchWidth(on: screen) ?? configuredWidth
            let restingWidth = min(max(systemNotchWidth, 170), 300)
            let mediaWidth = model.media.isPlaying ? max(restingWidth, 360) : restingWidth
            model.compactWidth = mediaWidth
            size = NSSize(width: mediaWidth, height: compactHeight)
        }
        let newFrame = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = expanded ? 0.27 : 0.17
                context.timingFunction = CAMediaTimingFunction(name: expanded ? .easeOut : .easeInEaseOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
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
