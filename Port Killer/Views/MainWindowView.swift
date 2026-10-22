import AppKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @State private var sortOrder = [KeyPathComparator(\PortRow.portNumber)]

    private var rows: [PortRow] {
        let sorted = viewModel.rows(matching: viewModel.searchText).sorted(using: sortOrder)
        // Pinned rows always stay on top, in the chosen sort order.
        return sorted.filter(\.isPinned) + sorted.filter { !$0.isPinned }
    }

    var body: some View {
        let rows = rows
        content(rows)
            .frame(minWidth: 640, minHeight: 320)
            .navigationTitle("Port Killer")
            .navigationSubtitle(viewModel.hasLoadedLivePorts && viewModel.scanError == nil ? "\(viewModel.ports.count) ports" : "")
            .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "ค้นหา port, process, PID")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("สแกน port ใหม่ (⌘R)")
                    .accessibilityLabel("Refresh ports")

                    Button(role: .destructive) {
                        viewModel.killSelectedPorts(origin: .mainWindow)
                    } label: {
                        Label("Kill ที่เลือก (\(viewModel.selectedPorts.count))", systemImage: "xmark.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(viewModel.selectedPorts.isEmpty)
                    .help("ปิด process ที่เลือก (ต้องยืนยันก่อน)")
                }
            }
            .killConfirmation(origin: .mainWindow)
            .background(WindowAccessor { window in
                // macOS 14 fallback: SwiftUI opens a Window scene at launch; close it unless requested.
                if #unavailable(macOS 15), !AppActivation.mainWindowRequested { window.close() }
            })
            .onAppear {
                if #available(macOS 15, *) { AppActivation.windowDidAppear(); viewModel.screenDidAppear() }
                else if AppActivation.mainWindowRequested { AppActivation.windowDidAppear(); viewModel.screenDidAppear() }
            }
            .onDisappear {
                if #available(macOS 15, *) { AppActivation.windowDidDisappear(); viewModel.screenDidDisappear() }
                else if AppActivation.mainWindowRequested { AppActivation.windowDidDisappear(); viewModel.screenDidDisappear() }
            }
    }

    @ViewBuilder
    private func content(_ rows: [PortRow]) -> some View {
        if !viewModel.hasLoadedLivePorts {
            ProgressView("กำลังสแกน port…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.scanError {
            ContentUnavailableView {
                Label("สแกน port ไม่สำเร็จ", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("ลองอีกครั้ง") { viewModel.refresh() }
            }
        } else if rows.isEmpty {
            if viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView(
                    "ไม่มี port ที่กำลังฟังอยู่",
                    systemImage: "network.slash",
                    description: Text("ไม่พบ TCP listener ในขณะนี้")
                )
            } else {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        } else {
            table(rows)
        }
    }

    private func table(_ rows: [PortRow]) -> some View {
        Table(rows, selection: $viewModel.selectedPortIDs, sortOrder: $sortOrder) {
            TableColumn("Port", value: \.portNumber) { row in
                HStack(spacing: 4) {
                    if row.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                    Text(row.port)
                        .font(.system(.body, design: .monospaced))
                }
                .opacity(row.isRunning ? 1 : 0.5)
            }
            .width(min: 80, ideal: 90)

            TableColumn("Process", value: \.processName) { row in
                HStack(spacing: 6) {
                    Text(row.processName).lineLimit(1)
                    if row.isDocker { TagLabel("Docker") }
                    if !row.isRunning { TagLabel("ไม่ได้รัน") }
                }
                .opacity(row.isRunning ? 1 : 0.5)
            }
            .width(min: 140, ideal: 200)

            TableColumn("PID", value: \.pidNumber) { row in
                Text(row.pid)
                    .font(.system(.body, design: .monospaced))
                    .opacity(row.isRunning ? 1 : 0.5)
            }
            .width(min: 60, ideal: 80)

            TableColumn("User", value: \.userText) { row in
                HStack(spacing: 4) {
                    Text(row.userText).lineLimit(1)
                    if row.isReadOnly {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("อ่านอย่างเดียว: ปิดจากแอปนี้ไม่ได้")
                            .accessibilityLabel("อ่านอย่างเดียว")
                    }
                }
                .opacity(row.isRunning ? 1 : 0.5)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Address", value: \.addressText) { row in
                Text(row.addressText)
                    .lineLimit(1)
                    .opacity(row.isRunning ? 1 : 0.5)
            }
        }
        .contextMenu(forSelectionType: PortRow.ID.self) { ids in
            PortActionsMenu(rows: rows.filter { ids.contains($0.id) }, origin: .mainWindow)
        }
        .onDeleteCommand { viewModel.killSelectedPorts(origin: .mainWindow) }
        .onCopyCommand {
            let pids = rows.filter { viewModel.selectedPortIDs.contains($0.id) && $0.isRunning }.map(\.pid)
            guard !pids.isEmpty else { return [] }
            return [NSItemProvider(object: pids.joined(separator: "\n") as NSString)]
        }
    }
}
