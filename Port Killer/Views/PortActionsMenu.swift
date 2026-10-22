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
        }
        if !running.isEmpty {
            Button("Copy PID") { PortActionsMenu.copy(running.map(\.pid), label: "PID", viewModel) }
        }
        if !rows.isEmpty {
            Button("Copy port") { PortActionsMenu.copy(rows.map(\.port), label: "port", viewModel) }
        }
        if rows.count == 1, let row = rows.first {
            if row.isPinned {
                Button("Unpin") { unpin(row) }
            } else if let item = row.item {
                Button("Pin") { viewModel.togglePinned(item) }
            }
            if let item = row.item, row.isReadOnly {
                Button("คัดลอกคำสั่ง sudo kill \(item.pid)") { viewModel.copySudoKillCommand(for: item) }
            }
        }
        if !running.isEmpty {
            Divider()
            Button("แสดงใน Activity Monitor") { PortActionsMenu.showInActivityMonitor() }
        }
    }

    private func unpin(_ row: PortRow) {
        if let item = row.item {
            viewModel.togglePinned(item)
        } else {
            viewModel.unpin(row.bookmark)
        }
    }

    static func copy(_ values: [String], label: String, _ viewModel: PortViewModel) {
        guard !values.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values.joined(separator: "\n"), forType: .string)
        viewModel.showBanner("คัดลอก \(label) แล้ว: \(values.joined(separator: ", "))")
    }

    static func showInActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Small capsule label (owner of a read-only row, "Docker", "ไม่ได้รัน").
struct TagLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .lineLimit(1)
    }
}
