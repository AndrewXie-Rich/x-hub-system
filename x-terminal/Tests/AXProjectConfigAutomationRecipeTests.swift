import Foundation
import Testing
@testable import XTerminal

struct AXProjectConfigAutomationRecipeTests {
    @Test
    func legacyConfigDecodeDefaultsAutomationFields() throws {
        let legacyJSON = """
        {
          "schemaVersion": 2,
          "roleModelOverrides": {},
          "verifyCommands": ["swift test"],
          "verifyAfterChanges": true,
          "toolProfile": "full",
          "toolAllow": [],
          "toolDeny": []
        }
        """

        let config = try JSONDecoder().decode(AXProjectConfig.self, from: Data(legacyJSON.utf8))

        #expect(config.schemaVersion == AXProjectConfig.currentSchemaVersion)
        #expect(config.automationRecipes.isEmpty)
        #expect(config.activeAutomationRecipeRef.isEmpty)
        #expect(config.lastAutomationLaunchRef.isEmpty)
        #expect(config.automationMode == .standard)
        #expect(config.trustedAutomationDeviceId.isEmpty)
        #expect(config.deviceToolGroups.isEmpty)
        #expect(config.workspaceBindingHash.isEmpty)
        #expect(config.governedReadableRoots.isEmpty)
        #expect(config.governedAutoApproveLocalToolCalls == false)
        #expect(config.automationSelfIterateEnabled == false)
        #expect(config.automationMaxAutoRetryDepth == 2)
        #expect(config.preferHubMemory == true)
        #expect(config.projectRecentDialogueProfile == .standard12Pairs)
        #expect(config.projectContextDepthProfile == .balanced)
        #expect(config.autonomyMode == .manual)
        #expect(config.autonomyAllowDeviceTools == false)
        #expect(config.autonomyAllowBrowserRuntime == false)
        #expect(config.autonomyAllowConnectorActions == false)
        #expect(config.autonomyAllowExtensions == false)
        #expect(config.autonomyTTLSeconds == 3600)
        #expect(config.autonomyUpdatedAtMs == 0)
        #expect(config.autonomyHubOverrideMode == .none)
    }

