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
    @Published var hasCompletedOnboarding: Bool = true
    @Published var isAutoRefreshEnabled: Bool = true
    @Published var refreshIntervalSeconds: Double = 8
    @Published var isLaunchAtLoginEnabled: Bool = false
    @Published var debugMessage: String = "Initializing..."
    @Published var lastRefreshAt: Date?
    @Published var hasLoadedLivePorts: Bool = false
    /// Non-nil when the last scan failed, so the UI does not present a failure as "no ports".
    @Published var scanError: String?
    @Published var pendingKill: KillRequest?
    @Published var pendingForceKill: KillRequest?
    @Published var resultBanner: String?

    private var pendingExpiryTask: Task<Void, Never>?
    private static let pendingLifetimeNanoseconds: UInt64 = 30_000_000_000

    private let portScanService = PortScanService()
    private let processKillerService = ProcessKillerService()
    private let launchAtLoginService = LaunchAtLoginService()

    private var autoRefreshCancellable: AnyCancellable?
    private var activeRefreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var killInFlightPIDs = Set<String>()
    private var bannerTask: Task<Void, Never>?

    /// Keys written by earlier builds for features that no longer exist.
    private static let legacyStorageKeys = [
        "PortKiller.autoKillRules",
        "PortKiller.killHistory",
        "PortKiller.hasCompletedOnboarding"
    ]

    private static func removeLegacyStorageKeys() {
        for key in legacyStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private enum StorageKey {
        static let pinnedBookmarks = "PortKiller.pinnedBookmarks"
        static let isAutoRefreshEnabled = "PortKiller.isAutoRefreshEnabled"
        static let refreshIntervalSeconds = "PortKiller.refreshIntervalSeconds"
        static let isLaunchAtLoginEnabled = "PortKiller.isLaunchAtLoginEnabled"
    }

    init() {
        Self.removeLegacyStorageKeys()
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
            return ports.first { $0.id == selectedPortID }
        }
        return visiblePorts.first
    }

    var selectedPorts: [PortItem] {
        ports.filter { selectedPortIDs.contains($0.id) }
    }

    var pinnedPortItems: [PortItem] {
        guard hasLoadedLivePorts else { return [] }
        let source = ports
        return pinnedBookmarks.compactMap { bookmark in
            source.first { item in
                item.port == bookmark.port && item.processName.localizedCaseInsensitiveContains(bookmark.processName)
            } ?? source.first { $0.port == bookmark.port }
        }
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
        killHistory.sorted { $0.createdAt > $1.createdAt }
    }

    var historySummary: String {
        if killHistory.isEmpty {
            return "No terminations recorded"
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
        guard hasLoadedLivePorts else { return [] }
        let source = ports

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

    /// Only creates a pending request. The UI must confirm before any signal is sent.
    func killProcess(pid: String, port: PortItem? = nil, origin: KillOrigin = .mainWindow) {
        let candidate = port ?? ports.first { $0.pid == pid }
        guard let candidate else {
            showBanner("ไม่พบ process ที่เลือก")
            return
        }
        requestKill([candidate], origin: origin)
    }

    func killSelectedPorts(origin: KillOrigin = .mainWindow) {
        let items = selectedPorts
        guard !items.isEmpty else {
            showBanner("เลือกอย่างน้อยหนึ่งรายการก่อน")
            return
        }
        requestKill(items, origin: origin)
    }

    private func requestKill(_ candidates: [PortItem], origin: KillOrigin) {
        guard hasLoadedLivePorts else {
            showBanner("ยังไม่ได้สแกน port")
            return
        }
        // Only items that are in the current scan result can be requested.
        let live = candidates.compactMap { candidate in ports.first { $0.id == candidate.id } }
        guard !live.isEmpty else {
            showBanner("process นี้ไม่อยู่ในรายการแล้ว")
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let user = NSUserName()
        var entries: [KillRequest.Entry] = []
        var refusedSelf = false
        var refusedUnverifiable = false
        for item in live {
            guard let pid = Int32(item.pid), let identity = ProcessInspector.identity(of: pid) else {
                refusedUnverifiable = true
                continue
            }
            let warnings = KillSafety.classify(
                item,
                currentUser: user,
                currentUID: getuid(),
                ownPID: ownPID,
                executablePath: ProcessInspector.executablePath(of:),
                identity: ProcessInspector.identity(of:)
            )
            if warnings.contains(where: \.isBlocking) {
                refusedSelf = true
                continue
            }
            let fullName = ProcessInspector.name(of: pid) ?? item.processName
            entries.append(
                KillRequest.Entry(
                    item: item,
                    displayName: KillSafety.sanitizeForDisplay(fullName),
                    path: identity.path.map { KillSafety.sanitizeForDisplay($0) },
                    identity: identity,
                    warnings: warnings
                )
            )
        }

        if refusedSelf {
            showBanner("ไม่สามารถปิด Port Killer เองได้")
        } else if refusedUnverifiable && entries.isEmpty {
            showBanner("ตรวจสอบ process ไม่ได้ (อาจปิดไปแล้ว)")
        }
        guard !entries.isEmpty else { return }
        setPending(kill: KillRequest(origin: origin, entries: entries), force: nil)
    }

    /// One pending request at a time across all origins; expires after 30 seconds.
    private func setPending(kill: KillRequest?, force: KillRequest?) {
        pendingExpiryTask?.cancel()
        pendingKill = kill
        pendingForceKill = force
        guard kill != nil || force != nil else { return }
        pendingExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.pendingLifetimeNanoseconds)
            guard !Task.isCancelled else { return }
            self?.pendingKill = nil
            self?.pendingForceKill = nil
        }
    }

    func cancelPendingKill() {
        setPending(kill: nil, force: pendingForceKill)
    }

    func cancelForceKill() {
        setPending(kill: pendingKill, force: nil)
    }

    /// Clears pending requests shown in a surface that is going away.
    func cancelPending(origin: KillOrigin) {
        if pendingKill?.origin == origin { cancelPendingKill() }
        if pendingForceKill?.origin == origin { cancelForceKill() }
    }

    func confirmKill() {
        guard let request = pendingKill else { return }
        setPending(kill: nil, force: nil)
        Task { [weak self] in
            await self?.execute(request, force: false)
        }
    }

    func confirmForceKill() {
        guard let request = pendingForceKill else { return }
        setPending(kill: nil, force: nil)
        Task { [weak self] in
            await self?.execute(request, force: true)
        }
    }

    func showBanner(_ message: String) {
        resultBanner = message
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.resultBanner = nil
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
        port.command ?? "-"
    }

    func detailUser(for port: PortItem) -> String {
        port.user ?? "-"
    }

    func detailUptime(for port: PortItem) -> String {
        port.uptime ?? "-"
    }

    func detailLoad(for port: PortItem) -> String {
        port.loadDescription ?? "-"
    }

    func detailSubtitle(for port: PortItem) -> String {
        "\(port.processName) • PID \(port.pid)"
    }

    func displayName(for port: PortItem) -> String {
        port.processName
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
            .sorted {
                let (a, b) = (Int($0.port) ?? 0, Int($1.port) ?? 0)
                return a != b ? a < b : (Int($0.pid) ?? 0) < (Int($1.pid) ?? 0)
            }
        hasLoadedLivePorts = true
        scanError = nil
        reconcileSelection()

        debugMessage = ports.isEmpty
            ? "No listening ports matched the current scan."
            : "Successfully fetched \(ports.count) ports."
    }

    private func applyScanFailure(_ error: Error, generation: Int) {
        guard generation == refreshGeneration else { return }

        ports = []
        hasLoadedLivePorts = true
        scanError = error.localizedDescription
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
            addresses: snapshot.addresses
        )
    }

    /// Re-validates every item right before ITS signal (fresh scan + pinned identity), then reports.
    private func execute(_ request: KillRequest, force: Bool) async {
        var messages: [String] = []
        var needForce: [KillRequest.Entry] = []

        for entry in request.entries {
            let item = entry.item
            let label = "\(entry.displayName) (\(KillSafety.sanitizeForDisplay(item.port, limit: 8)))"

            // Fresh scan per entry: earlier entries' SIGTERM waits can take seconds.
            let listening: Set<String>
            do {
                let snapshots = try await portScanService.scanListeningPorts()
                listening = Set(snapshots.map { "\($0.pid)-\($0.port)" })
            } catch {
                messages.append("ข้าม \(label): ตรวจสอบก่อนปิดไม่สำเร็จ")
                continue
            }

            let valid = KillSafety.revalidate(
                item,
                captured: entry.identity,
                identity: ProcessInspector.identity(of:),
                currentProcessName: ProcessInspector.name(of:),
                stillListeningOnPort: { pid, port in listening.contains("\(pid)-\(port)") }
            )
            guard valid, let pid = Int32(item.pid) else {
                messages.append("ข้าม \(label): process เปลี่ยนไปหรือปิดไปแล้ว")
                continue
            }
            guard pid != ProcessInfo.processInfo.processIdentifier else {
                messages.append("ไม่สามารถปิด Port Killer เองได้")
                continue
            }
            guard killInFlightPIDs.insert(item.pid).inserted else { continue }
            defer { killInFlightPIDs.remove(item.pid) }

            let captured = entry.identity
            let verify: @Sendable () -> Bool = { ProcessInspector.identity(of: pid) == captured }
            let outcome = force
                ? await processKillerService.forceKill(pid: pid, verify: verify)
                : await processKillerService.terminate(pid: pid, verify: verify)

            switch outcome {
            case .terminated:
                messages.append("ปิด \(label) แล้ว")
            case .stillRunning:
                if force {
                    messages.append("\(label) ยังไม่ปิดแม้ส่ง SIGKILL")
                } else {
                    messages.append("\(label) ยังไม่ปิดหลังรอ 3 วินาที")
                    needForce.append(entry)
                }
            case .notPermitted:
                messages.append("ไม่มีสิทธิ์ปิด process ของ \(KillSafety.sanitizeForDisplay(item.user ?? "user อื่น", limit: 16))")
            case .alreadyGone:
                messages.append("process ปิดไปก่อนแล้ว (\(label))")
            case .failed(let code):
                messages.append("ปิด \(label) ไม่สำเร็จ (errno \(code))")
            }
            selectedPortIDs.remove(item.id)
        }

        if !messages.isEmpty {
            showBanner(messages.joined(separator: "\n"))
        }
        if !needForce.isEmpty {
            setPending(kill: nil, force: KillRequest(origin: request.origin, entries: needForce))
        }
        requestPortRefresh()
    }

    private func loadPersistedState() {
        isAutoRefreshEnabled = persistBool(forKey: StorageKey.isAutoRefreshEnabled, defaultValue: true)
        refreshIntervalSeconds = persistDouble(forKey: StorageKey.refreshIntervalSeconds, defaultValue: 8)
        pinnedBookmarks = loadValue([PortBookmark].self, forKey: StorageKey.pinnedBookmarks) ?? []
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
}

struct QuickAction: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}

enum KillOrigin: Hashable {
    case mainWindow
    case menuBar
}

struct KillRequest: Identifiable {
    struct Entry: Identifiable {
        let item: PortItem
        /// Full name from libproc when available (lsof truncates names).
        let displayName: String
        /// Sanitized executable path, if known.
        let path: String?
        /// Identity captured when the request was created; every signal re-checks it.
        let identity: ProcessIdentity
        let warnings: [KillWarning]
        var id: String { item.id }
    }

    let id = UUID()
    let origin: KillOrigin
    let entries: [Entry]
}
