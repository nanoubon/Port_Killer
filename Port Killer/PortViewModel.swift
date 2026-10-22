import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class PortViewModel: ObservableObject {
    @Published var ports: [PortItem] = []
    @Published var searchText: String = ""
    @Published var selectedPortIDs: Set<String> = []
    @Published private(set) var pinStore = PinStore()
    @Published var isAutoRefreshEnabled: Bool = true
    @Published var refreshIntervalSeconds: Double = PortViewModel.defaultRefreshInterval
    /// Always read from `SMAppService.mainApp.status`; never persisted.
    @Published private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    /// Non-nil when the last register/unregister attempt failed.
    @Published private(set) var launchAtLoginMessage: String?
    @Published var hasLoadedLivePorts: Bool = false
    /// Non-nil when the last scan failed, so the UI does not present a failure as "no ports".
    @Published var scanError: String?
    @Published var pendingKill: KillRequest?
    @Published var pendingForceKill: KillRequest?
    @Published private(set) var resultBanner: String?
    /// The one surface that shows `resultBanner` (a banner is never shown in two windows at once).
    @Published private(set) var bannerOrigin: KillOrigin = .mainWindow
    /// Surfaces (popover, main window) that are really on screen right now. The refresh timer runs
    /// only while this is non-empty. Driven from NSWindow state, see `WindowVisibilityReader`.
    @Published private(set) var visibleSurfaces = Set<String>()

    enum Surface {
        static let popover = "popover"
        static let mainWindow = "main"
    }

    static let readOnlyMessage = "process ของ root/user อื่น ปิดจากแอปนี้ไม่ได้ ใช้ sudo kill ในเทอร์มินัล"

    private var pendingExpiryTask: Task<Void, Never>?
    private var expiryPaused = false
    private var bannerPaused = false
    private var observers: [NSObjectProtocol] = []
    private static let pendingLifetimeNanoseconds: UInt64 = 30_000_000_000

    private let portScanService = PortScanService()
    private let processKillerService = ProcessKillerService()
    private let launchAtLoginService = LaunchAtLoginService()

    static let defaultRefreshInterval: Double = 5
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
        // A confirmation must not survive the user leaving the app.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelAllPending() }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        activeRefreshTask?.cancel()
        autoRefreshCancellable?.cancel()
    }

    var selectedPorts: [PortItem] {
        ports.filter { selectedPortIDs.contains($0.id) && !$0.isReadOnly }
    }

    /// One entry per pin. `liveItem == nil` means "not running": show it dimmed, never killable, unpin only.
    var pinnedEntries: [PinnedEntry] {
        pinStore.entries(live: ports)
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

    /// Only creates a pending request. The UI must confirm before any signal is sent.
    func killProcess(pid: String, port: PortItem? = nil, origin: KillOrigin = .mainWindow) {
        let candidate = port ?? ports.first { $0.pid == pid }
        guard let candidate else {
            showBanner("ไม่พบ process ที่เลือก", origin: origin)
            return
        }
        requestKill([candidate], origin: origin)
    }

    /// Copies `sudo kill <pid>` for read-only (root / other user) rows. Nothing is executed.
    func copySudoKillCommand(for port: PortItem, origin: KillOrigin? = nil) {
        guard let pid = Int32(port.pid), pid > 1 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sudo kill \(pid)", forType: .string)
        showBanner("คัดลอก sudo kill \(pid) แล้ว", origin: origin)
    }

    /// Kill request for specific rows (context menu). Read-only and unknown ids are dropped by `requestKill`.
    func killPorts(ids: Set<String>, origin: KillOrigin) {
        let items = ports.filter { ids.contains($0.id) }
        guard !items.isEmpty else { return }
        requestKill(items, origin: origin)
    }

    func killSelectedPorts(origin: KillOrigin = .mainWindow) {
        let items = selectedPorts
        guard !items.isEmpty else {
            let onlyReadOnly = ports.contains { selectedPortIDs.contains($0.id) && $0.isReadOnly }
            showBanner(onlyReadOnly ? Self.readOnlyMessage : "เลือกอย่างน้อยหนึ่งรายการก่อน", origin: origin)
            return
        }
        requestKill(items, origin: origin)
    }

    private func requestKill(_ candidates: [PortItem], origin: KillOrigin) {
        guard hasLoadedLivePorts else {
            showBanner("ยังไม่ได้สแกน port", origin: origin)
            return
        }
        // Defense in depth: read-only (root / other user) rows can never be killed from the app,
        // whatever the caller passed in. Check the live scan row as well as the candidate.
        let isReadOnly: (PortItem) -> Bool = { item in
            item.isReadOnly || (self.ports.first { $0.id == item.id }?.isReadOnly ?? false)
        }
        if candidates.contains(where: isReadOnly) {
            showBanner(Self.readOnlyMessage, origin: origin)
        }
        // Only items that are in the current scan result can be requested.
        let live = candidates.compactMap { candidate in
            isReadOnly(candidate) ? nil : ports.first { $0.id == candidate.id }
        }
        guard !live.isEmpty else {
            if !candidates.contains(where: isReadOnly) { showBanner("process นี้ไม่อยู่ในรายการแล้ว", origin: origin) }
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
            showBanner("ไม่สามารถปิด Port Killer เองได้", origin: origin)
        } else if refusedUnverifiable && entries.isEmpty {
            showBanner("ตรวจสอบ process ไม่ได้ (อาจปิดไปแล้ว)", origin: origin)
        }
        guard !entries.isEmpty else { return }
        setPending(kill: KillRequest(origin: origin, entries: entries), force: nil)
    }

    /// One pending request at a time across all origins; expires after 30 seconds unless the
    /// confirmation panel has keyboard/VoiceOver focus (see `setPendingExpiryPaused`).
    private func setPending(kill: KillRequest?, force: KillRequest?) {
        pendingKill = kill
        pendingForceKill = force
        expiryPaused = false
        startExpiryTimer()
    }

    private func startExpiryTimer() {
        pendingExpiryTask?.cancel()
        pendingExpiryTask = nil
        guard !expiryPaused, pendingKill != nil || pendingForceKill != nil else { return }
        pendingExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.pendingLifetimeNanoseconds)
            guard !Task.isCancelled else { return }
            self?.expirePending()
        }
    }

    private func expirePending() {
        let origin = pendingKill?.origin ?? pendingForceKill?.origin
        pendingKill = nil
        pendingForceKill = nil
        pendingExpiryTask = nil
        showBanner("คำขอปิด process หมดเวลาแล้ว ไม่มีการส่งสัญญาณ", origin: origin)
    }

    /// The panel calls this with `true` while any of its controls has focus: the 30 s clock stops
    /// so a slow keyboard / VoiceOver user is not timed out mid-decision.
    func setPendingExpiryPaused(_ paused: Bool) {
        guard paused != expiryPaused else { return }
        expiryPaused = paused
        startExpiryTimer()
    }

    func isPending(for origin: KillOrigin) -> Bool {
        pendingKill?.origin == origin || pendingForceKill?.origin == origin
    }

    func cancelAllPending() {
        guard pendingKill != nil || pendingForceKill != nil else { return }
        setPending(kill: nil, force: nil)
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

    /// Shows `message` in exactly one surface: `origin` if given, else the popover while it is
    /// open, else the main window. Also announced to VoiceOver.
    func showBanner(_ message: String, origin: KillOrigin? = nil) {
        bannerOrigin = origin ?? (visibleSurfaces.contains(Surface.popover) ? .menuBar : .mainWindow)
        resultBanner = message
        bannerPaused = false
        Self.announce(message)
        scheduleBannerDismissal()
    }

    func dismissBanner() {
        bannerTask?.cancel()
        bannerTask = nil
        resultBanner = nil
    }

    /// Hover or focus on the banner stops its countdown.
    func setBannerPaused(_ paused: Bool) {
        guard paused != bannerPaused else { return }
        bannerPaused = paused
        scheduleBannerDismissal()
    }

    /// At least 5 s, longer for long messages (about 12 characters per second).
    nonisolated static func bannerDuration(for message: String) -> TimeInterval {
        max(5, Double(message.count) / 12)
    }

    private func scheduleBannerDismissal() {
        bannerTask?.cancel()
        bannerTask = nil
        guard let message = resultBanner, !bannerPaused else { return }
        let seconds = Self.bannerDuration(for: message)
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resultBanner = nil
        }
    }

    static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    func refresh() {
        requestPortRefresh()
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

    /// Idempotent. Call with the real on-screen state of a surface. Becoming visible scans
    /// immediately; the refresh timer runs only while at least one surface is visible. A surface
    /// going away also drops the confirmation request that belongs to it.
    func setSurface(_ id: String, visible: Bool) {
        if visible {
            guard visibleSurfaces.insert(id).inserted else { return }
            refreshLaunchAtLoginStatus()
            requestPortRefresh()
        } else {
            visibleSurfaces.remove(id)
            switch id {
            case Surface.popover: cancelPending(origin: .menuBar)
            case Surface.mainWindow: cancelPending(origin: .mainWindow)
            default: break
            }
        }
        configureAutoRefresh()
    }

    var isAutoRefreshRunning: Bool { autoRefreshCancellable != nil }

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

    func openLoginItemsSettings() {
        launchAtLoginService.openLoginItemsSettings()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    private func requestPortRefresh() {
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
        // Retried on every scan: the pinned process may start long after launch.
        if pinStore.hasMigrationCandidates, pinStore.migrateTruncatedNames(live: ports) { pinStore.save() }
        reconcileSelection()
    }

    private func applyScanFailure(_ error: Error, generation: Int) {
        guard generation == refreshGeneration else { return }

        ports = []
        hasLoadedLivePorts = true
        scanError = error.localizedDescription
        reconcileSelection()
    }

    private func makePortItem(from snapshot: PortScanSnapshot) -> PortItem {
        return PortItem(
            processName: snapshot.processName,
            pid: snapshot.pid,
            port: snapshot.port,
            user: snapshot.user,
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
            showBanner(messages.joined(separator: "\n"), origin: request.origin)
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

    }

    private func configureAutoRefresh() {
        autoRefreshCancellable?.cancel()
        autoRefreshCancellable = nil
        guard isAutoRefreshEnabled, !visibleSurfaces.isEmpty else { return }

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
