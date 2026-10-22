import AppKit
import SwiftUI

/// Port Killer is an LSUIElement (menu bar) app. While a user-facing window (main or Settings)
/// is open it becomes a regular app (Dock icon, ⌘-Tab, menu bar with commands); when the last
/// one closes it goes back to accessory.
///
/// Windows are tracked by identity: the `WindowAccessor` of the main and Settings views registers
/// the NSWindow, `NSWindow.willCloseNotification` removes it. The activation policy is derived from
/// "is the set empty", so counts can never drift out of balance.
@MainActor
enum AppActivation {
    private static var windows = Set<ObjectIdentifier>()
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private static weak var mainWindow: NSWindow?
    /// One-shot: set by `openMainWindow`, consumed by the first main window that registers.
    /// Anything else on macOS 14 is the window SwiftUI opens at launch, which gets closed.
    private static var mainWindowRequested = false

    static var trackedWindowCount: Int { windows.count }

    static func isTracked(_ window: NSWindow) -> Bool {
        windows.contains(ObjectIdentifier(window))
    }

    /// Registers a user-facing window (Settings). Idempotent.
    static func register(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard windows.insert(id).inserted else { return }
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppActivation.unregister(id) }
        }
        updatePolicy()
    }

    /// Registers the main window. On macOS 14 (no `.defaultLaunchBehavior(.suppressed)`) a window
    /// nobody asked for is closed instead and never counted.
    static func registerMainWindow(_ window: NSWindow) {
        if isTracked(window) { return }
        if #unavailable(macOS 15) {
            guard mainWindowRequested else {
                window.close()
                return
            }
        }
        mainWindowRequested = false
        mainWindow = window
        register(window)
    }

    private static func unregister(_ id: ObjectIdentifier) {
        windows.remove(id)
        if let token = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(token)
        }
        updatePolicy()
    }

    static func openMainWindow(_ openWindow: OpenWindowAction) {
        becomeRegular()
        if let window = mainWindow, isTracked(window) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        mainWindowRequested = true
        openWindow(id: "main")
        settlePolicyLater()
    }

    static func openSettings(_ openSettings: OpenSettingsAction) {
        becomeRegular()
        openSettings()
        settlePolicyLater()
    }

    private static func becomeRegular() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func updatePolicy() {
        let desired: NSApplication.ActivationPolicy = windows.isEmpty ? .accessory : .regular
        if NSApp.activationPolicy() != desired { NSApp.setActivationPolicy(desired) }
        if desired == .regular { NSApp.activate(ignoringOtherApps: true) }
    }

    /// If the requested window never showed up, fall back to accessory.
    private static func settlePolicyLater() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            updatePolicy()
        }
    }
}

// MARK: - Window access

/// Gives a view access to its hosting NSWindow. Reports once the view is attached to a window
/// (`viewDidMoveToWindow`, so there is no polling and no race with SwiftUI's hosting) and again
/// whenever that window becomes key, so a reused window is re-registered.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowReportingView)?.onWindow = onWindow
    }
}

final class WindowReportingView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var keyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        report()
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
    }

    /// Deferred one turn: closing or registering a window in the middle of a SwiftUI update is fragile.
    private func report() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.onWindow?(window)
        }
    }

    deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    }
}

/// Reports whether the hosting window is really on screen, from NSWindow state rather than
/// SwiftUI `onAppear`, which MenuBarExtra(.window) content does not deliver per open.
/// `requireKey: true` (popover) also treats losing key status or app deactivation as hidden,
/// because the popover is dismissed right after it resigns key.
struct WindowVisibilityReader: NSViewRepresentable {
    let requireKey: Bool
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.requireKey = requireKey
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {
        nsView.requireKey = requireKey
        nsView.onChange = onChange
    }

    static func dismantleNSView(_ nsView: VisibilityView, coordinator: ()) {
        nsView.detach()
    }
}

final class VisibilityView: NSView {
    var requireKey = false
    var onChange: ((Bool) -> Void)?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var last: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window else {
            report(false)
            return
        }
        let requireKey = requireKey
        let windowEvents: [(Notification.Name, Bool?)] = [
            (NSWindow.didBecomeKeyNotification, nil),
            (NSWindow.didResignKeyNotification, requireKey ? false : nil),
            (NSWindow.willCloseNotification, false),
            (NSWindow.didChangeOcclusionStateNotification, nil),
            (NSWindow.didMiniaturizeNotification, nil),
            (NSWindow.didDeminiaturizeNotification, nil)
        ]
        for (name, forced) in windowEvents {
            observe(NotificationCenter.default, name, object: window, forced: forced)
        }
        observe(NotificationCenter.default, NSApplication.didResignActiveNotification, object: nil, forced: requireKey ? false : nil)
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification, object: nil, forced: nil)
        // Initial state, after the window has had a chance to order front.
        DispatchQueue.main.async { [weak self] in self?.evaluate(forced: nil) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject?, forced: Bool?) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate(forced: forced) }
        }
        tokens.append((center, token))
    }

    private func evaluate(forced: Bool?) {
        if let forced {
            report(forced)
        } else if let window {
            report(window.isVisible && window.occlusionState.contains(.visible) && !window.isMiniaturized)
        } else {
            report(false)
        }
    }

    private func report(_ visible: Bool) {
        guard visible != last else { return }
        last = visible
        onChange?(visible)
    }

    private func removeObservers() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
    }

    func detach() {
        removeObservers()
        report(false)
    }

    deinit { removeObservers() }
}

/// Reports whether a text field editor (e.g. the toolbar search field) is the window's first
/// responder. macOS 14 has no `searchFocused`, so this observes the window directly.
struct FieldEditingObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> FieldEditingView {
        let view = FieldEditingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: FieldEditingView, context: Context) {
        nsView.onChange = onChange
    }
}

final class FieldEditingView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard let window else { return }
        observation = window.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
            let editing = (window.firstResponder as? NSText)?.isFieldEditor ?? false
            DispatchQueue.main.async { self?.onChange?(editing) }
        }
    }
}
