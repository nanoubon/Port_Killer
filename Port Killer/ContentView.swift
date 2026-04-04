import AppKit
import SwiftUI
import StoreKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @EnvironmentObject private var proStore: ProPurchaseManager

    var body: some View {
        WorkspaceShellView()
            .preferredColorScheme(.dark)
    }
}

struct WorkspaceShellView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @EnvironmentObject private var proStore: ProPurchaseManager

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !viewModel.hasCompletedOnboarding },
            set: { presented in
                if !presented {
                    viewModel.completeOnboarding()
                }
            }
        )
    }

    var body: some View {
        ZStack {
            WorkspaceBackground()

            HStack(spacing: 0) {
                WorkspaceSidebarView()
                    .frame(width: 248)

                Divider()
                    .overlay(Color.pkStroke.opacity(0.25))

                VStack(spacing: 0) {
                    WorkspaceHeaderBar()
                    Divider()
                        .overlay(Color.pkStroke.opacity(0.25))

                    WorkspaceSectionView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $viewModel.showAppStorePreview) {
            AppStorePreviewView()
                .environmentObject(viewModel)
                .environmentObject(proStore)
                .frame(minWidth: 1040, minHeight: 800)
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView()
                .environmentObject(viewModel)
                .frame(minWidth: 980, minHeight: 740)
        }
        .onAppear {
            viewModel.setProUnlocked(proStore.isProUnlocked)
        }
        .onChange(of: proStore.isProUnlocked) { _, isUnlocked in
            viewModel.setProUnlocked(isUnlocked)
        }
    }
}

struct WorkspaceBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.pkBackground,
                    Color.pkBackground.opacity(0.96),
                    Color.pkSurface.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.pkPrimary.opacity(0.12),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 680
            )

            RadialGradient(
                colors: [
                    Color.pkSecondary.opacity(0.08),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct WorkspaceSidebarView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @EnvironmentObject private var proStore: ProPurchaseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Port Killer")
                    .font(.system(size: 22, weight: .black, design: .default))
                    .tracking(-0.4)
                    .foregroundStyle(Color.pkText)
                Text("v2.4.0")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
            }
            .padding(.top, 20)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    SidebarSectionButton(
                        title: section.title,
                        symbol: section.symbolName,
                        isActive: viewModel.selectedSection == section
                    ) {
                        viewModel.setSection(section)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text(proStore.isProUnlocked ? "Pro features unlocked." : "Professional performance analytics enabled.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pkMuted)

                Button {
                    if proStore.isProUnlocked {
                        viewModel.setSection(.proFeatures)
                    } else {
                        proStore.unlockProImmediately()
                        viewModel.setSection(.proFeatures)
                    }
                } label: {
                    Text(proStore.isProUnlocked ? "Manage Pro" : "Upgrade to Pro")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.pkSidebar)
    }
}

struct SidebarSectionButton: View {
    let title: String
    let symbol: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(isActive ? Color.pkText : Color.pkMuted)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isActive ? Color.pkPrimary.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isActive ? Color.pkPrimary.opacity(0.7) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceHeaderBar: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedSection.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.pkText)
                Text(viewModel.selectedSection.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pkMuted)
            }

            Spacer(minLength: 12)

            SearchBar(text: $viewModel.searchText, placeholder: searchPlaceholder)
                .frame(maxWidth: 340)

            HeaderIconButton(systemName: viewModel.isAutoRefreshEnabled ? "arrow.triangle.2.circlepath" : "pause.circle") {
                viewModel.toggleAutoRefresh()
            }
            .help(viewModel.isAutoRefreshEnabled ? "Auto refresh enabled" : "Auto refresh paused")

            HeaderIconButton(systemName: "line.3.horizontal.decrease.circle") {
                viewModel.refresh()
            }
            .help("Refresh port list")

            HeaderIconButton(systemName: "clock.arrow.circlepath") {
                viewModel.setSection(.history)
            }
            .help("Open history")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.pkSurface.opacity(0.72))
    }

    private var searchPlaceholder: String {
        switch viewModel.selectedSection {
        case .activePorts: return "Search ports, PIDs or processes..."
        case .favorites: return "Search pinned ports..."
        case .history: return "Search history..."
        case .proFeatures: return "Search premium features..."
        }
    }
}

