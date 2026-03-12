import Foundation
import Testing
@testable import XTerminal

struct SupervisorBackgroundPreferenceTrackTests {
    @Test
    func backgroundPreferenceNoteEncodesAndDecodesStableSchema() throws {
        let note = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref_001",
            projectId: "proj_demo",
            domain: .uxStyle,
            strength: .weak,
            statement: "Prefer concise action-first updates over long narrative status dumps.",
            createdAtMs: 1_760_000_000_200
        )

        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(SupervisorBackgroundPreferenceNote.self, from: data)

        #expect(decoded.schemaVersion == "xt.supervisor_background_preference_note.v1")
        #expect(decoded.domain == .uxStyle)
        #expect(decoded.strength == .weak)
        #expect(decoded.mustNotPromoteWithoutDecision)
    }

    @Test
    func backgroundTrackMergeKeepsStrongestLatestNotePerIdentity() throws {
        let earlier = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref_stack",
            projectId: "proj_demo",
            domain: .techStack,
            strength: .weak,
            statement: "Prefer local-first experiments.",
            createdAtMs: 100
        )
        let later = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref_stack",
            projectId: "proj_demo",
            domain: .techStack,
            strength: .strong,
            statement: "Prefer SwiftUI if no formal decision exists.",
            createdAtMs: 200
        )

        let merged = try earlier.merged(with: later)

        #expect(merged.statement == "Prefer SwiftUI if no formal decision exists.")
        #expect(merged.strength == .strong)
        #expect(merged.mustNotPromoteWithoutDecision)
        #expect(merged.createdAtMs == 200)
    }

    @Test
    func backgroundPreferenceDoesNotSilentlyOverrideApprovedDecision() throws {
        let approvedDecision = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_stack",
            projectId: "proj_demo",
            category: .techStack,
            status: .approved,
            statement: "Use SwiftUI + Hub canonical memory.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit_decision_stack",
            createdAtMs: 100
        )
        let background = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref_stack",
            projectId: "proj_demo",
            domain: .techStack,
            strength: .strong,
            statement: "Prefer cross-platform web.",
            createdAtMs: 200
        )

        let resolved = SupervisorDecisionRailResolver.resolve(
            projectId: "proj_demo",
            decisions: [approvedDecision],
            backgroundNotes: [background]
        )
        let techStackResolution = try #require(resolved.resolution(for: .techStack))

        #expect(techStackResolution.usesDecisionTrack)
        #expect(techStackResolution.hardDecision?.status == .approved)
        #expect(techStackResolution.effectiveStatement == "Use SwiftUI + Hub canonical memory.")
        #expect(techStackResolution.preferredBackgroundNote == nil)
        #expect(techStackResolution.shadowedBackgroundNotes == [background])

        let onlyBackground = SupervisorDecisionRailResolver.resolve(
            projectId: "proj_demo",
            decisions: [],
            backgroundNotes: [background]
        )
        let backgroundOnlyResolution = try #require(onlyBackground.resolution(for: .techStack))

        #expect(backgroundOnlyResolution.hardDecision == nil)
        #expect(backgroundOnlyResolution.preferredBackgroundNote?.statement == "Prefer cross-platform web.")
        #expect(!backgroundOnlyResolution.usesDecisionTrack)
    }

    @Test
    func storeRoundTripsBackgroundPreferencesWithoutPromotingToDecisionTrack() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_background_track_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let note = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref_ux",
            projectId: "proj_demo",
            domain: .uxStyle,
            strength: .medium,
            statement: "Prefer action-first updates.",
            createdAtMs: 300
        )

        let saved = try SupervisorBackgroundPreferenceTrackStore.upsert(note, for: ctx)
        let loaded = SupervisorBackgroundPreferenceTrackStore.load(for: ctx)
        let resolved = SupervisorDecisionRailResolver.resolve(
            projectId: "proj_demo",
            decisions: [],
            backgroundNotes: loaded.notes
        )

        #expect(saved == loaded)
        #expect(loaded.notes == [note])
        #expect(resolved.hardDecision(for: .techStack) == nil)
        #expect(resolved.resolution(for: .uxStyle)?.preferredBackgroundNote?.statement == "Prefer action-first updates.")
    }
}
