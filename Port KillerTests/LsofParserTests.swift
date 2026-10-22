import XCTest
@testable import Port_Killer

/// Drop this file and the Fixtures/ folder into a unit-test target (Fixtures as bundle resources).
final class LsofParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: LsofParserTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "lsof"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func row(_ rows: [PortScanSnapshot], pid: String, port: String) -> PortScanSnapshot? {
        rows.first { $0.pid == pid && $0.port == port }
    }

    func testNormalMergesDuplicateRowsAndKeepsDistinctPorts() throws {
        let rows = LsofParser.parse(try fixture("normal"))
        XCTAssertEqual(rows.count, 5) // 7000, 5000, 64407, 3000, 3001
        XCTAssertEqual(row(rows, pid: "624", port: "7000")?.addresses, ["*"])
        XCTAssertNotNil(row(rows, pid: "624", port: "5000"))
        XCTAssertEqual(row(rows, pid: "9001", port: "3000")?.addresses, ["127.0.0.1"])
        XCTAssertNotNil(row(rows, pid: "9001", port: "3001"))
        XCTAssertEqual(row(rows, pid: "624", port: "7000")?.processName, "ControlCenter")
        XCTAssertEqual(row(rows, pid: "624", port: "7000")?.user, "nanodev")
    }

    func testIPv6AndDualStack() throws {
        let rows = LsofParser.parse(try fixture("ipv6"))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(row(rows, pid: "100", port: "5432")?.addresses, ["127.0.0.1", "::1"])
        XCTAssertEqual(row(rows, pid: "200", port: "5173")?.addresses, ["*", "::"])
        XCTAssertEqual(row(rows, pid: "300", port: "8080")?.addresses, ["fe80::1%lo0"])
        XCTAssertEqual(row(rows, pid: "300", port: "8080")?.user, "root")
    }

    func testEscapesAreDecodedToUTF8() throws {
        let rows = LsofParser.parse(try fixture("escapes"))
        XCTAssertEqual(row(rows, pid: "4242", port: "9222")?.processName, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(row(rows, pid: "4343", port: "8088")?.processName, "ไทย app")
    }

    func testLongNamesAreNotTruncated() throws {
        let rows = LsofParser.parse(try fixture("docker"))
        XCTAssertEqual(row(rows, pid: "888", port: "8085")?.processName, "com.docker.backend")
        XCTAssertEqual(row(rows, pid: "888", port: "8085")?.addresses, ["127.0.0.1", "::1"])
        XCTAssertEqual(row(rows, pid: "888", port: "3000")?.addresses, ["*"])
        XCTAssertEqual(row(rows, pid: "777", port: "2375")?.processName, "Docker Desktop")
    }

    func testEmptyOutput() throws {
        XCTAssertTrue(LsofParser.parse(try fixture("empty")).isEmpty)
    }

    func testPortValidation() {
        XCTAssertEqual(LsofParser.splitName("[::1]:3000")?.port, "3000")
        XCTAssertEqual(LsofParser.splitName("[::1]:3000")?.address, "::1")
        XCTAssertNil(LsofParser.splitName("*:0"))
        XCTAssertNil(LsofParser.splitName("*:65536"))
        XCTAssertNil(LsofParser.splitName("*:abc"))
        XCTAssertNil(LsofParser.splitName("nocolon"))
        XCTAssertEqual(LsofParser.splitName("*:65535")?.port, "65535")
    }

    func testIdsAreUniquePerProcessPort() throws {
        let rows = LsofParser.parse(try fixture("ipv6")) + LsofParser.parse(try fixture("normal"))
        let ids = rows.map { PortItem(processName: $0.processName, pid: $0.pid, port: $0.port).id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