struct HeaderIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.pkPrimary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.pkElevated.opacity(0.55))
                )
        }
        .buttonStyle(.plain)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pkMuted)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular, design: .monospaced))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.pkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.pkElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.pkStroke.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

struct WorkspaceSectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                switch viewModel.selectedSection {
                case .activePorts:
                    ActivePortsDashboardView()
                case .favorites:
                    FavoritesSectionView()
                case .history:
                    HistorySectionView()
                case .proFeatures:
                    ProFeaturesSectionView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 80)
        }
        .overlay(alignment: .bottom) {
            if viewModel.totalSelectedCount > 0 {
                BatchActionBarView()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
        }
    }
}

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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(viewModel.dashboardMetrics) { metric in
                    MetricCardView(metric: metric)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        TableHeaderRow()

                        VStack(spacing: 0) {
                            if viewModel.visiblePorts.isEmpty {
                                EmptyTablePlaceholder()
                            } else {
                                ForEach(viewModel.visiblePorts) { port in
                                    PortTableRowView(port: port)
                                        .environmentObject(viewModel)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                PortDetailPanel()
                    .frame(width: 360)
            }

            HStack(alignment: .top, spacing: 18) {
                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "PORT ACTIVITY MAP", trailing: "REAL-TIME TELEMETRY")
                        HeatmapStripView(states: viewModel.activityHeatmapState)
                            .frame(height: 240)
                    }
                }

                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "QUICK COMMANDS", trailing: "LIVE SUGGESTIONS")

                        VStack(spacing: 10) {
                            ForEach(viewModel.quickActions) { action in
                                QuickActionCard(action: action) {
                                    handleQuickAction(action)
                                }
                            }
                        }
                    }
                }
                .frame(width: 300)
            }
        }
    }

    private func handleQuickAction(_ action: QuickAction) {
        switch action.title {
        case "Refresh Scan":
            viewModel.refresh()
        case "Explore Favorites":
            viewModel.setSection(.favorites)
        case "Enable Pro Monitoring":
            viewModel.setSection(.proFeatures)
        default:
            viewModel.refresh()
        }
    }
}

struct TableHeaderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 24, height: 1)
            Text("PORT")
            Spacer().frame(width: 96)
            Text("PROCESS")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PID")
                .frame(width: 72, alignment: .leading)
            Text("USER")
                .frame(width: 88, alignment: .leading)
            Text("STATUS")
                .frame(width: 84, alignment: .leading)
            Text("COMMAND")
                .frame(width: 240, alignment: .leading)
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
            .frame(width: 20)

            Text(port.port)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.pkPrimary)
                .frame(width: 72, alignment: .leading)

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
                .frame(width: 72, alignment: .leading)

            Text(port.user ?? "admin")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.pkMuted)
                .frame(width: 88, alignment: .leading)

            StatusPill(state: port.state)
                .frame(width: 84, alignment: .leading)

            Text(port.command ?? "/usr/local/bin/\(port.processName.lowercased())")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.pkMuted.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 240, alignment: .leading)

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

struct EmptyTablePlaceholder: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.pkMuted)

            Text(viewModel.searchText.isEmpty ? "No active listening ports found." : "No matching ports.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.pkText)

            Text(viewModel.debugMessage)
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
        if let selected = viewModel.selectedPort {
            return selected
        }

        if !viewModel.hasLoadedLivePorts {
            return viewModel.demoPort(for: "3000") ?? demoFallback
        }

        return viewModel.visiblePorts.first ?? viewModel.ports.first
    }

    private var demoFallback: PortItem {
        PortItem(
            processName: "Node.js Runtime",
            pid: "451",
            port: "3000",
            protocolName: "TCP",
            icon: NSImage.symbol("terminal.fill"),
            state: .listening,
            user: "admin",
            command: "node server.js --config ./webpack.prod.js --inspect=9229",
            uptime: "Active since 2h 45m",
            loadDescription: "0.4% CPU"
        )
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
                        SecondaryActionButton(title: "MONITOR", symbol: "chart.xyaxis.line") {
                            viewModel.setSection(.proFeatures)
                        }

                        Button {
                            viewModel.killProcess(pid: port.pid, port: port)
                        } label: {
                            Text("Kill Process")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DangerActionButtonStyle())
                    }

                    Text("Process will be force-terminated immediately")
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

