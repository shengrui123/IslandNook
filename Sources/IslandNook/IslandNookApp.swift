import SwiftUI
import AppKit

@main
struct IslandNookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.model)
                .frame(width: 620, height: 560)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var settingsController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = NotchPanelController(model: model)
        panelController?.show()
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopServices()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menuIcon = NSApp.applicationIconImage.copy() as? NSImage
        menuIcon?.size = NSSize(width: 18, height: 18)
        menuIcon?.isTemplate = false
        item.button?.image = menuIcon
        let menu = NSMenu()
        menu.addItem(withTitle: "显示灵动岛", action: #selector(showNook), keyEquivalent: "n")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 IslandNook", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showNook() { panelController?.expandTemporarily() }

    @objc private func openSettings() {
        if settingsController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "IslandNook 设置"
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("IslandNookSettings")
            window.contentView = NSHostingView(rootView: SettingsView().environment(model))
            settingsController = NSWindowController(window: window)
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
