import AppKit
import SwiftUI

/// Context-menu items shared by the main table and the popover rows.
struct PortActionsMenu: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let rows: [PortRow]
    let origin: KillOrigin

    private var killable: [PortRow] { rows.filter(\.isKillable) }
    private var running: [PortRow] { rows.filter(\.isRunning) }

    var body: some View {
        if !killable.isEmpty {
            Button(killable.count == 1 ? "Kill" : "Kill (\(killable.count))", role: .destructive) {
                viewModel.killPorts(ids: Set(killable.map(\.id)), origin: origin)
            }
            Divider()
        } else if rows.contains(where: \.isReadOnly) {
            // Shown disabled instead of omitted, so the reason is discoverable.
            Button("Kill (ต้องใช้ sudo)", role: .destructive) {}
                .disabled(true)
            Divider()
        }
        if !running.isEmpty {
            Button("Copy PID") { PortActionsMenu.copy(running.map(\.pid), label: "PID", viewModel, origin: origin) }
        }
        if !rows.isEmpty {
            Button("Copy port") { PortActionsMenu.copy(rows.map(\.port), label: "port", viewModel, origin: origin) }
        }
        if rows.count == 1, let row = rows.first {
            Button(row.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(row) }
            if let item = row.item, row.isReadOnly {
                Button("คัดลอกคำสั่ง sudo kill \(item.pid)") { viewModel.copySudoKillCommand(for: item, origin: origin) }
            }
        }
        if !running.isEmpty {
            Divider()
            Button("เปิด Activity Monitor") { PortActionsMenu.showInActivityMonitor() }
        }
    }

    static func copy(_ values: [String], label: String, _ viewModel: PortViewModel, origin: KillOrigin? = nil) {
        guard !values.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values.joined(separator: "\n"), forType: .string)
        viewModel.showBanner("คัดลอก \(label) แล้ว: \(values.joined(separator: ", "))", origin: origin)
    }

    static func showInActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The row's actions for VoiceOver and other assistive technology. Used on rows that combine
/// their children, whose inline buttons are then not reachable on their own.
struct PortRowAccessibilityActions: ViewModifier {
    @EnvironmentObject private var viewModel: PortViewModel
    let row: PortRow
    let origin: KillOrigin

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if row.isKillable {
                Button("Kill") { viewModel.killPorts(ids: [row.id], origin: origin) }
            }
            if let item = row.item, row.isReadOnly {
                Button("คัดลอกคำสั่ง sudo kill \(item.pid)") { viewModel.copySudoKillCommand(for: item, origin: origin) }
            }
            Button(row.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(row) }
            if row.isRunning {
                Button("Copy PID") { PortActionsMenu.copy([row.pid], label: "PID", viewModel, origin: origin) }
            }
            Button("Copy port") { PortActionsMenu.copy([row.port], label: "port", viewModel, origin: origin) }
        }
    }
}

extension View {
    func portRowAccessibilityActions(_ row: PortRow, origin: KillOrigin) -> some View {
        modifier(PortRowAccessibilityActions(row: row, origin: origin))
    }
}

/// Small capsule label (owner of a read-only row, "Docker", "ไม่ได้รัน").
struct TagLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .lineLimit(1)
    }
}