struct FavoritesSectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    private var pinnedItems: [PortItem] {
        viewModel.pinnedPortItems.isEmpty ? Array(viewModel.visiblePorts.prefix(4)) : viewModel.pinnedPortItems
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
                MetricCardView(metric: DashboardMetric(title: "ACTIVE SERVICES", value: String(format: "%02d", max(pinnedItems.filter { $0.state == .listening }.count, 3)), tint: .secondary, detail: "Listening now"))
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

            CardShell(fill: Color.pkCard, radius: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "RESOURCE HEATMAP", trailing: "VIEW ANALYTICS")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(pinnedItems.prefix(4).enumerated()), id: \.offset) { index, port in
                            HeatmapLineView(label: "Port \(port.port)", state: port.state, emphasis: index == 1 ? .warning : .secondary)
                        }
                    }
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
                    Text("Up: \(port.uptime ?? "2h 45m")")
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

                    Button {
                        viewModel.setSection(.activePorts)
                        viewModel.selectPort(port)
                    } label: {
                        Text("Kill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TertiaryActionButtonStyle())
                }
            }
        }
        .frame(minHeight: 162)
    }
}

struct HeatmapLineView: View {
    let label: String
    let state: PortState
    let emphasis: HeatmapEmphasis

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.pkText.opacity(0.82))
                .frame(width: 90, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor(for: index))
                        .frame(width: 50, height: 8)
                }
            }

            Spacer()

            Text(emphasis == .warning ? "High Usage" : (state == .idle ? "Idle" : "Low Load"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(emphasis == .warning ? Color.pkWarning : Color.pkSecondary)
        }
    }

    private func barColor(for index: Int) -> Color {
        switch state {
        case .listening:
            return index < 4 ? Color.pkSecondary : (index == 4 ? Color.pkMuted.opacity(0.35) : Color.pkSurface)
        case .busy:
            return index < 6 ? Color.pkWarning : Color.pkDanger.opacity(0.45)
        case .idle:
            return index < 3 ? Color.pkMuted.opacity(0.35) : Color.pkSurface
        case .dormant:
            return index < 2 ? Color.pkMuted.opacity(0.25) : Color.pkSurface
        }
    }
}

enum HeatmapEmphasis {
    case secondary
    case warning
}

struct HistorySectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kill History")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.pkText)
                    Text(viewModel.historySummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.pkMuted)
                }
                Spacer()
                HeaderIconButton(systemName: "trash") {
                    viewModel.killHistory = []
                }
                .help("Clear history")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                MetricCardView(metric: DashboardMetric(title: "RECENT EVENTS", value: String(format: "%02d", viewModel.historyFeed.count), tint: .warning, detail: "Last terminations logged"))
                MetricCardView(metric: DashboardMetric(title: "TODAY", value: String(format: "%02d", min(3, viewModel.historyFeed.count)), tint: .secondary, detail: "Processes terminated"))
                MetricCardView(metric: DashboardMetric(title: "AUDIT", value: "Enabled", tint: .primary, detail: "Persistent local log"))
            }

            CardShell(fill: Color.pkCard, radius: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "RECENT TERMINATIONS", trailing: "LOCAL AUDIT LOG")
                    VStack(spacing: 10) {
                        ForEach(viewModel.historyFeed) { entry in
                            HistoryRowView(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

struct HistoryRowView: View {
    let entry: KillHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Circle()
                    .fill(Color.pkSecondary)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color.pkStroke.opacity(0.5))
                    .frame(width: 1, height: 34)
            }
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.processName) • Port \(entry.port)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text("PID \(entry.pid)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
                Text(entry.outcome)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.pkMuted.opacity(0.8))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkText.opacity(0.72))
                Text(entry.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.pkElevated)
        )
    }
}

