import Foundation
import RELFlowHubCore

// Lightweight file-backed storage helpers for the HubSkills v1 store.
//
// The authoritative writer is the embedded Node gRPC server (hub_grpc_server),
// but the macOS Hub UI reads/writes pins locally so Skills are "visible + usable"
// without requiring a Swift gRPC client.
enum HubSkillsStoreStorage {
    enum PinScope: String, Codable, CaseIterable {
        case memoryCore = "SKILL_PIN_SCOPE_MEMORY_CORE"
        case global = "SKILL_PIN_SCOPE_GLOBAL"
        case project = "SKILL_PIN_SCOPE_PROJECT"

        var shortLabel: String {
            switch self {
            case .memoryCore: return "Memory-Core"
            case .global: return "Global"
            case .project: return "Project"
            }
        }
    }

    struct SkillMeta: Codable, Hashable, Identifiable {
        var skillId: String
        var name: String
        var version: String
        var description: String
        var publisherId: String
        var capabilitiesRequired: [String]
        var sourceId: String
        var packageSha256: String
        var installHint: String

        var id: String {
            "\(skillId)::\(version)::\(sourceId)::\(packageSha256)"
        }

        enum CodingKeys: String, CodingKey {
            case skillId = "skill_id"
            case name
            case version
            case description
            case publisherId = "publisher_id"
            case capabilitiesRequired = "capabilities_required"
            case sourceId = "source_id"
            case packageSha256 = "package_sha256"
            case installHint = "install_hint"
        }
    }

    struct SkillPackageEntry: Codable, Hashable, Identifiable {
        var packageSha256: String
        var skillId: String
        var name: String
        var version: String
        var description: String
        var publisherId: String
        var capabilitiesRequired: [String]
        var sourceId: String
        var installHint: String

        var manifestJson: String?
        var packageSizeBytes: Int64?
        var createdAtMs: Int64?
        var updatedAtMs: Int64?

        var id: String { packageSha256 }

        enum CodingKeys: String, CodingKey {
            case packageSha256 = "package_sha256"
            case skillId = "skill_id"
            case name
            case version
            case description
            case publisherId = "publisher_id"
            case capabilitiesRequired = "capabilities_required"
            case sourceId = "source_id"
            case installHint = "install_hint"
            case manifestJson = "manifest_json"
            case packageSizeBytes = "package_size_bytes"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }

        func toMeta() -> SkillMeta {
            SkillMeta(
                skillId: skillId,
                name: name,
                version: version,
                description: description,
                publisherId: publisherId,
                capabilitiesRequired: capabilitiesRequired,
                sourceId: sourceId,
                packageSha256: packageSha256,
                installHint: installHint
            )
        }
    }

