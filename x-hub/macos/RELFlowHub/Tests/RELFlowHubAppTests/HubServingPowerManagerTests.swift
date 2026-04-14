import XCTest
@testable import RELFlowHub

@MainActor
final class HubServingPowerManagerTests: XCTestCase {
    func testDefaultsEnableSystemAwakeButNotDisplayAwake() {
        let driver = FakeHubServingPowerAssertionDriver()
        let caffeinateDriver = FakeHubServingCaffeinateDriver()
        let manager = makeManager(driver: driver, caffeinateDriver: caffeinateDriver)

        XCTAssertTrue(manager.keepSystemAwakeWhileServing)
        XCTAssertFalse(manager.keepDisplayAwakeWhileServing)
        XCTAssertEqual(manager.statusText, HubUIStrings.Settings.GRPC.ServingPower.statusStandby)
        XCTAssertNil(caffeinateDriver.runningArguments)
    }

    func testAutoStartAcquiresSystemAssertionAndPublishesActiveStatus() {
        let driver = FakeHubServingPowerAssertionDriver()
        let caffeinateDriver = FakeHubServingCaffeinateDriver()
        let manager = makeManager(driver: driver, caffeinateDriver: caffeinateDriver)

        manager.refreshServingState(
            autoStartEnabled: true,
            serverRunning: true,
            externalHost: "hub.tailnet.example"
        )

        XCTAssertEqual(driver.systemAcquireReasons.count, 1)
        XCTAssertEqual(driver.displayAcquireReasons.count, 0)
        XCTAssertEqual(manager.statusText, HubUIStrings.Settings.GRPC.ServingPower.statusSystemOnly)
        XCTAssertTrue(manager.detailText.contains("hub.tailnet.example"))
        XCTAssertEqual(caffeinateDriver.runningArguments, ["-i", "-m", "-s"])
    }

    func testRunningServerKeepsSystemAwakeEvenWhenAutoStartIsDisabled() {
        let driver = FakeHubServingPowerAssertionDriver()
        let caffeinateDriver = FakeHubServingCaffeinateDriver()
        let manager = makeManager(driver: driver, caffeinateDriver: caffeinateDriver)

        manager.refreshServingState(
            autoStartEnabled: false,
            serverRunning: true,
            externalHost: "hub.tailnet.example"
        )

        XCTAssertEqual(driver.systemAcquireReasons.count, 1)
        XCTAssertEqual(driver.displayAcquireReasons.count, 0)
        XCTAssertEqual(manager.statusText, HubUIStrings.Settings.GRPC.ServingPower.statusSystemOnly)
        XCTAssertTrue(manager.detailText.contains("hub.tailnet.example"))
        XCTAssertEqual(caffeinateDriver.runningArguments, ["-i", "-m", "-s"])
    }

    func testEnablingDisplayAwakeAcquiresDisplayAssertionAndSystemToggleReleaseBoth() {
        let driver = FakeHubServingPowerAssertionDriver()
        let caffeinateDriver = FakeHubServingCaffeinateDriver()
        let manager = makeManager(driver: driver, caffeinateDriver: caffeinateDriver)

        manager.refreshServingState(
            autoStartEnabled: true,
            serverRunning: true,
            externalHost: nil
        )
        manager.keepDisplayAwakeWhileServing = true

        XCTAssertEqual(driver.systemAcquireReasons.count, 1)
        XCTAssertEqual(driver.displayAcquireReasons.count, 1)
        XCTAssertEqual(manager.statusText, HubUIStrings.Settings.GRPC.ServingPower.statusSystemAndDisplay)
        XCTAssertEqual(caffeinateDriver.runningArguments, ["-d", "-i", "-m", "-s"])

        manager.keepSystemAwakeWhileServing = false

        XCTAssertEqual(driver.releasedAssertionIDs.count, 2)
        XCTAssertEqual(manager.statusText, HubUIStrings.Settings.GRPC.ServingPower.statusDisabled)
        XCTAssertNil(caffeinateDriver.runningArguments)
        XCTAssertEqual(caffeinateDriver.stopCount, 2)
    }

    func testAcquireFailureSurfacesUserFacingError() {
        let driver = FakeHubServingPowerAssertionDriver()
        driver.failSystemAcquire = true
        let caffeinateDriver = FakeHubServingCaffeinateDriver()
        let manager = makeManager(driver: driver, caffeinateDriver: caffeinateDriver)

        manager.refreshServingState(
            autoStartEnabled: true,
            serverRunning: false,
            externalHost: nil
        )

        XCTAssertTrue(manager.lastError.contains("在线保活失败"))
    }

    func testCaffeinateFailureStillStartsSystemAssertionAndKeepsStatusActive() {
        let driver = FakeHubServingPowerAssertionDriver()
        let caffeinateDriver = FakeHubServingCaffeinateDriver()
        caffeinateDriver.failStart = true
        let manager = makeManager(driver: driver, caffeinateDriver: caffeinateDriver)

        manager.refreshServingState(
            autoStartEnabled: true,
            serverRunning: true,
            externalHost: nil
        )

        XCTAssertEqual(driver.systemAcquireReasons.count, 1)
        XCTAssertNil(caffeinateDriver.runningArguments)
        XCTAssertEqual(manager.statusText, HubUIStrings.Settings.GRPC.ServingPower.statusSystemOnly)
    }

    private func makeManager(
        driver: FakeHubServingPowerAssertionDriver,
        caffeinateDriver: FakeHubServingCaffeinateDriver
    ) -> HubServingPowerManager {
        let suiteName = "HubServingPowerManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return HubServingPowerManager(driver: driver, caffeinateDriver: caffeinateDriver, defaults: defaults)
    }
}

private final class FakeHubServingPowerAssertionDriver: HubServingPowerAssertionDriving {
    var failSystemAcquire: Bool = false
    var failDisplayAcquire: Bool = false
    var nextAssertionID: UInt32 = 1
    var systemAcquireReasons: [String] = []
    var displayAcquireReasons: [String] = []
    var releasedAssertionIDs: [UInt32] = []

    func acquireSystemIdleSleep(reason: String) -> Result<UInt32, HubServingPowerAssertionFailure> {
        systemAcquireReasons.append(reason)
        if failSystemAcquire {
            return .failure(HubServingPowerAssertionFailure(message: "fake_system_error"))
        }
        defer { nextAssertionID += 1 }
        return .success(nextAssertionID)
    }

    func acquireDisplayIdleSleep(reason: String) -> Result<UInt32, HubServingPowerAssertionFailure> {
        displayAcquireReasons.append(reason)
        if failDisplayAcquire {
            return .failure(HubServingPowerAssertionFailure(message: "fake_display_error"))
        }
        defer { nextAssertionID += 1 }
        return .success(nextAssertionID)
    }

    func releaseAssertion(id: UInt32) -> String? {
        releasedAssertionIDs.append(id)
        return nil
    }
}

private final class FakeHubServingCaffeinateDriver: HubServingCaffeinateDriving {
    var failStart: Bool = false
    var runningArguments: [String]?
    var startHistory: [[String]] = []
    var stopCount: Int = 0

    func start(arguments: [String]) -> Result<Void, HubServingPowerAssertionFailure> {
        startHistory.append(arguments)
        if failStart {
            return .failure(HubServingPowerAssertionFailure(message: "fake_caffeinate_error"))
        }
        runningArguments = arguments
        return .success(())
    }

    func stop() -> String? {
        stopCount += 1
        runningArguments = nil
        return nil
    }
}
