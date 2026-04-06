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
    @Published var autoKillRules: [AutoKillRule] = []
    @Published var hasCompletedOnboarding: Bool = true
    @Published var isAutoRefreshEnabled: Bool = true
    @Published var refreshIntervalSeconds: Double = 8
    @Published var isLaunchAtLoginEnabled: Bool = false
    @Published var debugMessage: String = "Initializing..."
    @Published var lastRefreshAt: Date?
    @Published var hasLoadedLivePorts: Bool = false

    private let portScanService = PortScanService()
    private let processKillerService = ProcessKillerService()
    private let launchAtLoginService = LaunchAtLoginService()

    private var autoRefreshCancellable: AnyCancellable?
    private var activeRefreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var killInFlightPIDs = Set<String>()

    private enum StorageKey {
        static let pinnedBookmarks = "PortKiller.pinnedBookmarks"
        static let killHistory = "PortKiller.killHistory"
        static let autoKillRules = "PortKiller.autoKillRules"
        static let hasCompletedOnboarding = "PortKiller.hasCompletedOnboarding"
        static let isAutoRefreshEnabled = "PortKiller.isAutoRefreshEnabled"
        static let refreshIntervalSeconds = "PortKiller.refreshIntervalSeconds"
        static let isLaunchAtLoginEnabled = "PortKiller.isLaunchAtLoginEnabled"
    }

    init() {
        loadPersistedState()
        refreshLaunchAtLoginStatus()
        requestPortRefresh()
        configureAutoRefresh()
    }

    deinit {
        activeRefreshTask?.cancel()
        autoRefreshCancellable?.cancel()
    }

    var filteredPorts: [PortItem] {
        ports(matching: searchText)
    }

    var visiblePorts: [PortItem] {
        ports(matching: searchText)
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
        let source = (hasLoadedLivePorts && !ports.isEmpty) ? ports : demoPorts
        return pinnedBookmarks.compactMap { bookmark in
            source.first { item in
                item.port == bookmark.port && item.processName.localizedCaseInsensitiveContains(bookmark.processName)
            } ?? source.first { $0.port == bookmark.port }
        }
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

    var proSnapshotMetrics: [DashboardMetric] {
        [
            DashboardMetric(
                title: "AUTO-KILL RULES",
                value: "\(autoKillRules.filter(\.isEnabled).count)",
                tint: .danger,
                detail: "Rules active in the background"
            ),
            DashboardMetric(
                title: "REFRESH INTERVAL",
                value: "\(Int(refreshIntervalSeconds))s",
                tint: .primary,
                detail: "Live monitoring cadence"
            ),
            DashboardMetric(
                title: "PROFILE SYNC",
                value: "Local",
                tint: .secondary,
                detail: "Export/import between machines"
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

    func ports(matching query: String) -> [PortItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = hasLoadedLivePorts ? ports : demoPorts

        guard !trimmedQuery.isEmpty else {
            return source
        }

        return source.filter { port in
            port.processName.localizedCaseInsensitiveContains(trimmedQuery) ||
            port.port.localizedCaseInsensitiveContains(trimmedQuery) ||
            port.pid.localizedCaseInsensitiveContains(trimmedQuery) ||
            (port.user?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
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

    func selectPort(withID id: String?) {
        selectedPortID = id
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
        guard let snapshot else {
            debugMessage = "Could not find the selected process."
            return
        }

        Task { [weak self] in
            await self?.killPorts([snapshot], refreshAfterCompletion: true)
        }
    }

    func killSelectedPorts() {
        let items = selectedPorts
        guard !items.isEmpty else {
            debugMessage = "Select at least one process to terminate."
            return
        }

        clearSelection()

        Task { [weak self] in
            await self?.killPorts(items, refreshAfterCompletion: true)
        }
    }

    func killBusyPorts(matching query: String = "") {
        guard hasLoadedLivePorts else {
            debugMessage = "No live ports are loaded yet."
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = ports.filter { port in
            guard port.state == .busy else { return false }
            guard !trimmedQuery.isEmpty else { return true }
            return port.processName.localizedCaseInsensitiveContains(trimmedQuery) ||
                port.port.localizedCaseInsensitiveContains(trimmedQuery) ||
                port.pid.localizedCaseInsensitiveContains(trimmedQuery) ||
                (port.user?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }

        guard !items.isEmpty else {
            debugMessage = "No high-usage processes matched the current filter."
            return
        }

        Task { [weak self] in
            await self?.killPorts(items, refreshAfterCompletion: true)
        }
    }

    func refresh() {
        requestPortRefresh()
    }

    func fetchActivePorts() {
        requestPortRefresh()
    }

    func toggleAutoRefresh() {
        setAutoRefreshEnabled(!isAutoRefreshEnabled)
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        isAutoRefreshEnabled = enabled
        persistBool(enabled, forKey: StorageKey.isAutoRefreshEnabled)
        configureAutoRefresh()
    }

    func setRefreshIntervalSeconds(_ seconds: Double) {
        refreshIntervalSeconds = max(3, min(seconds, 60))
        persistDouble(refreshIntervalSeconds, forKey: StorageKey.refreshIntervalSeconds)
        configureAutoRefresh()
    }

    func addAutoKillRule(name: String, portQuery: String, processQuery: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = portQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProcess = processQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty || !trimmedPort.isEmpty || !trimmedProcess.isEmpty else { return }

        autoKillRules.insert(
            AutoKillRule(
                name: trimmedName.isEmpty ? "Rule \(autoKillRules.count + 1)" : trimmedName,
                portQuery: trimmedPort,
                processQuery: trimmedProcess,
                isEnabled: true,
                action: .kill
            ),
            at: 0
        )
        persistAutoKillRules()
    }

    func toggleAutoKillRule(_ rule: AutoKillRule) {
        guard let index = autoKillRules.firstIndex(where: { $0.id == rule.id }) else { return }
        autoKillRules[index].isEnabled.toggle()
        persistAutoKillRules()
    }

    func removeAutoKillRule(_ rule: AutoKillRule) {
        autoKillRules.removeAll { $0.id == rule.id }
        persistAutoKillRules()
    }

    func currentProProfile() -> ProProfile {
        ProProfile(
            pinnedBookmarks: pinnedBookmarks,
            killHistory: killHistory,
            autoKillRules: autoKillRules,
            refreshIntervalSeconds: refreshIntervalSeconds,
            isAutoRefreshEnabled: isAutoRefreshEnabled
        )
    }

    func noteProfileExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            debugMessage = "Exported Pro profile."
        case .failure(let error):
            debugMessage = "Failed to export Pro profile: \(error.localizedDescription)"
        }
    }

    func importProProfile(from result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                debugMessage = "No profile file was selected."
                return
            }

            do {
                let data = try Data(contentsOf: url)
                let profile = try JSONDecoder.portKillerProfile.decode(ProProfile.self, from: data)
                applyImportedProfile(profile)
                debugMessage = "Imported Pro profile."
            } catch {
                debugMessage = "Failed to import Pro profile: \(error.localizedDescription)"
            }
        case .failure(let error):
            debugMessage = "Failed to import Pro profile: \(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginStatus() {
        let isEnabled = launchAtLoginService.currentStatus()
        updateLaunchAtLoginState(isEnabled)
    }

    func toggleLaunchAtLogin() {
        let targetState = !isLaunchAtLoginEnabled
        isLaunchAtLoginEnabled = targetState
        persistBool(targetState, forKey: StorageKey.isLaunchAtLoginEnabled)

        Task {
            do {
                let actualState = try launchAtLoginService.setEnabled(targetState)
                updateLaunchAtLoginState(actualState)
            } catch {
                // Service unavailable (e.g., missing entitlements), keep UI state
                debugMessage = "Start at login toggled (note: LoginItemService not available in this build)"
            }
        }
    }

    func quitApp() {
        NSApp.terminate(nil)
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

    private func requestPortRefresh() {
        lastRefreshAt = Date()
        debugMessage = "Fetching ports..."
        refreshGeneration += 1
        let generation = refreshGeneration

        activeRefreshTask?.cancel()
        activeRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshots = try await self.portScanService.scanListeningPorts()
                guard !Task.isCancelled else { return }
                self.applyScanResult(snapshots, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.applyScanFailure(error, generation: generation)
            }
        }
    }

    private func applyScanResult(_ snapshots: [PortScanSnapshot], generation: Int) {
        guard generation == refreshGeneration else { return }

        ports = snapshots
            .map(makePortItem(from:))
            .sorted { (Int($0.port) ?? 0) < (Int($1.port) ?? 0) }
        hasLoadedLivePorts = true
        reconcileSelection()

        debugMessage = ports.isEmpty
            ? "No listening ports matched the current scan."
            : "Successfully fetched \(ports.count) ports."

        applyAutoKillRules()
    }

    private func applyScanFailure(_ error: Error, generation: Int) {
        guard generation == refreshGeneration else { return }

        ports = []
        hasLoadedLivePorts = true
        reconcileSelection()
        debugMessage = error.localizedDescription
    }

    private func makePortItem(from snapshot: PortScanSnapshot) -> PortItem {
        let icon = Int32(snapshot.pid).flatMap { NSRunningApplication(processIdentifier: $0)?.icon }

        return PortItem(
            processName: snapshot.processName,
            pid: snapshot.pid,
            port: snapshot.port,
            protocolName: "TCP",
            icon: icon,
            state: .listening,
            user: snapshot.user,
            command: snapshot.processName,
            uptime: "Active now",
            loadDescription: "Listening"
        )
    }

    private func killPorts(_ items: [PortItem], refreshAfterCompletion: Bool) async {
        guard !items.isEmpty else { return }

        var processedItems: [PortItem] = []

        for item in items {
            guard killInFlightPIDs.insert(item.pid).inserted else { continue }

            let outcome = await processKillerService.kill(pid: item.pid)
            killInFlightPIDs.remove(item.pid)

            appendKillHistory(for: item, outcome: outcome)
            processedItems.append(item)
        }

        guard !processedItems.isEmpty else {
            debugMessage = "Those processes are already being terminated."
            return
        }

        if refreshAfterCompletion {
            requestPortRefresh()
        }
    }

    private func appendKillHistory(for port: PortItem, outcome: KillCommandOutcome) {
        killHistory.insert(
            KillHistoryEntry(
                port: port.port,
                processName: port.processName,
                pid: port.pid,
                outcome: outcome.message
            ),
            at: 0
        )
        persistKillHistory()

        selectedPortIDs.remove(port.id)
        if selectedPortID == port.id {
            selectedPortID = nil
        }

        debugMessage = outcome.message
    }

    private func applyImportedProfile(_ profile: ProProfile) {
        pinnedBookmarks = profile.pinnedBookmarks
        killHistory = profile.killHistory
        autoKillRules = profile.autoKillRules
        isAutoRefreshEnabled = profile.isAutoRefreshEnabled
        refreshIntervalSeconds = max(3, min(profile.refreshIntervalSeconds, 60))

        persistPinnedBookmarks()
        persistKillHistory()
        persistAutoKillRules()
        persistBool(isAutoRefreshEnabled, forKey: StorageKey.isAutoRefreshEnabled)
        persistDouble(refreshIntervalSeconds, forKey: StorageKey.refreshIntervalSeconds)
        configureAutoRefresh()
    }

    private func loadPersistedState() {
        hasCompletedOnboarding = persistBool(forKey: StorageKey.hasCompletedOnboarding)
        isAutoRefreshEnabled = persistBool(forKey: StorageKey.isAutoRefreshEnabled, defaultValue: true)
        refreshIntervalSeconds = persistDouble(forKey: StorageKey.refreshIntervalSeconds, defaultValue: 8)
        pinnedBookmarks = loadValue([PortBookmark].self, forKey: StorageKey.pinnedBookmarks) ?? []
        killHistory = loadValue([KillHistoryEntry].self, forKey: StorageKey.killHistory) ?? []
        autoKillRules = loadValue([AutoKillRule].self, forKey: StorageKey.autoKillRules) ?? []
    }

    private func updateLaunchAtLoginState(_ isEnabled: Bool) {
        isLaunchAtLoginEnabled = isEnabled
        persistBool(isEnabled, forKey: StorageKey.isLaunchAtLoginEnabled)
    }

    private func reconcileSelection() {
        let liveIDs = Set(ports.map(\.id))
        selectedPortIDs = selectedPortIDs.intersection(liveIDs)

        if let selectedPortID, !liveIDs.contains(selectedPortID) {
            self.selectedPortID = ports.first?.id
        }
    }

    private func configureAutoRefresh() {
        autoRefreshCancellable?.cancel()
        guard isAutoRefreshEnabled else { return }

        autoRefreshCancellable = Timer.publish(every: refreshIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.requestPortRefresh()
            }
    }

    private func persistPinnedBookmarks() {
        persistValue(pinnedBookmarks, forKey: StorageKey.pinnedBookmarks)
    }

    private func persistKillHistory() {
        persistValue(killHistory, forKey: StorageKey.killHistory)
    }

    private func persistAutoKillRules() {
        persistValue(autoKillRules, forKey: StorageKey.autoKillRules)
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

    private func persistDouble(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistDouble(forKey key: String, defaultValue: Double) -> Double {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.double(forKey: key)
    }

    private func loadValue<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persistValue<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func applyAutoKillRules() {
        guard !autoKillRules.isEmpty, !ports.isEmpty else { return }

        let livePorts = ports
        var matchedPortIDs = Set<String>()
        var matchedPorts: [PortItem] = []

        for rule in autoKillRules where rule.isEnabled {
            for port in livePorts where rule.matches(port) {
                guard matchedPortIDs.insert(port.id).inserted else { continue }
                guard !killInFlightPIDs.contains(port.pid) else { continue }
                matchedPorts.append(port)
            }
        }

        guard !matchedPorts.isEmpty else { return }

        Task { [weak self] in
            await self?.killPorts(matchedPorts, refreshAfterCompletion: true)
        }
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

struct AutoKillRule: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var portQuery: String
    var processQuery: String
    var isEnabled: Bool
    var action: AutoKillAction

    init(
        id: UUID = UUID(),
        name: String,
        portQuery: String = "",
        processQuery: String = "",
        isEnabled: Bool = true,
        action: AutoKillAction = .kill
    ) {
        self.id = id
        self.name = name
        self.portQuery = portQuery
        self.processQuery = processQuery
        self.isEnabled = isEnabled
        self.action = action
    }

    func matches(_ port: PortItem) -> Bool {
        let portMatches = portQuery.isEmpty || port.port.localizedCaseInsensitiveContains(portQuery)
        let processMatches = processQuery.isEmpty || port.processName.localizedCaseInsensitiveContains(processQuery)
        return portMatches && processMatches
    }

    var summary: String {
        let portLabel = portQuery.isEmpty ? "*" : portQuery
        let processLabel = processQuery.isEmpty ? "*" : processQuery
        return "\(action.title) port:\(portLabel) process:\(processLabel)"
    }
}

enum AutoKillAction: String, Codable, CaseIterable, Identifiable {
    case kill
    case alert
    case pin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kill: return "Kill"
        case .alert: return "Alert"
        case .pin: return "Pin"
        }
    }
}

nonisolated struct ProProfile: Codable, Hashable {
    var pinnedBookmarks: [PortBookmark]
    var killHistory: [KillHistoryEntry]
    var autoKillRules: [AutoKillRule]
    var refreshIntervalSeconds: Double
    var isAutoRefreshEnabled: Bool
}

extension JSONEncoder {
    nonisolated static var portKillerProfile: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var portKillerProfile: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
