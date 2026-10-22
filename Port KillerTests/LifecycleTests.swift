import XCTest
@testable import Port_Killer

@MainActor
final class LifecycleTests: XCTestCase {
    func testSurfaceVisibilityIsIdempotentSetNotRefCount() {
        let vm = PortViewModel()
        vm.setAutoRefreshEnabled(true)
        vm.setSurface("popover", visible: true)
        vm.setSurface("popover", visible: true)
        XCTAssertEqual(vm.visibleSurfaces, ["popover"])
        XCTAssertTrue(vm.isAutoRefreshRunning)
        vm.setSurface("popover", visible: false)
        vm.setSurface("popover", visible: false)
        XCTAssertTrue(vm.visibleSurfaces.isEmpty)
        XCTAssertFalse(vm.isAutoRefreshRunning)
    }

    func testTimerRunsWhileAnySurfaceVisible() {
        let vm = PortViewModel()
        vm.setAutoRefreshEnabled(true)
        vm.setSurface("main", visible: true)
        vm.setSurface("popover", visible: true)
        vm.setSurface("popover", visible: false)
        XCTAssertTrue(vm.isAutoRefreshRunning)
        vm.setSurface("main", visible: false)
        XCTAssertFalse(vm.isAutoRefreshRunning)
    }

    func testBannerShownInOneOriginAndDurationScalesWithLength() {
        let vm = PortViewModel()
        vm.showBanner("x", origin: .menuBar)
        XCTAssertEqual(vm.bannerOrigin, .menuBar)
        vm.showBanner("y", origin: .mainWindow)
        XCTAssertEqual(vm.bannerOrigin, .mainWindow)
        XCTAssertEqual(PortViewModel.bannerDuration(for: "short"), 5)
        XCTAssertGreaterThan(PortViewModel.bannerDuration(for: String(repeating: "a", count: 240)), 5)
        vm.dismissBanner()
        XCTAssertNil(vm.resultBanner)
    }

    func testRowAccessibilitySummary() {
        let item = PortItem(processName: "node", pid: "42", port: "3000", user: "alice", isReadOnly: true, ownerLabel: "root")
        let row = PortRow(id: item.id, item: item, bookmark: PortBookmark(portItem: item), isPinned: true)
        let text = row.accessibilitySummary
        for part in ["Port 3000", "node", "PID 42", "Pinned", "อ่านอย่างเดียว"] {
            XCTAssertTrue(text.contains(part), part)
        }
        let gone = PortRow(id: "pin-x", item: nil, bookmark: PortBookmark(port: "5432", processName: "postgres"), isPinned: true)
        XCTAssertTrue(gone.accessibilitySummary.contains("ไม่ได้รัน"))
        XCTAssertFalse(gone.accessibilitySummary.contains("PID"))
        XCTAssertEqual(PortRow.spoken("—"), "ไม่มี")
    }

    func testLsofExitOneWithEmptyStdoutIsNoListenersEvenWithStderr() throws {
        let result = ShellCommandResult(standardOutput: "", standardError: "lsof: WARNING: can't stat() fuse", exitStatus: 1)
        XCTAssertEqual(try PortScanService.interpretLsof(result), [])
    }

    func testLsofOtherExitCodesSurfaceStderr() {
        let result = ShellCommandResult(standardOutput: "", standardError: "boom", exitStatus: 2)
        XCTAssertThrowsError(try PortScanService.interpretLsof(result)) {
            XCTAssertEqual($0.localizedDescription, "boom")
        }
        let timedOut = ShellCommandResult(standardOutput: "", standardError: "", exitStatus: -1, timedOut: true)
        XCTAssertThrowsError(try PortScanService.interpretLsof(timedOut))
    }
}
