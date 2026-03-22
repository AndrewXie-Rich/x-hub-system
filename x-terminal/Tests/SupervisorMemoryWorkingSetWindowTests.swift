import Foundation
import Testing
@testable import XTerminal

struct SupervisorMemoryRouteAttempt: Sendable {
    var reviewLevelHint: String?
    var servingProfile: String
}

actor SupervisorMemoryRouteRecorder {
    private var attempts: [SupervisorMemoryRouteAttempt] = []

    func record(reviewLevelHint: String?, servingProfile: String) {
        attempts.append(
            SupervisorMemoryRouteAttempt(
                reviewLevelHint: reviewLevelHint,
                servingProfile: servingProfile
            )
        )
    }

    func snapshot() -> [SupervisorMemoryRouteAttempt] {
        attempts
    }
}

@Suite(.serialized)
@MainActor
struct SupervisorMemoryWorkingSetWindowTests {

    @Test
    func localMemoryWorkingSetUsesRecentRawContextDefaultProfile() async {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = makeConversation(turns: 10)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续推进当前项目")
        let lines = Set(localMemory.split(separator: "\n").map(String.init))
        let dialogueLines = localMemory
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("- user: ") || $0.hasPrefix("- assistant: ") }

        #expect(localMemory.contains("[DIALOGUE_WINDOW]"))
        #expect(localMemory.contains("window_profile: standard_12_pairs"))
        #expect(localMemory.contains("raw_window_floor_pairs: 8"))
        #expect(localMemory.contains("raw_window_selected_pairs: 10"))
        #expect(lines.contains("- user: user-turn-1"))
        #expect(lines.contains("- assistant: assistant-turn-2"))
        #expect(lines.contains("- user: user-turn-10"))
        #expect(lines.contains("- assistant: assistant-turn-10"))
        #expect(lines.contains("- system: system-turn-10"))
        #expect(dialogueLines.count == 20)
    }

    @Test
    func explicitCrossProjectDrillDownAddsStructuredWorkingSetNotFullHistory() async throws {
        let now = Date(timeIntervalSince1970: 1_773_500_500).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w3_35_cross_drill_\(UUID().uuidString)")
        let project = AXProjectEntry(
            projectId: "p-cross",
            rootPath: projectRoot.path,
            displayName: "Cross Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "waiting on structured drill-down",
            nextStepSummary: "review plan summary",
            blockerSummary: "cross-project context is still digest-only",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let ctx = AXProjectContext(root: projectRoot)
        try ctx.ensureDirs()
        try SupervisorProjectSpecCapsuleStore.upsert(
            SupervisorProjectSpecCapsuleBuilder.build(
                projectId: project.projectId,
                goal: "Let supervisor inspect another project without full chat history",
                mvpDefinition: "Inject explicit structured drill-down block",
                nonGoals: ["Do not inject raw logs"],
                approvedTechStack: ["Swift"],
                milestoneMap: [
                    SupervisorProjectSpecMilestone(
                        milestoneId: "ms-cross-1",
                        title: "cross-project drill-down",
                        status: .active
                    )
                ]
            ),
            for: ctx
        )
        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)
        _ = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsuleOnly,
            openedReason: "cross_project_review"
        )

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("看另一个项目的结构化摘要")

        #expect(localMemory.contains("[cross_project_drilldown]"))
        #expect(localMemory.contains("view=drilldown"))
        #expect(localMemory.contains("mode=explicit_structured_drilldown"))
        #expect(localMemory.contains("reason=cross_project_review"))
        #expect(localMemory.contains("project=Cross Project (p-cross)"))
        #expect(localMemory.contains("refs_count="))
        #expect(localMemory.contains("spec_goal=Let supervisor inspect another project without full chat history"))
        #expect(localMemory.contains("scope_safe_refs:"))
        #expect(!localMemory.contains("raw_log.jsonl"))
    }

    @Test
    func reviewProfileExpandsFocusedStrategicConversationWindowToDeepDive() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-review-window-m3")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.messages = makeConversation(turns: 14)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查当前项目的上下文记忆，给出最具体的执行方案"
        )
        let dialogueWindowLines = Set(extractDialogueWindowLines(from: localMemory))

        #expect(!dialogueWindowLines.contains("- user: user-turn-1"))
        #expect(!dialogueWindowLines.contains("- user: user-turn-2"))
        #expect(dialogueWindowLines.contains("- user: user-turn-3"))
        #expect(dialogueWindowLines.contains("- assistant: assistant-turn-3"))
        #expect(dialogueWindowLines.contains("- user: user-turn-14"))
        #expect(dialogueWindowLines.contains("- assistant: assistant-turn-14"))
        #expect(localMemory.contains("window_profile: standard_12_pairs"))
        #expect(localMemory.contains("raw_window_selected_pairs: 12"))
        #expect(localMemory.contains("[SERVING_GOVERNOR]"))
        #expect(localMemory.contains("review_level_hint: r2_strategic"))
        #expect(localMemory.contains("profile_floor: m3_deep_dive"))
        #expect(localMemory.contains("minimum_pack: portfolio_brief, focused_project_anchor_pack, longterm_outline, delta_feed, conflict_set, context_refs, evidence_pack"))
        #expect(localMemory.contains("[SERVING_PROFILE]"))
        #expect(localMemory.contains("profile_id: m3_deep_dive"))
    }

    @Test
    func strategicReviewWithoutFocusedProjectStaysAtPlanReviewWindow() async {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = makeConversation(turns: 14)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查当前项目的上下文记忆，给出最具体的执行方案"
        )
        let dialogueWindowLines = Set(extractDialogueWindowLines(from: localMemory))

        #expect(!dialogueWindowLines.contains("- user: user-turn-1"))
        #expect(!dialogueWindowLines.contains("- user: user-turn-2"))
        #expect(dialogueWindowLines.contains("- user: user-turn-3"))
        #expect(dialogueWindowLines.contains("- assistant: assistant-turn-3"))
        #expect(dialogueWindowLines.contains("- user: user-turn-14"))
        #expect(dialogueWindowLines.contains("- assistant: assistant-turn-14"))
        #expect(localMemory.contains("window_profile: standard_12_pairs"))
        #expect(localMemory.contains("raw_window_selected_pairs: 12"))
        #expect(localMemory.contains("[SERVING_GOVERNOR]"))
        #expect(localMemory.contains("review_level_hint: r2_strategic"))
        #expect(localMemory.contains("profile_floor: m2_plan_review"))
        #expect(localMemory.contains("minimum_pack: portfolio_brief, focused_project_anchor_pack, longterm_outline, delta_feed, conflict_set, context_refs"))
        #expect(!localMemory.contains("minimum_pack: portfolio_brief, focused_project_anchor_pack, longterm_outline, delta_feed, conflict_set, context_refs, evidence_pack"))
        #expect(localMemory.contains("[SERVING_PROFILE]"))
        #expect(localMemory.contains("profile_id: m2_plan_review"))
    }

    @Test
    func recentRawContextDropsLowSignalTailAndAddsRollingDigest() async {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = makeConversationWithLowSignalTail()

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续推进")

        #expect(localMemory.contains("window_profile: standard_12_pairs"))
        #expect(localMemory.contains("raw_window_selected_pairs: 12"))
        #expect(localMemory.contains("low_signal_dropped_messages: 4"))
        #expect(localMemory.contains("rolling_dialogue_digest:"))
        #expect(localMemory.contains("source_eligible_messages: 4"))
        #expect(!localMemory.contains("- user: 你好"))
        #expect(!localMemory.contains("- assistant: 收到"))
        #expect(!localMemory.contains("- user: 好"))
        #expect(!localMemory.contains("- assistant: 好的"))
        #expect(localMemory.contains("- user: user-turn-3"))
        #expect(localMemory.contains("- assistant: assistant-turn-14"))
        #expect(localMemory.contains("- user-turn-2"))
        #expect(localMemory.contains("- assistant-turn-1"))
    }

    @Test
    func supervisorRemoteMemoryRequestCarriesReviewLevelHintAndProfileFloor() async throws {
        let recorder = SupervisorMemoryRouteRecorder()
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            await recorder.record(
                reviewLevelHint: route.payload.reviewLevelHint,
                servingProfile: route.servingProfile.rawValue
            )
            return HubIPCClient.MemoryContextResolutionResult(
                response: HubIPCClient.MemoryContextResponsePayload(
                    text: "[MEMORY_V1]\n[/MEMORY_V1]",
                    source: "test_override",
                    resolvedMode: mode.rawValue,
                    resolvedProfile: route.servingProfile.rawValue,
                    budgetTotalTokens: 1_800,
                    usedTotalTokens: route.servingProfile == .m1Execute ? 1_560 : 820,
                    layerUsage: [],
                    truncatedLayers: route.servingProfile == .m1Execute ? ["l1_canonical"] : [],
                    redactedItems: 0,
                    privateDrops: 0
                ),
                source: "test_override",
                resolvedMode: mode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "fresh_local_ipc",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-remote-memory-m3")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        _ = await manager.buildSupervisorMemoryV1ForTesting(
            "审查当前项目的上下文记忆，给出最具体的执行方案"
        )

        let snapshot = await recorder.snapshot()
        let strategicAttempt = snapshot.last {
            $0.reviewLevelHint == SupervisorReviewLevel.r2Strategic.rawValue
        }
        #expect(strategicAttempt?.servingProfile == XTMemoryServingProfile.m3DeepDive.rawValue)
    }

    @Test
    func supervisorRemoteStrategicMemoryWithoutFocusedProjectStaysAtM2() async throws {
        let recorder = SupervisorMemoryRouteRecorder()
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            await recorder.record(
                reviewLevelHint: route.payload.reviewLevelHint,
                servingProfile: route.servingProfile.rawValue
            )
            return HubIPCClient.MemoryContextResolutionResult(
                response: HubIPCClient.MemoryContextResponsePayload(
                    text: "[MEMORY_V1]\n[/MEMORY_V1]",
                    source: "test_override",
                    resolvedMode: mode.rawValue,
                    resolvedProfile: route.servingProfile.rawValue,
                    budgetTotalTokens: 1_800,
                    usedTotalTokens: 820,
                    layerUsage: [],
                    truncatedLayers: [],
                    redactedItems: 0,
                    privateDrops: 0
                ),
                source: "test_override",
                resolvedMode: mode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "fresh_local_ipc",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let manager = SupervisorManager.makeForTesting()
        let rootA = try makeProjectRoot(named: "supervisor-remote-memory-unfocused-a")
        let rootB = try makeProjectRoot(named: "supervisor-remote-memory-unfocused-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let projectA = makeProjectEntry(root: rootA, displayName: "项目 A")
        let projectB = makeProjectEntry(root: rootB, displayName: "项目 B")
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)
        _ = await manager.buildSupervisorMemoryV1ForTesting(
            "审查当前项目的上下文记忆，给出最具体的执行方案"
        )

        let snapshot = await recorder.snapshot()
        let strategicAttempt = snapshot.last {
            $0.reviewLevelHint == SupervisorReviewLevel.r2Strategic.rawValue
        }
        #expect(strategicAttempt?.servingProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
    }

    @Test
    func focusedStrategicReviewDefaultsToM3AndExpandsLineageAndEvidence() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-strategic-m3")
        defer { try? FileManager.default.removeItem(at: root) }

        var project = makeProjectEntry(root: root, displayName: "亮亮")
        project.currentStateSummary = "主链在推进，但要防止策略跑偏"
        project.nextStepSummary = "先完成验证，再决定是否改路"
        project.blockerSummary = "release gate 还没绿"

        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        try SupervisorProjectSpecCapsuleStore.save(
            SupervisorProjectSpecCapsuleBuilder.build(
                projectId: project.projectId,
                goal: "稳定推进主链并保住既定战略边界",
                mvpDefinition: "通过 release gate 后再决定是否改路",
                nonGoals: ["不要在验证完成前扩大 scope"],
                approvedTechStack: ["Swift", "Hub memory", "governed channels"],
                milestoneMap: [
                    SupervisorProjectSpecMilestone(
                        milestoneId: "m1",
                        title: "先完成 release 验证",
                        status: .active
                    ),
                    SupervisorProjectSpecMilestone(
                        milestoneId: "m2",
                        title: "验证后再决定是否切换路径",
                        status: .planned
                    )
                ],
                sourceRefs: ["spec://proj-liang"]
            ),
            for: ctx
        )

        _ = try SupervisorDecisionTrackStore.upsert(
            SupervisorDecisionTrackBuilder.build(
                decisionId: "decision-scope-freeze",
                projectId: project.projectId,
                category: .scopeFreeze,
                status: .approved,
                statement: "在 release gate 通过前，不允许提前切换到新战略路径。",
                source: "user_confirmed_strategy",
                reversible: true,
                approvalRequired: false,
                auditRef: "audit-decision-scope-freeze",
                evidenceRefs: ["decision://scope-freeze"],
                createdAtMs: 1_773_800_000_000
            ),
            for: ctx
        )
        _ = try SupervisorDecisionTrackStore.upsert(
            SupervisorDecisionTrackBuilder.build(
                decisionId: "decision-risk-posture",
                projectId: project.projectId,
                category: .riskPosture,
                status: .approved,
                statement: "当前阶段优先稳态验证，不接受高波动战略切换。",
                source: "strategic_review",
                reversible: true,
                approvalRequired: false,
                auditRef: "audit-decision-risk-posture",
                evidenceRefs: ["decision://risk-posture"],
                createdAtMs: 1_773_800_100_000
            ),
            for: ctx
        )

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "先别急着换路线，先把 release gate 跑绿。",
            createdAt: Date(timeIntervalSince1970: 1_773_800_200).timeIntervalSince1970
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "收到，当前 blocker 是 release gate 还没绿。",
            createdAt: Date(timeIntervalSince1970: 1_773_800_201).timeIntervalSince1970
        )

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("profile_id: m3_deep_dive"))
        #expect(localMemory.contains("review_level_hint: r2_strategic"))
        #expect(localMemory.contains("profile_floor: m3_deep_dive"))
        #expect(localMemory.contains("minimum_pack: portfolio_brief, focused_project_anchor_pack, longterm_outline, delta_feed, conflict_set, context_refs, evidence_pack"))
        #expect(localMemory.contains("decision_lineage:"))
        #expect(localMemory.contains("category: risk_posture"))
        #expect(localMemory.contains("blocker_lineage:"))
        #expect(localMemory.contains("current_blocker: release gate 还没绿"))
        #expect(localMemory.contains("guidance_guardrail: (none)"))
        #expect(localMemory.contains("why_included=durable_background_outline"))
        #expect(localMemory.contains("why_included=decision_lineage_anchor"))
        #expect(localMemory.contains("why_included=active_blocker_lineage"))
    }

    @Test
    func focusedProjectAnchorPackIncludesLatestUIReviewSummary() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-ui-review-anchor")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let ctx = AXProjectContext(root: root)
        let bundle = XTUIObservationBundle(
            schemaVersion: XTUIObservationBundle.currentSchemaVersion,
            bundleID: "bundle-supervisor-anchor",
            projectID: project.projectId,
            runID: "run-supervisor-anchor",
            stepID: "step-supervisor-anchor",
            sessionID: "session-supervisor-anchor",
            surfaceType: .browserPage,
            surfaceID: "surface-supervisor-anchor",
            probeDepth: .standard,
            triggerSource: "test",
            captureStatus: .captured,
            captureStartedAtMs: 1_773_800_299_000,
            captureCompletedAtMs: 1_773_800_300_000,
            viewport: XTUIObservationViewport(width: 1280, height: 720, scale: 2),
            environment: XTUIObservationEnvironment(platform: "macos", theme: "light", locale: "en-US"),
            pixelLayer: XTUIObservationPixelLayer(
                status: .captured,
                fullRef: XTUIObservationStore.artifactRef(bundleID: "bundle-supervisor-anchor", relativePath: "full.png"),
                thumbnailRef: XTUIObservationStore.artifactRef(bundleID: "bundle-supervisor-anchor", relativePath: "thumb.png"),
                cropRefs: [],
                width: 1280,
                height: 720
            ),
            structureLayer: XTUIObservationStructureLayer(
                status: .captured,
                roleSnapshotRef: XTUIObservationStore.artifactRef(bundleID: "bundle-supervisor-anchor", relativePath: "role_snapshot.txt"),
                axTreeRef: XTUIObservationStore.artifactRef(bundleID: "bundle-supervisor-anchor", relativePath: "structure.json")
            ),
            textLayer: XTUIObservationTextLayer(
                status: .captured,
                visibleTextRef: XTUIObservationStore.artifactRef(bundleID: "bundle-supervisor-anchor", relativePath: "visible_text.txt"),
                ocrRef: ""
            ),
            runtimeLayer: XTUIObservationRuntimeLayer(
                status: .captured,
                consoleErrorCount: 0,
                networkErrorCount: 0,
                runtimeLogRef: XTUIObservationStore.artifactRef(bundleID: "bundle-supervisor-anchor", relativePath: "runtime.json")
            ),
            layoutLayer: XTUIObservationLayoutLayer(
                status: .captured,
                layoutMetricsRef: XTUIObservationStore.artifactRef(bundleID: "bundle-supervisor-anchor", relativePath: "layout.json"),
                interactiveTargets: 0,
                visiblePrimaryCTA: false
            ),
            privacy: XTUIObservationPrivacy(classification: "internal", redacted: false, redactionRef: ""),
            acceptancePackRef: "",
            auditRef: "audit-bundle-supervisor-anchor"
        )
        _ = try XTUIObservationStore.writeBundle(
            bundle,
            artifacts: [
                "full.png": Data([0x89, 0x50, 0x4E, 0x47]),
                "thumb.png": Data([0x89, 0x50, 0x4E, 0x47]),
                "visible_text.txt": Data("Sign in".utf8),
                "role_snapshot.txt": Data("AXButton Continue".utf8),
                "structure.json": Data("{}".utf8),
                "runtime.json": Data("{}".utf8),
                "layout.json": Data("{}".utf8)
            ],
            for: ctx
        )
        let review = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-supervisor-anchor",
            projectID: project.projectId,
            bundleID: "bundle-supervisor-anchor",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-supervisor-anchor.json",
            surfaceType: .browserPage,
            probeDepth: .standard,
            objective: "browser_page_actionability",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            interactiveTargetCount: 0,
            criticalActionExpected: true,
            criticalActionVisible: false,
            issueCodes: ["critical_action_not_visible"],
            checks: [
                XTUIReviewCheck(
                    code: "critical_action_not_visible",
                    status: .warning,
                    detail: "The page looks like a login or gated flow, but no likely primary action was detected."
                )
            ],
            summary: "attention needed; confidence=medium; issues=critical_action_not_visible",
            createdAtMs: 1_773_800_300_000,
            auditRef: "audit-supervisor-ui-review"
        )
        _ = try XTUIReviewStore.writeReview(review, for: ctx)

        let previousReview = XTUIReviewRecord(
            schemaVersion: XTUIReviewRecord.currentSchemaVersion,
            reviewID: "uir-supervisor-anchor-previous",
            projectID: project.projectId,
            bundleID: "bundle-supervisor-anchor",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-supervisor-anchor.json",
            surfaceType: .browserPage,
            probeDepth: .standard,
            objective: "browser_page_actionability",
            verdict: .ready,
            confidence: .high,
            sufficientEvidence: true,
            objectiveReady: true,
            interactiveTargetCount: 1,
            criticalActionExpected: false,
            criticalActionVisible: false,
            issueCodes: [],
            checks: [
                XTUIReviewCheck(
                    code: "pixel_capture_available",
                    status: .pass,
                    detail: "Screen capture evidence is available for this browser page."
                )
            ],
            summary: "ready; confidence=high; all core review checks passed",
            createdAtMs: 1_773_800_240_000,
            auditRef: "audit-supervisor-ui-review-previous"
        )
        _ = try XTUIReviewStore.writeReview(previousReview, for: ctx)
        _ = try XTUIReviewStore.writeReview(review, for: ctx)

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，确认当前页面是否可继续自动化"
        )

        #expect(localMemory.contains("latest_ui_review:"))
        #expect(localMemory.contains("ref=local://.xterminal/ui_review/reviews/uir-supervisor-anchor.json"))
        #expect(localMemory.contains("verdict=attention_needed"))
        #expect(localMemory.contains("artifact_refs:"))
        #expect(localMemory.contains("screenshot_ref=local://.xterminal/ui_observation/artifacts/bundle-supervisor-anchor/full.png"))
        #expect(localMemory.contains("recent_history:"))
        #expect(localMemory.contains("review_id=uir-supervisor-anchor-previous"))
        #expect(localMemory.contains("latest_ui_review=ref=local://.xterminal/ui_review/reviews/uir-supervisor-anchor.json"))
        #expect(localMemory.contains("source_scope=ui_review_agent_evidence"))
        #expect(localMemory.contains("local://.xterminal/ui_review/agent_evidence/uir-supervisor-anchor.json"))
        #expect(localMemory.contains("issues=critical_action_not_visible"))
    }

    @Test
    func focusedStrategicAssemblySnapshotCapturesSectionsAndTruncationTelemetry() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-assembly-snapshot-m3")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            HubIPCClient.MemoryContextResolutionResult(
                response: HubIPCClient.MemoryContextResponsePayload(
                    text: "[MEMORY_V1]\n[/MEMORY_V1]",
                    source: "test_override",
                    resolvedMode: mode.rawValue,
                    requestedProfile: route.servingProfile.rawValue,
                    resolvedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    progressiveUpgradeCount: 0,
                    freshness: "fresh_local_ipc",
                    cacheHit: false,
                    denyCode: nil,
                    downgradeCode: nil,
                    budgetTotalTokens: 1_800,
                    usedTotalTokens: 1_560,
                    layerUsage: [],
                    truncatedLayers: ["l1_canonical"],
                    redactedItems: 0,
                    privateDrops: 0
                ),
                source: "test_override",
                resolvedMode: mode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "fresh_local_ipc",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let snapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(snapshot?.requestedProfile == XTMemoryServingProfile.m3DeepDive.rawValue)
        #expect(snapshot?.profileFloor == XTMemoryServingProfile.m3DeepDive.rawValue)
        #expect(snapshot?.resolvedProfile == XTMemoryServingProfile.m3DeepDive.rawValue)
        #expect(snapshot?.focusedProjectId == project.projectId)
        #expect(snapshot?.rawWindowProfile == XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue)
        #expect(snapshot?.rawWindowFloorPairs == 8)
        #expect(snapshot?.rawWindowSelectedPairs == 0)
        #expect(snapshot?.rawWindowSource == "xt_cache")
        #expect(snapshot?.selectedSections.contains("focused_project_anchor_pack") == true)
        #expect(snapshot?.selectedSections.contains("dialogue_window") == true)
        #expect(snapshot?.selectedSections.contains("evidence_pack") == true)
        #expect(snapshot?.contextRefsSelected ?? 0 > 0)
        #expect(snapshot?.evidenceItemsSelected ?? 0 > 0)
        #expect(snapshot?.truncatedLayers == ["l1_canonical"])
        #expect(snapshot?.usedTotalTokens == 1_560)
        #expect(snapshot?.budgetTotalTokens == 1_800)
    }

    @Test
    func unfocusedStrategicAssemblySnapshotReportsM2AndOmittedDeepDiveSections() async throws {
        let manager = SupervisorManager.makeForTesting()

        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            HubIPCClient.MemoryContextResolutionResult(
                response: HubIPCClient.MemoryContextResponsePayload(
                    text: "[MEMORY_V1]\n[/MEMORY_V1]",
                    source: "test_override",
                    resolvedMode: mode.rawValue,
                    requestedProfile: route.servingProfile.rawValue,
                    resolvedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    progressiveUpgradeCount: 0,
                    freshness: "fresh_local_ipc",
                    cacheHit: false,
                    denyCode: nil,
                    downgradeCode: nil,
                    budgetTotalTokens: 1_800,
                    usedTotalTokens: 820,
                    layerUsage: [],
                    truncatedLayers: [],
                    redactedItems: 0,
                    privateDrops: 0
                ),
                source: "test_override",
                resolvedMode: mode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "fresh_local_ipc",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let snapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting(
            "审查当前项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(snapshot?.requestedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(snapshot?.profileFloor == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(snapshot?.resolvedProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(snapshot?.focusedProjectId == nil)
        #expect(snapshot?.rawWindowProfile == XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue)
        #expect(snapshot?.rawWindowFloorPairs == 8)
        #expect(snapshot?.rawWindowSource == "xt_cache")
        #expect(snapshot?.selectedSections.contains("delta_feed") == true)
        #expect(snapshot?.selectedSections.contains("dialogue_window") == true)
        #expect(snapshot?.omittedSections.contains("focused_project_anchor_pack") == true)
        #expect(snapshot?.omittedSections.contains("portfolio_brief") == true)
        #expect(snapshot?.omittedSections.contains("context_refs") == true)
        #expect(snapshot?.omittedSections.contains("evidence_pack") == true)
        #expect(snapshot?.evidenceItemsSelected == 0)
    }

    @Test
    func supervisorAssemblySnapshotCanUseHubThreadAsContinuitySource() async throws {
        let manager = SupervisorManager.makeForTesting()

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            HubRouteDecision(
                mode: .auto,
                hasRemoteProfile: true,
                preferRemote: true,
                allowFileFallback: true,
                requiresRemote: false,
                remoteUnavailableReasonCode: nil
            )
        }
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: true,
                source: "hub_thread",
                workingEntries: [
                    "user: user-turn-1",
                    "assistant: assistant-turn-1",
                    "user: user-turn-2",
                    "assistant: assistant-turn-2",
                ],
                cacheHit: false,
                reasonCode: nil
            )
        }
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            HubIPCClient.MemoryContextResolutionResult(
                response: HubIPCClient.MemoryContextResponsePayload(
                    text: "[MEMORY_V1]\n[/MEMORY_V1]",
                    source: "test_override",
                    resolvedMode: mode.rawValue,
                    requestedProfile: route.servingProfile.rawValue,
                    resolvedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    progressiveUpgradeCount: 0,
                    freshness: "fresh_remote",
                    cacheHit: false,
                    denyCode: nil,
                    downgradeCode: nil,
                    budgetTotalTokens: 1_800,
                    usedTotalTokens: 640,
                    layerUsage: [],
                    truncatedLayers: [],
                    redactedItems: 0,
                    privateDrops: 0
                ),
                source: "test_override",
                resolvedMode: mode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "fresh_remote",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let snapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting("继续推进当前项目")
        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续推进当前项目")

        #expect(snapshot?.rawWindowSource == "hub_thread")
        #expect(snapshot?.rawWindowSelectedPairs == 2)
        #expect(snapshot?.continuityTraceLines.contains(where: { $0.contains("remote_continuity=ok") }) == true)
        #expect(localMemory.contains("raw_window_source: hub_thread"))
        #expect(localMemory.contains("- user: user-turn-1"))
        #expect(localMemory.contains("- assistant: assistant-turn-2"))
    }

    @Test
    func supervisorAssemblySnapshotCanMergeHubThreadWithLocalTail() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = [
            SupervisorMessage(id: "u2", role: .user, content: "user-turn-2", isVoice: false, timestamp: 2),
            SupervisorMessage(id: "a2", role: .assistant, content: "assistant-turn-2", isVoice: false, timestamp: 3),
            SupervisorMessage(id: "u3", role: .user, content: "user-turn-3", isVoice: false, timestamp: 4),
        ]

        HubIPCClient.installHubRouteDecisionOverrideForTesting {
            HubRouteDecision(
                mode: .auto,
                hasRemoteProfile: true,
                preferRemote: true,
                allowFileFallback: true,
                requiresRemote: false,
                remoteUnavailableReasonCode: nil
            )
        }
        HubIPCClient.installSupervisorRemoteContinuityOverrideForTesting { _ in
            HubIPCClient.SupervisorRemoteContinuityResult(
                ok: true,
                source: "hub_thread",
                workingEntries: [
                    "user: user-turn-1",
                    "assistant: assistant-turn-1",
                    "user: user-turn-2",
                    "assistant: assistant-turn-2",
                ],
                cacheHit: false,
                reasonCode: nil
            )
        }
        HubIPCClient.installMemoryContextResolutionOverrideForTesting { route, mode, _ in
            HubIPCClient.MemoryContextResolutionResult(
                response: HubIPCClient.MemoryContextResponsePayload(
                    text: "[MEMORY_V1]\n[/MEMORY_V1]",
                    source: "test_override",
                    resolvedMode: mode.rawValue,
                    requestedProfile: route.servingProfile.rawValue,
                    resolvedProfile: route.servingProfile.rawValue,
                    attemptedProfiles: [route.servingProfile.rawValue],
                    progressiveUpgradeCount: 0,
                    freshness: "fresh_remote",
                    cacheHit: false,
                    denyCode: nil,
                    downgradeCode: nil,
                    budgetTotalTokens: 1_800,
                    usedTotalTokens: 720,
                    layerUsage: [],
                    truncatedLayers: [],
                    redactedItems: 0,
                    privateDrops: 0
                ),
                source: "test_override",
                resolvedMode: mode,
                requestedProfile: route.servingProfile.rawValue,
                attemptedProfiles: [route.servingProfile.rawValue],
                freshness: "fresh_remote",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let snapshot = await manager.buildSupervisorMemoryAssemblySnapshotForTesting("继续推进当前项目")
        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting("继续推进当前项目")

        #expect(snapshot?.rawWindowSource == "mixed")
        #expect(snapshot?.rawWindowSelectedPairs == 3)
        #expect(snapshot?.continuityTraceLines.contains(where: { $0.contains("assembled_source=mixed") }) == true)
        #expect(localMemory.contains("raw_window_source: mixed"))
        #expect(localMemory.contains("- user: user-turn-1"))
        #expect(localMemory.contains("- assistant: assistant-turn-2"))
        #expect(localMemory.contains("- user: user-turn-3"))
    }

    @Test
    func focusedProjectReviewAutoAddsGovernedRetrievalSnippets() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-retrieval")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_supervisor_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: nil,
                denyCode: nil,
                snippets: [
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "snippet-1",
                        sourceKind: "decision_track",
                        title: "approved architecture direction",
                        ref: "memory://decision/proj-liang/dec-1",
                        text: "Use governed project phases: scan, isolate, refactor, verify.",
                        score: 97,
                        truncated: false
                    ),
                    HubIPCClient.MemoryRetrievalSnippet(
                        snippetId: "snippet-2",
                        sourceKind: "project_spec_capsule",
                        title: "tech stack capsule",
                        ref: "memory://spec/proj-liang/capsule",
                        text: "Current stack is Swift + governed Hub memory orchestration.",
                        score: 92,
                        truncated: false
                    )
                ],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("[focused_project_retrieval]"))
        #expect(localMemory.contains("focus_project=亮亮 (\(project.projectId))"))
        #expect(localMemory.contains("retrieval_source=test_supervisor_retrieval"))
        #expect(localMemory.contains("[decision_track] approved architecture direction"))
        #expect(localMemory.contains("Use governed project phases: scan, isolate, refactor, verify."))
        #expect(localMemory.contains("[project_spec_capsule] tech stack capsule"))
    }

    @Test
    func focusedProjectReviewSurfacesRetrievalDenyMetadata() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-memory-retrieval-denied")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(root: root, displayName: "亮亮")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        HubIPCClient.installMemoryRetrievalOverrideForTesting { payload, _ in
            HubIPCClient.MemoryRetrievalResponsePayload(
                source: "test_supervisor_retrieval",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "scope_gate",
                denyCode: "cross_scope_memory_denied",
                snippets: [],
                truncatedItems: 0,
                redactedItems: 0
            )
        }
        defer { HubIPCClient.resetMemoryContextResolutionOverrideForTesting() }

        let localMemory = await manager.buildSupervisorLocalMemoryV1ForTesting(
            "审查亮亮项目的上下文记忆，给出最具体的执行方案"
        )

        #expect(localMemory.contains("[focused_project_retrieval]"))
        #expect(localMemory.contains("focus_project=亮亮 (\(project.projectId))"))
        #expect(localMemory.contains("status=denied"))
        #expect(localMemory.contains("reason_code=scope_gate"))
        #expect(localMemory.contains("deny_code=cross_scope_memory_denied"))
        #expect(localMemory.contains("retrieval_source=test_supervisor_retrieval"))
    }

    private func makeConversation(turns: Int) -> [SupervisorMessage] {
        var out: [SupervisorMessage] = []
        for index in 1...turns {
            let base = Double(index * 10)
            out.append(
                SupervisorMessage(
                    id: "u-\(index)",
                    role: .user,
                    content: "user-turn-\(index)",
                    isVoice: false,
                    timestamp: base
                )
            )
            out.append(
                SupervisorMessage(
                    id: "a-\(index)",
                    role: .assistant,
                    content: "assistant-turn-\(index)",
                    isVoice: false,
                    timestamp: base + 1
                )
            )
            out.append(
                SupervisorMessage(
                    id: "s-\(index)",
                    role: .system,
                    content: "system-turn-\(index)",
                    isVoice: false,
                    timestamp: base + 2
                )
            )
        }
        return out
    }

    private func makeConversationWithLowSignalTail() -> [SupervisorMessage] {
        var out = makeConversation(turns: 14)
        out.append(
            SupervisorMessage(
                id: "u-15",
                role: .user,
                content: "你好",
                isVoice: false,
                timestamp: 150
            )
        )
        out.append(
            SupervisorMessage(
                id: "a-15",
                role: .assistant,
                content: "收到",
                isVoice: false,
                timestamp: 151
            )
        )
        out.append(
            SupervisorMessage(
                id: "u-16",
                role: .user,
                content: "好",
                isVoice: false,
                timestamp: 160
            )
        )
        out.append(
            SupervisorMessage(
                id: "a-16",
                role: .assistant,
                content: "好的",
                isVoice: false,
                timestamp: 161
            )
        )
        return out
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    private func makeProjectEntry(root: URL, displayName: String) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "梳理结构并给出执行方案",
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt-\(name)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func extractDialogueWindowLines(from localMemory: String) -> [String] {
        guard let start = localMemory.range(of: "[DIALOGUE_WINDOW]\n"),
              let end = localMemory.range(of: "\n[/DIALOGUE_WINDOW]") else {
            return []
        }
        let body = localMemory[start.upperBound..<end.lowerBound]
        return body
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("- user: ") || $0.hasPrefix("- assistant: ") }
    }
}
