import XCTest
@testable import RELFlowHub

final class LocalRuntimeProviderRecoveryTests: XCTestCase {
    func testPlanReturnsNoneWhenProviderAlreadyReady() {
        let action = LocalRuntimeProviderRecoveryPlanner.plan(
            runtimeAlive: true,
            providerReady: true,
            currentPythonPath: "/usr/bin/python3",
            targetPythonPath: "/Users/test/.venv/bin/python3",
            targetSupportsProvider: true
        )

        XCTAssertEqual(action, .none)
    }

    func testPlanReturnsNoneWhenNoCandidateSupportsProvider() {
        let action = LocalRuntimeProviderRecoveryPlanner.plan(
            runtimeAlive: true,
            providerReady: false,
            currentPythonPath: "/usr/bin/python3",
            targetPythonPath: "/usr/bin/python3",
            targetSupportsProvider: false
        )

        XCTAssertEqual(action, .none)
    }

    func testPlanStartsRuntimeWhenProviderCapablePythonExistsAndRuntimeIsDown() {
        let action = LocalRuntimeProviderRecoveryPlanner.plan(
            runtimeAlive: false,
            providerReady: false,
            currentPythonPath: "/usr/bin/python3",
            targetPythonPath: "/Users/test/Documents/AX/project/.venv/bin/python3",
            targetSupportsProvider: true
        )

        XCTAssertEqual(
            action,
            .start(targetPythonPath: "/Users/test/Documents/AX/project/.venv/bin/python3")
        )
    }

    func testPlanRestartsRuntimeWhenCurrentPythonNowSupportsProvider() {
        let action = LocalRuntimeProviderRecoveryPlanner.plan(
            runtimeAlive: true,
            providerReady: false,
            currentPythonPath: "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11",
            targetPythonPath: "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11",
            targetSupportsProvider: true
        )

        XCTAssertEqual(
            action,
            .restart(targetPythonPath: "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11")
        )
    }
}
