import AppKit
import Foundation
import ServiceManagement

struct PortScanSnapshot: Sendable, Hashable {
    let processName: String
    let pid: String
    let user: String
    let port: String
}

struct KillCommandOutcome: Sendable {
    let pid: String
    let succeeded: Bool
    let message: String
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

actor ProcessKillerService {
    func kill(pid: String) async -> KillCommandOutcome {
        guard let result = ShellHelper.executeCommand(command: "/bin/kill", arguments: ["-9", pid]) else {
            return KillCommandOutcome(pid: pid, succeeded: false, message: "Kill command could not be executed.")
        }

        guard result.succeeded else {
            let stderr = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = "Kill command exited with status \(result.exitStatus)."
            return KillCommandOutcome(pid: pid, succeeded: false, message: stderr.isEmpty ? fallback : stderr)
        }

        return KillCommandOutcome(pid: pid, succeeded: true, message: "Process terminated.")
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
