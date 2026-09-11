import Foundation
import Testing
@testable import XTerminal

struct ProcessCaptureTests {
    @Test
    func drainsLargeStdoutWithoutDeadlocking() throws {
        let result = try ProcessCapture.run(
            "/bin/zsh",
            ["-f", "-c", "yes x | head -c 1048576"],
            cwd: nil,
            timeoutSec: 5,
            maxOutputBytes: 2 * 1024 * 1024
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 1_048_576)
        #expect(result.outputTruncated == false)
    }

    @Test
    func boundsOutputAndReportsTruncation() throws {
        let result = try ProcessCapture.run(
            "/bin/zsh",
            ["-f", "-c", "yes x | head -c 1048576"],
            cwd: nil,
            timeoutSec: 5,
            maxOutputBytes: 4096,
            outputLimitBehavior: .truncate
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.count <= 4096)
        #expect(result.outputTruncated)
    }

    @Test
    func timeoutTerminatesTheProcessGroup() throws {
        #expect(throws: Error.self) {
            _ = try ProcessCapture.run(
                "/bin/zsh",
                ["-f", "-c", "sleep 5"],
                cwd: nil,
                timeoutSec: 0.1
            )
        }
    }

    @Test
    func executionSafetyContract() async throws {
        try await ExecutionSafetyRegression.runAll()
    }

    @Test
    func managedProcessLifecycleAndLogSafetyContract() async throws {
        try await ManagedProcessSafetyRegression.runAll()
    }
}
