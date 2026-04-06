import Foundation

struct ShellCommandResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitStatus: Int32

    nonisolated var succeeded: Bool {
        exitStatus == 0
    }
}

/// A helper struct to safely execute shell commands.
///
/// **How to use:**
/// - `command`: Must be the absolute path to the executable (e.g., "/usr/sbin/lsof", "/bin/kill", "/usr/bin/python3"). Do not just pass "ls" or "kill".
/// - `arguments`: An array of strings representing the flags or parameters passed to the command.
///
/// **Example 1: Getting a list of files**
/// ```swift
/// if let output = ShellHelper.executeCommand(command: "/bin/ls", arguments: ["-la", "/tmp"]) {
///     print(output)
/// }
/// ```
///
/// **Example 2: Killing a process**
/// ```swift
/// // Kills process with PID 1234 forcefully
/// let _ = ShellHelper.executeCommand(command: "/bin/kill", arguments: ["-9", "1234"])
/// ```
struct ShellHelper {

    /// Executes a shell command and returns the standard output.
    /// It runs locally without needing a full bash profile.
    nonisolated static func executeCommand(command: String, arguments: [String]) -> ShellCommandResult? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return ShellCommandResult(
                standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
                standardError: String(data: stderrData, encoding: .utf8) ?? "",
                exitStatus: process.terminationStatus
            )
        } catch {
            print("Error executing shell command \(command): \(error)")
            return nil
        }
    }
}
