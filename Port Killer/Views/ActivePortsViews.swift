import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ActivePortsDashboardView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running Processes")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.pkText)
                    Text(viewModel.remainingSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.pkMuted)
                }

                Spacer()

                if viewModel.hasLoadedLivePorts {
                    Text("\(viewModel.visiblePorts.count) ACTIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(Color.pkSuccess)
                        .background(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(Color.pkSuccess.opacity(0.12))
                        )
                }
            }

            HStack(alignment: .top, spacing: 18) {
                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        TableHeaderRow()

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if !viewModel.hasLoadedLivePorts {
                                    LoadingTablePlaceholder()
                                } else if viewModel.visiblePorts.isEmpty {
                                    EmptyTablePlaceholder()
                                } else {
                                    ForEach(viewModel.visiblePorts) { port in
                                        PortTableRowView(port: port)
                                            .environmentObject(viewModel)
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 200, idealHeight: 350)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PortDetailPanel()
                    .frame(width: 340)
            }

        }
    }
}

struct TableHeaderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 24, height: 1)
            Text("PORT")
                .frame(minWidth: 60, idealWidth: 72, alignment: .leading)
            Text("PROCESS")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PID")
                .frame(minWidth: 60, idealWidth: 72, alignment: .leading)
            Text("USER")
                .frame(minWidth: 70, idealWidth: 88, alignment: .leading)
            Text("STATUS")
                .frame(minWidth: 70, idealWidth: 84, alignment: .leading)
            Text("COMMAND")
                .frame(minWidth: 180, idealWidth: 240, alignment: .leading)
            Text("ACTION")
                .frame(width: 88, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.pkMuted.opacity(0.72))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.pkElevated.opacity(0.35))
    }
}

struct PortTableRowView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let port: PortItem

    var isSelected: Bool {
        viewModel.selectedPortIDs.contains(port.id)
    }

    var isFocused: Bool {
        viewModel.selectedPort?.id == port.id
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleSelection(for: port)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.pkPrimary : Color.pkMuted)
            }
            .buttonStyle(.plain)
            .disabled(port.isReadOnly)
            .opacity(port.isReadOnly ? 0.3 : 1)
            .frame(width: 20)

            Text(port.port)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.pkPrimary)
                .frame(minWidth: 60, idealWidth: 72, alignment: .leading)

            HStack(spacing: 10) {
                PortThumbnailView(port: port)
                VStack(alignment: .leading, spacing: 2) {
                    Text(port.processName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.pkText)
                    Text(port.state == .busy ? "High usage" : "Listening socket")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.pkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(port.pid)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.pkText.opacity(0.82))
                .frame(minWidth: 60, idealWidth: 72, alignment: .leading)

            HStack(spacing: 6) {
                Text(port.user ?? "-")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.pkMuted)
                if port.isReadOnly { OwnerBadge(port: port) }
            }
            .frame(minWidth: 70, idealWidth: 88, alignment: .leading)

            StatusPill(state: port.state)
                .frame(minWidth: 70, idealWidth: 84, alignment: .leading)

            Text(port.command ?? "-")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.pkMuted.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 180, idealWidth: 240, alignment: .leading)

            Group {
                if port.isReadOnly {
                    CopySudoKillButton(port: port)
                } else {
                    Button {
                        viewModel.killProcess(pid: port.pid, port: port)
                    } label: {
                        Text("KILL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(Color.pkDangerText)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.pkDanger.opacity(0.18))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isFocused ? Color.pkPrimary.opacity(0.11) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectPort(port)
        }
    }
}

struct LoadingTablePlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Scanning listening ports...")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.pkText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(28)
    }
}

struct EmptyTablePlaceholder: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.pkMuted)

            Text(viewModel.scanError != nil
                 ? "Scan failed."
                 : (viewModel.searchText.isEmpty ? "No active listening ports found." : "No matching ports."))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.pkText)

            Text(viewModel.scanError ?? viewModel.debugMessage)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.pkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(28)
    }
}

struct PortDetailPanel: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var port: PortItem? {
        viewModel.selectedPort
    }

    var body: some View {
        CardShell(fill: Color.pkCard, radius: 18) {
            if let port {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        PortThumbnailView(port: port, size: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(port.processName)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.pkText)
                            Text(viewModel.detailSubtitle(for: port))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.pkMuted)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            StatusPill(state: port.state)
                            Text(viewModel.detailLoad(for: port))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.pkMuted)
                        }
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        DetailStatCard(title: "PORT", value: port.port)
                        DetailStatCard(title: "PID", value: port.pid)
                        DetailStatCard(title: "USER", value: viewModel.detailUser(for: port))
                        DetailStatCard(title: "PROTO", value: port.protocolName)
                    }

                    DetailField(title: "EXECUTABLE PATH", value: viewModel.detailCommand(for: port))
                    DetailField(title: "COMMAND", value: viewModel.detailCommand(for: port))

                    HStack(spacing: 10) {
                        SecondaryActionButton(title: "COPY PID", symbol: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(port.pid, forType: .string)
                        }

                        SecondaryActionButton(title: viewModel.portActionLabel(for: port).uppercased(), symbol: "star") {
                            viewModel.togglePinned(port)
                        }
                    }

                    HStack(spacing: 10) {
                        if port.isReadOnly {
                            Button {
                                viewModel.copySudoKillCommand(for: port)
                            } label: {
                                Text("คัดลอกคำสั่ง sudo kill \(port.pid)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                        } else {
                            Button {
                                viewModel.killProcess(pid: port.pid, port: port)
                            } label: {
                                Text("Kill Process")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(DangerActionButtonStyle())
                        }
                    }

                    Text("You will be asked to confirm before the process is closed")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.pkDangerText.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No process selected")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.pkText)
                    Text("Run a scan or pick a port from the table to inspect details, pin it, or kill it.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.pkMuted)

                    VStack(alignment: .leading, spacing: 10) {
                        DetailField(title: "STATUS", value: "No live ports are selected")
                        DetailField(title: "ACTION", value: "Refresh the scan to populate process details")
                    }
                }
            }
        }
    }
}

struct DetailStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.pkMuted.opacity(0.75))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.pkText)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.pkElevated)
        )
    }
}

struct DetailField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.pkMuted.opacity(0.75))
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.pkText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.pkSurface)
                )
        }
    }
}

struct OwnerBadge: View {
    let port: PortItem

    var body: some View {
        Text(port.ownerLabel ?? "other user")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(Color.pkWarning)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.pkWarning.opacity(0.16))
            )
            .help("อ่านอย่างเดียว: process ของ \(port.ownerLabel ?? "user อื่น") ปิดจากแอปนี้ไม่ได้")
    }
}

/// Replaces the kill button on read-only rows: copies `sudo kill <pid>` instead of acting.
struct CopySudoKillButton: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let port: PortItem

    var body: some View {
        Button {
            viewModel.copySudoKillCommand(for: port)
        } label: {
            Text("COPY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(Color.pkMuted)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.pkSurface.opacity(0.92))
                )
        }
        .buttonStyle(.plain)
        .help("คัดลอกคำสั่ง sudo kill \(port.pid)")
        .accessibilityLabel("คัดลอกคำสั่ง sudo kill \(port.pid)")
    }
}
