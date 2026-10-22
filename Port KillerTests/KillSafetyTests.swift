import XCTest
@testable import Port_Killer

final class KillSafetyTests: XCTestCase {
    private let me: UInt32 = 501

    private func item(name: String = "node", pid: String = "4242", port: String = "3000", user: String? = "alice") -> PortItem {
        PortItem(processName: name, pid: pid, port: port, user: user)
    }

    private func ident(uid: UInt32 = 501, path: String? = "/usr/local/bin/node") -> ProcessIdentity {
        ProcessIdentity(startSeconds: 100, startMicroseconds: 5, uid: uid, path: path)
    }

    private func classify(
        _ i: PortItem,
        user: String = "alice",
        ownPID: Int32 = 1,
        path: String? = nil,
        identity: ProcessIdentity? = nil
    ) -> [KillWarning] {
        KillSafety.classify(i, currentUser: user, currentUID: me, ownPID: ownPID,
                            executablePath: { _ in path }, identity: { _ in identity })
    }

    // MARK: classify

    func testClassifyPlainOwnProcessHasNoWarnings() {
        XCTAssertEqual(classify(item(), identity: ident()), [])
    }

    func testClassifyDockerByNamePrefixCaseInsensitive() {
        XCTAssertTrue(classify(item(name: "com.docker.backend"), identity: ident()).contains(.docker))
        XCTAssertTrue(classify(item(name: "vpnkit-bridge"), identity: ident()).contains(.docker))
        XCTAssertTrue(classify(item(name: "Docker"), identity: ident()).contains(.docker))
    }

    func testClassifySystemByKnownNameAndByPathPrefix() {
        XCTAssertTrue(classify(item(name: "rapportd"), identity: ident()).contains(.system))
        XCTAssertTrue(classify(item(name: "foo"), path: "/System/Library/CoreServices/foo", identity: ident()).contains(.system))
        XCTAssertTrue(classify(item(name: "foo"), path: "/usr/sbin/foo", identity: ident()).contains(.system))
        XCTAssertFalse(classify(item(name: "foo"), path: "/usr/local/bin/foo", identity: ident()).contains(.system))
    }

    func testClassifyOtherUserUsesNumericUIDWhenIdentityAvailable() {
        XCTAssertTrue(classify(item(user: "alice"), identity: ident(uid: 0)).contains(.otherUser))
        // Numeric uid wins over a mismatching lsof user name.
        XCTAssertFalse(classify(item(user: "bob"), identity: ident(uid: 501)).contains(.otherUser))
    }

    func testClassifyOtherUserFallsBackToNameWithoutIdentity() {
        XCTAssertTrue(classify(item(user: "root"), identity: nil).contains(.otherUser))
        XCTAssertFalse(classify(item(user: "alice"), identity: nil).contains(.otherUser))
    }

    func testClassifyTruncatedEightCharUserNameMatchesLongerCurrentUser() {
        XCTAssertFalse(classify(item(user: "nanodev1"), user: "nanodev1987", identity: nil).contains(.otherUser))
        XCTAssertTrue(classify(item(user: "nanodev"), user: "nanodev1987", identity: nil).contains(.otherUser))
    }

    func testClassifySelfProcessIsBlocking() {
        let w = classify(item(pid: "777"), ownPID: 777, identity: ident())
        XCTAssertEqual(w, [.selfProcess])
        XCTAssertTrue(w.allSatisfy(\.isBlocking))
        XCTAssertFalse(KillWarning.docker.isBlocking)
        XCTAssertFalse(KillWarning.system.isBlocking)
        XCTAssertFalse(KillWarning.otherUser.isBlocking)
    }

    func testClassifyNonNumericPidNeverMatchesSelf() {
        XCTAssertFalse(classify(item(pid: "abc"), ownPID: 0, identity: nil).contains(.selfProcess))
    }

    // MARK: namesMatch

    func testNamesMatchExact() {
        XCTAssertTrue(KillSafety.namesMatch("node", "node"))
    }

    func testNamesMatchDecodesEscapedSpace() {
        XCTAssertTrue(KillSafety.namesMatch("Google\\x20Chrome", "Google Chrome"))
    }

    func testNamesMatchNineCharPrefixAccepted() {
        XCTAssertTrue(KillSafety.namesMatch("Google Ch", "Google Chrome Helper"))
        XCTAssertTrue(KillSafety.namesMatch("Google Chrome Helper", "Google Ch"))
    }

    func testNamesMatchRejectsShortPrefix() {
        XCTAssertFalse(KillSafety.namesMatch("node", "node-server-extra"))
        XCTAssertFalse(KillSafety.namesMatch("12345678", "123456789abc")) // 8 chars < 9
    }

    func testNamesMatchRejectsNonPrefixAndEmpty() {
        XCTAssertFalse(KillSafety.namesMatch("Google Chrome", "Chrome Google"))
        XCTAssertFalse(KillSafety.namesMatch("", ""))
        XCTAssertFalse(KillSafety.namesMatch("node", ""))
    }

