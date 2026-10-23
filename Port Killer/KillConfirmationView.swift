import AppKit
import SwiftUI

/// Inline confirmation panel + result banner. The panel is an overlay (not a sheet/alert) so it
/// also works inside the MenuBarExtra .window popover; it is exposed to assistive technology as a
/// modal (base content hidden and disabled while it is up).
private struct KillOverlayModifier: ViewModifier {
    @EnvironmentObject private var viewModel: PortViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let origin: KillOrigin

    func body(content: Content) -> some View {
        let isPending = viewModel.isPending(for: origin)
        content
            .disabled(isPending)
            .accessibilityHidden(isPending)
            // In the layout (not an overlay on top of it), so the banner can never cover footer buttons.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let banner = viewModel.resultBanner, viewModel.bannerOrigin == origin {
                    ResultBanner(message: banner)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                if let request = viewModel.pendingKill, request.origin == origin {
                    KillConfirmationPanel(
                        request: request,
                        title: "Kill process?",
                        confirmTitle: "Kill",
                        footnote: "Sends SIGTERM first and waits up to about 3 seconds.",
                        onCancel: { viewModel.cancelPendingKill() },
                        onConfirm: { viewModel.confirmKill() },
                        onFocusChange: { viewModel.setPendingExpiryPaused($0) }
                    )
                } else if let request = viewModel.pendingForceKill, request.origin == origin {
                    KillConfirmationPanel(
                        request: request,
                        title: "Force kill (SIGKILL)?",
                        confirmTitle: "Force Kill",
                        footnote: "These processes are still running after 3 seconds. SIGKILL stops them immediately without letting them save data.",
                        isForce: true,
                        onCancel: { viewModel.cancelForceKill() },
                        onConfirm: { viewModel.confirmForceKill() },
                        onFocusChange: { viewModel.setPendingExpiryPaused($0) }
                    )
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: viewModel.resultBanner)
            .onDisappear { viewModel.cancelPending(origin: origin) }
    }
}

extension View {
    func killConfirmation(origin: KillOrigin) -> some View {
        modifier(KillOverlayModifier(origin: origin))
    }
}

/// Result message. The countdown pauses while the pointer is over it or the dismiss button has focus.
private struct ResultBanner: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let message: String
    @FocusState private var dismissFocused: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
                .font(.body)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(12)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { viewModel.dismissBanner() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
            .focused($dismissFocused)
            .accessibilityLabel("Dismiss message")
            .help("Dismiss message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .onHover { hovering = $0; syncPause() }
        .onChange(of: dismissFocused) { syncPause() }
        .onChange(of: message) { syncPause() }
        .onDisappear { viewModel.setBannerPaused(false) }
    }

    private func syncPause() {
        viewModel.setBannerPaused(hovering || dismissFocused)
    }
}

struct KillConfirmationPanel: View {
    let request: KillRequest
    let title: String
    let confirmTitle: String
    let footnote: String
    var isForce: Bool = false
    let onCancel: () -> Void
    let onConfirm: () -> Void
    /// True while any control of the panel has focus (pauses the 30 s expiry).
    var onFocusChange: (Bool) -> Void = { _ in }

    private enum Field { case cancel, confirm }

    @FocusState private var focus: Field?
    @State private var confirmEnabled = false
    @State private var contentHeight: CGFloat = 120
    @State private var previousResponder: NSResponder?

    private var uniqueWarnings: [KillWarning] {
        var seen = Set<KillWarning>()
        return request.entries.flatMap(\.warnings).filter { seen.insert($0).inserted }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(request.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().padding(.leading, 50) }
                HStack(alignment: .top, spacing: 10) {
                    ProcessIconView(
                        processName: entry.displayName,
                        path: entry.identity.path ?? entry.path,
                        size: 30
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.displayName)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let path = entry.path {
                            Text(path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        HStack(spacing: 6) {
                            PortBadge(port: KillSafety.sanitizeForDisplay(entry.item.port, limit: 8))
                                .font(.caption)
                            Text("PID \(KillSafety.sanitizeForDisplay(entry.item.pid, limit: 12))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.displayName), Port \(KillSafety.sanitizeForDisplay(entry.item.port, limit: 8)), PID \(KillSafety.sanitizeForDisplay(entry.item.pid, limit: 12))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.separator))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isForce ? "bolt.trianglebadge.exclamationmark.fill" : "xmark.octagon.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background((isForce ? Color.red : Color.orange).gradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(request.entries.count == 1 ? "1 process" : "\(request.entries.count) processes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var announcement: String {
        let names = request.entries.map(\.displayName).joined(separator: ", ")
        let warnings = uniqueWarnings.map { "Warning: \($0.message)" }.joined(separator: ". ")
        return [title, names, warnings, "Cancel button is selected"].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 12) {
                    // Title, warnings, list and footnote scroll together when taller than the
                    // space the surface offers; the buttons stay pinned below.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header

                            if !uniqueWarnings.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(uniqueWarnings, id: \.self) { warning in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                                .accessibilityHidden(true)
                                            Text(warning.message)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("Warning: \(warning.message)")
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.orange.opacity(0.35)))
                            }

                            entryList

                            Label(footnote, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: PanelContentHeightKey.self, value: proxy.size.height)
                        })
                    }
                    .frame(height: min(contentHeight, max(120, geo.size.height - 36 - 32 - 52)))
                    .onPreferenceChange(PanelContentHeightKey.self) { contentHeight = $0 }

                    HStack {
                        Spacer()
                        // Cancel is the default action (Return) and takes initial focus.
                        Button("Cancel", action: onCancel)
                            .keyboardShortcut(.defaultAction)
                            .focused($focus, equals: .cancel)
                        Button(role: .destructive, action: onConfirm) {
                            Label(confirmTitle, systemImage: isForce ? "bolt.fill" : "xmark.circle")
                        }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .focused($focus, equals: .confirm)
                            .disabled(!confirmEnabled)
                            .accessibilityHint(confirmEnabled ? "" : "Available in about 1 second, to prevent accidental clicks")
                    }
                }
                .padding(18)
                .frame(maxWidth: 380)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityLabel(title)
                .onExitCommand(perform: onCancel)
            }
        }
        .onAppear {
            previousResponder = Self.currentResponder()
            focus = .cancel
            PortViewModel.announce(announcement)
        }
        .onDisappear { Self.restore(previousResponder) }
        .onChange(of: focus) { onFocusChange(focus != nil) }
        .task(id: request.id) {
            confirmEnabled = !isForce
            guard isForce else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            confirmEnabled = true
            PortViewModel.announce("\(confirmTitle) button is now available")
        }
    }

    // Focus restore on dismiss: remember what had focus (a text field's field editor maps back to
    // the field) and hand it back when the panel goes away.
    private static func currentResponder() -> NSResponder? {
        guard let responder = NSApp.keyWindow?.firstResponder, !(responder is NSWindow) else { return nil }
        if let text = responder as? NSText, text.isFieldEditor { return text.delegate as? NSResponder }
        return responder
    }

    private static func restore(_ responder: NSResponder?) {
        guard let view = responder as? NSView, let window = view.window else { return }
        window.makeFirstResponder(view)
    }
}

private struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
