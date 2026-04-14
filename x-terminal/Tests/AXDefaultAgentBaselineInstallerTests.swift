import Foundation
import Testing
@testable import XTerminal

struct AXDefaultAgentBaselineInstallerTests {
    @Test
    func planSeparatesResolvedInstallableMissingAndBundleGrouping() {
        let baseline = [
            AXDefaultAgentBaselineSkill(skillID: "find-skills", displayName: "Find Skills", summary: "baseline"),
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: "baseline"),
            AXDefaultAgentBaselineSkill(skillID: "summarize", displayName: "Summarize", summary: "baseline"),
        ]
        let bundles = [
            AXDefaultAgentBaselineBundle(
                bundleID: "coding-core",
                displayName: "Coding Core",
                summary: "coding",
                skillIDs: ["find-skills", "summarize"],
                capabilityFamilies: ["skills.discover", "repo.read"],
                capabilityProfiles: ["observe_only"]
            ),
            AXDefaultAgentBaselineBundle(
                bundleID: "browser-research",
                displayName: "Browser Research",
                summary: "browser",
                skillIDs: ["agent-browser"],
                capabilityFamilies: ["web.live", "browser.observe", "browser.interact", "browser.secret_fill"],
                capabilityProfiles: ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"]
            ),
        ]
        let resolved = [
            HubIPCClient.ResolvedSkillEntry(
                scope: "global",
                skill: makeCatalogEntry(
                    skillID: "find-skills",
                    packageSHA256: "sha-find",
                    installHint: "installed",
                    capabilitiesRequired: ["skills.search"]
                )
            )
        ]
        let searchResultsBySkillID = [
            "find-skills": [
                makeCatalogEntry(
                    skillID: "find-skills",
                    packageSHA256: "",
                    installHint: "builtin wrapper",
                    capabilitiesRequired: ["skills.search"]
                )
            ],
            "agent-browser": [
                makeCatalogEntry(
                    skillID: "agent-browser",
                    packageSHA256: "sha-browser",
                    sourceID: "local:upload",
                    installHint: "uploadable package",
                    capabilitiesRequired: ["browser.read", "device.browser.control", "web.fetch"]
                )
            ],
            "summarize": [
                makeCatalogEntry(
                    skillID: "summarize",
                    packageSHA256: "",
                    installHint: "needs package upload",
                    capabilitiesRequired: ["document.read", "document.summarize"]
                )
            ],
        ]

        let plan = AXDefaultAgentBaselineInstaller.makePlan(
            scope: .project(projectId: "project-a", projectName: "Project A"),
            baseline: baseline,
            bundles: bundles,
            resolvedSkills: resolved,
            searchResultsBySkillID: searchResultsBySkillID
        )

        #expect(plan.totalBaselineCount == 3)
        #expect(plan.alreadyResolvedSkillIDs == ["find-skills"])
        #expect(plan.installableCandidates.map(\.skillID) == ["agent-browser"])
        #expect(plan.installableCandidates.first?.packageSHA256 == "sha-browser")
        #expect(plan.installableCandidates.first?.capabilityProfiles == ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"])
        #expect(plan.missingPackageSkills.map(\.skillID) == ["summarize"])
        #expect(plan.missingPackageSkills.first?.capabilityProfiles == ["observe_only"])

