import Testing
@testable import XTerminal

struct XTGlobalHomeStoreTests {
    @Test
    @MainActor
    func appModelMirrorsSkillsIntoFocusedGlobalHomeStore() {
        let appModel = AppModel.makeForTesting()

        var skills = AXSkillsDoctorSnapshot.empty
        skills.installedSkillCount = 3
        skills.statusKind = .supported
        skills.statusLine = "skills ready"
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

        let snapshot = appModel.globalHomeStore.snapshot.skills
        #expect(snapshot.installedSkillCount == 3)
        #expect(snapshot.statusLine == "skills ready")
        #expect(snapshot.builtinGovernedSkillCount == 1)
        #expect(snapshot.builtinGovernedSkills.first?.skillID == "guarded-automation")
    }

    @Test
    @MainActor
    func appModelMirrorsPaidAccessIntoFocusedGlobalHomeStore() {
        let appModel = AppModel.makeForTesting()

        appModel.hubRemotePaidAccessSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "allowlisted",
            dailyTokenLimit: 10_000,
            singleRequestTokenLimit: 2_000
        )

        let snapshot = appModel.globalHomeStore.snapshot.remotePaidAccessSnapshot
        #expect(snapshot?.trustProfilePresent == true)
        #expect(snapshot?.paidModelPolicyMode == "allowlisted")
        #expect(snapshot?.dailyTokenLimit == 10_000)
    }

    @Test
    @MainActor
    func globalHomeStoreSuppressesIdenticalSnapshots() {
        let snapshot = XTGlobalHomeSnapshot(
            latestResumeReminder: nil,
            preferredResumeProject: nil,
            remotePaidAccessSnapshot: nil,
            skills: XTGlobalHomeSkillsSnapshot(
                builtinGovernedSkills: [],
                installedSkillCount: 1,
                statusKind: .supported,
                statusLine: "ready"
            )
        )
        let store = XTGlobalHomeStore(snapshot: snapshot)

        store.update(snapshot)

        #expect(store.snapshot == snapshot)
    }
}
