import Dispatch
import Foundation

enum XTResolvedSkillsCacheStore {
    private static let queue = DispatchQueue(label: "xterminal.resolved_skills_cache_store")

    static func url(for ctx: AXProjectContext) -> URL {
        ctx.resolvedSkillsCacheURL
    }

    static func load(for ctx: AXProjectContext) -> XTResolvedSkillsCacheSnapshot? {
        queue.sync {
            loadUnlocked(for: ctx)
        }
    }

    static func activeSnapshot(
        for ctx: AXProjectContext,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> XTResolvedSkillsCacheSnapshot? {
        queue.sync {
            guard let snapshot = loadUnlocked(for: ctx) else { return nil }
            guard snapshot.expiresAtMs >= nowMs else { return nil }
            return snapshot
        }
    }

    @discardableResult
    static func refreshFromHub(
        projectId: String,
        projectName: String? = nil,
        context: AXProjectContext,
        hubBaseDir: URL? = nil,
        ttlMs: Int64 = 15 * 60 * 1000,
        nowMs: Int64? = nil
    ) -> XTResolvedSkillsCacheSnapshot? {
        queue.sync {
            guard let snapshot = AXSkillsLibrary.resolvedSkillsCacheSnapshot(
                projectId: projectId,
                projectName: projectName,
                hubBaseDir: hubBaseDir,
                ttlMs: ttlMs,
                nowMs: nowMs
            ) else {
                return nil
            }
            saveUnlocked(snapshot, for: context)
            return snapshot
        }
    }

    static func clear(for ctx: AXProjectContext) {
        queue.sync {
            try? FileManager.default.removeItem(at: url(for: ctx))
        }
    }

    private static func loadUnlocked(for ctx: AXProjectContext) -> XTResolvedSkillsCacheSnapshot? {
        let cacheURL = url(for: ctx)
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(XTResolvedSkillsCacheSnapshot.self, from: data),
              snapshot.schemaVersion == XTResolvedSkillsCacheSnapshot.currentSchemaVersion else {
            return nil
        }
        return snapshot
    }

    private static func saveUnlocked(_ snapshot: XTResolvedSkillsCacheSnapshot, for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url(for: ctx), options: .atomic)
    }
}
