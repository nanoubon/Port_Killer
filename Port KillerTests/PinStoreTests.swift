import XCTest
@testable import Port_Killer

final class PinStoreTests: XCTestCase {
    private func item(_ name: String, port: String, pid: String = "100") -> PortItem {
        PortItem(processName: name, pid: pid, port: port, user: "alice")
    }

    private func store(_ pairs: (String, String)...) -> PinStore {
        PinStore(bookmarks: pairs.map { PortBookmark(port: $0.0, processName: $0.1) })
    }

    func testExactMatchIsPinned() {
        let s = store(("3000", "node"))
        XCTAssertTrue(s.isPinned(item("node", port: "3000")))
    }

    func testNoSubstringMatch() {
        let s = store(("3000", "node"))
        XCTAssertFalse(s.isPinned(item("nodemon", port: "3000")))
        XCTAssertFalse(s.isPinned(item("no", port: "3000")))
    }

    func testNoBarePortFallback() {
        let s = store(("3000", "node"))
        XCTAssertFalse(s.isPinned(item("python3", port: "3000")))
        XCTAssertFalse(s.isPinned(item("node", port: "3001")))
    }

    func testToggleAddsAndRemovesExactPairOnly() {
        var s = PinStore()
        XCTAssertTrue(s.toggle(item("node", port: "3000")))
        XCTAssertTrue(s.toggle(item("python3", port: "3000")))
        XCTAssertEqual(s.bookmarks.count, 2)
        XCTAssertFalse(s.toggle(item("node", port: "3000")))
        XCTAssertEqual(s.bookmarks.map(\.processName), ["python3"])
    }

    func testPinnedSortToTopKeepingOtherOrder() {
        let s = store(("9000", "ruby"))
        let items = [item("a", port: "80"), item("ruby", port: "9000"), item("b", port: "443")]
        XCTAssertEqual(s.sortedPinnedFirst(items).map(\.processName), ["ruby", "a", "b"])
    }

    func testNotRunningPlaceholder() {
        let s = store(("3000", "node"), ("5432", "postgres"))
        let entries = s.entries(live: [item("node", port: "3000")])
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].isRunning)
        XCTAssertFalse(entries[1].isRunning)
        XCTAssertNil(entries[1].liveItem)
        // A different process on the pinned port must not satisfy the pin.
        let other = s.entries(live: [item("python3", port: "5432")])
        XCTAssertFalse(other[1].isRunning)
    }

    func testPlaceholderCanBeUnpinned() {
        var s = store(("5432", "postgres"))
        s.remove(s.bookmarks[0])
        XCTAssertTrue(s.bookmarks.isEmpty)
    }

    func testMigratesTruncatedNameWhenPortMatchesAndPrefix() {
        var s = store(("8080", "com.docke"))
        let changed = s.migrateTruncatedNames(live: [item("com.docker.backend", port: "8080")])
        XCTAssertTrue(changed)
        XCTAssertEqual(s.bookmarks.map(\.processName), ["com.docker.backend"])
        XCTAssertTrue(s.isPinned(item("com.docker.backend", port: "8080")))
    }

    func testNoMigrationWhenPortDiffers() {
        var s = store(("8080", "com.docke"))
        let changed = s.migrateTruncatedNames(live: [item("com.docker.backend", port: "9090")])
        XCTAssertFalse(changed)
        XCTAssertEqual(s.bookmarks.map(\.processName), ["com.docke"])
    }

    func testNoMigrationWhenNotPrefixOrNotTruncatedLength() {
        var s = store(("8080", "com.docke"), ("3000", "node"))
        let changed = s.migrateTruncatedNames(live: [item("other.thing.long", port: "8080"), item("nodemon", port: "3000")])
        XCTAssertFalse(changed)
        XCTAssertEqual(s.bookmarks.map(\.processName), ["com.docke", "node"])
    }

    func testMigrationDoesNotDuplicateExistingFullPin() {
        var s = store(("8080", "com.docke"), ("8080", "com.docker.backend"))
        s.migrateTruncatedNames(live: [item("com.docker.backend", port: "8080")])
        XCTAssertEqual(s.bookmarks.map(\.processName), ["com.docker.backend"])
    }

    func testPersistenceRoundTripWithThrowawaySuite() throws {
        let name = "PinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        var s = PinStore()
        s.toggle(item("node", port: "3000"))
        s.toggle(item("ruby", port: "9000"))
        s.save(to: defaults, key: "k")

        let loaded = PinStore.load(from: defaults, key: "k")
        XCTAssertEqual(loaded, s)
        XCTAssertTrue(PinStore.load(from: defaults, key: "missing").bookmarks.isEmpty)
    }

    func testMigrationPersists() throws {
        let name = "PinStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        var s = store(("8080", "com.docke"))
        if s.migrateTruncatedNames(live: [item("com.docker.backend", port: "8080")]) { s.save(to: defaults, key: "k") }
        XCTAssertEqual(PinStore.load(from: defaults, key: "k").bookmarks.map(\.processName), ["com.docker.backend"])
    }
}