struct ProFeaturesSectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @EnvironmentObject private var proStore: ProPurchaseManager
    @State private var ruleName = ""
    @State private var rulePort = ""
    @State private var ruleProcess = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            if proStore.isProUnlocked {
                ProUnlockedDashboardView(
                    ruleName: $ruleName,
                    rulePort: $rulePort,
                    ruleProcess: $ruleProcess
                )
                .environmentObject(viewModel)
                .environmentObject(proStore)
            } else {
                ProUpsellDashboardView()
                    .environmentObject(viewModel)
                    .environmentObject(proStore)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(proStore.isProUnlocked ? "Pro unlocked for this Mac" : "Precision Mastery for")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Color.pkText)
                Text(proStore.isProUnlocked ? "All premium controls are active." : "Professional Power Users")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Color.pkPrimary)
                Text(proStore.isProUnlocked ? "Advanced monitoring, automation, and sync tools are now available." : "Level up your local development environment with industrial-grade monitoring, automation, and analytics.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.pkMuted)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            Spacer()
        }
    }
}

struct ProUpsellDashboardView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @EnvironmentObject private var proStore: ProPurchaseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                FeatureCard(title: "Real-time Port Monitoring", subtitle: "Instant visual tracking of traffic spikes and socket status.", symbol: "chart.line.uptrend.xyaxis", tint: .primary)
                FeatureCard(title: "Custom Auto-Kill Scripts", subtitle: "Define rules that automatically terminate noisy ports and repeat offenders.", symbol: "terminal", tint: .secondary)
                FeatureCard(title: "Kill History", subtitle: "Full audit log of every killed process with local persistence.", symbol: "clock.arrow.circlepath", tint: .warning)
                FeatureCard(title: "Multi-Environment Sync", subtitle: "Export and import your saved port profile between Macs.", symbol: "airplane", tint: .primary)
            }

            CardShell(fill: Color.pkCard, radius: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Choose your Pro plan")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.pkText)
                        Spacer()
                        if proStore.isLoadingProducts {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                        ForEach(proStore.sortedProducts, id: \.id) { product in
                            ProProductCard(product: product)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await proStore.restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())

                        Button {
                            proStore.openManageSubscriptions()
                        } label: {
                            Text("Manage Subscription")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TertiaryActionButtonStyle())
                    }
                }
            }

            CardShell(fill: Color.pkSurface.opacity(0.78), radius: 16) {
                HStack(spacing: 18) {
                    Text("PRO INCLUDES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.pkMuted)
                    Spacer()
                    ForEach(["LIVE MONITORING", "AUTO-KILL", "SYNC"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.pkMuted.opacity(0.8))
                    }
                }
            }
        }
    }
}

struct ProUnlockedDashboardView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @EnvironmentObject private var proStore: ProPurchaseManager
    @Binding var ruleName: String
    @Binding var rulePort: String
    @Binding var ruleProcess: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(viewModel.proSnapshotMetrics) { metric in
                    MetricCardView(metric: metric)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "LIVE MONITORING", trailing: "PRO CONTROL")

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Auto refresh")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.pkText)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { viewModel.isAutoRefreshEnabled },
                                    set: { viewModel.setAutoRefreshEnabled($0) }
                                ))
                                .labelsHidden()
                            }

                            HStack {
                                Text("Refresh interval")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.pkText)
                                Spacer()
                                Text("\(Int(viewModel.refreshIntervalSeconds)) s")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.pkPrimary)
                            }

                            Slider(value: Binding(
                                get: { viewModel.refreshIntervalSeconds },
                                set: { viewModel.setRefreshIntervalSeconds($0) }
                            ), in: 3...60, step: 1)

                            HStack(spacing: 10) {
                                SecondaryActionButton(title: "Refresh Now", symbol: "arrow.clockwise") {
                                    viewModel.refresh()
                                }

                                SecondaryActionButton(title: "Open History", symbol: "clock.arrow.circlepath") {
                                    viewModel.setSection(.history)
                                }
                            }
                        }
                    }
                }

                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "AUTO-KILL RULES", trailing: "BACKGROUND ENFORCEMENT")

                        VStack(spacing: 10) {
                            TextField("Rule name", text: $ruleName)
                            TextField("Port contains", text: $rulePort)
                            TextField("Process contains", text: $ruleProcess)
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            viewModel.addAutoKillRule(name: ruleName, portQuery: rulePort, processQuery: ruleProcess)
                            ruleName = ""
                            rulePort = ""
                            ruleProcess = ""
                        } label: {
                            Text("Add Rule")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryActionButtonStyle())

                        VStack(spacing: 10) {
                            ForEach(viewModel.autoKillRules) { rule in
                                AutoKillRuleRow(rule: rule)
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "PROFILE SYNC", trailing: "EXPORT / IMPORT")
                        Text("Save your bookmarks, rules, refresh interval, and kill history to move the setup between machines.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.pkMuted)

                        HStack(spacing: 10) {
                            SecondaryActionButton(title: "Export Profile", symbol: "square.and.arrow.up") {
                                viewModel.exportProProfile()
                            }

                            SecondaryActionButton(title: "Import Profile", symbol: "square.and.arrow.down") {
                                viewModel.importProProfile()
                            }
                        }

                        HStack(spacing: 10) {
                            SecondaryActionButton(title: "Manage Subscription", symbol: "gearshape") {
                                proStore.openManageSubscriptions()
                            }

                            SecondaryActionButton(title: "Restore", symbol: "arrow.clockwise") {
                                Task { await proStore.restorePurchases() }
                            }
                        }
                    }
                }

                CardShell(fill: Color.pkCard, radius: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "PRO STATUS", trailing: "ENTITLEMENT")
                        Text("Unlocked on this Mac")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(Color.pkSecondary)
                        Text(proStore.statusMessage ?? "Active entitlement detected through StoreKit.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.pkMuted)

                        ComparisonTableView()
                    }
                }
            }
        }
    }
}

