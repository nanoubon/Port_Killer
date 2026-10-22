import AppKit
import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct FavoritesSectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    private var pinnedItems: [PortItem] {
        viewModel.pinnedPortItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pinned Environments")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.pkText)
                    Text("Quick-access ports and saved workflows")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.pkMuted)
                }

                Spacer()

                HeaderIconButton(systemName: "plus") {
                    if let first = viewModel.visiblePorts.first {
                        viewModel.togglePinned(first)
                    }
                }
                .help("Pin a new port")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                MetricCardView(metric: DashboardMetric(title: "TOTAL PINNED", value: String(format: "%02d", pinnedItems.count), tint: .neutral, detail: "Saved across launches"))
                MetricCardView(metric: DashboardMetric(title: "ACTIVE SERVICES", value: String(format: "%02d", pinnedItems.filter { $0.state == .listening }.count), tint: .secondary, detail: "Listening now"))
                QuickActionCard(action: QuickAction(title: "Pin New Port", subtitle: "Attach a new environment", symbol: "plus.circle.fill")) {
                    if let first = viewModel.visiblePorts.first {
                        viewModel.togglePinned(first)
                    } else {
                        viewModel.setSection(.activePorts)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                ForEach(Array(pinnedItems.enumerated()), id: \.element.id) { index, port in
                    PinnedPortCard(port: port, isMuted: index % 3 == 2)
                        .environmentObject(viewModel)
                }
            }

            CardShell(fill: Color.pkElevated.opacity(0.85), radius: 14) {
                HStack(spacing: 10) {
                    Text("$")
                        .foregroundStyle(Color.pkMuted)
                    Text("quick command (e.g. kill 3000, monitor all, pin 9000)")
                        .foregroundStyle(Color.pkMuted.opacity(0.6))
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                    Spacer()
                    Text("⌘K")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.pkMuted.opacity(0.45))
                }
            }
        }
    }
}

struct PinnedPortCard: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let port: PortItem
    let isMuted: Bool

    var body: some View {
        CardShell(fill: isMuted ? Color.pkElevated.opacity(0.9) : Color.pkCard, radius: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(port.processName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.pkMuted.opacity(0.7))
                        Text(port.port)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundStyle(port.state == .busy ? Color.pkWarning : Color.pkText)
                        StatusPill(state: port.state)
                    }

                    Spacer()

                    Button {
                        viewModel.togglePinned(port)
                    } label: {
                        Image(systemName: viewModel.isPinned(port) ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(viewModel.isPinned(port) ? Color.pkWarning : Color.pkMuted)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.pkSurface)
                            )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("PID: \(port.pid)")
                    Text("Up: \(port.uptime ?? "-")")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.pkMuted)

                HStack(spacing: 10) {
                    Button {
                        viewModel.selectPort(port)
                    } label: {
                        Text("Monitor")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    if port.isReadOnly {
                        Button {
                            viewModel.copySudoKillCommand(for: port)
                        } label: {
                            Text("Copy sudo kill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TertiaryActionButtonStyle())
                    } else {
                        Button {
                            viewModel.killProcess(pid: port.pid, port: port)
                        } label: {
                            Text("Kill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TertiaryActionButtonStyle())
                    }
                }
            }
        }
        .frame(minHeight: 162)
    }
}
