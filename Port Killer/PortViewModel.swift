import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class PortViewModel: ObservableObject {
    @Published var ports: [PortItem] = []
    @Published var searchText: String = ""
    @Published var selectedSection: AppSection = .activePorts
    @Published var selectedPortID: String?
    @Published var selectedPortIDs: Set<String> = []
    @Published private(set) var pinStore = PinStore()
    @Published var isAutoRefreshEnabled: Bool = true
    @Published var refreshIntervalSeconds: Double = PortViewModel.defaultRefreshInterval
    /// Always read from `SMAppService.mainApp.status`; never persisted.
    @Published private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    /// Non-nil when the last register/unregister attempt failed.
    @Published private(set) var launchAtLoginMessage: String?
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

    static let defaultRefreshInterval: Double = 5
    private var visibleSurfaceCount = 0
    private var needsPinMigration = true
    private var autoRefreshCancellable: AnyCancellable?
    private var activeRefreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var killInFlightPIDs = Set<String>()
    private var bannerTask: Task<Void, Never>?

    /// Keys written by earlier builds for features that no longer exist.
    private static let legacyStorageKeys = [
        "PortKiller.autoKillRules",
        "PortKiller.killHistory",
        "PortKiller.hasCompletedOnboarding",
        "PortKiller.isLaunchAtLoginEnabled"
    ]

    private static func removeLegacyStorageKeys() {
        for key in legacyStorageKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private enum StorageKey {
        static let isAutoRefreshEnabled = "PortKiller.isAutoRefreshEnabled"
        static let refreshIntervalSeconds = "PortKiller.refreshIntervalSeconds"
    }

    init() {
        Self.removeLegacyStorageKeys()
        loadPersistedState()
        refreshLaunchAtLoginStatus()
        requestPortRefresh()
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
        ports.filter { selectedPortIDs.contains($0.id) && !$0.isReadOnly }
    }

    var pinnedBookmarks: [PortBookmark] { pinStore.bookmarks }

    /// One entry per pin. `liveItem == nil` means "not running": show it dimmed, never killable, unpin only.
    var pinnedEntries: [PinnedEntry] {
        pinStore.entries(live: ports)
    }

    var pinnedPortItems: [PortItem] {
        pinnedEntries.compactMap(\.liveItem)
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
            return pinStore.sortedPinnedFirst(source)
        }

        return pinStore.sortedPinnedFirst(source.filter { port in
            port.processName.localizedCaseInsensitiveContains(trimmedQuery) ||
            port.port.localizedCaseInsensitiveContains(trimmedQuery) ||
            port.pid.localizedCaseInsensitiveContains(trimmedQuery) ||
            (port.user?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        })
    }

    func setSection(_ section: AppSection) {
        selectedSection = section
    }

    func toggleSelection(for port: PortItem) {
        guard !port.isReadOnly else { return }
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
        pinStore.isPinned(port)
    }

    func togglePinned(_ port: PortItem) {
        pinStore.toggle(port)
        pinStore.save()
    }

    func unpin(_ bookmark: PortBookmark) {
        pinStore.remove(bookmark)
        pinStore.save()
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

    /// Copies `sudo kill <pid>` for read-only (root / other user) rows. Nothing is executed.
    func copySudoKillCommand(for port: PortItem) {
        guard let pid = Int32(port.pid), pid > 1 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sudo kill \(pid)", forType: .string)
        showBanner("คัดลอก sudo kill \(pid) แล้ว")
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
        // Defense in depth: read-only (root / other user) rows can never be killed from the app,
        // whatever the caller passed in. Check the live scan row as well as the candidate.
        let isReadOnly: (PortItem) -> Bool = { item in
            item.isReadOnly || (self.ports.first { $0.id == item.id }?.isReadOnly ?? false)
        }
        if candidates.contains(where: isReadOnly) {
            showBanner("process ของ root/user อื่น ปิดจากแอปนี้ไม่ได้ ใช้ sudo kill ในเทอร์มินัล")
        }
        // Only items that are in the current scan result can be requested.
        let live = candidates.compactMap { candidate in
            isReadOnly(candidate) ? nil : ports.first { $0.id == candidate.id }
        }
        guard !live.isEmpty else {
            if !candidates.contains(where: isReadOnly) { showBanner("process นี้ไม่อยู่ในรายการแล้ว") }
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

    /// Call from every surface (popover, main window) when it appears. Scans immediately and
    /// keeps the refresh timer running while at least one surface is visible.
    func screenDidAppear() {
        visibleSurfaceCount += 1
        refreshLaunchAtLoginStatus()
        requestPortRefresh()
        configureAutoRefresh()
    }

    func screenDidDisappear() {
        visibleSurfaceCount = max(0, visibleSurfaceCount - 1)
        configureAutoRefresh()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginService.status
    }

    /// True for `.enabled` and `.requiresApproval` (registered, waiting for the user in System Settings).
    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginMessage = nil
        do {
            try launchAtLoginService.setEnabled(enabled)
        } catch {
            launchAtLoginMessage = "ตั้งค่า Start at login ไม่สำเร็จ: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
        if launchAtLoginStatus == .requiresApproval {
            launchAtLoginMessage = "ต้องอนุมัติใน System Settings › General › Login Items"
        }
    }

    func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled)
    }

    func openLoginItemsSettings() {
        launchAtLoginService.openLoginItemsSettings()
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
        if needsPinMigration {
            needsPinMigration = false
            if pinStore.migrateTruncatedNames(live: ports) { pinStore.save() }
        }
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
            addresses: snapshot.addresses,
            isReadOnly: snapshot.isReadOnly,
            ownerLabel: snapshot.ownerLabel
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
        refreshIntervalSeconds = max(3, min(persistDouble(forKey: StorageKey.refreshIntervalSeconds, defaultValue: Self.defaultRefreshInterval), 60))
        pinStore = PinStore.load()
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
        autoRefreshCancellable = nil
        guard isAutoRefreshEnabled, visibleSurfaceCount > 0 else { return }

        autoRefreshCancellable = Timer.publish(every: refreshIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.requestPortRefresh()
            }
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