struct ProProductCard: View {
    let product: Product

    var body: some View {
        CardShell(fill: Color.pkElevated, radius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(product.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text(product.description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.pkMuted)
                Text(product.displayPrice)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.pkPrimary)
                Text(product.id.contains("monthly") ? "Best for short-term projects" : "Best value for long-term use")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkMuted.opacity(0.7))
            }
        }
    }
}

struct ProProductPurchaseCard: View {
    let product: Product
    let action: () -> Void

    var body: some View {
        CardShell(fill: Color.pkElevated, radius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(product.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text(product.description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.pkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(product.displayPrice)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.pkPrimary)

                Button(action: action) {
                    Text(product.id.contains("monthly") ? "Subscribe Now" : "Unlock Lifetime Pro")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
    }
}

struct AutoKillRuleRow: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let rule: AutoKillRule

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text(rule.summary)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
            }

            Spacer()

            Button {
                viewModel.toggleAutoKillRule(rule)
            } label: {
                Text(rule.isEnabled ? "Enabled" : "Disabled")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(rule.isEnabled ? Color.pkSecondary : Color.pkMuted)
                    .background(
                        Capsule(style: .continuous)
                            .fill(rule.isEnabled ? Color.pkSecondary.opacity(0.12) : Color.pkSurface)
                    )
            }
            .buttonStyle(.plain)

            Button {
                viewModel.removeAutoKillRule(rule)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.pkDangerText)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.pkDanger.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.pkSurface)
        )
    }
}

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: ColorToken

    var body: some View {
        CardShell(fill: Color.pkCard, radius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.token(tint))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.pkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 130, alignment: .topLeading)
    }
}

struct ComparisonTableView: View {
    private let rows: [(String, Bool, Bool)] = [
        ("Basic Process Termination", true, true),
        ("Listening Port Detection", true, true),
        ("Real-time Traffic Heatmap", false, true),
        ("Auto-Kill Rules engine", false, true),
        ("Log Persistence (30 Days)", false, true)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Capability")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Standard")
                    .frame(width: 100, alignment: .center)
                Text("Pro Tier")
                    .frame(width: 100, alignment: .center)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.pkMuted)
            .padding(.bottom, 10)

            ForEach(rows, id: \.0) { row in
                HStack(spacing: 12) {
                    Text(row.0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color.pkText)
                    CapabilityIndicator(isOn: row.1)
                        .frame(width: 100, alignment: .center)
                    CapabilityIndicator(isOn: row.2)
                        .frame(width: 100, alignment: .center)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 12)

                if row.0 != rows.last?.0 {
                    Divider().overlay(Color.pkStroke.opacity(0.4))
                }
            }
        }
    }
}

struct CapabilityIndicator: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle.fill")
            .foregroundStyle(isOn ? Color.pkSuccess : Color.pkMuted.opacity(0.55))
    }
}

