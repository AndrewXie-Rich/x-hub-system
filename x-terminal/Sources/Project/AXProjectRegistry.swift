import Foundation
import CryptoKit

struct AXProjectEntry: Codable, Identifiable, Equatable {
    var projectId: String
    var rootPath: String
    var displayName: String
    var lastOpenedAt: Double
    var manualOrderIndex: Int?
    var pinned: Bool
    var statusDigest: String?
    var currentStateSummary: String?
    var nextStepSummary: String?
    var blockerSummary: String?
    var lastSummaryAt: Double?
    var lastEventAt: Double?

    var id: String { projectId }
}

struct AXProjectRegistry: Codable, Equatable {
    static let currentVersion = "1.0"
    static let globalHomeId = "__global_home__"

    var version: String
    var updatedAt: Double
    var sortPolicy: String
    var globalHomeVisible: Bool
    var lastSelectedProjectId: String?
    var projects: [AXProjectEntry]

    static func empty() -> AXProjectRegistry {
        AXProjectRegistry(
            version: currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: true,
            lastSelectedProjectId: nil,
            projects: []
        )
    }

    func project(for projectId: String) -> AXProjectEntry? {
        projects.first { $0.projectId == projectId }
    }

    func sortedProjects() -> [AXProjectEntry] {
        projects.sorted { a, b in
            let pa = a.pinned ? 0 : 1
            let pb = b.pinned ? 0 : 1
            if pa != pb { return pa < pb }

            let ma = a.manualOrderIndex ?? Int.max
            let mb = b.manualOrderIndex ?? Int.max
            if ma != mb { return ma < mb }

            if a.lastOpenedAt != b.lastOpenedAt { return a.lastOpenedAt < b.lastOpenedAt }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }
}

enum AXProjectRegistryStore {
    private static let fileName = "projects.json"

