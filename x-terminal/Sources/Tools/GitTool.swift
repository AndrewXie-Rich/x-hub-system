import Foundation

enum GitTool {
    static func isGitRepo(root: URL) -> Bool {
        let fm = FileManager.default
        var candidate = root.standardizedFileURL

        while true {
            if fm.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                return true
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return false
            }
            candidate = parent
        }
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
