import Foundation
import Testing
@testable import XTerminal

struct AXDefaultAgentBaselineInstallerTests {
    @Test
    func planSeparatesResolvedInstallableAndMissingBaselineSkills() {
        let baseline = [
            AXDefaultAgentBaselineSkill(skillID: "find-skills", displayName: "Find Skills", summary: "baseline"),
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: "baseline"),
            AXDefaultAgentBaselineSkill(skillID: "summarize", displayName: "Summarize", summary: "baseline"),
        ]
        let resolved = [
            HubIPCClient.ResolvedSkillEntry(
                scope: "global",
                skill: makeCatalogEntry(
                    skillID: "find-skills",
                    packageSHA256: "sha-find",
                    installHint: "installed"
                )
            )
        ]
        let searchResultsBySkillID = [
            "find-skills": [
                makeCatalogEntry(skillID: "find-skills", packageSHA256: "", installHint: "builtin wrapper")
            ],
            "agent-browser": [
                makeCatalogEntry(skillID: "agent-browser", packageSHA256: "sha-browser", installHint: "uploadable package")
            ],
            "summarize": [
                makeCatalogEntry(skillID: "summarize", packageSHA256: "", installHint: "needs package upload")
            ],
        ]

        let plan = AXDefaultAgentBaselineInstaller.makePlan(
            scope: .project(projectId: "project-a", projectName: "Project A"),
            baseline: baseline,
            resolvedSkills: resolved,
            searchResultsBySkillID: searchResultsBySkillID
        )

        #expect(plan.totalBaselineCount == 3)
        #expect(plan.alreadyResolvedSkillIDs == ["find-skills"])
        #expect(plan.installableCandidates.map(\.skillID) == ["agent-browser"])
        #expect(plan.installableCandidates.first?.packageSHA256 == "sha-browser")
        #expect(plan.missingPackageSkills.map(\.skillID) == ["summarize"])
        #expect(plan.missingPackageSkills.first?.installHint == "needs package upload")
    }

    @Test
    func planPrefersUploadedExactSkillCandidateOverBuiltinOnlyCatalogEntry() {
        let baseline = [
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: "baseline")
        ]
        let searchResultsBySkillID = [
            "agent-browser": [
                makeCatalogEntry(skillID: "agent-browser", version: "1.0.0", packageSHA256: "", sourceID: "builtin:catalog", installHint: "builtin only"),
                makeCatalogEntry(skillID: "agent-browser", version: "1.2.0", packageSHA256: "sha-live", sourceID: "local:upload", installHint: "uploaded package"),
                makeCatalogEntry(skillID: "agent-browser-legacy", version: "0.9.0", packageSHA256: "sha-legacy", sourceID: "local:upload", installHint: "wrong skill"),
            ]
        ]

        let plan = AXDefaultAgentBaselineInstaller.makePlan(
            scope: .global,
            baseline: baseline,
            resolvedSkills: [],
            searchResultsBySkillID: searchResultsBySkillID
        )

        #expect(plan.installableCandidates.count == 1)
        #expect(plan.installableCandidates.first?.skillID == "agent-browser")
        #expect(plan.installableCandidates.first?.packageSHA256 == "sha-live")
        #expect(plan.missingPackageSkills.isEmpty)
    }
}

private func makeCatalogEntry(
    skillID: String,
    version: String = "1.0.0",
    packageSHA256: String,
    sourceID: String = "builtin:catalog",
    installHint: String
) -> HubIPCClient.SkillCatalogEntry {
    HubIPCClient.SkillCatalogEntry(
        skillID: skillID,
        name: skillID,
        version: version,
        description: "\(skillID) desc",
        publisherID: "xhub.official",
        capabilitiesRequired: [],
        sourceID: sourceID,
        packageSHA256: packageSHA256,
        installHint: installHint
    )
}
