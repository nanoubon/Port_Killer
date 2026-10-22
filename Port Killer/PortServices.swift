import Darwin
import Foundation
import ServiceManagement

actor PortScanService {
    enum ScanError: LocalizedError {
        case unavailable
        case timedOut
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Unable to run the lsof scan."
            case .timedOut:
                return "lsof did not respond in time."
            case .commandFailed(let message):
                return message
            }
        }
    }

    /// lsof is the source of truth (full names, current user). netstat adds root / other-user
    /// listeners as read-only rows. A netstat failure is silent; an lsof failure is thrown.
    func scanListeningPorts() async throws -> [PortScanSnapshot] {
        let lsofRows = try scanLsof()
        try Task.checkCancellation()
        return Self.merge(lsof: lsofRows, netstat: scanNetstat())
    }

    private func scanNetstat() -> [NetstatRow] {
        guard let result = ShellHelper.executeCommand(
            command: "/usr/sbin/netstat",
            arguments: ["-anv", "-p", "tcp"]
        ), result.succeeded else { return [] }
        return NetstatParser.parse(result.standardOutput)
    }

    /// Adds netstat-only (pid, port) pairs as read-only snapshots after the lsof rows.
    nonisolated static func merge(lsof: [PortScanSnapshot], netstat: [NetstatRow]) -> [PortScanSnapshot] {
        var known = Set(lsof.map { "\($0.pid)-\($0.port)" })
        var merged = lsof
        for row in netstat where known.insert("\(row.pid)-\(row.port)").inserted {
            guard let pidValue = Int32(row.pid) else { continue }
            let owner = ProcessInspector.ownerLabel(of: pidValue)
            merged.append(PortScanSnapshot(
                processName: ProcessInspector.fullName(of: pidValue, truncated: row.processName),
                pid: row.pid,
                user: owner,
                port: row.port,
                addresses: row.addresses,
                isReadOnly: true,
                ownerLabel: owner
            ))
        }
        return merged
    }

    private func scanLsof() throws -> [PortScanSnapshot] {
        try Task.checkCancellation()

        guard let result = ShellHelper.executeCommand(
            command: "/usr/sbin/lsof",
            arguments: ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0", "-F", "pcLun"]
        ) else {
            throw ScanError.unavailable
        }
        try Task.checkCancellation()
        return try Self.interpretLsof(result)
    }

    /// Maps an lsof run to rows or an error. Exit 1 with empty stdout means "no listeners" even if
    /// lsof wrote warnings to stderr; exit 1 with output keeps the output; other failures surface stderr.
    nonisolated static func interpretLsof(_ result: ShellCommandResult) throws -> [PortScanSnapshot] {
        if result.timedOut { throw ScanError.timedOut }

        let stdoutEmpty = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if result.exitStatus == 1, stdoutEmpty { return [] }

        guard result.succeeded || (result.exitStatus == 1 && !stdoutEmpty) else {
            let fallback = "lsof exited with status \(result.exitStatus)."
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScanError.commandFailed(message.isEmpty ? fallback : message)
        }

        return LsofParser.parse(result.standardOutput)
    }
}

enum KillSignalOutcome: Sendable, Equatable {
    case terminated
    case stillRunning
    case notPermitted
    case alreadyGone
    case failed(Int32)
}

/// Read-only process lookups through libproc. No shell involved.
enum ProcessInspector {
    nonisolated static func name(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    nonisolated static func identity(of pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard written == size, info.pbi_pid == UInt32(pid) else { return nil }
        return ProcessIdentity(
            startSeconds: info.pbi_start_tvsec,
            startMicroseconds: info.pbi_start_tvusec,
            uid: info.pbi_uid,
            path: executablePath(of: pid)
        )
    }

    /// "root", the account name, or "other user" when the uid cannot be resolved.
    nonisolated static func ownerLabel(of pid: Int32) -> String {
        guard let uid = identity(of: pid)?.uid else { return "other user" }
        if uid == 0 { return "root" }
        if let entry = getpwuid(uid), let name = String(validatingUTF8: entry.pointee.pw_name), !name.isEmpty {
            return name
        }
        return "other user"
    }

    /// Full process name: the executable's file name when it extends netstat's truncated name,
    /// else proc_name, else the truncated netstat name.
    nonisolated static func fullName(of pid: Int32, truncated: String) -> String {
        if let path = executablePath(of: pid) {
            let base = (path as NSString).lastPathComponent
            if !base.isEmpty, base.hasPrefix(truncated) { return base }
        }
        if let name = name(of: pid), !name.isEmpty, name.hasPrefix(truncated) || truncated.hasPrefix(name) {
            return name.count >= truncated.count ? name : truncated
        }
        return truncated
    }

    nonisolated static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}

actor ProcessKillerService {
    private static let gracePeriodNanoseconds: UInt64 = 3_000_000_000
    private static let pollNanoseconds: UInt64 = 100_000_000

    /// Sends SIGTERM and polls up to ~3s for the process to exit.
    /// `verify` runs immediately before the signal; false means the identity changed.
    func terminate(pid: Int32, verify: @Sendable () -> Bool) async -> KillSignalOutcome {
        guard verify() else { return .alreadyGone }
        if let early = Self.send(SIGTERM, to: pid) { return early }

        var waited: UInt64 = 0
        while waited < Self.gracePeriodNanoseconds {
            try? await Task.sleep(nanoseconds: Self.pollNanoseconds)
            waited += Self.pollNanoseconds
            if !Self.exists(pid) { return .terminated }
        }
        return Self.exists(pid) ? .stillRunning : .terminated
    }

    func forceKill(pid: Int32, verify: @Sendable () -> Bool) async -> KillSignalOutcome {
        guard verify() else { return .alreadyGone }
        if let early = Self.send(SIGKILL, to: pid) { return early }

        var waited: UInt64 = 0
        while waited < 2_000_000_000 {
            try? await Task.sleep(nanoseconds: Self.pollNanoseconds)
            waited += Self.pollNanoseconds
            if !Self.exists(pid) { return .terminated }
        }
        return Self.exists(pid) ? .stillRunning : .terminated
    }

    /// Returns a final outcome if the signal could not be delivered, nil if it was sent.
    private nonisolated static func send(_ signal: Int32, to pid: Int32) -> KillSignalOutcome? {
        guard pid > 1 else { return .notPermitted }
        if Darwin.kill(pid, signal) == 0 { return nil }
        switch errno {
        case ESRCH: return .alreadyGone
        case EPERM: return .notPermitted
        default: return .failed(errno)
        }
    }

    private nonisolated static func exists(_ pid: Int32) -> Bool {
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}

@MainActor
struct LaunchAtLoginService {
    /// Source of truth for the Start at login switch; never cached or persisted.
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
