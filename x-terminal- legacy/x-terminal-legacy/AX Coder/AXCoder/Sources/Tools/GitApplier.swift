import Foundation

enum GitApplier {
    static func applyPatch(_ patch: String, cwd: URL) throws -> (exit: Int32, output: String) {
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
