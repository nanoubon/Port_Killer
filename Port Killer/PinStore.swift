import Foundation

/// A pinned port together with the live process currently holding it (nil = not running).
struct PinnedEntry: Identifiable, Hashable {
    let bookmark: PortBookmark
    let liveItem: PortItem?

    var id: String { bookmark.id }
    var isRunning: Bool { liveItem != nil }
}

/// Pure pin logic (no UI). A pin is identified by the exact pair (port, process name).
/// There is no substring match and no bare-port fallback.
struct PinStore: Equatable {
    static let defaultsKey = "PortKiller.pinnedBookmarks"
    /// lsof truncates command names to 9 characters; only such names are migration candidates.
    static let legacyTruncatedNameLength = 9

    private(set) var bookmarks: [PortBookmark]

    init(bookmarks: [PortBookmark] = []) {
        self.bookmarks = bookmarks
    }

    // MARK: Persistence

    static func load(from defaults: UserDefaults = .standard, key: String = defaultsKey) -> PinStore {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PortBookmark].self, from: data) else {
            return PinStore()
        }
        return PinStore(bookmarks: decoded)
    }

    func save(to defaults: UserDefaults = .standard, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: Matching

    func isPinned(port: String, processName: String) -> Bool {
        bookmarks.contains { $0.port == port && $0.processName == processName }
    }

    func isPinned(_ item: PortItem) -> Bool {
        isPinned(port: item.port, processName: item.processName)
    }

    /// Returns true when the item is pinned after the call.
    @discardableResult
    mutating func toggle(_ item: PortItem) -> Bool {
        if let index = bookmarks.firstIndex(where: { $0.port == item.port && $0.processName == item.processName }) {
            bookmarks.remove(at: index)
            return false
        }
        bookmarks.insert(PortBookmark(portItem: item), at: 0)
        return true
    }

    mutating func remove(_ bookmark: PortBookmark) {
        bookmarks.removeAll { $0.port == bookmark.port && $0.processName == bookmark.processName }
    }

    // MARK: Ordering and placeholders

    /// Pinned items first (stable: relative order is otherwise unchanged).
    func sortedPinnedFirst(_ items: [PortItem]) -> [PortItem] {
        items.filter(isPinned) + items.filter { !isPinned($0) }
    }

    /// One entry per bookmark, in bookmark order. `liveItem` is nil when the port is not listening.
    func entries(live: [PortItem]) -> [PinnedEntry] {
        bookmarks.map { bookmark in
            PinnedEntry(
                bookmark: bookmark,
                liveItem: live.first { $0.port == bookmark.port && $0.processName == bookmark.processName }
            )
        }
    }

    // MARK: Migration

    /// True while some bookmark still has a name that could be a truncated lsof name.
    var hasMigrationCandidates: Bool {
        bookmarks.contains { $0.processName.count == Self.legacyTruncatedNameLength }
    }

    /// Upgrades bookmarks saved with a truncated (9 char) lsof name to the full name when the live
    /// items on the same port offer exactly one longer name that starts with the stored one. An
    /// ambiguous port (two different longer names) is left alone. Returns true if anything changed.
    @discardableResult
    mutating func migrateTruncatedNames(live: [PortItem]) -> Bool {
        var changed = false
        var result: [PortBookmark] = []
        for bookmark in bookmarks {
            let hasExactLive = live.contains { $0.port == bookmark.port && $0.processName == bookmark.processName }
            let longerNames = Set(live.compactMap { item -> String? in
                guard item.port == bookmark.port,
                      item.processName.count > bookmark.processName.count,
                      item.processName.hasPrefix(bookmark.processName) else { return nil }
                return item.processName
            })
            guard !hasExactLive,
                  bookmark.processName.count == Self.legacyTruncatedNameLength,
                  longerNames.count == 1,
                  let fullName = longerNames.first else {
                result.append(bookmark)
                continue
            }
            changed = true
            let upgraded = PortBookmark(port: bookmark.port, processName: fullName, user: bookmark.user)
            if !result.contains(where: { $0.id == upgraded.id }) && !bookmarks.contains(where: { $0.id == upgraded.id }) {
                result.append(upgraded)
            }
        }
        if changed { bookmarks = result }
        return changed
    }
}
