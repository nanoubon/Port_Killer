import AppKit
import SwiftUI

/// Process icon: the enclosing app bundle's icon when the executable lives inside a `.app`,
/// otherwise a small tinted SF Symbol tile chosen from the process name and path.
struct ProcessIconView: View {
    let processName: String
    let path: String?
    var size: CGFloat = 18
    var isRunning = true

    var body: some View {
        Group {
            if let path, let image = ProcessIcon.appIcon(forExecutable: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                let symbol = ProcessIcon.symbol(for: processName, path: path)
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(symbol.color.gradient)
                    .overlay {
                        Image(systemName: symbol.name)
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .saturation(isRunning ? 1 : 0)
        .opacity(isRunning ? 1 : 0.5)
        .accessibilityHidden(true)
    }
}

enum ProcessIcon {
    struct Symbol {
        let name: String
        let color: Color
    }

    private static var pathCache: [String: String?] = [:]
    private static var iconCache: [String: NSImage] = [:]

    private static let databases = ["postgres", "mysql", "mariadb", "mongo", "redis", "memcached", "clickhouse", "elasticsearch", "cockroach"]
    private static let webServers = ["nginx", "httpd", "caddy", "apache", "traefik", "envoy"]
    private static let runtimes = ["node", "python", "ruby", "java", "php", "deno", "bun", "dotnet", "beam", "erl", "uvicorn", "gunicorn", "rails", "vite", "next"]
    private static let systemPathPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/"]

    /// Executable path of a live PID, cached per PID + name (PIDs can be recycled).
    static func executablePath(pid: String, processName: String) -> String? {
        let key = "\(pid)|\(processName)"
        if let cached = pathCache[key] { return cached }
        let path = Int32(pid).flatMap { ProcessInspector.executablePath(of: $0) }
        if pathCache.count > 512 { pathCache.removeAll() }
        pathCache[key] = path
        return path
    }

    /// Icon of the outermost `.app` bundle containing `path` (helpers resolve to their host app).
    static func appIcon(forExecutable path: String) -> NSImage? {
        guard let bundle = appBundlePath(containing: path) else { return nil }
        if let cached = iconCache[bundle] { return cached }
        let image = NSWorkspace.shared.icon(forFile: bundle)
        iconCache[bundle] = image
        return image
    }

    static func appBundlePath(containing path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components[...index]))
    }

    static func symbol(for processName: String, path: String?) -> Symbol {
        let name = processName.lowercased()
        if KillSafety.isDocker(processName: processName) {
            return Symbol(name: "shippingbox.fill", color: .blue)
        }
        if databases.contains(where: { name.hasPrefix($0) }) {
            return Symbol(name: "cylinder.split.1x2.fill", color: .indigo)
        }
        if webServers.contains(where: { name.hasPrefix($0) }) {
            return Symbol(name: "server.rack", color: .teal)
        }
        if runtimes.contains(where: { name.hasPrefix($0) }) {
            return Symbol(name: "chevron.left.forwardslash.chevron.right", color: .green)
        }
        if let path, systemPathPrefixes.contains(where: { path.hasPrefix($0) }) {
            return Symbol(name: "gearshape.fill", color: .gray)
        }
        return Symbol(name: "terminal.fill", color: .gray)
    }
}

/// IANA port range, shown as the tint of `PortBadge`.
enum PortRange {
    case wellKnown, registered, ephemeral

    init(_ port: Int) {
        switch port {
        case ..<1024: self = .wellKnown
        case 49152...: self = .ephemeral
        default: self = .registered
        }
    }

    var color: Color {
        switch self {
        case .wellKnown: .orange
        case .registered: .accentColor
        case .ephemeral: .gray
        }
    }

    var help: String {
        switch self {
        case .wellKnown: "พอร์ตระบบ (0–1023)"
        case .registered: "พอร์ตทั่วไป (1024–49151)"
        case .ephemeral: "พอร์ตชั่วคราว (49152 ขึ้นไป)"
        }
    }
}

/// Monospaced port number on a tint of its range. Text stays primary for contrast.
struct PortBadge: View {
    let port: String
    var isRunning = true

    var body: some View {
        let range = PortRange(Int(port) ?? 0)
        let tint = isRunning ? range.color : .gray
        Text(port)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundStyle(isRunning ? HierarchicalShapeStyle.primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(tint.opacity(0.35)))
            .help(range.help)
    }
}

/// Where a listener accepts connections from.
enum AddressScope {
    case allInterfaces, loopback, specific

