import Foundation

enum GitTool {
    static func isGitRepo(root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
    }

    static func status(root: URL) throws -> ProcessResult {
        try ProcessCapture.run("/usr/bin/git", ["status", "--porcelain=v1"], cwd: root, timeoutSec: 10.0)
    }

    static func diff(root: URL, cached: Bool = false) throws -> ProcessResult {
        let args = cached ? ["diff", "--cached"] : ["diff"]
        return try ProcessCapture.run("/usr/bin/git", args, cwd: root, timeoutSec: 20.0)
    }

    static func diffFile(root: URL, path: String) throws -> ProcessResult {
        // Path is passed to git; still guard it's inside the project root.
        let url = FileTool.resolvePath(path, projectRoot: root)
        try PathGuard.requireInside(root: root, target: url)

        return try ProcessCapture.run("/usr/bin/git", ["diff", "--", url.path], cwd: root, timeoutSec: 20.0)
    }
}
