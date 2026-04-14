import XCTest
@testable import RELFlowHub

final class ProcessCaptureSupportTests: XCTestCase {
    func testRunCaptureCollectsEnvironmentBackedStdout() {
        let result = ProcessCaptureSupport.runCapture(
            "/bin/sh",
            ["-c", "printf '%s' \"$RELFLOWHUB_TEST_VALUE\""],
            env: ["RELFLOWHUB_TEST_VALUE": "probe-ok"],
            timeoutSec: 1.0
        )

        XCTAssertEqual(result.code, 0)
        XCTAssertEqual(result.out, "probe-ok")
        XCTAssertEqual(result.err, "")
    }

    func testWaitForExitCanTimeoutWithoutRunLoopPumping() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.3"]
        try process.run()

        XCTAssertFalse(ProcessWaitSupport.waitForExit(process, timeoutSec: 0.05))

        process.terminate()
        XCTAssertTrue(ProcessWaitSupport.waitForExit(process, timeoutSec: 1.0))
    }
}