        #expect(plan.bundles.map(\.bundleID) == ["browser-research", "coding-core"])
        #expect(plan.bundles.first?.ready == true)
        #expect(plan.bundles.first?.availableCapabilityProfiles == ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"])
        #expect(plan.bundles.last?.missingPackageSkills.map(\.skillID) == ["summarize"])
        #expect(plan.targetCapabilityProfiles == ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"])
    }

    @Test
    func planPrefersUploadedExactSkillCandidateOverBuiltinOnlyCatalogEntry() {
        let baseline = [
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: "baseline")
        ]
        let bundles = [
            AXDefaultAgentBaselineBundle(
                bundleID: "browser-research",
                displayName: "Browser Research",
                summary: "browser",
                skillIDs: ["agent-browser"],
                capabilityFamilies: ["web.live", "browser.observe", "browser.interact", "browser.secret_fill"],
                capabilityProfiles: ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"]
            )
        ]
        let searchResultsBySkillID = [
            "agent-browser": [
                makeCatalogEntry(
                    skillID: "agent-browser",
                    version: "1.0.0",
                    packageSHA256: "",
                    sourceID: "builtin:catalog",
                    installHint: "builtin only",
                    capabilitiesRequired: ["browser.read"]
                ),
                makeCatalogEntry(
                    skillID: "agent-browser",
                    version: "1.2.0",
                    packageSHA256: "sha-live",
                    sourceID: "local:upload",
                    installHint: "uploaded package",
                    capabilitiesRequired: ["browser.read", "device.browser.control", "web.fetch"]
                ),
                makeCatalogEntry(
                    skillID: "agent-browser-legacy",
                    version: "0.9.0",
                    packageSHA256: "sha-legacy",
                    sourceID: "local:upload",
                    installHint: "wrong skill",
                    capabilitiesRequired: ["browser.read"]
                ),
            ]
        ]

        let plan = AXDefaultAgentBaselineInstaller.makePlan(
            scope: .global,
            baseline: baseline,
            bundles: bundles,
            resolvedSkills: [],
            searchResultsBySkillID: searchResultsBySkillID
        )

        #expect(plan.installableCandidates.count == 1)
        #expect(plan.installableCandidates.first?.skillID == "agent-browser")
        #expect(plan.installableCandidates.first?.packageSHA256 == "sha-live")
        #expect(plan.installableCandidates.first?.capabilityProfiles == ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"])
        #expect(plan.missingPackageSkills.isEmpty)
        #expect(plan.bundles.first?.ready == true)
        #expect(plan.bundles.first?.missingPackageSkills.isEmpty == true)
    }

    @Test
    func planComputesProfileDeltaAndResidualBlockedProfiles() {
        let baseline = [
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: "baseline")
        ]
        let bundles = [
            AXDefaultAgentBaselineBundle(
                bundleID: "browser-research",
                displayName: "Browser Research",
                summary: "browser",
                skillIDs: ["agent-browser"],
                capabilityFamilies: ["web.live", "browser.observe", "browser.interact", "browser.secret_fill"],
                capabilityProfiles: ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"]
            )
        ]
        let searchResultsBySkillID = [
            "agent-browser": [
                makeCatalogEntry(
                    skillID: "agent-browser",
                    packageSHA256: "sha-browser",
                    sourceID: "local:upload",
                    installHint: "uploaded package",
                    capabilitiesRequired: ["browser.read", "device.browser.control", "web.fetch"]
                )
            ]
        ]
        let currentSnapshot = makeProfileSnapshot(
            discoverableProfiles: ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"],
            installableProfiles: ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"],
            runnableNowProfiles: ["observe_only"],
            blockedProfiles: [
                XTProjectEffectiveSkillBlockedProfile(
                    profileID: "browser_research",
                    reasonCode: "profile_not_resolved",
                    state: XTSkillExecutionReadinessState.notInstalled.rawValue,
                    source: "hub_skill_registry",
                    unblockActions: ["install_baseline"]
                ),
                XTProjectEffectiveSkillBlockedProfile(
                    profileID: "browser_operator_with_secrets",
                    reasonCode: "policy_clamped",
                    state: XTSkillExecutionReadinessState.policyClamped.rawValue,
                    source: "project_policy",
                    unblockActions: ["open_project_settings"]
                ),
            ]
        )

        let plan = AXDefaultAgentBaselineInstaller.makePlan(
            scope: .project(projectId: "project-a", projectName: "Project A"),
            baseline: baseline,
            bundles: bundles,
            resolvedSkills: [],
            searchResultsBySkillID: searchResultsBySkillID,
            currentProfileSnapshot: currentSnapshot
        )

        #expect(plan.availableCapabilityProfiles == ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"])
        #expect(plan.deltaCapabilityProfiles == ["browser_research", "browser_operator", "browser_operator_with_secrets"])
        #expect(plan.residualBlockedProfiles.map(\.profileID) == ["browser_operator_with_secrets"])
        #expect(plan.residualBlockedProfiles.first?.reasonCode == "policy_clamped")
        #expect(plan.bundles.first?.deltaCapabilityProfiles == ["browser_research", "browser_operator", "browser_operator_with_secrets"])
        #expect(plan.bundles.first?.residualBlockedProfiles.map(\.profileID) == ["browser_operator_with_secrets"])
    }

    @Test
    func builtinOnlyCatalogEntryDoesNotMakeBundleLookReady() {
        let baseline = [
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: "baseline")
        ]
        let bundles = [
            AXDefaultAgentBaselineBundle(
                bundleID: "browser-research",
                displayName: "Browser Research",
                summary: "browser",
                skillIDs: ["agent-browser"],
                capabilityFamilies: ["web.live", "browser.observe", "browser.interact", "browser.secret_fill"],
                capabilityProfiles: ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"]
            )
        ]
        let searchResultsBySkillID = [
            "agent-browser": [
                makeCatalogEntry(
                    skillID: "agent-browser",
                    version: "1.0.0",
                    packageSHA256: "",
                    sourceID: "builtin:catalog",
                    installHint: "builtin only",
                    capabilitiesRequired: ["browser.read"]
                )
            ]
        ]

        let plan = AXDefaultAgentBaselineInstaller.makePlan(
            scope: .global,
            baseline: baseline,
            bundles: bundles,
            resolvedSkills: [],
            searchResultsBySkillID: searchResultsBySkillID
        )

        #expect(plan.installableCandidates.isEmpty)
        #expect(plan.missingPackageSkills.map(\.skillID) == ["agent-browser"])
        #expect(plan.bundles.first?.ready == false)
        #expect(plan.bundles.first?.availableCapabilityProfiles.isEmpty == true)
        #expect(plan.bundles.first?.residualBlockedProfiles.map(\.profileID) == ["observe_only", "browser_research", "browser_operator", "browser_operator_with_secrets"])
    }
}