struct PricingCard: View {
    let title: String
    let subtitle: String
    let price: String
    let footnote: String
    let buttonLabel: String
    let isFeatured: Bool
    let action: () -> Void

    var body: some View {
        CardShell(fill: isFeatured ? Color.pkElevated.opacity(0.95) : Color.pkCard, radius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                if isFeatured {
                    Text("BEST VALUE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.pkPrimary)
                }

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.pkMuted)
                Text(price)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Color.pkText)
                Text(footnote)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkMuted.opacity(0.7))

                if isFeatured {
                    Button(action: action) {
                        Text(buttonLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                } else {
                    Button(action: action) {
                        Text(buttonLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct AppStorePreviewView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @EnvironmentObject private var proStore: ProPurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.pkBackground, Color.pkBackground, Color.pkPrimary.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Label("PORT KILLER v2.4.0", systemImage: "shield.lefthalf.filled")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.pkSuccess)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                    .fill(Color.pkSuccess.opacity(0.08))
                            )

                        Text("Reclaim Your Ports.")
                            .font(.system(size: 58, weight: .black))
                            .foregroundStyle(Color.pkText)
                        Text("Instantly.")
                            .font(.system(size: 58, weight: .black))
                            .foregroundStyle(Color.pkPrimary)

                        Text("The ultimate surgical tool for developers. No more hunting for PIDs. One click to clear your development environment.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.pkMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 720)
                    }
                    .padding(.top, 20)

                    CardShell(fill: Color.pkElevated.opacity(0.7), radius: 26) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Port Killer")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.pkText)
                                Spacer()
                                Text("ACTIVE CONNECTIONS")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.pkPrimary)
                            }

                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                    MetricCardView(metric: DashboardMetric(title: "TOTAL PORTS", value: "14", tint: .primary, detail: "Listening sockets"))
                                    MetricCardView(metric: DashboardMetric(title: "MEMORY LOAD", value: "2.4 GB", tint: .secondary, detail: "Real-time footprint"))
                                }
                                .frame(width: 220)

                                CardShell(fill: Color.pkCard, radius: 18) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Network Traffic Heatmap")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color.pkMuted)
                                        HeatmapStripView(states: [.listening, .listening, .busy, .listening, .idle, .busy, .listening, .dormant])
                                            .frame(height: 180)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        FeatureBadge(title: "Kill processes safely", subtitle: "Advanced verification layer prevents errors", symbol: "shield.checkerboard")
                        FeatureBadge(title: "Pinned common ports", subtitle: "Keep your dev stack in easy reach", symbol: "pin.fill")
                        FeatureBadge(title: "Menu bar quick access", subtitle: "Kill ports without switching focus", symbol: "menubar.rectangle")
                    }

                    CardShell(fill: Color.pkCard, radius: 22) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(proStore.isProUnlocked ? "Pro is already unlocked" : "Choose your Pro plan")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.pkText)
                                Spacer()
                                if proStore.isLoadingProducts {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                                ForEach(proStore.sortedProducts, id: \.id) { product in
                                    ProProductPurchaseCard(product: product) {
                                        Task { await proStore.purchase(product) }
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                Button {
                                    Task { await proStore.restorePurchases() }
                                } label: {
                                    Text("Restore Purchases")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryActionButtonStyle())

                                Button {
                                    proStore.openManageSubscriptions()
                                } label: {
                                    Text("Manage Subscription")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(TertiaryActionButtonStyle())
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.pkText)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.pkElevated.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }
}

struct FeatureBadge: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        CardShell(fill: Color.pkCard, radius: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.pkPrimary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.pkMuted)
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @State private var page = 0

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "Instantly Detect Active Ports",
            subtitle: "Eliminate the lsof guesswork. Real-time visibility into every listening socket on your machine.",
            note: "Step 01 / 03"
        ),
        OnboardingStep(
            title: "Kill with Precision",
            subtitle: "See live PIDs, monitor usage, and terminate exactly the process you want with a single click.",
            note: "Step 02 / 03"
        ),
        OnboardingStep(
            title: "Unlock the Professional Layer",
            subtitle: "Pin common ports, automate guardrails, and keep your environment surgically clean.",
            note: "Step 03 / 03"
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.pkBackground, Color.pkBackground, Color.pkPrimary.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Text("PORT KILLER")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(Color.pkText)
                    Spacer()
                }
                .padding(.top, 18)

                Text(steps[page].note)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.pkPrimary.opacity(0.08))
                    )

                VStack(spacing: 14) {
                    Text(steps[page].title)
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(Color.pkText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 680)

                    Text(steps[page].subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.pkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 760)
                }

                CardShell(fill: Color.pkCard, radius: 26) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("12 Ports Listening")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.pkText)
                            VStack(alignment: .leading, spacing: 8) {
                                OnboardingBullet(symbol: "waveform.path.ecg") {
                                    Text("Track live sockets with one glance")
                                }
                                OnboardingBullet(symbol: "bolt.fill") {
                                    Text("Kill noisy processes without context switching")
                                }
                                OnboardingBullet(symbol: "star.fill") {
                                    Text("Save the ports you use every day")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        CardShell(fill: Color.pkElevated, radius: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("SYSTEM SNAPSHOT")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.pkMuted)
                                VStack(spacing: 8) {
                                    ForEach(viewModel.visiblePorts.prefix(3)) { port in
                                        HStack {
                                            Text(port.port)
                                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                .foregroundStyle(Color.pkPrimary)
                                            Spacer()
                                            Text(port.processName)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Color.pkText)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 300)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            page = max(0, page - 1)
                        }
                    } label: {
                        Text("Skip")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button {
                        if page < steps.count - 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                page += 1
                            }
                        } else {
                            viewModel.completeOnboarding()
                        }
                    } label: {
                        Text(page < steps.count - 1 ? "Next Step" : "Get Started")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }

                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(index == page ? Color.pkPrimary : Color.pkStroke)
                            .frame(width: index == page ? 32 : 20, height: 4)
                    }
                }
                .padding(.top, 4)
            }
            .padding(26)
            .frame(maxWidth: 980)
        }
    }
}