    static func baseDir() -> URL {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        if let override = env["XTERMINAL_PROJECT_REGISTRY_BASE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let base = URL(fileURLWithPath: override, isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        }
        if isRunningUnderUnitTests() {
            let base = fm.temporaryDirectory
                .appendingPathComponent("xterminal-tests-support", isDirectory: true)
                .appendingPathComponent("ProjectRegistry", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        }
        let supportBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
        let legacy = supportBase.appendingPathComponent("XTerminal", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        let preferredFile = base.appendingPathComponent(fileName)
        let legacyFile = legacy.appendingPathComponent(fileName)
        if !fm.fileExists(atPath: preferredFile.path),
           fm.fileExists(atPath: legacyFile.path),
           let data = try? Data(contentsOf: legacyFile) {
            try? data.write(to: preferredFile, options: .atomic)
        }

        return base
    }

    static func url() -> URL {
        baseDir().appendingPathComponent(fileName)
    }

    static func load() -> AXProjectRegistry {
        let u = url()
        guard let data = try? Data(contentsOf: u) else { return .empty() }
        guard let decoded = try? JSONDecoder().decode(AXProjectRegistry.self, from: data) else {
            return .empty()
        }
        let sanitized = sanitizeLoadedRegistry(decoded)
        if sanitized.changed {
            save(sanitized.registry)
        }
        return sanitized.registry
    }

    static func save(_ reg: AXProjectRegistry) {
        var cur = reg
        cur.updatedAt = Date().timeIntervalSince1970
        if cur.version.isEmpty { cur.version = AXProjectRegistry.currentVersion }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cur) {
            try? writeAtomic(data: data, to: url())
        }
    }

    private static func defaultDisplayName(forNormalizedRoot normalizedRoot: String) -> String {
        let trimmedRoot = normalizedRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoot.isEmpty else { return "" }
        let rootURL = URL(fileURLWithPath: trimmedRoot, isDirectory: true)
        let basename = rootURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return basename.isEmpty ? trimmedRoot : basename
    }

    private static func resolvedDisplayName(
        existing existingDisplayName: String?,
        existingRootPath: String?,
        projectId: String,
        normalizedRootPath: String
    ) -> String {
        let candidate = defaultDisplayName(forNormalizedRoot: normalizedRootPath)
        let existing = (existingDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existing.isEmpty else { return candidate }
        guard existing != projectId else { return candidate }

        let previousDefault = defaultDisplayName(
            forNormalizedRoot: (existingRootPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if !previousDefault.isEmpty, existing == previousDefault {
            return candidate
        }

        return existing
    }

    static func displayName(
        forRoot root: URL,
        registry: AXProjectRegistry? = nil,
        preferredDisplayName: String? = nil
    ) -> String {
        let normalizedRoot = normalizeRoot(root)
        let projectId = self.projectId(for: normalizedRoot)
        let availableRegistry = registry ?? load()
        let normalizedRegistry = sanitizeLoadedRegistry(availableRegistry).registry

        if let displayName = normalizedRegistry.projects.first(where: { $0.projectId == projectId })?.displayName {
            let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, cleaned != projectId {
                return cleaned
            }
        }

        let preferred = (preferredDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty, preferred != projectId {
            return preferred
        }

        return defaultDisplayName(forNormalizedRoot: normalizedRoot)
    }

    static func upsertProject(_ reg: AXProjectRegistry, root: URL) -> (AXProjectRegistry, AXProjectEntry) {
        let normalized = normalizeRoot(root)
        let pid = projectId(for: normalized)
        let name = defaultDisplayName(forNormalizedRoot: normalized)
        let now = Date().timeIntervalSince1970

        var out = reg
        if let idx = out.projects.firstIndex(where: { $0.projectId == pid }) {
            var cur = out.projects[idx]
            cur.rootPath = normalized
            cur.displayName = resolvedDisplayName(
                existing: cur.displayName,
                existingRootPath: cur.rootPath,
                projectId: pid,
                normalizedRootPath: normalized
            )
            cur.lastOpenedAt = now
            out.projects[idx] = cur
            return (out, cur)
        }

        let entry = AXProjectEntry(
            projectId: pid,
            rootPath: normalized,
            displayName: name,
            lastOpenedAt: now,
            manualOrderIndex: nextManualOrderIndex(in: out.projects),
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        out.projects.append(entry)
        return (out, entry)
    }

    static func removeProject(_ reg: AXProjectRegistry, projectId: String) -> AXProjectRegistry {
        var out = reg
        out.projects.removeAll { $0.projectId == projectId }
        if out.lastSelectedProjectId == projectId {
            out.lastSelectedProjectId = nil
        }
        return out
    }

    static func touchOpened(_ reg: AXProjectRegistry, projectId: String) -> AXProjectRegistry {
        var out = reg
        if let idx = out.projects.firstIndex(where: { $0.projectId == projectId }) {
            out.projects[idx].lastOpenedAt = Date().timeIntervalSince1970
        }
        return out
    }

    static func normalizedRootPath(_ root: URL) -> String {
        normalizeRoot(root)
    }

    static func projectId(forRoot root: URL) -> String {
        projectId(for: normalizeRoot(root))
    }

    static func updateStatusDigest(
        forRoot root: URL,
        digest: String?,
        lastSummaryAt: Double?,
        currentState: String? = nil,
        nextStep: String? = nil,
        blocker: String? = nil
    ) -> AXProjectStatusDigestUpdateResult {
        var reg = load()
        let normalized = normalizeRoot(root)
        let projectId = self.projectId(for: normalized)
        let existedBefore = reg.projects.contains(where: { $0.projectId == projectId })
        let res = upsertProject(reg, root: root)
        reg = res.0
        guard let idx = reg.projects.firstIndex(where: { $0.projectId == res.1.projectId }) else {
            return AXProjectStatusDigestUpdateResult(
                registry: reg,
                entry: nil,
                changed: false,
                created: !existedBefore
            )
        }

        var entry = reg.projects[idx]
        let cleaned = normalizeDigest(digest)
        let currentDigest = entry.statusDigest ?? ""
        let nextDigest = cleaned
        let nextSummaryAt = lastSummaryAt ?? Date().timeIntervalSince1970
        let nextState = normalizeSnippet(currentState, maxChars: 120)
        let nextNext = normalizeSnippet(nextStep, maxChars: 120)
        let nextBlocker = normalizeSnippet(blocker, maxChars: 120)

        if currentDigest == nextDigest,
           entry.lastSummaryAt == nextSummaryAt,
           (entry.currentStateSummary ?? "") == nextState,
           (entry.nextStepSummary ?? "") == nextNext,
           (entry.blockerSummary ?? "") == nextBlocker {
            return AXProjectStatusDigestUpdateResult(
                registry: reg,
                entry: entry,
                changed: false,
                created: !existedBefore
            )
        }

        entry.statusDigest = nextDigest.isEmpty ? nil : nextDigest
        entry.currentStateSummary = nextState.isEmpty ? nil : nextState
        entry.nextStepSummary = nextNext.isEmpty ? nil : nextNext
        entry.blockerSummary = nextBlocker.isEmpty ? nil : nextBlocker
        entry.lastSummaryAt = nextSummaryAt
        reg.projects[idx] = entry
        save(reg)
        return AXProjectStatusDigestUpdateResult(
            registry: reg,
            entry: entry,
            changed: true,
            created: !existedBefore
        )
    }

    static func touchActivity(
        forRoot root: URL,
        eventAt: Double? = nil,
        minIntervalSec: Double = 2.0
    ) -> AXProjectActivityTouchResult {
        var reg = load()
        let normalized = normalizeRoot(root)
        let projectId = self.projectId(for: normalized)
        let existedBefore = reg.projects.contains(where: { $0.projectId == projectId })
        let displayName = defaultDisplayName(forNormalizedRoot: normalized)
        let now = max(0, eventAt ?? Date().timeIntervalSince1970)
        let minInterval = max(0, minIntervalSec)

        if let idx = reg.projects.firstIndex(where: { $0.projectId == projectId }) {
            var entry = reg.projects[idx]
            let resolvedDisplayName = resolvedDisplayName(
                existing: entry.displayName,
                existingRootPath: entry.rootPath,
                projectId: projectId,
                normalizedRootPath: normalized
            )
            let prevEventAt = entry.lastEventAt ?? 0
            let sameMetadata = entry.rootPath == normalized && entry.displayName == resolvedDisplayName
            let throttled = prevEventAt > 0 && now < (prevEventAt + minInterval)
            if throttled && sameMetadata {
                return AXProjectActivityTouchResult(
                    registry: reg,
                    entry: entry,
                    changed: false,
                    created: false
                )
            }

            entry.rootPath = normalized
            entry.displayName = resolvedDisplayName
            entry.lastOpenedAt = max(entry.lastOpenedAt, now)
            entry.lastEventAt = max(prevEventAt, now)
            reg.projects[idx] = entry
            save(reg)
            return AXProjectActivityTouchResult(
                registry: reg,
                entry: entry,
                changed: true,
                created: false
            )
        }

        let entry = AXProjectEntry(
            projectId: projectId,
            rootPath: normalized,
            displayName: displayName,
            lastOpenedAt: now,
            manualOrderIndex: nextManualOrderIndex(in: reg.projects),
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: now
        )
        reg.projects.append(entry)
        save(reg)
        return AXProjectActivityTouchResult(
            registry: reg,
            entry: entry,
            changed: true,
            created: !existedBefore
        )
    }

    private static func normalizeRoot(_ root: URL) -> String {
        root.standardizedFileURL.path
    }

    private static func projectId(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func normalizeDigest(_ digest: String?) -> String {
        let raw = (digest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        var s = raw.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        if s.count <= 160 { return s }
        let idx = s.index(s.startIndex, offsetBy: 160)
        return String(s[..<idx])
    }

    private static func normalizeSnippet(_ text: String?, maxChars: Int) -> String {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        var s = raw.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        if s.count <= max(8, maxChars) { return s }
        let idx = s.index(s.startIndex, offsetBy: max(8, maxChars))
        return String(s[..<idx])
    }

    private static func normalizeManualOrderIndices(_ reg: AXProjectRegistry) -> (registry: AXProjectRegistry, changed: Bool) {
        var out = reg
        var changed = false
        var used = Set<Int>()
        var next = 0

        for idx in out.projects.indices {
            if let manual = out.projects[idx].manualOrderIndex, manual >= 0, !used.contains(manual) {
                used.insert(manual)
                if manual >= next {
                    next = manual + 1
                }
                continue
            }

            while used.contains(next) {
                next += 1
            }
            out.projects[idx].manualOrderIndex = next
            used.insert(next)
            next += 1
            changed = true
        }

        return (out, changed)
    }

    static func sanitizeLoadedRegistry(_ reg: AXProjectRegistry) -> (registry: AXProjectRegistry, changed: Bool) {
        let normalized = normalizeManualOrderIndices(reg)
        let pruned = pruneTemporaryOrEphemeralTestProjects(normalized.registry)

        var out = pruned.registry
        var changed = normalized.changed || pruned.changed

        if let selected = out.lastSelectedProjectId,
           !out.projects.contains(where: { $0.projectId == selected }) {
            out.lastSelectedProjectId = out.projects.first?.projectId
            changed = true
        }

        return (out, changed)
    }

    private static func pruneTemporaryOrEphemeralTestProjects(_ reg: AXProjectRegistry) -> (registry: AXProjectRegistry, changed: Bool) {
        let fm = FileManager.default
        var out = reg
        let originalCount = out.projects.count
        out.projects.removeAll { entry in
            let rootPath = entry.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rootPath.isEmpty else { return true }
            guard isTemporaryPath(rootPath) else { return false }
            if isEphemeralTestProjectPath(rootPath) {
                return true
            }
            return !fm.fileExists(atPath: rootPath)
        }
        return (out, out.projects.count != originalCount)
    }

    private static func isTemporaryPath(_ path: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path

        if normalizedPath.hasPrefix(tempRoot) {
            return true
        }

        let normalizedWithoutPrivate = normalizedPath.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
        let tempWithoutPrivate = tempRoot.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
        return normalizedWithoutPrivate.hasPrefix(tempWithoutPrivate)
    }

    private static func isRunningUnderUnitTests() -> Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    private static func isEphemeralTestProjectPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let basename = url.lastPathComponent.lowercased()
        let components = Set(url.pathComponents.map { $0.lowercased() })
        if components.contains("xterminal-tests") || components.contains("xterminal-tests-support") {
            return true
        }

        let prefixes = [
            "xterminal-supervisor-manager-automation-",
            "xt-supervisor-last-actual-model-",
            "xt_chat_direct_reply_",
            "xterminal-skills-compat-",
            "voice-heartbeat-",
            "xt_w3_",
            "xt_w331_"
        ]
        return prefixes.contains(where: { basename.hasPrefix($0) })
    }

    private static func nextManualOrderIndex(in projects: [AXProjectEntry]) -> Int {
        let maxIndex = projects.compactMap { $0.manualOrderIndex }.max() ?? -1
        return maxIndex + 1
    }

    private static func writeAtomic(data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}

struct AXProjectStatusDigestUpdateResult {
    var registry: AXProjectRegistry
    var entry: AXProjectEntry?
    var changed: Bool
    var created: Bool
}

struct AXProjectActivityTouchResult {
    var registry: AXProjectRegistry
    var entry: AXProjectEntry?
    var changed: Bool
    var created: Bool
}
