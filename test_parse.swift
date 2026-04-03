import Foundation

struct PortItem {
    let processName: String
    let pid: String
    let port: String
    let protocolName: String
}

struct ShellHelper {
    static func executeCommand(command: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error executing shell command \(command): \(error)")
            return nil
        }
    }
}

guard let output = ShellHelper.executeCommand(command: "/usr/sbin/lsof", arguments: ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]) else {
    print("No output from executeCommand")
    exit(1)
}

print("Raw output first 200 chars:")
print(String(output.prefix(200)))

var newPorts: [PortItem] = []
let lines = output.components(separatedBy: .newlines).filter { '/Users/nano/Documents/Projects/Port Killer/Port Killer'0.isEmpty }

print("\nParsing lines (skipping first)...")
for line in lines.dropFirst() {
    let columns = line.components(separatedBy: .whitespaces).filter { '/Users/nano/Documents/Projects/Port Killer/Port Killer'0.isEmpty }
    
    if columns.count >= 9 {
        let processName = columns[0]
        let pid = columns[1]
        let nameColumn = columns[8]
        
        if let portRange = nameColumn.range(of: ":\\d+", options: .regularExpression) {
            let portString = String(nameColumn[portRange].dropFirst())
            let item = PortItem(processName: processName, pid: pid, port: portString, protocolName: "TCP")
            
            if !newPorts.contains(where: { $0.port == item.port && $0.processName == item.processName }) {
                newPorts.append(item)
            }
        }
    }
}

print("\nFound ports: \(newPorts.count)")
for p in newPorts {
    print("\(p.processName) - \(p.port)")
}
