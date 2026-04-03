import Foundation
import AppKit // Required for NSImage

struct PortItem: Identifiable, Hashable {
    let id = UUID()
    let processName: String
    let pid: String
    let port: String
    let protocolName: String
    var icon: NSImage? // Holds the application icon if found

    // NSImage doesn't conform to Hashable, so we provide a custom implementation.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PortItem, rhs: PortItem) -> Bool {
        lhs.id == rhs.id
    }
}
