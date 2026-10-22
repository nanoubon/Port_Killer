import Foundation

/// Warnings shown in the kill confirmation dialog. Pure data, no UI.
enum KillWarning: Hashable, Sendable {
    case docker
    case system
    case otherUser
    case selfProcess

    var message: String {
        switch self {
        case .docker:
            return "เป็น Docker: จะหยุด container ทุกตัว"
        case .system:
            return "เป็น process ของระบบ macOS: การปิดอาจทำให้บางฟีเจอร์ของระบบหยุดทำงาน"
        case .otherUser:
            return "เป็น process ของ user อื่น: น่าจะไม่มีสิทธิ์ปิด"
        case .selfProcess:
            return "นี่คือ Port Killer เอง: ไม่อนุญาตให้ปิด"
        }
    }

    /// A blocking warning forbids the kill entirely.
    var isBlocking: Bool { self == .selfProcess }
}

enum KillSafety {
    private static let systemPathPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/"]
    private static let knownSystemNames = ["ControlCenter", "ControlCe", "rapportd", "AirPlayXPCHelper"]
    private static let dockerNamePrefixes = ["com.docker", "vpnkit", "docker"]

    static func classify(
        _ item: PortItem,
        currentUser: String,
        ownPID: Int32,
        executablePath: (Int32) -> String?
    ) -> [KillWarning] {
        var warnings: [KillWarning] = []
        let pid = Int32(item.pid)
        let name = normalizedName(item.processName)

        if dockerNamePrefixes.contains(where: { name.lowercased().hasPrefix($0) }) {
            warnings.append(.docker)
        }

        var isSystem = knownSystemNames.contains(name)
        if !isSystem, let pid, let path = executablePath(pid) {
            isSystem = systemPathPrefixes.contains { path.hasPrefix($0) }
        }
        if isSystem { warnings.append(.system) }

        if let user = item.user, !usersMatch(user, currentUser) {
            warnings.append(.otherUser)
        }

        if let pid, pid == ownPID {
            warnings.append(.selfProcess)
        }
        return warnings
    }

    /// True only if the PID still exists, still has the scanned name and still listens on the port.
    static func revalidate(
        _ item: PortItem,
        currentProcessName: (Int32) -> String?,
        stillListeningOnPort: (Int32, Int) -> Bool
    ) -> Bool {
        guard let pid = Int32(item.pid), let port = Int(item.port) else { return false }
        guard let liveName = currentProcessName(pid) else { return false }
        guard namesMatch(item.processName, liveName) else { return false }
        return stillListeningOnPort(pid, port)
    }

    /// lsof truncates names and escapes spaces as \x20, so compare with prefix tolerance.
    static func namesMatch(_ scanned: String, _ live: String) -> Bool {
        let a = normalizedName(scanned)
        let b = normalizedName(live)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    static func normalizedName(_ name: String) -> String {
        name.replacingOccurrences(of: "\\x20", with: " ")
    }

    /// lsof truncates long user names to 8 characters.
    private static func usersMatch(_ scanned: String, _ current: String) -> Bool {
        if scanned == current { return true }
        return scanned.count >= 8 && current.hasPrefix(scanned)
    }
}
