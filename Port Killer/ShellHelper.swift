import Foundation

struct ShellCommandResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitStatus: Int32
    /// True when the process exceeded the timeout and was terminated. Output is whatever was read so far.
    var timedOut: Bool = false

    nonisolated var succeeded: Bool {
        exitStatus == 0 && !timedOut
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

    static let defaultTimeout: TimeInterval = 10
    /// Per-stream capture cap (16 MB) so a runaway child cannot exhaust memory.
    static let maxCapturedBytes = 16 * 1024 * 1024

    /// Thread-safe byte accumulator for one pipe.
    private final class PipeBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        nonisolated init() {}
        /// Keeps at most `ShellHelper.maxCapturedBytes`; extra bytes are drained and dropped.
        nonisolated func append(_ chunk: Data) {
            lock.lock()
            if data.count < ShellHelper.maxCapturedBytes {
                data.append(chunk.prefix(ShellHelper.maxCapturedBytes - data.count))
            }
            lock.unlock()
        }
        nonisolated var value: Data { lock.lock(); defer { lock.unlock() }; return data }
    }

    /// Runs a command, draining stdout and stderr concurrently while it runs (so a full pipe can
    /// never block the child), and terminates it after `timeout` seconds.
    /// Returns nil only if the process could not be launched.
    nonisolated static func executeCommand(
        command: String,
        arguments: [String],
        timeout: TimeInterval = ShellHelper.defaultTimeout
    ) -> ShellCommandResult? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()
        let readers = DispatchGroup()
        for (pipe, buffer) in [(stdoutPipe, outBuffer), (stderrPipe, errBuffer)] {
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = pipe.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break } // EOF
                    buffer.append(chunk)
                }
                readers.leave()
            }
        }

        do {
            try process.run()
        } catch {
            print("Error executing shell command \(command): \(error)")
            // Closing our write ends lets the reader threads see EOF and finish.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            readers.wait()
            return nil
        }
        // The child owns the write ends now; close ours so EOF is delivered when it exits.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }

        // If a grandchild inherited the pipes, do not wait forever for EOF.
        _ = readers.wait(timeout: .now() + 1)

        return ShellCommandResult(
            standardOutput: String(decoding: outBuffer.value, as: UTF8.self),
            standardError: String(decoding: errBuffer.value, as: UTF8.self),
            exitStatus: process.isRunning ? -1 : process.terminationStatus,
            timedOut: timedOut
        )
    }
}
