import Foundation

struct AXProjectContext: Equatable {
    let root: URL

    var xterminalDir: URL {
        root.appendingPathComponent(".xterminal", isDirectory: true)
    }

    var legacyAxcoderDir: URL {
        root.appendingPathComponent(".axcoder", isDirectory: true)
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
        try migrateLegacyDataDirIfNeeded()
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

    private func migrateLegacyDataDirIfNeeded() throws {
        let fm = FileManager.default
        let modern = xterminalDir
        let legacy = legacyAxcoderDir

        let hasModern = fm.fileExists(atPath: modern.path)
        let hasLegacy = fm.fileExists(atPath: legacy.path)
        guard hasLegacy else { return }

        if !hasModern {
            do {
                try fm.moveItem(at: legacy, to: modern)
                return
            } catch {
                try fm.createDirectory(at: modern, withIntermediateDirectories: true)
            }
        }

        guard let items = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let dest = modern.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath)
            if fm.fileExists(atPath: dest.path) { continue }
            if (try? fm.moveItem(at: item, to: dest)) == nil {
                try? fm.copyItem(at: item, to: dest)
            }
        }

        if let remain = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil),
           remain.isEmpty {
            try? fm.removeItem(at: legacy)
        }
    }
}