    func testNamesMatchThaiNames() {
        XCTAssertTrue(KillSafety.namesMatch("แอปทดสอบ", "แอปทดสอบ"))
        XCTAssertFalse(KillSafety.namesMatch("แอปทดสอบ", "แอปอื่น"))
    }

    // MARK: revalidate

    private func revalidate(
        _ i: PortItem? = nil,
        captured: ProcessIdentity? = nil,
        live: ProcessIdentity?? = nil,
        liveName: String?? = nil,
        listening: Bool = true
    ) -> Bool {
        let it = i ?? item()
        let cap = captured ?? ident()
        let liveID: ProcessIdentity? = live ?? cap
        let name: String? = liveName ?? it.processName
        return KillSafety.revalidate(it, captured: cap,
                                     identity: { _ in liveID },
                                     currentProcessName: { _ in name },
                                     stillListeningOnPort: { _, _ in listening })
    }

    func testRevalidateAllMatchPasses() {
        XCTAssertTrue(revalidate())
    }

    func testRevalidateRefusesWhenIdentityChanged() {
        let recycled = ProcessIdentity(startSeconds: 999, startMicroseconds: 5, uid: 501, path: "/usr/local/bin/node")
        XCTAssertFalse(revalidate(live: .some(recycled)))
    }

    func testRevalidateFailsClosedWhenIdentityNil() {
        XCTAssertFalse(revalidate(live: .some(nil)))
    }

    func testRevalidateRefusesWhenNameChanged() {
        XCTAssertFalse(revalidate(liveName: .some("python3-something")))
    }

    func testRevalidateRefusesWhenNameUnavailable() {
        XCTAssertFalse(revalidate(liveName: .some(nil)))
    }

    func testRevalidateRefusesWhenNoLongerListening() {
        XCTAssertFalse(revalidate(listening: false))
    }

    func testRevalidateRefusesWhenPidOrPortNotNumeric() {
        XCTAssertFalse(revalidate(item(pid: "")))
        XCTAssertFalse(revalidate(item(port: "http")))
    }

    func testRevalidateAcceptsLsofTruncatedName() {
        let i = item(name: "Google Ch")
        XCTAssertTrue(revalidate(i, liveName: .some("Google Chrome Helper")))
    }

    // MARK: sanitizeForDisplay

    func testSanitizeStripsControlFormatAndSeparators() {
        let dirty = "a\u{0007}b\u{202E}c\u{200B}d\u{2028}e\u{2029}f\u{0000}g"
        XCTAssertEqual(KillSafety.sanitizeForDisplay(dirty), "abcdefg")
    }

    func testSanitizeCollapsesWhitespaceAndTrims() {
        XCTAssertEqual(KillSafety.sanitizeForDisplay("  a \t  b\u{00A0}\u{00A0}c  "), "a b c")
    }

    func testSanitizeCapsLengthWithEllipsis() {
        let out = KillSafety.sanitizeForDisplay(String(repeating: "x", count: 200), limit: 10)
        XCTAssertEqual(out, String(repeating: "x", count: 9) + "…")
        XCTAssertEqual(out.count, 10)
    }

    func testSanitizeLeavesAtLimitUntouchedAndDefaultLimitIs64() {
        XCTAssertEqual(KillSafety.sanitizeForDisplay("abcde", limit: 5), "abcde")
        XCTAssertEqual(KillSafety.sanitizeForDisplay(String(repeating: "y", count: 64)).count, 64)
        XCTAssertEqual(KillSafety.sanitizeForDisplay(String(repeating: "y", count: 65)).count, 64)
    }

    func testSanitizeKeepsThai() {
        XCTAssertEqual(KillSafety.sanitizeForDisplay("  ทดสอบ   ระบบ "), "ทดสอบ ระบบ")
    }

    func testSanitizeEmptyAndOnlyControl() {
        XCTAssertEqual(KillSafety.sanitizeForDisplay(""), "")
        XCTAssertEqual(KillSafety.sanitizeForDisplay("\u{0001}\u{200B}"), "")
    }
}

final class ProcessKillerServiceGuardTests: XCTestCase {
    // pid 1 (launchd) is refused before any signal is sent; negative pids would target process groups.
    func testTerminateRefusesPidOne() async {
        let outcome = await ProcessKillerService().terminate(pid: 1, verify: { true })
        XCTAssertEqual(outcome, .notPermitted)
    }

    func testForceKillRefusesPidOne() async {
        let outcome = await ProcessKillerService().forceKill(pid: 1, verify: { true })
        XCTAssertEqual(outcome, .notPermitted)
    }

    func testTerminateRefusesVeryNegativePid() async {
        let outcome = await ProcessKillerService().terminate(pid: Int32.min, verify: { true })
        XCTAssertEqual(outcome, .notPermitted)
    }

    func testTerminateReportsAlreadyGoneWithoutSignalWhenVerifyFails() async {
        let outcome = await ProcessKillerService().terminate(pid: 1, verify: { false })
        XCTAssertEqual(outcome, .alreadyGone)
    }
}
