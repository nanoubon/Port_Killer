import SwiftUI

/// Inline confirmation panel + result banner. Implemented as an overlay (not a sheet/alert)
/// so it also works inside the MenuBarExtra .window popover.
private struct KillOverlayModifier: ViewModifier {
    @EnvironmentObject private var viewModel: PortViewModel
    let origin: KillOrigin

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let banner = viewModel.resultBanner {
                    Text(banner)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.pkText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(12)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 420, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.pkElevated))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        .padding(14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .overlay {
                if let request = viewModel.pendingKill, request.origin == origin {
                    KillConfirmationPanel(
                        request: request,
                        title: "ปิด process?",
                        confirmTitle: "ปิด process",
                        footnote: "ส่ง SIGTERM ก่อน รอสูงสุดประมาณ 3 วินาที",
                        onCancel: { viewModel.cancelPendingKill() },
                        onConfirm: { viewModel.confirmKill() }
                    )
                } else if let request = viewModel.pendingForceKill, request.origin == origin {
                    KillConfirmationPanel(
                        request: request,
                        title: "บังคับปิด (SIGKILL)?",
                        confirmTitle: "บังคับปิด",
                        footnote: "process เหล่านี้ยังไม่ปิดหลังรอ 3 วินาที SIGKILL จะหยุดทันทีโดยไม่ให้บันทึกข้อมูล",
                        isForce: true,
                        onCancel: { viewModel.cancelForceKill() },
                        onConfirm: { viewModel.confirmForceKill() }
                    )
                }
            }
            .animation(.easeOut(duration: 0.15), value: viewModel.resultBanner)
            .onDisappear { viewModel.cancelPending(origin: origin) }
    }
}

extension View {
    func killConfirmation(origin: KillOrigin) -> some View {
        modifier(KillOverlayModifier(origin: origin))
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

    @State private var confirmEnabled = false

    private var uniqueWarnings: [KillWarning] {
        var seen = Set<KillWarning>()
        return request.entries.flatMap(\.warnings).filter { seen.insert($0).inserted }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.pkText)

                // Warnings sit above the scrolling list so a long name can never push them out of view.
                if !uniqueWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(uniqueWarnings, id: \.self) { warning in
                            Text(warning.message)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.yellow)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(request.entries) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.pkText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if let path = entry.path {
                                    Text(path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.pkMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Text("Port \(KillSafety.sanitizeForDisplay(entry.item.port, limit: 8)) · PID \(KillSafety.sanitizeForDisplay(entry.item.pid, limit: 12))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.pkMuted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)

                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("ยกเลิก", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    if isForce {
                        // Destructive style, never the default action, disabled briefly on appear.
                        Button(confirmTitle, role: .destructive, action: onConfirm)
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(!confirmEnabled)
                    } else {
                        Button(confirmTitle, action: onConfirm)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.pkSidebar))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.pkStroke.opacity(0.5), lineWidth: 1))
            .padding(16)
        }
        .task(id: request.id) {
            confirmEnabled = !isForce
            guard isForce else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            confirmEnabled = true
        }
    }
}
