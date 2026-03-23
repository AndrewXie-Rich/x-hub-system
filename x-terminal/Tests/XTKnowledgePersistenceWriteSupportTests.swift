import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTKnowledgePersistenceWriteSupportTests {
    @Test
    func skillCandidatesFallBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeTempDirectory("skill_candidates")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXSkillCandidateStore.saveCandidates(
            [
                AXSkillCandidate(
                    id: "cand-old",
                    projectId: "proj-alpha",
                    projectName: "Project Alpha",
                    title: "Old Candidate",
                    summary: "old summary",
                    source: "test"
                )
            ],
            for: ctx
        )

        let capture = XTKnowledgeWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: root, capture: capture)
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        AXSkillCandidateStore.saveCandidates(
            [
                AXSkillCandidate(
                    id: "cand-new",
                    projectId: "proj-alpha",
                    projectName: "Project Alpha",
                    title: "New Candidate",
                    summary: "new summary",
                    source: "test"
                )
            ],
            for: ctx
        )

        let loaded = AXSkillCandidateStore.loadCandidates(for: ctx)
        #expect(loaded.map(\.id) == ["cand-new"])
        #expect(loaded.map(\.title) == ["New Candidate"])

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func curationSuggestionsFallBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeTempDirectory("curation_suggestions")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXCurationSuggestionStore.saveSuggestions(
            [
                AXCurationSuggestion(
                    id: "s-old",
                    projectId: "proj-alpha",
                    projectName: "Project Alpha",
                    type: "promote_skill",
                    title: "Old Suggestion",
                    summary: "old summary",
                    refs: ["references/old.md"]
                )
            ],
            for: ctx
        )

        let capture = XTKnowledgeWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: root, capture: capture)
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        AXCurationSuggestionStore.saveSuggestions(
            [
                AXCurationSuggestion(
                    id: "s-new",
                    projectId: "proj-alpha",
                    projectName: "Project Alpha",
                    type: "promote_skill",
                    title: "New Suggestion",
                    summary: "new summary",
                    refs: ["references/new.md"]
                )
            ],
            for: ctx
        )

        let loaded = AXCurationSuggestionStore.loadSuggestions(for: ctx)
        #expect(loaded.map(\.id) == ["s-new"])
        #expect(loaded.map(\.title) == ["New Suggestion"])

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func projectSkillsIndexFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let skillsDir = try makeTempDirectory("skills_project_index")
        defer { try? FileManager.default.removeItem(at: skillsDir) }

        let projectDir = skillsDir.appendingPathComponent("_projects/project-alpha-12345678", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        AXSkillsLibrary.updateProjectSkillsIndex(
            projectDir: projectDir,
            skillName: "old-skill",
            summary: "old summary"
        )

        let capture = XTKnowledgeWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: skillsDir, capture: capture)
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        AXSkillsLibrary.updateProjectSkillsIndex(
            projectDir: projectDir,
            skillName: "new-skill",
            summary: "new summary"
        )

        let indexURL = projectDir.appendingPathComponent("skills-index.md")
        let text = try String(contentsOf: indexURL, encoding: .utf8)
        #expect(text.contains("old-skill"))
        #expect(text.contains("new-skill"))

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func globalSkillsIndexFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let skillsDir = try makeTempDirectory("skills_global_index")
        defer { try? FileManager.default.removeItem(at: skillsDir) }

        let projectDirA = skillsDir.appendingPathComponent("_projects/project-alpha-12345678", isDirectory: true)
        let projectDirB = skillsDir.appendingPathComponent("_projects/project-beta-87654321", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectDirB, withIntermediateDirectories: true)

        AXSkillsLibrary.updateGlobalSkillsIndex(
            skillsDir: skillsDir,
            projectDir: projectDirA,
            projectName: "Project Alpha"
        )

        let capture = XTKnowledgeWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: skillsDir, capture: capture)
        defer { XTStoreWriteSupport.resetWriteBehaviorForTesting() }

        AXSkillsLibrary.updateGlobalSkillsIndex(
            skillsDir: skillsDir,
            projectDir: projectDirB,
            projectName: "Project Beta"
        )

        let indexURL = skillsDir
            .appendingPathComponent("memory-core", isDirectory: true)
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("skills-index.md")
        let text = try String(contentsOf: indexURL, encoding: .utf8)
        #expect(text.contains("Project Alpha"))
        #expect(text.contains("Project Beta"))

        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options.filter { $0.contains(.atomic) }.count == 1)
        #expect(options.filter(\.isEmpty).count == 1)
    }

    @Test
    func forgottenVaultIndexFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeTempDirectory("forgotten_vault")
        let skillsDir = try makeTempDirectory("forgotten_vault_skills")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: skillsDir)
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
        }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        try withSkillsDirOverride(skillsDir) {
            var firstDelta = AXMemoryDelta.empty()
            firstDelta.currentStateAdd = ["Implement local memory retrieval"]
            AXForgottenVault.autoArchiveTurn(
                ctx: ctx,
                turn: AXConversationTurn(
                    createdAt: 1_800_100_000,
                    user: "实现项目级长期记忆检索",
                    assistant: "已接入 memory retrieval pipeline"
                ),
                delta: firstDelta
            )

            let capture = XTKnowledgeWriteCapture()
            installScopedExistingFileOutOfSpaceOverride(root: skillsDir, capture: capture)

            var secondDelta = AXMemoryDelta.empty()
            secondDelta.currentStateAdd = ["Document fallback write path"]
            AXForgottenVault.autoArchiveTurn(
                ctx: ctx,
                turn: AXConversationTurn(
                    createdAt: 1_800_100_100,
                    user: "补上 forgotten vault 的索引回退写入",
                    assistant: "已加 fail-soft index write"
                ),
                delta: secondDelta
            )

            let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
            let projectDir = try #require(
                AXSkillsLibrary.projectSkillsDir(
                    projectId: projectId,
                    projectName: ctx.projectName(),
                    skillsDir: skillsDir
                )
            )
            let indexURL = projectDir
                .appendingPathComponent("forgotten-vault", isDirectory: true)
                .appendingPathComponent("references", isDirectory: true)
                .appendingPathComponent("index.md")
            let text = try String(contentsOf: indexURL, encoding: .utf8)
            #expect(text.contains("Implement local memory retrieval"))
            #expect(text.contains("Document fallback write path"))

            let options = capture.writeOptionsSnapshot()
            #expect(options.count == 3)
            #expect(options.filter { $0.contains(.atomic) }.count == 2)
            #expect(options.filter(\.isEmpty).count == 1)
        }
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_knowledge_write_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func installScopedExistingFileOutOfSpaceOverride(root: URL, capture: XTKnowledgeWriteCapture) {
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            if !Self.normalizedPath(url).hasPrefix(Self.normalizedPath(root)) {
                try data.write(to: url, options: options)
                return
            }
            capture.appendWriteOption(options)
            if options.contains(.atomic),
               let existingTarget = Self.existingTargetForAtomicTemp(url),
               FileManager.default.fileExists(atPath: existingTarget.path) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
    }

    private static func existingTargetForAtomicTemp(_ url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."),
              let tempRange = name.range(of: ".tmp-") else {
            return nil
        }
        let targetName = String(name[name.index(after: name.startIndex)..<tempRange.lowerBound])
        guard !targetName.isEmpty else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(targetName)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
    }
}

private final class XTKnowledgeWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}

private let xtKnowledgeSkillsDirOverrideLock = NSLock()

private func withSkillsDirOverride<T>(_ skillsDir: URL, _ body: () throws -> T) throws -> T {
    xtKnowledgeSkillsDirOverrideLock.lock()
    defer { xtKnowledgeSkillsDirOverrideLock.unlock() }

    let key = AXSkillsLibrary.skillsDirDefaultsKey
    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: key)
    defaults.set(skillsDir.path, forKey: key)
    defer {
        if let previous {
            defaults.set(previous, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    return try body()
}