struct OnboardingStep {
    let title: String
    let subtitle: String
    let note: String
}

struct OnboardingBullet<Content: View>: View {
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.pkSecondary)
                .frame(width: 16)
            content()
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.pkText)
            Spacer(minLength: 0)
        }
    }
}

struct MenuBarPopoverView: View {
    @EnvironmentObject private var viewModel: PortViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                HStack {
                    Text("Port Killer")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.pkText)
                    Spacer()
                    HeaderIconButton(systemName: "clock.arrow.circlepath") {
                        viewModel.setSection(.history)
                    }
                    .frame(width: 22, height: 22)
                    HeaderIconButton(systemName: "line.3.horizontal.decrease.circle") {
                        viewModel.refresh()
                    }
                    .frame(width: 22, height: 22)
                    HeaderIconButton(systemName: "arrow.clockwise") {
                        viewModel.refresh()
                    }
                    .frame(width: 22, height: 22)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.pkSurface.opacity(0.9))

                VStack(spacing: 10) {
                    SearchBar(text: $viewModel.searchText, placeholder: "Search ports or PIDs...")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("SYSTEM ACTIVITY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.pkMuted)
                            Spacer()
                            Text(viewModel.visiblePorts.isEmpty ? "STANDBY" : "HEALTHY")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(viewModel.visiblePorts.isEmpty ? Color.pkMuted : Color.pkSecondary)
                        }
                        HeatmapStripView(states: viewModel.activityHeatmapState)
                            .frame(height: 10)
                    }
                    .padding(.top, 4)
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
                        ForEach(viewModel.visiblePorts) { port in
                            MenuPortRowView(port: port)
                                .environmentObject(viewModel)
                        }
                    }
                }
                .background(Color.pkElevated.opacity(0.55))

                VStack(spacing: 10) {
                    Button {
                        viewModel.killSelectedPorts()
                    } label: {
                        Text("Kill All High Usage")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())

                    Button {
                        dismiss()
                        openWindow(id: "main")
                        NSApplication.shared.activate(ignoringOtherApps: true)
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
    }
}

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

            Button {
                viewModel.killProcess(pid: port.pid, port: port)
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

struct HeatmapStripView: View {
    let states: [PortState]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(for: state))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for state: PortState) -> Color {
        switch state {
        case .listening: return Color.pkSecondary
        case .busy: return Color.pkWarning
        case .idle: return Color.pkMuted.opacity(0.38)
        case .dormant: return Color.pkSurface
        }
    }
}