private func makeCatalogEntry(
    skillID: String,
    version: String = "1.0.0",
    packageSHA256: String,
    sourceID: String = "builtin:catalog",
    installHint: String,
    capabilitiesRequired: [String] = []
) -> HubIPCClient.SkillCatalogEntry {
    HubIPCClient.SkillCatalogEntry(
        skillID: skillID,
        name: skillID,
        version: version,
        description: "\(skillID) desc",
        publisherID: "xhub.official",
        capabilitiesRequired: capabilitiesRequired,
        sourceID: sourceID,
        packageSHA256: packageSHA256,
        installHint: installHint
    )
}

private func makeProfileSnapshot(
    discoverableProfiles: [String],
    installableProfiles: [String],
    requestableProfiles: [String] = [],
    runnableNowProfiles: [String] = [],
    grantRequiredProfiles: [String] = [],
    approvalRequiredProfiles: [String] = [],
    blockedProfiles: [XTProjectEffectiveSkillBlockedProfile] = []
) -> XTProjectEffectiveSkillProfileSnapshot {
    XTProjectEffectiveSkillProfileSnapshot(
        schemaVersion: XTProjectEffectiveSkillProfileSnapshot.currentSchemaVersion,
        projectId: "project-a",
        projectName: "Project A",
        source: "test",
        executionTier: "a2Delegate",
        runtimeSurfaceMode: "local_only",
        hubOverrideMode: "inherit",
        legacyToolProfile: "observe_only",
        discoverableProfiles: discoverableProfiles,
        installableProfiles: installableProfiles,
        requestableProfiles: requestableProfiles,
        runnableNowProfiles: runnableNowProfiles,
        grantRequiredProfiles: grantRequiredProfiles,
        approvalRequiredProfiles: approvalRequiredProfiles,
        blockedProfiles: blockedProfiles,
        ceilingCapabilityFamilies: [],
        runnableCapabilityFamilies: [],
        localAutoApproveEnabled: false,
        trustedAutomationReady: false,
        profileEpoch: "epoch-1",
        trustRootSetHash: "trust-1",
        revocationEpoch: "rev-1",
        officialChannelSnapshotID: "official-1",
        runtimeSurfaceHash: "runtime-1",
        auditRef: "audit-test"
    )
}
