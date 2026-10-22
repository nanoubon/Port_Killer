import Foundation

/// One listening pid+port seen by `netstat`, with IPv4/IPv6 rows already merged.
struct NetstatRow: Sendable, Hashable {
    /// Truncated by netstat to 16 characters; may contain spaces.
    let processName: String
    let pid: String
    let port: String
    /// Bind addresses in first-seen order ("*", "127.0.0.1", "::1").
    let addresses: [String]

    nonisolated init(processName: String, pid: String, port: String, addresses: [String]) {
        self.processName = processName
        self.pid = pid
        self.port = port
        self.addresses = addresses
    }
}

/// Pure parser for `netstat -anv -p tcp`. No I/O, no actor state.
///
/// Only LISTEN rows are used. The `process:pid` column can contain spaces ("Claude Helper:27549"),
/// so it is located by position: the columns before it are fixed (proto, recv-q, send-q, local,
/// foreign, state, rxbytes, txbytes, rhiwat, shiwat = 10 tokens) and 8 fixed columns follow it
/// (state, options, gencnt, flags, flags1, usecnt, rtncnt, fltrs). The pid is read from the right
/// of the column, after the last colon.
enum NetstatParser {
    private nonisolated static let leadingColumns = 10
    private nonisolated static let trailingColumns = 8

    nonisolated static func parse(_ output: String) -> [NetstatRow] {
        struct Entry {
            var processName: String
            var addresses: [String]
        }
        var order: [String] = []
        var entries: [String: Entry] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard tokens.count >= leadingColumns + 1 + trailingColumns,
                  tokens[0].hasPrefix("tcp"),
                  tokens[5] == "LISTEN",
                  let local = splitLocal(String(tokens[3])),
                  let owner = splitOwner(tokens[leadingColumns..<(tokens.count - trailingColumns)].joined(separator: " "))
            else { continue }

            let key = "\(owner.pid):\(local.port)"
            if var entry = entries[key] {
                if !entry.addresses.contains(local.address) { entry.addresses.append(local.address) }
                entries[key] = entry
            } else {
                order.append(key)
                entries[key] = Entry(processName: owner.name, addresses: [local.address])
            }
        }

        return order.compactMap { key in
            guard let entry = entries[key], let colon = key.firstIndex(of: ":") else { return nil }
            return NetstatRow(
                processName: entry.processName,
                pid: String(key[..<colon]),
                port: String(key[key.index(after: colon)...]),
                addresses: entry.addresses
            )
        }
    }

    /// Splits "127.0.0.1.5432" / "::1.3000" / "*.8000" at the LAST dot. Rejects ports outside 1...65535.
    nonisolated static func splitLocal(_ text: String) -> (address: String, port: String)? {
        guard let dot = text.lastIndex(of: ".") else { return nil }
        let portText = text[text.index(after: dot)...]
        guard !portText.isEmpty, portText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let port = Int(portText), (1...65535).contains(port) else { return nil }
        let address = String(text[..<dot])
        return (address.isEmpty ? "*" : address, String(port))
    }

    /// Splits "Claude Helper:27549" at the LAST colon. Rejects pid <= 0 or a missing name.
    nonisolated static func splitOwner(_ text: String) -> (name: String, pid: String)? {
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let pidText = text[text.index(after: colon)...]
        guard !pidText.isEmpty, pidText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let pid = Int(pidText), pid > 0 else { return nil }
        let name = text[..<colon].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return (name, String(pid))
    }
}