    init(_ addresses: [String]) {
        if addresses.contains(where: { ["*", "0.0.0.0", "::"].contains($0) }) {
            self = .allInterfaces
        } else if !addresses.isEmpty, addresses.allSatisfy(AddressScope.isLoopback) {
            self = .loopback
        } else {
            self = .specific
        }
    }

    private nonisolated static func isLoopback(_ address: String) -> Bool {
        address.hasPrefix("127.") || address == "::1" || address == "localhost" || address.hasSuffix("%lo0")
    }

    var symbol: String {
        switch self {
        case .allInterfaces: "globe"
        case .loopback: "laptopcomputer"
        case .specific: "network"
        }
    }

    var color: Color {
        switch self {
        case .allInterfaces: .orange
        case .loopback: .green
        case .specific: .blue
        }
    }

    var help: String {
        switch self {
        case .allInterfaces: "เปิดรับจากทุก interface (เครื่องอื่นในเครือข่ายเข้าถึงได้)"
        case .loopback: "เฉพาะเครื่องนี้ (loopback)"
        case .specific: "เฉพาะ interface ที่ระบุ"
        }
    }
}

/// Count chip for the main window's summary bar.
struct StatChip: View {
    let symbol: String
    let tint: Color
    let text: String
    var help: String = ""
    /// Full text for VoiceOver when `text` is shortened (compact chips).
    var spokenText: String?
    var pulses = false
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: pulses && !reduceMotion)
                .accessibilityHidden(true)
            Text(text)
                .monospacedDigit()
        }
        .font(compact ? .caption : .callout)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 2 : 3)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenText ?? text)
    }
}

/// System Settings-style icon tile for a Settings row.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    init(_ symbol: String, color: Color) {
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Live-port counts and chips shared by the main window and the popover. Counts cover all live
/// ports; `shown` (rows matching `query`) appears only while a search is active.
struct PortSummaryBar: View {
    @EnvironmentObject private var viewModel: PortViewModel
    let shown: Int
    let query: String
    /// Popover: smaller chips, secondary counts as icon + number only.
    var compact = false

    var body: some View {
        let all = viewModel.rows(matching: "")
        let live = all.filter(\.isRunning)
        let pinned = all.filter(\.isPinned).count
        let docker = live.filter(\.isDocker).count
        let readOnly = live.filter(\.isReadOnly).count
        let exposed = live.filter { AddressScope($0.item?.addresses ?? []) == .allInterfaces }.count
        let isFiltering = !query.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: compact ? 4 : 6) {
            StatChip(
                symbol: "circle.fill", tint: .green, text: "\(live.count) listening",
                help: viewModel.isAutoRefreshEnabled ? "รีเฟรชอัตโนมัติทุก \(Int(viewModel.refreshIntervalSeconds)) วินาที" : "รีเฟรชอัตโนมัติปิดอยู่",
                pulses: viewModel.isAutoRefreshEnabled, compact: compact
            )
            if exposed > 0 {
                StatChip(symbol: "globe", tint: .orange, text: compact ? "\(exposed)" : "\(exposed) เปิดสู่เครือข่าย",
                         help: AddressScope.allInterfaces.help, spokenText: "\(exposed) เปิดสู่เครือข่าย", compact: compact)
            }
            if pinned > 0 {
                StatChip(symbol: "pin.fill", tint: .yellow, text: compact ? "\(pinned)" : "\(pinned) pinned",
                         help: "pinned", spokenText: "\(pinned) pinned", compact: compact)
            }
            if docker > 0 {
                StatChip(symbol: "shippingbox.fill", tint: .blue, text: compact ? "\(docker)" : "\(docker) Docker",
                         help: "Docker", spokenText: "\(docker) Docker", compact: compact)
            }
            if readOnly > 0 {
                StatChip(symbol: "lock.fill", tint: .secondary, text: compact ? "\(readOnly)" : "\(readOnly) อ่านอย่างเดียว",
                         help: "เป็นของ root หรือผู้ใช้อื่น ปิดจากแอปนี้ไม่ได้", spokenText: "\(readOnly) อ่านอย่างเดียว", compact: compact)
            }
            Spacer(minLength: 4)
            if isFiltering {
                Text(compact ? "\(shown)/\(all.count)" : "แสดง \(shown) จาก \(all.count)")
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("แสดง \(shown) จาก \(all.count)")
            }
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 7)
        .frame(maxWidth: .infinity)
    }
}
