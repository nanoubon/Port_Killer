import AppKit
import Darwin
import Foundation
import ServiceManagement

struct PortScanSnapshot: Sendable, Hashable {
    let processName: String
    let pid: String
    let user: String
    let port: String
}

actor PortScanService {
    enum ScanError: LocalizedError {
        case unavailable
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Unable to run the lsof scan."
            case .commandFailed(let message):
                return message
            }
        }
    }

    func scanListeningPorts() async throws -> [PortScanSnapshot] {
        try Task.checkCancellation()

        guard let result = ShellHelper.executeCommand(
            command: "/usr/sbin/lsof",
            arguments: ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        ) else {
            throw ScanError.unavailable
        }

        guard result.succeeded else {
            let fallback = "lsof exited with status \(result.exitStatus)."
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScanError.commandFailed(message.isEmpty ? fallback : message)
        }

        return Self.parse(result.standardOutput)
    }

    private static func parse(_ output: String) -> [PortScanSnapshot] {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        var parsed: [PortScanSnapshot] = []
        var seen = Set<String>()

        for line in lines.dropFirst() {
            let columns = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard columns.count >= 9 else { continue }

            let processName = columns[0]
            let pid = columns[1]
            let user = columns[2]
            let nameColumn = columns[8]

            guard let portRange = nameColumn.range(of: ":\\d+", options: .regularExpression) else {
                continue
            }

            let port = String(nameColumn[portRange].dropFirst())
            let key = "\(port)-\(pid)-\(processName)"
            guard seen.insert(key).inserted else { continue }

            parsed.append(
                PortScanSnapshot(
                    processName: processName,
                    pid: pid,
                    user: user,
                    port: port
                )
            )
        }

        return parsed
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
    private var loginItemIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.portkiller.app") + ".launchhelper"
    }

    func currentStatus() -> Bool {
        let service = SMAppService.loginItem(identifier: loginItemIdentifier)
        return service.status == .enabled
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> Bool {
        let service = SMAppService.loginItem(identifier: loginItemIdentifier)
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
        return service.status == .enabled
    }
}
