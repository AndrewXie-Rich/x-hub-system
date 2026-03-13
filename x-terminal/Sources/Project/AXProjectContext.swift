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

    var supervisorJobsURL: URL {
        xterminalDir.appendingPathComponent("supervisor_jobs.json")
    }

    var supervisorPlansURL: URL {
        xterminalDir.appendingPathComponent("supervisor_plans.json")
    }

    var supervisorSkillCallsURL: URL {
        xterminalDir.appendingPathComponent("supervisor_skill_calls.json")
    }

    var supervisorSkillResultsDir: URL {
        xterminalDir.appendingPathComponent("supervisor_skill_results", isDirectory: true)
    }

    var resolvedSkillsCacheURL: URL {
        xterminalDir.appendingPathComponent("resolved_skills_cache.json")
    }

    var usageLogURL: URL {
        xterminalDir.appendingPathComponent("usage.jsonl")
    }

    var configURL: URL {
        xterminalDir.appendingPathComponent("config.json")
    }

    var browserRuntimeDir: URL {
        xterminalDir.appendingPathComponent("browser_runtime", isDirectory: true)
    }

    var browserRuntimeSessionURL: URL {
        browserRuntimeDir.appendingPathComponent("session.json")
    }

    var browserRuntimeSnapshotsDir: URL {
        browserRuntimeDir.appendingPathComponent("snapshots", isDirectory: true)
    }

    var browserRuntimeProfilesDir: URL {
        browserRuntimeDir.appendingPathComponent("profiles", isDirectory: true)
    }

    var browserRuntimeActionLogURL: URL {
        browserRuntimeDir.appendingPathComponent("action_log.jsonl")
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

    func supervisorSkillResultEvidenceURL(requestId: String) -> URL {
        let base = requestId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let safe = base.isEmpty ? UUID().uuidString.lowercased() : base
        return supervisorSkillResultsDir.appendingPathComponent("\(safe).json")
    }
}
