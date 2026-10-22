import XCTest
@testable import Port_Killer

/// Uses Fixtures/netstat.txt (bundle resource, same setup as LsofParserTests).
final class NetstatParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: NetstatParserTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func row(_ rows: [NetstatRow], pid: String, port: String) -> NetstatRow? {
        rows.first { $0.pid == pid && $0.port == port }
    }

    func testOnlyListenRowsAreParsedAndDualStackIsMerged() throws {
        let rows = NetstatParser.parse(try fixture("netstat"))
        // rapportd, docker 8000, postgres, node 3000 (tcp4+tcp6 merged), Claude Helper, launchd
        XCTAssertEqual(rows.count, 6)
        XCTAssertNil(row(rows, pid: "27742", port: "64443"))  // ESTABLISHED
        XCTAssertNil(rows.first { $0.pid == "679" })          // SYN_SENT
        XCTAssertNil(rows.first { $0.pid == "12" })           // CLOSED
        XCTAssertEqual(row(rows, pid: "4001", port: "3000")?.addresses, ["::1", "127.0.0.1"])
    }

    func testNamesAndPids() throws {
        let rows = NetstatParser.parse(try fixture("netstat"))
        XCTAssertEqual(row(rows, pid: "675", port: "59963")?.processName, "rapportd")
        XCTAssertEqual(row(rows, pid: "1372", port: "8000")?.processName, "com.docker.backe")
        XCTAssertEqual(row(rows, pid: "27549", port: "9229")?.processName, "Claude Helper")
        XCTAssertEqual(row(rows, pid: "1", port: "59961")?.addresses, ["*"])
        XCTAssertEqual(row(rows, pid: "910", port: "5432")?.addresses, ["127.0.0.1"])
    }

    func testLocalAddressSplitsAtLastDot() {
        XCTAssertEqual(NetstatParser.splitLocal("*.8000")?.port, "8000")
        XCTAssertEqual(NetstatParser.splitLocal("*.8000")?.address, "*")
        XCTAssertEqual(NetstatParser.splitLocal("127.0.0.1.5432")?.address, "127.0.0.1")
        XCTAssertEqual(NetstatParser.splitLocal("::1.3000")?.address, "::1")
        XCTAssertNil(NetstatParser.splitLocal("*.0"))
        XCTAssertNil(NetstatParser.splitLocal("*.65536"))
        XCTAssertNil(NetstatParser.splitLocal("nodot"))
    }

    func testOwnerSplitsAtLastColon() {
        XCTAssertEqual(NetstatParser.splitOwner("Claude Helper:27549")?.name, "Claude Helper")
        XCTAssertEqual(NetstatParser.splitOwner("Claude Helper:27549")?.pid, "27549")
        XCTAssertNil(NetstatParser.splitOwner("kernel_task:0"))
        XCTAssertNil(NetstatParser.splitOwner("noPid"))
        XCTAssertNil(NetstatParser.splitOwner(":12"))
    }

    func testGarbageAndEmptyInput() {
        XCTAssertTrue(NetstatParser.parse("").isEmpty)
        XCTAssertTrue(NetstatParser.parse("Active Internet connections\nProto Recv-Q\nfoo bar").isEmpty)
    }
}
