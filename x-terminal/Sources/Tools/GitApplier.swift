import Foundation

enum GitApplier {
    static func checkPatch(_ patch: String, cwd: URL) throws -> (exit: Int32, output: String) {
        let res = try ProcessCapture.run(
            "/usr/bin/git",
            ["apply", "--check", "-"],
            cwd: cwd,
            stdin: patch.data(using: .utf8),
            timeoutSec: 20.0
        )
        return (res.exitCode, res.combined)
    }

    static func applyPatch(_ patch: String, cwd: URL) throws -> (exit: Int32, output: String) {
        let precheck = try checkPatch(patch, cwd: cwd)
        if precheck.exit != 0 {
            let detail = precheck.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = detail.isEmpty ? "precheck_failed" : "precheck_failed\n\(detail)"
            return (precheck.exit, output)
        }

        let res = try ProcessCapture.run(
            "/usr/bin/git",
            ["apply", "-"],
            cwd: cwd,
            stdin: patch.data(using: .utf8),
            timeoutSec: 20.0
        )
        return (res.exitCode, res.combined)
    }
}
