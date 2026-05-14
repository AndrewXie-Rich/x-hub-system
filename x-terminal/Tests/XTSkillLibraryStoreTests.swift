import Foundation
import Testing
@testable import XTerminal

struct XTSkillLibraryStoreTests {
    @Test
    @MainActor
    func appModelMirrorsSkillsAndImportStateIntoFocusedSkillLibraryStore() {
        let appModel = AppModel.makeForTesting()
        let importedSkillDirectory = URL(fileURLWithPath: "/tmp/agent-browser", isDirectory: true)

        var skills = AXSkillsDoctorSnapshot.empty
        skills.installedSkillCount = 2
        skills.statusKind = .partial
        skills.statusLine = "skills partial"
        skills.conflictWarnings = ["agent-browser has a local conflict"]
        skills.builtinGovernedSkills = [
            AXBuiltinGovernedSkillSummary(
                skillID: "guarded-automation",
                displayName: "Guarded Automation",
                summary: "Run governed local automation.",
                capabilitiesRequired: ["device_automation"],
                sideEffectClass: "device",
                riskLevel: "medium",
                policyScope: "x_terminal"
            )
        ]

        appModel.skillsCompatibilitySnapshot = skills
        appModel.lastImportedAgentSkillDirectory = importedSkillDirectory
        appModel.lastImportedAgentSkillName = "agent-browser"
        appModel.lastImportedAgentSkillStage = HubIPCClient.AgentImportStageResult(
            ok: true,
            source: "hub_runtime_grpc",
            stagingId: "stage-review-001",
            status: "staged",
            auditRef: "audit-stage-001",
            preflightStatus: "passed",
            skillId: "agent-browser",
            policyScope: "global",
            findingsCount: 1,
            vetterStatus: "passed",
            vetterCriticalCount: 0,
            vetterWarnCount: 1,
            vetterAuditRef: "audit-vetter-001",
            recordPath: nil,
            reasonCode: nil
        )
        appModel.lastImportedAgentSkillStatusLine = "agent-browser: staged"

        let snapshot = appModel.skillLibraryStore.snapshot
        #expect(snapshot.skillsSnapshot.installedSkillCount == 2)
        #expect(snapshot.skillsSnapshot.statusLine == "skills partial")
        #expect(snapshot.skillsSnapshot.builtinGovernedSkills.first?.skillID == "guarded-automation")
        #expect(snapshot.lastImportedAgentSkillStatusLine == "agent-browser: staged")
        #expect(snapshot.canReviewLastImportedAgentSkill == true)
        #expect(snapshot.canEnableLastImportedAgentSkill == true)
    }

    @Test
    @MainActor
    func skillLibraryStoreSuppressesIdenticalSnapshots() {
        let snapshot = XTSkillLibrarySnapshot.empty
        let store = XTSkillLibraryStore(snapshot: snapshot)

        store.update(snapshot)

        #expect(store.snapshot == snapshot)
    }
}
