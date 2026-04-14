import XCTest
@testable import RELFlowHub

final class HubLocalRuntimeWatchdogTests: XCTestCase {
    func testHealthyProbeResetsFailuresAndDoesNotRestart() {
        let evaluation = HubLocalRuntimeWatchdog.evaluate(
            now: 100,
            launchAt: 10,
            consecutiveFailureCount: 2,
            lastRestartAt: 0,
            pairingHealthy: true
        )

        XCTAssertEqual(evaluation.nextFailureCount, 0)
        XCTAssertFalse(evaluation.shouldRestart)
    }

    func testUnhealthyProbeWithinStartupGraceDoesNotAccumulateFailures() {
        let evaluation = HubLocalRuntimeWatchdog.evaluate(
            now: 20,
            launchAt: 12,
            consecutiveFailureCount: 2,
            lastRestartAt: 0,
            pairingHealthy: false
        )

        XCTAssertTrue(evaluation.withinStartupGrace)
        XCTAssertEqual(evaluation.nextFailureCount, 0)
        XCTAssertFalse(evaluation.shouldRestart)
    }

    func testUnhealthyProbeTriggersRestartAfterThresholdOutsideGrace() {
        let evaluation = HubLocalRuntimeWatchdog.evaluate(
            now: 40,
            launchAt: 10,
            consecutiveFailureCount: 2,
            lastRestartAt: 0,
            pairingHealthy: false
        )

        XCTAssertFalse(evaluation.withinStartupGrace)
        XCTAssertEqual(evaluation.nextFailureCount, HubLocalRuntimeWatchdog.unhealthyThreshold)
        XCTAssertTrue(evaluation.shouldRestart)
    }

    func testRestartCooldownSuppressesImmediateRepeatedRestart() {
        let evaluation = HubLocalRuntimeWatchdog.evaluate(
            now: 50,
            launchAt: 10,
            consecutiveFailureCount: 2,
            lastRestartAt: 20,
            pairingHealthy: false
        )

        XCTAssertTrue(evaluation.inRestartCooldown)
        XCTAssertEqual(evaluation.nextFailureCount, HubLocalRuntimeWatchdog.unhealthyThreshold)
        XCTAssertFalse(evaluation.shouldRestart)
    }
}
