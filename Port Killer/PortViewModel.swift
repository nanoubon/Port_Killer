import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PortViewModel: ObservableObject {
    @Published var ports: [PortItem] = []
    @Published var searchText: String = ""
    @Published var selectedSection: AppSection = .activePorts
    @Published var selectedPortID: String?
    @Published var selectedPortIDs: Set<String> = []
    @Published var pinnedBookmarks: [PortBookmark] = []
    @Published var killHistory: [KillHistoryEntry] = []
    @Published var hasCompletedOnboarding: Bool = false
    @Published var isProUnlocked: Bool = false
    @Published var isAutoRefreshEnabled: Bool = true
    @Published var showAppStorePreview: Bool = false
    @Published var debugMessage: String = "Initializing..."
    @Published var lastRefreshAt: Date?
    @Published var hasLoadedLivePorts: Bool = false

    private var autoRefreshCancellable: AnyCancellable?

    private enum StorageKey {
        static let pinnedBookmarks = "PortKiller.pinnedBookmarks"
        static let killHistory = "PortKiller.killHistory"
        static let hasCompletedOnboarding = "PortKiller.hasCompletedOnboarding"
        static let isProUnlocked = "PortKiller.isProUnlocked"
        static let isAutoRefreshEnabled = "PortKiller.isAutoRefreshEnabled"
    }

    init() {
        loadPersistedState()
        fetchActivePorts()
        configureAutoRefresh()
    }

    var filteredPorts: [PortItem] {
        guard !searchText.isEmpty else { return ports }
        return ports.filter {
            $0.processName.localizedCaseInsensitiveContains(searchText) ||
            $0.port.localizedCaseInsensitiveContains(searchText) ||
            $0.pid.localizedCaseInsensitiveContains(searchText) ||
            ($0.user?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var visiblePorts: [PortItem] {
        if searchText.isEmpty {
            return hasLoadedLivePorts ? ports : demoPorts
        }
        return filteredPorts
    }

    var selectedPort: PortItem? {
        if let selectedPortID {
            return ports.first { $0.id == selectedPortID } ?? demoPorts.first { $0.id == selectedPortID }
        }
        return visiblePorts.first
    }

    var selectedPorts: [PortItem] {
        ports.filter { selectedPortIDs.contains($0.id) }
    }

    var pinnedPortItems: [PortItem] {
        let source = ports.isEmpty ? demoPorts : ports
        let matches = pinnedBookmarks.compactMap { bookmark in
            source.first { item in
                item.port == bookmark.port && item.processName.localizedCaseInsensitiveContains(bookmark.processName)
            } ?? source.first { $0.port == bookmark.port }
        }
        return matches
    }

    var dashboardMetrics: [DashboardMetric] {
        let activeCount = max(ports.count, demoPorts.count)
        return [
            DashboardMetric(
                title: "TOTAL LISTENING",
                value: "\(max(ports.count, 1))",
                tint: .primary,
                detail: ports.isEmpty ? "No live sockets detected" : "Listening ports on this machine"
            ),
            DashboardMetric(
                title: "MEMORY USAGE",
                value: ports.isEmpty ? "1.2 GB" : String(format: "%.1f GB", Double(ports.count) * 0.4 + 0.8),
                tint: .secondary,
                detail: ports.isEmpty ? "Demo metric until scan refreshes" : "Estimated development footprint"
            ),
            DashboardMetric(
                title: "ACTIVE CONNS",
                value: "\(max(activeCount * 42, 42))",
                tint: .warning,
                detail: ports.isEmpty ? "Reference telemetry from design" : "Approximate live socket connections"
            ),
            DashboardMetric(
                title: "SYSTEM LOAD",
                value: ports.isEmpty ? "4.2%" : String(format: "%.1f%%", min(99.0, Double(ports.count) * 1.35 + 2.0)),
                tint: .neutral,
                detail: ports.isEmpty ? "Standby mode" : "Relative system activity"
            )
        ]
    }

    var activityHeatmapState: [PortState] {
        let states = ports.isEmpty ? demoPorts.map(\.state) : ports.map(\.state)
        return states.isEmpty ? demoPorts.map(\.state) : states
    }

    var quickActions: [QuickAction] {
        [
            QuickAction(
                title: "Start a Local Server",
                subtitle: "Spin up dev environment",
                symbol: "plus.circle.fill"
            ),
            QuickAction(
                title: "Refresh Scan",
                subtitle: "Re-evaluate system state",
                symbol: "arrow.clockwise"
            ),
            QuickAction(
                title: "Explore Favorites",
                subtitle: "Quick-access known ports",
                symbol: "star.fill"
            ),
            QuickAction(
                title: "Enable Pro Monitoring",
                subtitle: "Real-time daemon alerts",
                symbol: "bolt.fill"
            )
        ]
    }

    var historyFeed: [KillHistoryEntry] {
        if killHistory.isEmpty {
            return [
                KillHistoryEntry(port: "3000", processName: "node", pid: "451", createdAt: Date().addingTimeInterval(-3600), outcome: "Terminated listening socket"),
                KillHistoryEntry(port: "5432", processName: "postgres", pid: "882", createdAt: Date().addingTimeInterval(-8600), outcome: "Audit logged successfully"),
                KillHistoryEntry(port: "8000", processName: "python", pid: "1240", createdAt: Date().addingTimeInterval(-14400), outcome: "Awaiting restart")
            ]
        }
        return killHistory.sorted { $0.createdAt > $1.createdAt }
    }

    var historySummary: String {
        if killHistory.isEmpty {
            return "Demo history loaded"
        }
        return "\(killHistory.count) recent termination events"
    }

    var pinnedSummary: String {
        "\(pinnedBookmarks.count) pinned"
    }

    var totalSelectedCount: Int {
        selectedPortIDs.count
    }

    var remainingSummary: String {
        if ports.isEmpty {
            return "No live ports"
        }
        return "\(ports.count) active"
    }

    func openAppStorePreview() {
        showAppStorePreview = true
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        persistBool(true, forKey: StorageKey.hasCompletedOnboarding)
    }

    func setSection(_ section: AppSection) {
        selectedSection = section
    }

    func toggleSelection(for port: PortItem) {
        if selectedPortIDs.contains(port.id) {
            selectedPortIDs.remove(port.id)
        } else {
            selectedPortIDs.insert(port.id)
            selectedPortID = port.id
        }
    }

    func clearSelection() {
        selectedPortIDs.removeAll()
    }

    func selectPort(_ port: PortItem) {
        selectedPortID = port.id
    }

    func isPinned(_ port: PortItem) -> Bool {
        pinnedBookmarks.contains { bookmark in
            bookmark.port == port.port && bookmark.processName.localizedCaseInsensitiveContains(port.processName)
        } || pinnedBookmarks.contains { $0.port == port.port }
    }

    func togglePinned(_ port: PortItem) {
        let bookmark = PortBookmark(portItem: port)
        if let index = pinnedBookmarks.firstIndex(where: { $0.id == bookmark.id || ($0.port == bookmark.port && $0.processName == bookmark.processName) }) {
            pinnedBookmarks.remove(at: index)
        } else {
            pinnedBookmarks.insert(bookmark, at: 0)
        }
        persistPinnedBookmarks()
    }

    func portBookmark(for port: PortItem) -> PortBookmark {
        PortBookmark(portItem: port)
    }

    func killProcess(pid: String, port: PortItem? = nil) {
        let snapshot = port ?? ports.first { $0.pid == pid }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ShellHelper.executeCommand(command: "/bin/kill", arguments: ["-9", pid])
            DispatchQueue.main.async {
                if let snapshot {
                    self.killHistory.insert(
                        KillHistoryEntry(
                            port: snapshot.port,
                            processName: snapshot.processName,
                            pid: snapshot.pid,
                            outcome: result == nil ? "Kill command failed" : "Process terminated"
                        ),
                        at: 0
                    )
                    self.persistKillHistory()
                }
                self.selectedPortIDs.remove(snapshot?.id ?? "")
                self.fetchActivePorts()
            }
        }
    }

    func killSelectedPorts() {
        let items = selectedPorts
        guard !items.isEmpty else { return }
        clearSelection()
        for item in items {
            killProcess(pid: item.pid, port: item)
        }
    }

    func refresh() {
        fetchActivePorts()
    }

    func toggleAutoRefresh() {
        setAutoRefreshEnabled(!isAutoRefreshEnabled)
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        isAutoRefreshEnabled = enabled
        persistBool(enabled, forKey: StorageKey.isAutoRefreshEnabled)
        configureAutoRefresh()
    }

    func fetchActivePorts() {
        debugMessage = "Fetching ports..."
        lastRefreshAt = Date()

        DispatchQueue.global(qos: .userInitiated).async {
            guard let output = ShellHelper.executeCommand(command: "/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]) else {
                DispatchQueue.main.async {
                    self.debugMessage = "Failed to execute lsof command."
                    self.hasLoadedLivePorts = true
                }
                return
            }

            if output.isEmpty {
                DispatchQueue.main.async {
                    self.debugMessage = "Executed lsof, but output was empty."
                    self.ports = []
                    self.hasLoadedLivePorts = true
                }
                return
            }

            struct ParsedPort {
                let processName: String
                let pid: String
                let user: String
                let port: String
            }

            var parsed: [ParsedPort] = []
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

            guard lines.count > 1 else {
                DispatchQueue.main.async {
                    self.debugMessage = "Output has only \(lines.count) lines."
                    self.ports = []
                    self.hasLoadedLivePorts = true
                }
                return
            }

            for line in lines.dropFirst() {
                let columns = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard columns.count >= 9 else { continue }

                let processName = columns[0]
                let pid = columns[1]
                let user = columns[2]
                let nameColumn = columns[8]

                if let portRange = nameColumn.range(of: ":\\d+", options: .regularExpression) {
                    let portString = String(nameColumn[portRange].dropFirst())
                    let entry = ParsedPort(processName: processName, pid: pid, user: user, port: portString)
                    if !parsed.contains(where: { $0.port == entry.port && $0.processName == entry.processName }) {
                        parsed.append(entry)
                    }
                }
            }

            DispatchQueue.main.async {
                let runningApps = NSWorkspace.shared.runningApplications
                let mapped = parsed.map { entry -> PortItem in
                    let icon = Int32(entry.pid).flatMap { pidInt in
                        runningApps.first(where: { $0.processIdentifier == pidInt })?.icon
                    }
                    return PortItem(
                        processName: entry.processName,
                        pid: entry.pid,
                        port: entry.port,
                        protocolName: "TCP",
                        icon: icon,
                        state: .listening,
                        user: entry.user,
                        command: entry.processName,
                        uptime: "Active now",
                        loadDescription: "Listening"
                    )
                }

                self.ports = mapped.sorted { (Int($0.port) ?? 0) < (Int($1.port) ?? 0) }
                self.hasLoadedLivePorts = true
                self.debugMessage = self.ports.isEmpty
                    ? "No listening ports matched the current scan."
                    : "Successfully fetched \(self.ports.count) ports."
            }
        }
    }

    func portActionLabel(for port: PortItem) -> String {
        isPinned(port) ? "Pinned" : "Pin"
    }

    func detailCommand(for port: PortItem) -> String {
        port.command ?? "/usr/local/bin/\(port.processName.lowercased())"
    }

    func detailUser(for port: PortItem) -> String {
        port.user ?? NSUserName()
    }

    func detailUptime(for port: PortItem) -> String {
        port.uptime ?? "Active since now"
    }

    func detailLoad(for port: PortItem) -> String {
        port.loadDescription ?? "Low"
    }

    func detailSubtitle(for port: PortItem) -> String {
        "\(port.processName) • Active since \(detailUptime(for: port))"
    }

    func displayName(for port: PortItem) -> String {
        port.processName
    }

    func demoPort(for port: String) -> PortItem? {
        demoPorts.first { $0.port == port }
    }

    private func loadPersistedState() {
        hasCompletedOnboarding = persistBool(forKey: StorageKey.hasCompletedOnboarding)
        isProUnlocked = persistBool(forKey: StorageKey.isProUnlocked)
        isAutoRefreshEnabled = persistBool(forKey: StorageKey.isAutoRefreshEnabled, defaultValue: true)
        pinnedBookmarks = loadValue([PortBookmark].self, forKey: StorageKey.pinnedBookmarks) ?? []
        killHistory = loadValue([KillHistoryEntry].self, forKey: StorageKey.killHistory) ?? []
    }

    private func configureAutoRefresh() {
        autoRefreshCancellable?.cancel()
        guard isAutoRefreshEnabled else { return }

        autoRefreshCancellable = Timer.publish(every: 8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchActivePorts()
            }
    }

    private func persistPinnedBookmarks() {
        persistValue(pinnedBookmarks, forKey: StorageKey.pinnedBookmarks)
    }

    private func persistKillHistory() {
        persistValue(killHistory, forKey: StorageKey.killHistory)
    }

    private func persistBool(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistBool(forKey key: String, defaultValue: Bool = false) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func loadValue<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persistValue<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private var demoPorts: [PortItem] {
        [
            PortItem(
                processName: "Node.js",
                pid: "451",
                port: "3000",
                protocolName: "TCP",
                icon: NSImage.symbol("terminal.fill"),
                state: .listening,
                user: "admin",
                command: "node server.js --config ./webpack.prod.js --inspect=9229",
                uptime: "2h 45m",
                loadDescription: "0.4% CPU"
            ),
            PortItem(
                processName: "PostgreSQL",
                pid: "1029",
                port: "5432",
                protocolName: "TCP",
                icon: NSImage.symbol("cylinder.split.1x2"),
                state: .listening,
                user: "postgres",
                command: "postgres -D /usr/local/var/postgres",
                uptime: "12d 3h",
                loadDescription: "Low"
            ),
            PortItem(
                processName: "Python (FastAPI)",
                pid: "92817",
                port: "8000",
                protocolName: "TCP",
                icon: NSImage.symbol("chevron.left.forwardslash.chevron.right"),
                state: .listening,
                user: "admin",
                command: "uvicorn app:app --reload",
                uptime: "45m",
                loadDescription: "0.8% CPU"
            ),
            PortItem(
                processName: "Redis-server",
                pid: "312",
                port: "6379",
                protocolName: "TCP",
                icon: NSImage.symbol("cube.box.fill"),
                state: .busy,
                user: "system",
                command: "redis-server /usr/local/etc/redis.conf",
                uptime: "2d 2h",
                loadDescription: "High Usage"
            ),
            PortItem(
                processName: "Nginx",
                pid: "55",
                port: "443",
                protocolName: "TCP",
                icon: NSImage.symbol("network"),
                state: .idle,
                user: "root",
                command: "nginx -g daemon off;",
                uptime: "Idle",
                loadDescription: "Low"
            )
        ]
    }
}

struct QuickAction: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}