    @Test
    func settingProjectContextAssemblyPersistsAcrossSaveLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-project-context-assembly-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectContextAssembly(
            projectRecentDialogueProfile: .deep20Pairs,
            projectContextDepthProfile: .full
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.projectRecentDialogueProfile == .deep20Pairs)
        #expect(reloaded.projectContextDepthProfile == .full)
    }

    @Test
    func settingAutomationSelfIterationNormalizesDepth() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-self-iterate-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)

        config = config.settingAutomationSelfIteration(enabled: true, maxAutoRetryDepth: 0)

        #expect(config.automationSelfIterateEnabled == true)
        #expect(config.automationMaxAutoRetryDepth == 1)
    }

    @Test
    func hubMemoryPreferenceDefaultsOnAndPersistsAcrossSaveLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-hub-memory-config-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)

        #expect(config.preferHubMemory == true)

        config = config.settingHubMemoryPreference(enabled: false)
        try AXProjectStore.saveConfig(config, for: ctx)

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.preferHubMemory == false)
    }

    @Test
    func runtimeSurfacePresetPersistsAndClampTakesEffect() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-runtime-surface-policy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let armedAt = Date(timeIntervalSince1970: 1_773_100_000)

        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 600,
            hubOverrideMode: .clampGuided,
            updatedAt: armedAt
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let effective = reloaded.effectiveRuntimeSurfacePolicy(now: armedAt.addingTimeInterval(120))

        #expect(reloaded.autonomyMode == .trustedOpenClawMode)
        #expect(reloaded.autonomyAllowDeviceTools == true)
        #expect(reloaded.autonomyAllowBrowserRuntime == true)
        #expect(reloaded.autonomyAllowConnectorActions == true)
        #expect(reloaded.autonomyAllowExtensions == true)
        #expect(reloaded.autonomyTTLSeconds == 600)
        #expect(reloaded.autonomyHubOverrideMode == .clampGuided)
        #expect(effective.effectiveMode == .guided)
        #expect(effective.allowBrowserRuntime == true)
        #expect(effective.allowDeviceTools == false)
        #expect(effective.allowConnectorActions == false)
        #expect(effective.allowExtensions == false)
        #expect(effective.remainingSeconds == 480)
    }

    @Test
    func governedReadableRootsNormalizeRelativePathsAndDeduplicate() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-governed-roots-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)

        config = config.settingGovernedReadableRoots(
            paths: [
                "../shared",
                root.appendingPathComponent("nested").path,
                "../shared",
                "   ",
            ],
            projectRoot: root
        )

        #expect(config.governedReadableRoots.count == 2)
        #expect(config.governedReadableRoots.contains(PathGuard.resolve(root.deletingLastPathComponent().appendingPathComponent("shared")).path))
        #expect(config.governedReadableRoots.contains(PathGuard.resolve(root.appendingPathComponent("nested")).path))
    }

    @Test
    func runtimeSurfaceTTLExpiryFailsClosedToManual() {
        var config = AXProjectConfig.default(
            forProjectRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("xterminal-runtime-surface-expiry-\(UUID().uuidString)", isDirectory: true)
        )
        let armedAt = Date(timeIntervalSince1970: 1_773_200_000)

        config = config.settingRuntimeSurfacePolicy(
            mode: .trustedOpenClawMode,
            ttlSeconds: 120,
            updatedAt: armedAt
        )
        let effective = config.effectiveRuntimeSurfacePolicy(now: armedAt.addingTimeInterval(180))

        #expect(effective.expired)
        #expect(effective.effectiveMode == .manual)
        #expect(effective.allowBrowserRuntime == false)
        #expect(effective.allowDeviceTools == false)
        #expect(effective.remainingSeconds == 0)
    }

    @Test
    func saveLoadPersistsActiveReadyAutomationRecipe() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-automation-config-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let stored = config.upsertAutomationRecipe(makeRecipe(), activate: true)

        #expect(config.activeAutomationRecipeRef == stored.ref)
        #expect(config.activeAutomationRecipe?.recipeID == "xt-auto-pr-review")

        try AXProjectStore.saveConfig(config, for: ctx)
        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let persisted = try #require(reloaded.activeAutomationRecipe)

        #expect(reloaded.activeAutomationRecipeRef == stored.ref)
        #expect(reloaded.automationRecipes.count == 1)
        #expect(persisted.recipeVersion == 1)
        #expect(persisted.triggerRefs == [
            "xt.automation_trigger_envelope.v1:schedule/nightly",
            "xt.automation_trigger_envelope.v1:webhook/github_pr"
        ])
        #expect(persisted.requiredToolGroups == [
            "group:full",
            "group:device_automation"
        ])
        #expect(persisted.requiredDeviceToolGroups == [
            "device.ui.observe",
            "device.ui.act"
        ])
        #expect(persisted.actionGraph.count == 1)
        #expect(persisted.actionGraph.first?.tool == .deviceUIStep)
    }

    @Test
    func versionedEditCreatesDraftAndKeepsLivePointerOnPreviousReadyRecipe() throws {
        var config = AXProjectConfig.default(
            forProjectRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("xterminal-automation-edit-\(UUID().uuidString)", isDirectory: true)
        )
        let ready = config.upsertAutomationRecipe(makeRecipe(), activate: true)

        let edited = config.versionedEditAutomationRecipe(
            from: ready.ref,
            editedAt: Date(timeIntervalSince1970: 1_773_000_000),
            lastEditAuditRef: "audit-xt-auto-edit-001"
        ) { draft in
            draft.goal = "nightly triage + gated summary delivery"
            draft.deliveryTargets.append("channel://slack/project-a")
        }

        let draft = try #require(edited)
        #expect(draft.recipeVersion == 2)
        #expect(draft.lifecycleState == .draft)
        #expect(draft.rolloutStatus == .inactive)
        #expect(draft.goal == "nightly triage + gated summary delivery")
        #expect(draft.deliveryTargets == [
            "channel://telegram/project-a",
            "channel://slack/project-a"
        ])
        #expect(config.activeAutomationRecipeRef == ready.ref)
        #expect(config.automationRecipes.count == 2)
        #expect(config.automationRecipes.contains { $0.ref == ready.ref && $0.lifecycleState == .ready })
        #expect(config.automationRecipes.contains { $0.ref == draft.ref && $0.recipeVersion == 2 })
    }

    @Test
    func recipeManifestBridgePersistsRuntimeBindingIntoProjectConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-automation-manifest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ctx = AXProjectContext(root: root)
        let manifest = XTAutomationRecipeManifest(
            schemaVersion: "xt.automation_recipe_manifest.v1",
            recipeID: "xt-auto-daily-digest",
            projectID: "project-alpha",
            goal: "daily digest + routed summary delivery",
            triggerRefs: ["xt.automation_trigger_envelope.v1:manual/retry"],
            executionProfile: .conservative,
            touchMode: .criticalTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            auditRef: "audit-xt-auto-manifest-001"
        )

        let binding = manifest.runtimeBinding(
            requiredToolGroups: ["group:full"],
            requiredDeviceToolGroups: ["device.ui.step"],
            requiresTrustedAutomation: true,
            trustedDeviceID: "device://trusted/project-a",
            workspaceBindingHash: "sha256:workspace-binding-project-a",
            grantPolicyRef: "policy://automation-trigger/project-a",
            lastEditedAt: Date(timeIntervalSince1970: 1_773_000_100)
        )
        let stored = try AXProjectStore.upsertAutomationRecipe(binding, activate: true, for: ctx)
        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let active = try #require(reloaded.activeAutomationRecipe)

        #expect(stored.recipeID == "xt-auto-daily-digest")
        #expect(active.recipeID == manifest.recipeID)
        #expect(active.goal == manifest.goal)
        #expect(active.executionProfile == .conservative)
        #expect(active.touchMode == .criticalTouch)
        #expect(active.laneStrategy == .singleLane)
        #expect(active.requiredToolGroups == ["group:full", "group:device_automation"])
        #expect(active.requiredDeviceToolGroups == ["device.ui.observe", "device.ui.act"])
    }

    @Test
    func trustedAutomationBindingPersistsAndComputesSafeState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-trusted-automation-config-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.clipboard.read", "device.clipboard.write"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let readiness = AXTrustedAutomationPermissionOwnerReadiness(
            schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
            ownerID: "owner-local",
            ownerType: "xterminal_app",
            bundleID: "com.xterminal.app",
            installState: "ready",
            mode: "managed_or_prompted",
            accessibility: .granted,
            automation: .granted,
            screenRecording: .granted,
            fullDiskAccess: .missing,
            inputMonitoring: .missing,
            canPromptUser: true,
            managedByMDM: false,
            overallState: "ready",
            openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
            auditRef: "audit-xt-trusted-binding-ready"
        )
        let status = reloaded.trustedAutomationStatus(forProjectRoot: root, permissionReadiness: readiness)

        #expect(reloaded.automationMode == .trustedAutomation)
        #expect(reloaded.trustedAutomationDeviceId == "device_xt_001")
        #expect(reloaded.toolAllow.contains("group:device_automation"))
        #expect(status.trustedAutomationReady)
        #expect(status.permissionOwnerReady)
        #expect(status.state == .active)
    }

    @Test
    func trustedAutomationPermissionReadinessMaterializesRequirementsAndRepairActions() {
        let readiness = AXTrustedAutomationPermissionOwnerReadiness(
            schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
            ownerID: "owner-001",
            ownerType: "xterminal_runner",
            bundleID: "com.xterminal.runner",
            installState: "ready",
            mode: "managed_or_prompted",
            accessibility: .granted,
            automation: .missing,
            screenRecording: .missing,
            fullDiskAccess: .managed,
            inputMonitoring: .denied,
            canPromptUser: true,
            managedByMDM: false,
            overallState: "partial",
            openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
            auditRef: "audit-xt-ta-readiness-001"
        )

        let groups = ["device.ui.act", "device.browser.control", "device.screen.capture", "device.browser.control"]
        let requirements = readiness.requirementStatuses(forDeviceToolGroups: groups)
        let missing = readiness.missingRequirements(forDeviceToolGroups: groups)
        let repairActions = readiness.suggestedOpenSettingsActions(forDeviceToolGroups: groups)

        #expect(requirements.map { $0.key.rawValue } == ["accessibility", "automation", "screen_recording"])
        #expect(requirements.map { $0.status.rawValue } == ["granted", "missing", "missing"])
        #expect(missing == ["permission_automation_missing", "permission_screen_recording_missing"])
        #expect(repairActions == ["privacy_automation", "privacy_screen_recording"])
        #expect(readiness.permissionStatusMap()["input_monitoring"] == AXTrustedAutomationPermissionStatus.denied)
    }

    @Test
    func recipeActionDecodeDefaultsRequiresVerificationToFalse() throws {
        let json = """
        {
          "action_id": "write_readme",
          "title": "Write README",
          "tool": "write_file",
          "args": {
            "path": "README.md",
            "content": "hello"
          }
        }
        """

        let action = try JSONDecoder().decode(XTAutomationRecipeAction.self, from: Data(json.utf8))

        #expect(action.actionID == "write_readme")
        #expect(action.tool == .write_file)
        #expect(action.requiresVerification == false)
    }

    @Test
    func trustedAutomationStatusScopesPermissionReadinessToRecipeRequiredDeviceGroups() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-trusted-automation-scope-\(UUID().uuidString)", isDirectory: true)
        let config = AXProjectConfig.default(forProjectRoot: root).settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.ui.observe", "device.ui.act", "device.screen.capture"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
        )
        let readiness = AXTrustedAutomationPermissionOwnerReadiness(
            schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
            ownerID: "owner-xt",
            ownerType: "xterminal_app",
            bundleID: "com.xterminal.app",
            installState: "ready",
            mode: "managed_or_prompted",
            accessibility: .granted,
            automation: .missing,
            screenRecording: .missing,
            fullDiskAccess: .missing,
            inputMonitoring: .missing,
            canPromptUser: true,
            managedByMDM: false,
            overallState: "partial",
            openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
            auditRef: "audit-xt-ta-scope-001"
        )

        let broadStatus = config.trustedAutomationStatus(
            forProjectRoot: root,
            permissionReadiness: readiness
        )
        let scopedStatus = config.trustedAutomationStatus(
            forProjectRoot: root,
            permissionReadiness: readiness,
            requiredDeviceToolGroups: ["device.ui.step"]
        )

        #expect(!broadStatus.permissionOwnerReady)
        #expect(scopedStatus.permissionOwnerReady)
        #expect(scopedStatus.deviceToolGroups == ["device.ui.observe", "device.ui.act"])
        #expect(scopedStatus.armedDeviceToolGroups == ["device.ui.observe", "device.ui.act", "device.screen.capture"])
        #expect(scopedStatus.requiredDeviceToolGroups == ["device.ui.observe", "device.ui.act"])
        #expect(scopedStatus.missingRequiredDeviceToolGroups.isEmpty)
    }

    private func makeRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-pr-review",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "nightly triage + code review + summary delivery",
            triggerRefs: [
                " xt.automation_trigger_envelope.v1:schedule/nightly ",
                "xt.automation_trigger_envelope.v1:schedule/nightly",
                "",
                "xt.automation_trigger_envelope.v1:webhook/github_pr"
            ],
            deliveryTargets: [
                "channel://telegram/project-a",
                "channel://telegram/project-a"
            ],
            acceptancePackRef: " build/reports/xt_w3_22_acceptance_pack.v1.json ",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l2,
            laneStrategy: .adaptive,
            requiredToolGroups: [
                "group:full",
                "group:device_automation",
                "group:device_automation"
            ],
            requiredDeviceToolGroups: [
                "device.ui.step",
                "device.ui.observe"
            ],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Submit form",
                    tool: .deviceUIStep,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Submit"),
                        "max_results": .number(1)
                    ]
                )
            ],
            requiresTrustedAutomation: true,
            trustedDeviceID: " device-xt-001 ",
            workspaceBindingHash: " sha256:workspace-binding ",
            grantPolicyRef: " policy://automation-trigger/project-a ",
            rolloutStatus: .active,
            lastEditedAtMs: 1_772_100_030_000,
            lastEditAuditRef: " audit-xt-auto-bind-001 ",
            lastLaunchRef: ""
        )
    }
}
