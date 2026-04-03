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

            var newPorts: [PortItem] = []
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

                    // Extract the port number from the name column
                    if let portRange = nameColumn.range(of: ":\\d+", options: .regularExpression) {
                        let portString = String(nameColumn[portRange].dropFirst()) // Remove the ':'

                        var appIcon: NSImage? = nil

                        // NSWorkspace must be accessed on the main thread
                        if let pidInt = Int32(pid) {
                            appIcon = NSWorkspace.shared.runningApplications
                                .first(where: { $0.processIdentifier == pidInt })?.icon
                        }

                        let item = PortItem(processName: processName, pid: pid, port: portString, protocolName: "TCP", icon: appIcon)

                        // Avoid duplicating ports on different interfaces (e.g. IPv4 and IPv6)
                        if !newPorts.contains(where: { $0.port == item.port && $0.processName == item.processName }) {
                            newPorts.append(item)
                        }
                    }
                }
            }

            DispatchQueue.main.async {
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
