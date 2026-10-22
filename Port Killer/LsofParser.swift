import Foundation

/// One listening process+port, with IPv4/IPv6 rows already merged.
struct PortScanSnapshot: Sendable, Hashable {
    let processName: String
    let pid: String
    let user: String
    let port: String
    /// Bind addresses without brackets, in first-seen order ("*", "127.0.0.1", "::1", "fe80::1%lo0").
    let addresses: [String]
    /// True for rows that only netstat could see (root / other users): shown, never killable.
    let isReadOnly: Bool
    /// "root", a username, or "other user". Only set for read-only rows.
    let ownerLabel: String?

    nonisolated init(
        processName: String, pid: String, user: String, port: String, addresses: [String] = [],
        isReadOnly: Bool = false, ownerLabel: String? = nil
    ) {
        self.processName = processName
        self.pid = pid
        self.user = user
        self.port = port
        self.addresses = addresses
        self.isReadOnly = isReadOnly
        self.ownerLabel = ownerLabel
    }
}

/// Pure parser for `lsof -iTCP -sTCP:LISTEN -P -n +c 0 -F pcLun` output. No I/O, no actor state.
///
/// Field output is line based: the first character is the field id, the rest is the value.
/// `p` starts a process record; `c`, `L`, `u` apply to that process; every `n` line is one socket
/// belonging to the current process. Unknown fields (e.g. `f`) are ignored.
enum LsofParser {
    nonisolated static func parse(_ output: String) -> [PortScanSnapshot] {
        struct Entry {
            var processName: String
            var user: String
            var addresses: [String]
        }

        var order: [String] = []
        var entries: [String: Entry] = [:]

        var pid: String?
        var command = ""
        var login = ""
        var uid = ""

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch tag {
            case "p":
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                pid = (Int(trimmed).map { $0 > 0 } ?? false) ? trimmed : nil
                command = ""
                login = ""
                uid = ""
            case "c":
                command = decodeEscapes(value)
            case "L":
                login = decodeEscapes(value)
            case "u":
                uid = value
            case "n":
                guard let pid, let parts = splitName(decodeEscapes(value)) else { continue }
                let (address, port) = (parts.address, parts.port)
                let key = "\(pid):\(port)"
                if var entry = entries[key] {
                    if !entry.addresses.contains(address) { entry.addresses.append(address) }
                    entries[key] = entry
                } else {
                    order.append(key)
                    entries[key] = Entry(
                        processName: command.isEmpty ? "pid \(pid)" : command,
                        user: login.isEmpty ? uid : login,
                        addresses: [address]
                    )
                }
            default:
                continue
            }
        }

        return order.compactMap { key in
            guard let entry = entries[key], let colon = key.firstIndex(of: ":") else { return nil }
            return PortScanSnapshot(
                processName: entry.processName,
                pid: String(key[..<colon]),
                user: entry.user,
                port: String(key[key.index(after: colon)...]),
                addresses: entry.addresses
            )
        }
    }

    /// Splits "[::1]:3000" into ("::1", "3000") using the LAST colon. Rejects ports outside 1...65535.
    nonisolated static func splitName(_ name: String) -> (address: String, port: String)? {
        // Defensive: a connected socket looks like "a:1->b:2"; only the local side matters.
        let local = name.components(separatedBy: "->").first ?? name
        guard let colon = local.lastIndex(of: ":") else { return nil }
        let portText = local[local.index(after: colon)...]
        guard !portText.isEmpty, portText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = Int(portText), (1...65535).contains(port) else { return nil }
        var address = String(local[..<colon])
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        return (address.isEmpty ? "*" : address, String(port))
    }

    /// Decodes every `\xHH` byte escape, then interprets the byte sequence as UTF-8.
    nonisolated static func decodeEscapes(_ text: String) -> String {
        guard text.contains("\\x") else { return text }
        let input = Array(text.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(input.count)
        var i = 0
        while i < input.count {
            if input[i] == 0x5C, i + 3 < input.count, input[i + 1] == 0x78,
               let hi = hexValue(input[i + 2]), let lo = hexValue(input[i + 3]) {
                bytes.append(UInt8(hi << 4 | lo))
                i += 4
            } else {
                bytes.append(input[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private nonisolated static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case 0x30...0x39: return Int(byte) - 0x30
        case 0x41...0x46: return Int(byte) - 0x41 + 10
        case 0x61...0x66: return Int(byte) - 0x61 + 10
        default: return nil
        }
    }
}