struct QuickActionCard: View {
    let action: QuickAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.pkText)
                    Text(action.subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.pkMuted)
                }
                Spacer()
                Image(systemName: action.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.pkPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.pkSurface)
                    )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.pkElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.pkStroke.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MetricCardView: View {
    let metric: DashboardMetric

    var body: some View {
        CardShell(fill: Color.pkCard, radius: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(metric.title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkMuted.opacity(0.7))
                Text(metric.value)
                    .font(.system(size: 28, weight: .black, design: .default))
                    .foregroundStyle(Color.token(metric.tint))
                Text(metric.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.pkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 90, alignment: .topLeading)
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

struct SectionHeading: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pkMuted.opacity(0.72))
            }
            Spacer()
        }
    }
}

struct CardShell<Content: View>: View {
    let fill: Color
    let radius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(fill: Color, radius: CGFloat, padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.fill = fill
        self.radius = radius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.pkStroke.opacity(0.55), lineWidth: 1)
                    )
            )
    }
}

struct PortThumbnailView: View {
    let port: PortItem
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let icon = port.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.6, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(Color.pkPrimary)
        .background(
            RoundedRectangle(cornerRadius: max(6, size * 0.25), style: .continuous)
                .fill(Color.pkSurface)
        )
    }

    private var fallbackSymbol: String {
        switch port.processName.lowercased() {
        case let name where name.contains("postgre"): return "cylinder.split.1x2"
        case let name where name.contains("redis"): return "cube.box.fill"
        case let name where name.contains("python"): return "chevron.left.forwardslash.chevron.right"
        case let name where name.contains("nginx"): return "network"
        default: return "terminal.fill"
        }
    }
}

struct StatusPill: View {
    let state: PortState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(state.displayTitle)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(accent)
        .background(
            Capsule(style: .continuous)
                .fill(accent.opacity(0.12))
        )
    }

    private var accent: Color {
        switch state {
        case .listening: return Color.pkSecondary
        case .busy: return Color.pkWarning
        case .idle: return Color.pkMuted
        case .dormant: return Color.pkStroke
        }
    }
}

struct SecondaryActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryActionButtonStyle())
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkText)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkElevated.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pkStroke.opacity(0.5), lineWidth: 1)
            )
    }
}

struct TertiaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkMuted)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pkStroke.opacity(0.45), lineWidth: 1)
            )
    }
}

struct DangerActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkDangerText)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkDanger.opacity(configuration.isPressed ? 0.22 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pkDanger.opacity(0.7), lineWidth: 1)
            )
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.vertical, 12)
            .foregroundStyle(Color.pkOnPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pkPrimary.opacity(configuration.isPressed ? 0.84 : 1))
            )
    }
}

extension Color {
    static let pkBackground = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let pkSurface = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let pkSidebar = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let pkCard = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let pkElevated = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let pkStroke = Color(red: 0.24, green: 0.25, blue: 0.28)
    static let pkMuted = Color(red: 0.71, green: 0.73, blue: 0.78)
    static let pkText = Color(red: 0.91, green: 0.91, blue: 0.92)
    static let pkPrimary = Color(red: 0.52, green: 0.68, blue: 1.00)
    static let pkOnPrimary = Color(red: 0.00, green: 0.16, blue: 0.36)
    static let pkSuccess = Color(red: 0.30, green: 0.87, blue: 0.40)
    static let pkSecondary = Color(red: 0.30, green: 0.87, blue: 0.40)
    static let pkWarning = Color(red: 1.00, green: 0.70, blue: 0.65)
    static let pkDanger = Color(red: 0.68, green: 0.02, blue: 0.08)
    static let pkDangerText = Color(red: 1.00, green: 0.85, blue: 0.84)

    static func token(_ token: ColorToken) -> Color {
        switch token {
        case .primary: return pkPrimary
        case .secondary: return pkSecondary
        case .warning: return pkWarning
        case .danger: return pkDangerText
        case .neutral: return pkText
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PortViewModel())
        .environmentObject(ProPurchaseManager())
        .frame(width: 1360, height: 960)
}

#Preview("Menu Bar") {
    MenuBarPopoverView()
        .environmentObject(PortViewModel())
}
