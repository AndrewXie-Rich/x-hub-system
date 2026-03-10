import Foundation

enum FileTool {
    static func resolvePath(_ path: String, projectRoot: URL) -> URL {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return projectRoot }

        if p.hasPrefix("/") {
            return URL(fileURLWithPath: p)
        }
        // Treat as project-relative.
        return projectRoot.appendingPathComponent(p)
    }

    static func readText(path: String, projectRoot: URL, maxBytes: Int = 512_000) throws -> String {
        let url = resolvePath(path, projectRoot: projectRoot)
        try PathGuard.requireInside(root: projectRoot, target: url)

        let data = try Data(contentsOf: url)
        if data.count > maxBytes {
            let prefix = data.prefix(maxBytes)
            let s = String(decoding: prefix, as: UTF8.self)
            return s + "\n\n[x-terminal] truncated: \(data.count) bytes > \(maxBytes) bytes"
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func writeText(path: String, content: String, projectRoot: URL, createDirs: Bool = true) throws {
        let url = resolvePath(path, projectRoot: projectRoot)
        try PathGuard.requireInside(root: projectRoot, target: url)

        if createDirs {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func listDir(path: String, projectRoot: URL) throws -> [String] {
        let url = resolvePath(path, projectRoot: projectRoot)
        try PathGuard.requireInside(root: projectRoot, target: url)

        let items = try FileManager.default.contentsOfDirectory(atPath: url.path)
        return items.sorted()
    }

    static func search(pattern: String, projectRoot: URL, glob: String? = nil, maxResults: Int = 200) throws -> [String] {
        let pat = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if pat.isEmpty { return [] }

        // Prefer ripgrep when available.
        if let rg = findExecutable(["/opt/homebrew/bin/rg", "/usr/local/bin/rg", "/usr/bin/rg"]) {
            var args: [String] = ["--line-number", "--no-heading", "--smart-case", "--max-count", String(maxResults)]
            if let g = glob?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                args += ["--glob", g]
            }
            args.append(pat)
            args.append(projectRoot.path)

            let res = try ProcessCapture.run(rg, args, cwd: projectRoot, timeoutSec: 20.0)
            if res.exitCode == 0 {
                return res.stdout.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
            }
            // rg returns 1 when no matches.
            if res.exitCode == 1 {
                return []
            }
            throw NSError(domain: "xterminal", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.combined])
        }

        // Fallback to grep.
        let grepExe = "/usr/bin/grep"
        let args: [String] = ["-RIn", "--", pat, projectRoot.path]
        let res = try ProcessCapture.run(grepExe, args, cwd: projectRoot, timeoutSec: 20.0)
        if res.exitCode == 0 {
            return res.stdout.split(separator: "\n", omittingEmptySubsequences: true).prefix(maxResults).map { String($0) }
        }
        if res.exitCode == 1 {
            return []
        }
        throw NSError(domain: "xterminal", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.combined])
    }

    private static func findExecutable(_ candidates: [String]) -> String? {
        for p in candidates {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }
}
