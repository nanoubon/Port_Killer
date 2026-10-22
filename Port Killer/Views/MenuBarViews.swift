import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarPopoverView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""

    private var filteredPorts: [PortItem] {
        viewModel.ports(matching: searchText)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                HStack {
                    Text("Port Killer")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.pkText)
                    Spacer()
                    HeaderIconButton(systemName: "arrow.clockwise") {
                        viewModel.refresh()
                    }
                    .frame(width: 22, height: 22)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.pkSurface.opacity(0.9))

                VStack(spacing: 10) {
                    SearchBar(text: $searchText, placeholder: "Search ports or PIDs...")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.pkSurface.opacity(0.82))

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("ACTIVE PORTS")
                        Spacer()
                        Text("PID")
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    VStack(spacing: 0) {
                        if !viewModel.hasLoadedLivePorts {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Scanning...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.pkMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            ForEach(filteredPorts) { port in
                                MenuPortRowView(port: port)
                                    .environmentObject(viewModel)
                            }
                        }
                    }
                }
                .background(Color.pkElevated.opacity(0.55))

                VStack(spacing: 10) {
                    Button {
                        openMainWindow()
                    } label: {
                        Text("Open Full App")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.pkMuted)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.pkSurface.opacity(0.92))
            }
        }
        .scrollIndicators(.visible)
        .frame(width: 320, height: 560)
        .background(Color.pkSidebar)
        .killConfirmation(origin: .menuBar)
        .onAppear { viewModel.screenDidAppear() }
        .onDisappear { viewModel.screenDidDisappear() }
    }

    private func openMainWindow() {
        dismiss()
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// Badge for read-only rows (ports held by root / another user).

struct MenuPortRowView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let port: PortItem

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusAccent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.port)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkPrimary)
                Text(port.processName.lowercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.pkMuted)
            }

            Spacer(minLength: 12)

            Text(port.pid)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.pkMuted.opacity(0.82))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.pkSurface.opacity(0.92))
                )

            if port.isReadOnly {
                OwnerBadge(port: port)
                Button {
                    viewModel.copySudoKillCommand(for: port)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color.pkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("คัดลอกคำสั่ง sudo kill \(port.pid)")
                .help("คัดลอกคำสั่ง sudo kill \(port.pid)")
            } else {
                Button {
                    viewModel.killProcess(pid: port.pid, port: port, origin: .menuBar)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color.pkDangerText)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.pkDanger.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ปิด \(port.processName) port \(port.port)")
                .help("ปิด process")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(port.state == .busy ? Color.pkDanger.opacity(0.08) : Color.clear)
    }

    private var statusAccent: Color {
        switch port.state {
        case .listening: return Color.pkSecondary
        case .busy: return Color.pkWarning
        case .idle: return Color.pkMuted
        case .dormant: return Color.pkSurface
        }
    }
}

struct BatchActionBarView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.totalSelectedCount) selected")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.pkText)
                Text("Processes flagged")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
            }

            Spacer()

            Button {
                viewModel.clearSelection()
            } label: {
                Text("Deselect All")
                    .frame(width: 132)
            }
            .buttonStyle(SecondaryActionButtonStyle())

            Button {
                viewModel.killSelectedPorts()
            } label: {
                Text("Kill Selected Processes")
                    .frame(width: 188)
            }
            .buttonStyle(DangerActionButtonStyle())

            Button {
                viewModel.clearSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.pkMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.pkElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.pkStroke.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        )
    }
}
