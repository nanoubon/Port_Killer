import SwiftUI
import Combine

class PortViewModel: ObservableObject {
    @Published var ports: [PortItem] = []
    @Published var debugMessage: String = "Initializing..."
    
    // We call this periodically or on demand to update the list
    func fetchActivePorts() {
        self.debugMessage = "Fetching ports..."
        DispatchQueue.global(qos: .userInitiated).async {
            guard let output = ShellHelper.executeCommand(command: "/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]) else {
                DispatchQueue.main.async {
                    self.debugMessage = "Failed to execute lsof command. (Returns nil)"
                }
                return
            }

            if output.isEmpty {
                DispatchQueue.main.async {
                    self.debugMessage = "Executed lsof, but output is exactly empty."
                }
                return
            }

            // Parse lsof output on background thread (no AppKit access here)
            struct ParsedPort {
                let processName: String
                let pid: String
                let port: String
            }
            var parsed: [ParsedPort] = []
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

            if lines.count <= 1 {
                DispatchQueue.main.async {
                    self.debugMessage = "Output has only \(lines.count) lines. Output: \(output)"
                }
                return
            }

            // Skip the header line
            for line in lines.dropFirst() {
                let columns = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

                if columns.count >= 9 {
                    let processName = columns[0]
                    let pid = columns[1]
                    let nameColumn = columns[8] // Example: *:8080 or 127.0.0.1:8080

                    if let portRange = nameColumn.range(of: ":\\d+", options: .regularExpression) {
                        let portString = String(nameColumn[portRange].dropFirst()) // Remove the ':'
                        let entry = ParsedPort(processName: processName, pid: pid, port: portString)
                        if !parsed.contains(where: { $0.port == entry.port && $0.processName == entry.processName }) {
                            parsed.append(entry)
                        }
                    }
                }
            }

            // NSWorkspace must be accessed on the main thread
            DispatchQueue.main.async {
                let runningApps = NSWorkspace.shared.runningApplications
                var newPorts: [PortItem] = []
                for entry in parsed {
                    let icon = Int32(entry.pid).flatMap { pidInt in
                        runningApps.first(where: { $0.processIdentifier == pidInt })?.icon
                    }
                    newPorts.append(PortItem(processName: entry.processName, pid: entry.pid, port: entry.port, protocolName: "TCP", icon: icon))
                }
                // Parentheses required: ?? has lower precedence than <
                self.ports = newPorts.sorted { (Int($0.port) ?? 0) < (Int($1.port) ?? 0) }
                if self.ports.isEmpty {
                    self.debugMessage = "Found \(lines.count) lines but regex matched 0 ports. Example line: \(lines.dropFirst().first ?? "none")"
                } else {
                    self.debugMessage = "Successfully fetched \(self.ports.count) ports."
                }
            }
        }
    }

    // Kill the process by its PID using the 'kill' command
    func killProcess(pid: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Run 'kill -9 <pid>'
            let _ = ShellHelper.executeCommand(command: "/bin/kill", arguments: ["-9", pid])

            // Refresh the list after a short delay to allow the OS to update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.fetchActivePorts()
            }
        }
    }
}