    struct SkillsIndexSnapshot: Codable, Sendable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var skills: [SkillPackageEntry]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case skills
        }
    }

    struct SkillSourceEntry: Codable, Sendable, Identifiable {
        var sourceId: String
        var type: String
        var defaultTrustPolicy: String
        var updatedAtMs: Int64
        var discoveryIndex: [SkillMeta]

        var id: String { sourceId }

        enum CodingKeys: String, CodingKey {
            case sourceId = "source_id"
            case type
            case defaultTrustPolicy = "default_trust_policy"
            case updatedAtMs = "updated_at_ms"
            case discoveryIndex = "discovery_index"
        }
    }

    struct SkillSourcesSnapshot: Codable, Sendable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var sources: [SkillSourceEntry]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case sources
        }
    }

    struct SkillPin: Codable, Hashable, Identifiable {
        var scope: PinScope
        var userId: String?
        var projectId: String?
        var skillId: String
        var packageSha256: String
        var note: String?
        var updatedAtMs: Int64?

        var id: String {
            let u = userId ?? ""
            let p = projectId ?? ""
            return "\(scope.rawValue)::\(u)::\(p)::\(skillId)"
        }

        enum CodingKeys: String, CodingKey {
            case scope
            case userId = "user_id"
            case projectId = "project_id"
            case skillId = "skill_id"
            case packageSha256 = "package_sha256"
            case note
            case updatedAtMs = "updated_at_ms"
        }
    }

    struct SkillPinsSnapshot: Codable, Sendable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var memoryCorePins: [SkillPin]
        var globalPins: [SkillPin]
        var projectPins: [SkillPin]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case memoryCorePins = "memory_core_pins"
            case globalPins = "global_pins"
            case projectPins = "project_pins"
        }
    }

    struct ResolvedSkill: Identifiable, Hashable {
        var scope: PinScope
        var pin: SkillPin
        var meta: SkillMeta?

        var id: String { "\(scope.rawValue)::\(pin.id)" }
    }

    // MARK: - Paths

    static func skillsStoreDir(baseDir: URL? = nil) -> URL {
        let base = baseDir ?? SharedPaths.ensureHubDirectory()
        return base.appendingPathComponent("skills_store", isDirectory: true)
    }

    static func skillsIndexURL(baseDir: URL? = nil) -> URL {
        skillsStoreDir(baseDir: baseDir).appendingPathComponent("skills_store_index.json")
    }

    static func skillsPinsURL(baseDir: URL? = nil) -> URL {
        skillsStoreDir(baseDir: baseDir).appendingPathComponent("skills_pins.json")
    }

    static func skillSourcesURL(baseDir: URL? = nil) -> URL {
        skillsStoreDir(baseDir: baseDir).appendingPathComponent("skill_sources.json")
    }

    static func skillPackageURL(packageSha256: String, baseDir: URL? = nil) -> URL {
        skillsStoreDir(baseDir: baseDir)
            .appendingPathComponent("packages", isDirectory: true)
            .appendingPathComponent(packageSha256.lowercased() + ".tgz")
    }

    static func skillManifestURL(packageSha256: String, baseDir: URL? = nil) -> URL {
        skillsStoreDir(baseDir: baseDir)
            .appendingPathComponent("manifests", isDirectory: true)
            .appendingPathComponent(packageSha256.lowercased() + ".json")
    }

    // MARK: - Load/save

    static func loadSkillsIndex(baseDir: URL? = nil) -> SkillsIndexSnapshot {
        let url = skillsIndexURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else {
            return SkillsIndexSnapshot(schemaVersion: "skills_store_index.v1", updatedAtMs: 0, skills: [])
        }
        return (try? JSONDecoder().decode(SkillsIndexSnapshot.self, from: data))
            ?? SkillsIndexSnapshot(schemaVersion: "skills_store_index.v1", updatedAtMs: 0, skills: [])
    }

    static func loadSkillPins(baseDir: URL? = nil) -> SkillPinsSnapshot {
        let url = skillsPinsURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else {
            return SkillPinsSnapshot(schemaVersion: "skills_pins.v1", updatedAtMs: 0, memoryCorePins: [], globalPins: [], projectPins: [])
        }
        return (try? JSONDecoder().decode(SkillPinsSnapshot.self, from: data))
            ?? SkillPinsSnapshot(schemaVersion: "skills_pins.v1", updatedAtMs: 0, memoryCorePins: [], globalPins: [], projectPins: [])
    }

    static func saveSkillPins(_ snap: SkillPinsSnapshot, baseDir: URL? = nil) throws {
        let url = skillsPinsURL(baseDir: baseDir)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data0 = try enc.encode(snap)
        let data = (String(data: data0, encoding: .utf8) ?? "") + "\n"
        try Data(data.utf8).write(to: url, options: .atomic)
    }

    static func loadSkillSources(baseDir: URL? = nil) -> SkillSourcesSnapshot {
        let url = skillSourcesURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else {
            return SkillSourcesSnapshot(schemaVersion: "skill_sources.v1", updatedAtMs: 0, sources: [])
        }
        return (try? JSONDecoder().decode(SkillSourcesSnapshot.self, from: data))
            ?? SkillSourcesSnapshot(schemaVersion: "skill_sources.v1", updatedAtMs: 0, sources: [])
    }

    // MARK: - Operations

    static func setPin(
        scope: PinScope,
        userId: String?,
        projectId: String?,
        skillId: String,
        packageSha256: String,
        note: String? = nil,
        baseDir: URL? = nil
    ) throws -> (previousSha: String, updated: SkillPin?) {
        let sid = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uid = (userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = (projectId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { return ("", nil) }

        var pins = loadSkillPins(baseDir: baseDir)
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        pins.updatedAtMs = now

        func upsert(_ arr: inout [SkillPin], pred: (SkillPin) -> Bool, newPin: SkillPin?) -> String {
            var prev = ""
            var out: [SkillPin] = []
            out.reserveCapacity(arr.count + 1)
            for p in arr {
                if pred(p) {
                    prev = p.packageSha256
                    continue
                }
                out.append(p)
            }
            if let np = newPin, !np.packageSha256.isEmpty {
                out.append(np)
            }
            arr = out
            return prev
        }

        let np: SkillPin? = {
            if sha.isEmpty {
                return nil
            }
            return SkillPin(
                scope: scope,
                userId: uid.isEmpty ? nil : uid,
                projectId: pid.isEmpty ? nil : pid,
                skillId: sid,
                packageSha256: sha,
                note: note,
                updatedAtMs: now
            )
        }()

        let previous: String
        switch scope {
        case .memoryCore:
            previous = upsert(&pins.memoryCorePins, pred: { $0.skillId == sid }, newPin: np)
        case .global:
            previous = upsert(&pins.globalPins, pred: { ($0.userId ?? "") == uid && $0.skillId == sid }, newPin: np)
        case .project:
            previous = upsert(&pins.projectPins, pred: { ($0.userId ?? "") == uid && ($0.projectId ?? "") == pid && $0.skillId == sid }, newPin: np)
        }

        try saveSkillPins(pins, baseDir: baseDir)
        return (previous, np)
    }

    static func resolvedSkills(index: SkillsIndexSnapshot, pins: SkillPinsSnapshot, userId: String, projectId: String) -> [ResolvedSkill] {
        let uid = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = projectId.trimmingCharacters(in: .whitespacesAndNewlines)

        var bySha: [String: SkillMeta] = [:]
        bySha.reserveCapacity(index.skills.count)
        for it in index.skills {
            let sha = it.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if sha.isEmpty { continue }
            bySha[sha] = it.toMeta()
        }

        func addPins(_ arr: [SkillPin], scope: PinScope, pred: (SkillPin) -> Bool, into out: inout [ResolvedSkill]) {
            for p in arr {
                if !pred(p) { continue }
                let sha = p.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let meta = sha.isEmpty ? nil : bySha[sha]
                out.append(ResolvedSkill(scope: scope, pin: p, meta: meta))
            }
        }

        var all: [ResolvedSkill] = []
        addPins(pins.memoryCorePins, scope: .memoryCore, pred: { _ in true }, into: &all)
        if !uid.isEmpty {
            addPins(pins.globalPins, scope: .global, pred: { ($0.userId ?? "") == uid }, into: &all)
            if !pid.isEmpty {
                addPins(pins.projectPins, scope: .project, pred: { ($0.userId ?? "") == uid && ($0.projectId ?? "") == pid }, into: &all)
            }
        }

        var seen = Set<String>()
        var out: [ResolvedSkill] = []
        for r in all {
            let sid = r.pin.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
            if sid.isEmpty { continue }
            if seen.contains(sid) { continue } // precedence is defined by insertion order
            seen.insert(sid)
            out.append(r)
        }
        return out
    }

    static func searchSkills(index: SkillsIndexSnapshot, sources: SkillSourcesSnapshot, query: String, limit: Int = 30) -> [SkillMeta] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lim = max(1, min(100, limit))

        struct Row {
            var meta: SkillMeta
            var uploaded: Bool
            var sortUpdatedAtMs: Int64
            var score: Int
        }

        func score(_ meta: SkillMeta, query: String) -> Int {
            if query.isEmpty { return 0 }
            let needle = query
            var s = 0
            if meta.skillId.lowercased().contains(needle) { s += 100 }
            if meta.name.lowercased().contains(needle) { s += 80 }
            if meta.description.lowercased().contains(needle) { s += 50 }
            if meta.publisherId.lowercased().contains(needle) { s += 20 }
            if meta.sourceId.lowercased().contains(needle) { s += 5 }
            if meta.capabilitiesRequired.contains(where: { $0.lowercased().contains(needle) }) { s += 10 }
            return s
        }

        var merged: [Row] = []
        merged.reserveCapacity(index.skills.count + 16)

        for it in index.skills {
            let meta = it.toMeta()
            merged.append(
                Row(
                    meta: meta,
                    uploaded: true,
                    sortUpdatedAtMs: it.updatedAtMs ?? 0,
                    score: score(meta, query: q)
                )
            )
        }

        for src in sources.sources {
            for raw in src.discoveryIndex {
                let meta = raw
                merged.append(
                    Row(
                        meta: meta,
                        uploaded: !meta.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        sortUpdatedAtMs: src.updatedAtMs,
                        score: score(meta, query: q)
                    )
                )
            }
        }

        // De-dup: prefer uploaded, then higher updated_at.
        var dedup: [String: Row] = [:]
        dedup.reserveCapacity(merged.count)
        for r in merged {
            let key = "\(r.meta.skillId)::\(r.meta.version)::\(r.meta.sourceId)"
            if let prev = dedup[key] {
                if r.uploaded && !prev.uploaded {
                    dedup[key] = r
                    continue
                }
                if r.sortUpdatedAtMs > prev.sortUpdatedAtMs {
                    dedup[key] = r
                    continue
                }
            } else {
                dedup[key] = r
            }
        }

        var out: [Row] = []
        out.reserveCapacity(dedup.count)
        for r in dedup.values {
            if !q.isEmpty, r.score <= 0 { continue }
            out.append(r)
        }

        out.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.uploaded != b.uploaded { return a.uploaded && !b.uploaded }
            if a.sortUpdatedAtMs != b.sortUpdatedAtMs { return a.sortUpdatedAtMs > b.sortUpdatedAtMs }
            return a.meta.skillId.localizedCaseInsensitiveCompare(b.meta.skillId) == .orderedAscending
        }

        return Array(out.prefix(lim)).map { $0.meta }
    }
}
