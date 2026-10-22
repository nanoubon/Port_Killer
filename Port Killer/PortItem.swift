import AppKit
import Foundation

enum AppSection: String, CaseIterable, Identifiable, Codable {
    case activePorts
    case favorites
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activePorts: return "Active Ports"
        case .favorites: return "Favorites"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .activePorts: return "Real-time listening sockets"
        case .favorites: return "Pinned environments and quick access"
        case .settings: return "App preferences and configuration"
        }
    }

    var symbolName: String {
        switch self {
        case .activePorts: return "antenna.radiowaves.left.and.right"
        case .favorites: return "star.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum PortState: String, Codable, Hashable {
    case listening
    case idle
    case busy
    case dormant

    var displayTitle: String {
        switch self {
        case .listening: return "LISTENING"
        case .idle: return "IDLE"
        case .busy: return "BUSY"
        case .dormant: return "DORMANT"
        }
    }

    var accentSymbol: String {
        switch self {
        case .listening: return "circle.fill"
        case .idle: return "circle.dashed"
        case .busy: return "triangle.fill"
        case .dormant: return "pause.circle.fill"
        }
    }
}

struct PortItem: Identifiable, Hashable {
    let processName: String
    let pid: String
    let port: String
    let protocolName: String
    var icon: NSImage?
    var state: PortState
    var user: String?
    var command: String?
    var uptime: String?
    var loadDescription: String?
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
        protocolName: String,
        icon: NSImage? = nil,
        state: PortState = .listening,
        user: String? = nil,
        command: String? = nil,
        uptime: String? = nil,
        loadDescription: String? = nil,
        addresses: [String] = [],
        isReadOnly: Bool = false,
        ownerLabel: String? = nil
    ) {
        self.processName = processName
        self.pid = pid
        self.port = port
        self.protocolName = protocolName
        self.icon = icon
        self.state = state
        self.user = user
        self.command = command
        self.uptime = uptime
        self.loadDescription = loadDescription
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

extension NSImage {
    static func symbol(_ name: String, accessibilityDescription: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
    }
}
