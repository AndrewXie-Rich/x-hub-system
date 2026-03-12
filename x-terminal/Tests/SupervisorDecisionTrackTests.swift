import Foundation
import Testing
@testable import XTerminal

struct SupervisorDecisionTrackTests {
    @Test
    func decisionTrackEventEncodesDecodesAndCoversRequiredFormalCategories() throws {
        let covered = Set(SupervisorDecisionCategory.minimumFormalCategories.map(\.rawValue))
        #expect(covered == Set(["tech_stack", "scope_freeze", "risk_posture", "approval_result"]))

        let event = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_001",
            projectId: "proj_demo",
            category: .techStack,
            status: .approved,
            statement: "Use SwiftUI + Hub canonical memory + role-based routing.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit_decision_001",
            evidenceRefs: ["docs/memory-new/xhub-lane-command-board-v2.md"],
            createdAtMs: 1_760_000_000_100
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SupervisorDecisionTrackEvent.self, from: data)

        #expect(decoded.schemaVersion == "xt.supervisor_decision_track_event.v1")
        #expect(decoded.category == .techStack)
        #expect(decoded.status == .approved)
        #expect(decoded.canWriteApproved)
        #expect(decoded.evidenceRefs == ["docs/memory-new/xhub-lane-command-board-v2.md"])
    }

    @Test
    func invalidApprovedDecisionFailsClosedDuringStorageSanitization() {
        let event = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_approval",
            projectId: "proj_demo",
            category: .approvalResult,
            status: .approved,
            statement: "Approved by policy.",
            source: "hub",
            reversible: false,
            approvalRequired: true,
            approvedBy: "",
            auditRef: "audit_decision_approval",
            createdAtMs: 300
        )

        #expect(event.status == .proposed)
        #expect(!event.canWriteApproved)
    }

    @Test
    func decisionTrackMergeKeepsLatestAuthoritativeStatusAndUnionsEvidenceRefs() throws {
        let approved = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_stack",
            projectId: "proj_demo",
            category: .techStack,
            status: .approved,
            statement: "Use SwiftUI.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit_decision_stack_approved",
            evidenceRefs: ["ref/a"],
            createdAtMs: 100,
            updatedAtMs: 120
        )

        let invalidLaterApproval = SupervisorDecisionTrackEvent(
            schemaVersion: SupervisorDecisionTrackEvent.schemaVersion,
            decisionId: "dec_stack",
            projectId: "proj_demo",
            category: .techStack,
            status: .approved,
            statement: "Use web stack.",
            source: "user",
            reversible: true,
            approvalRequired: true,
            approvedBy: "",
            auditRef: "audit_decision_stack_invalid",
            evidenceRefs: ["ref/b"],
            createdAtMs: 100,
            updatedAtMs: 180
        )

        let merged = try approved.merged(with: invalidLaterApproval)

        #expect(merged.status == .approved)
        #expect(merged.statement == "Use SwiftUI.")
        #expect(merged.source == "user")
        #expect(merged.auditRef == "audit_decision_stack_approved")
        #expect(merged.evidenceRefs == ["ref/a", "ref/b"])
        #expect(merged.updatedAtMs == 180)
    }

    @Test
    func storeRoundTripsDecisionTrackAndResolvesHardConstraints() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w333_decision_track_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let techStack = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_stack",
            projectId: "proj_demo",
            category: .techStack,
            status: .approved,
            statement: "Use SwiftUI.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit_decision_stack",
            createdAtMs: 100
        )
        let riskPosture = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec_risk",
            projectId: "proj_demo",
            category: .riskPosture,
            status: .approved,
            statement: "Keep fail-closed medium risk posture.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit_decision_risk",
            createdAtMs: 101
        )

        _ = try SupervisorDecisionTrackStore.upsert(techStack, for: ctx)
        let saved = try SupervisorDecisionTrackStore.upsert(riskPosture, for: ctx)
        let loaded = SupervisorDecisionTrackStore.load(for: ctx)
        let hardConstraints = SupervisorDecisionTrack.hardConstraints(from: loaded.events)

        #expect(saved == loaded)
        #expect(loaded.events.count == 2)
        #expect(hardConstraints[.techStack]?.statement == "Use SwiftUI.")
        #expect(hardConstraints[.riskPosture]?.status == .approved)
    }
}
