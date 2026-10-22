import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var searchText = ""

    private static let rowHeight: CGFloat = 48
    private static let maxListHeight: CGFloat = 384
    private static let minListHeight: CGFloat = 200

    var body: some View {
        let rows = viewModel.rows(matching: searchText)
        VStack(spacing: 0) {
            header
            Divider()
            list(rows)
            Divider()
            footer
        }
        .frame(width: 340)
        .killConfirmation(origin: .menuBar)
        .onAppear { viewModel.screenDidAppear() }
        .onDisappear { viewModel.screenDidDisappear() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("ค้นหา port, process, PID", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search ports")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .help("ล้างคำค้นหา")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Button { viewModel.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh ports")
            .help("สแกน port ใหม่")
        }
        .padding(10)
    }

    @ViewBuilder
    private func list(_ rows: [PortRow]) -> some View {
        Group {
            if !viewModel.hasLoadedLivePorts {
                ProgressView("กำลังสแกน port…")
                    .controlSize(.small)
            } else if let error = viewModel.scanError {
                ContentUnavailableView {
                    Label("สแกน port ไม่สำเร็จ", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("ลองอีกครั้ง") { viewModel.refresh() }
                }
            } else if rows.isEmpty {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("ไม่มี port ที่กำลังฟังอยู่", systemImage: "network.slash")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            MenuPortRow(row: row)
                                .frame(height: Self.rowHeight)
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: listHeight(rows))
    }

    private func listHeight(_ rows: [PortRow]) -> CGFloat {
        guard viewModel.hasLoadedLivePorts, viewModel.scanError == nil, !rows.isEmpty else { return Self.minListHeight }
        return min(max(CGFloat(rows.count) * (Self.rowHeight + 1), Self.minListHeight), Self.maxListHeight)
    }

    private var footer: some View {
        HStack {
            Button("เปิดหน้าต่าง") {
                AppActivation.openMainWindow(openWindow)
            }
            .keyboardShortcut("o")
            .help("เปิดหน้าต่างหลัก (⌘O)")

            Spacer()

            Button("ตั้งค่า") {
                AppActivation.openSettings(openSettings)
            }
            .keyboardShortcut(",")
            .help("เปิดการตั้งค่า (⌘,)")

            Button("ออก") { viewModel.quitApp() }
                .keyboardShortcut("q")
                .help("ออกจาก Port Killer (⌘Q)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct MenuPortRow: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let row: PortRow

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                if row.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Pinned")
                }
                Text(row.port)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }
            .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.processName).lineLimit(1).truncationMode(.tail)
                    if row.isDocker { TagLabel("Docker") }
                }
                Text(row.isRunning ? "PID \(row.pid) · \(row.userText)" : "ไม่ได้รัน")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 10)
        .opacity(row.isRunning ? 1 : 0.55)
        .contentShape(Rectangle())
        .contextMenu { PortActionsMenu(rows: [row], origin: .menuBar) }
    }

    @ViewBuilder
    private var trailing: some View {
        if let item = row.item, row.isReadOnly {
            if let owner = row.ownerLabel { TagLabel(owner) }
            Button { viewModel.copySudoKillCommand(for: item) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("คัดลอกคำสั่ง sudo kill \(item.pid)")
            .help("คัดลอกคำสั่ง sudo kill \(item.pid)")
        } else if let item = row.item {
            Button {
                viewModel.killProcess(pid: item.pid, port: item, origin: .menuBar)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Kill \(row.processName) on port \(row.port)")
            .help("ปิด \(row.processName) (port \(row.port))")
        } else {
            Button { viewModel.unpin(row.bookmark) } label: {
                Image(systemName: "pin.slash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Unpin \(row.processName) port \(row.port)")
            .help("ยกเลิก pin")
        }
    }
}
