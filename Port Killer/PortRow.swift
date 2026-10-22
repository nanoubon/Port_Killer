import Foundation

/// One line in the main table / popover: a live listener, or a pinned port that is not running.
struct PortRow: Identifiable, Hashable {
    let id: String
    /// nil = pinned but not running (dimmed, unpin only).
    let item: PortItem?
    let bookmark: PortBookmark
    let isPinned: Bool

    var isRunning: Bool { item != nil }
    var isReadOnly: Bool { item?.isReadOnly ?? false }
    var isKillable: Bool { isRunning && !isReadOnly }

    var port: String { item?.port ?? bookmark.port }
    var portNumber: Int { Int(port) ?? 0 }
    var processName: String { KillSafety.normalizedName(item?.processName ?? bookmark.processName) }
    var pid: String { item?.pid ?? "—" }
    var pidNumber: Int { item.flatMap { Int($0.pid) } ?? Int.max }
    var ownerLabel: String? { isReadOnly ? item?.ownerLabel : nil }
    var userText: String {
        guard let item else { return "—" }
        return item.isReadOnly ? (item.ownerLabel ?? item.user ?? "—") : (item.user ?? "—")
    }
    var addressText: String {
        guard let item, !item.addresses.isEmpty else { return "—" }
        return item.addresses.joined(separator: ", ")
    }
    var isDocker: Bool { KillSafety.isDocker(processName: processName) }
}

extension PortViewModel {
    /// Live rows matching `query` (pinned first), followed by nothing else: pinned-but-not-running
    /// rows are merged in at the top. Returns [] before the first scan completes.
    func rows(matching query: String) -> [PortRow] {
        guard hasLoadedLivePorts else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let live = ports(matching: trimmed).map {
            PortRow(id: $0.id, item: $0, bookmark: PortBookmark(portItem: $0), isPinned: isPinned($0))
        }
        let notRunning = pinnedEntries.filter { !$0.isRunning }.filter { entry in
            trimmed.isEmpty
                || entry.bookmark.port.localizedCaseInsensitiveContains(trimmed)
                || entry.bookmark.processName.localizedCaseInsensitiveContains(trimmed)
        }.map {
            PortRow(id: "pin-\($0.bookmark.id)", item: nil, bookmark: $0.bookmark, isPinned: true)
        }
        return live.filter(\.isPinned) + notRunning + live.filter { !$0.isPinned }
    }
}
