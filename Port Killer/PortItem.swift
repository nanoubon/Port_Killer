import Foundation
import AppKit // Required for NSImage

struct PortItem: Identifiable, Hashable {
    let id = UUID()
    let processName: String
    let pid: String
    let port: String
    let protocolName: String
    var icon: NSImage? // Holds the application icon if found
}
