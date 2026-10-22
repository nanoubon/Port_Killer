import AppKit
import SwiftUI

/// Port Killer is an LSUIElement (menu bar) app. While a user-facing window (main or Settings)
/// is open it becomes a regular app (Dock icon, ⌘-Tab, menu bar with commands); when the last
/// one closes it goes back to accessory.
@MainActor
enum AppActivation {
    private static var openWindowCount = 0
    /// Set only when the user asked for the main window. Guards the macOS 14 fallback that closes
    /// the window SwiftUI opens at launch.
    private(set) static var mainWindowRequested = false

    static func windowDidAppear() {
        openWindowCount += 1
        setRegular()
    }

    static func windowDidDisappear() {
        openWindowCount = max(0, openWindowCount - 1)
        if openWindowCount == 0 { NSApp.setActivationPolicy(.accessory) }
    }

    static func openMainWindow(_ openWindow: OpenWindowAction) {
        mainWindowRequested = true
        setRegular()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    static func openSettings(_ openSettings: OpenSettingsAction) {
        setRegular()
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func setRegular() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Gives a view access to its hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
