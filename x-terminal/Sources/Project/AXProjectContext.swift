import Foundation

struct AXProjectContext: Equatable {
    let root: URL

    var xterminalDir: URL {
        root.appendingPathComponent(".xterminal", isDirectory: true)
    }

    var memoryJSONURL: URL {
        xterminalDir.appendingPathComponent("ax_memory.json")
    }

    var memoryMarkdownURL: URL {
        xterminalDir.appendingPathComponent("AX_MEMORY.md")
    }

    var rawLogURL: URL {
        xterminalDir.appendingPathComponent("raw_log.jsonl")
    }

    var usageLogURL: URL {
        xterminalDir.appendingPathComponent("usage.jsonl")
    }

    var configURL: URL {
        xterminalDir.appendingPathComponent("config.json")
    }

    func ensureDirs() throws {
        try FileManager.default.createDirectory(at: xterminalDir, withIntermediateDirectories: true)

        // Keep project memory local by default when the project is a git repo.
        // Users can still override their repo-level .gitignore if desired.
        let gi = xterminalDir.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: gi.path) {
            let s = "*\n!.gitignore\n"
            try? s.data(using: .utf8)?.write(to: gi, options: .atomic)
        }

        // Create a default config on first run.
        if !FileManager.default.fileExists(atPath: configURL.path) {
            let cfg = AXProjectConfig.default(forProjectRoot: root)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(cfg) {
                try? data.write(to: configURL, options: .atomic)
            }
        }
    }

    func projectName() -> String {
        root.lastPathComponent
    }
}
