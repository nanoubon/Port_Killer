import Foundation

struct PortItem: Identifiable, Hashable {
    let processName: String
    let pid: String
    let port: String
    var user: String?
    /// Bind addresses (merged IPv4 + IPv6), e.g. ["*"] or ["127.0.0.1", "::1"].
    var addresses: [String]
    /// Seen only through netstat (root / other user): display only, must never be killed from the app.
    var isReadOnly: Bool
    /// "root", a username, or "other user" for read-only rows.
    var ownerLabel: String?

    var id: String {
        "\(port)-\(pid)-\(processName)"
    }

    init(
        processName: String,
        pid: String,
        port: String,
        user: String? = nil,
        addresses: [String] = [],
        isReadOnly: Bool = false,
        ownerLabel: String? = nil
    ) {
        self.processName = processName
        self.pid = pid
        self.port = port
        self.user = user
        self.addresses = addresses
        self.isReadOnly = isReadOnly
        self.ownerLabel = ownerLabel
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PortItem, rhs: PortItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct PortBookmark: Identifiable, Codable, Hashable {
    let id: String
    let port: String
    let processName: String
    let user: String?

    init(port: String, processName: String, user: String? = nil) {
        self.id = "\(port)-\(processName)"
        self.port = port
        self.processName = processName
        self.user = user
    }

    init(portItem: PortItem) {
        self.init(port: portItem.port, processName: portItem.processName, user: portItem.user)
    }
}
