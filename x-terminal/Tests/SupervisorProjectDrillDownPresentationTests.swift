import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectDrillDownPresentationTests {

    @Test
    func mapBuildsRichAllowedPresentation() throws {
        let capsule = SupervisorPortfolioProjectCard(
            projectId: "project-alpha",
            displayName: "Project Alpha",
            projectState: .blocked,
            runtimeState: "running",
            currentAction: "Validate the current implementation",
            topBlocker: "Awaiting a final API choice",
            nextStep: "Approve the API contract",
            memoryFreshness: .fresh,
            updatedAt: 42,
            recentMessageCount: 4
        )
        let spec = SupervisorProjectSpecCapsuleBuilder.build(
            projectId: "project-alpha",
            goal: "Ship a governed agent runtime",
            mvpDefinition: "Connect skills, memory, and approvals",
            nonGoals: ["Mobile app"],
            approvedTechStack: ["SwiftUI", "Node"],
            milestoneMap: [
                SupervisorProjectSpecMilestone(
                    milestoneId: "m1",
                    title: "Skill runtime",
                    status: .active
                )
            ]
        )
        let decision = SupervisorDecisionTrackEvent(
            schemaVersion: SupervisorDecisionTrackEvent.schemaVersion,
            decisionId: "decision-1",
            projectId: "project-alpha",
            category: .techStack,
            status: .approved,
            statement: "Use SwiftUI for supervisor surfaces",
            source: "supervisor",
            reversible: true,
            approvalRequired: false,
            approvedBy: "",
            auditRef: "audit-decision-1",
            evidenceRefs: ["evidence://decision/1"],
            createdAtMs: 100,
            updatedAtMs: 200
        )
        let backgroundNote = SupervisorBackgroundPreferenceNote(
            schemaVersion: SupervisorBackgroundPreferenceNote.schemaVersion,
            noteId: "note-1",
            projectId: "project-alpha",
            domain: .uxStyle,
            strength: .medium,
            statement: "Prefer compact operational cards",
            mustNotPromoteWithoutDecision: true,
            createdAtMs: 150
        )
        let rails = SupervisorProjectDecisionRails(
            projectId: "project-alpha",
            decisionTrack: [decision],
            backgroundPreferenceTrack: [backgroundNote],
            resolutions: [
                SupervisorDecisionRailResolution(
                    domain: .techStack,
                    hardDecision: decision,
                    preferredBackgroundNote: nil,
                    shadowedBackgroundNotes: []
                ),
                SupervisorDecisionRailResolution(
                    domain: .uxStyle,
                    hardDecision: nil,
                    preferredBackgroundNote: backgroundNote,
                    shadowedBackgroundNotes: []
                )
            ]
        )
        let review = SupervisorReviewNoteRecord(
            schemaVersion: SupervisorReviewNoteRecord.currentSchemaVersion,
            reviewId: "review-1",
            projectId: "project-alpha",
            trigger: .manualRequest,
            reviewLevel: .r2Strategic,
            verdict: .watch,
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            ackRequired: true,
            effectiveSupervisorTier: .s3StrategicCoach,
            effectiveWorkOrderDepth: .executionReady,
            projectAIStrengthBand: .capable,
            projectAIStrengthConfidence: 0.82,
            projectAIStrengthAuditRef: nil,
            workOrderRef: "wo-123",
            summary: "Project is moving, but API choices remain open.",
            recommendedActions: ["Freeze the API contract before adding more skills."],
            anchorGoal: "Ship the runtime",
            anchorDoneDefinition: "Green smoke tests",
            anchorConstraints: ["Keep UI responsive"],
            currentState: "running",
            nextStep: "Freeze API",
            blocker: "API uncertainty",
            memoryCursor: nil,
            projectStateHash: nil,
            portfolioStateHash: nil,
            createdAtMs: 300,
            auditRef: "audit-review-1"
        )
        let pendingGuidance = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-pending",
            reviewId: "review-1",
            projectId: "project-alpha",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: "Pause implementation after the current step and freeze the API.",
            ackStatus: .pending,
            ackRequired: true,
            effectiveSupervisorTier: .s3StrategicCoach,
            effectiveWorkOrderDepth: .executionReady,
            workOrderRef: "wo-123",
            ackNote: "",
            injectedAtMs: 320,
            ackUpdatedAtMs: 320,
            expiresAtMs: 0,
            retryAtMs: 0,
            retryCount: 0,
            maxRetryCount: 0,
            auditRef: "audit-guidance-pending"
        )
        let latestGuidance = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-latest",
            reviewId: "review-1",
            projectId: "project-alpha",
            targetRole: .coder,
            deliveryMode: .contextAppend,
            interventionMode: .suggestNextSafePoint,
            safePointPolicy: .checkpointBoundary,
            guidanceText: "Keep the implementation notes in memory after the freeze.",
            ackStatus: .accepted,
            ackRequired: true,
            effectiveSupervisorTier: .s2PeriodicReview,
            effectiveWorkOrderDepth: .brief,
            workOrderRef: "wo-122",
            ackNote: "accepted",
            injectedAtMs: 280,
            ackUpdatedAtMs: 340,
            expiresAtMs: 0,
            retryAtMs: 0,
            retryCount: 0,
            maxRetryCount: 0,
            auditRef: "audit-guidance-latest"
        )
        let activeJob = SupervisorJobRecord(
            schemaVersion: SupervisorJobRecord.currentSchemaVersion,
            jobId: "job-1",
            projectId: "project-alpha",
            goal: "Stabilize the supervisor workflow",
            priority: .high,
            status: .running,
            source: .supervisor,
            currentOwner: "coder",
            activePlanId: "plan-1",
            createdAtMs: 100,
            updatedAtMs: 400,
            auditRef: "audit-job-1"
        )
        let activePlan = SupervisorPlanRecord(
            schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
            planId: "plan-1",
            jobId: "job-1",
            projectId: "project-alpha",
            status: .active,
            currentOwner: "coder",
            steps: [
                SupervisorPlanStepRecord(
                    schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                    stepId: "step-2",
                    title: "Run the contract tests",
                    kind: .callSkill,
                    status: .pending,
                    skillId: "code-review",
                    currentOwner: "coder",
                    detail: "Run tests",
                    dependsOn: nil,
                    timeoutMs: nil,
                    maxRetries: nil,
                    failurePolicy: nil,
                    orderIndex: 1,
                    updatedAtMs: 401
                ),
                SupervisorPlanStepRecord(
                    schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                    stepId: "step-1",
                    title: "Freeze the API contract",
                    kind: .askUser,
                    status: .running,
                    skillId: "",
                    currentOwner: "supervisor",
                    detail: "Freeze contract",
                    dependsOn: nil,
                    timeoutMs: nil,
                    maxRetries: nil,
                    failurePolicy: nil,
                    orderIndex: 0,
                    updatedAtMs: 402
                )
            ],
            createdAtMs: 200,
            updatedAtMs: 410,
            auditRef: "audit-plan-1"
        )
        let workflow = SupervisorProjectWorkflowSnapshot(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            updatedAtMs: 410,
            activeJob: activeJob,
            activePlan: activePlan,
            activeSkillCall: nil,
            auditRef: "audit-workflow-1"
        )
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 500,
            projectId: "project-alpha",
            projectName: "Project Alpha",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsulePlusRecent,
            grantedScope: .capsulePlusRecent,
            capsule: capsule,
            specCapsule: spec,
            decisionRails: rails,
            latestReview: review,
            latestGuidance: latestGuidance,
            pendingAckGuidance: pendingGuidance,
            followUpRhythmSummary: "review every 4h or on blocker",
            workflow: workflow,
            recentMessages: [
                AXRecentContextMessage(role: "user", content: "Please freeze the API today.", createdAt: 1),
                AXRecentContextMessage(role: "assistant", content: "I will stabilize the contract first.", createdAt: 2)
            ],
            denyReason: nil,
            refs: [
                "/tmp/project-alpha/AX_MEMORY.md",
                "hub://project/project-alpha/snapshot/xterminal.project.snapshot"
            ]
        )
        let latestUIReview = XTUIReviewPresentation(
            reviewRef: "local://.xterminal/ui_review/reviews/project-alpha-latest.json",
            bundleRef: "local://.xterminal/ui_observation/bundles/project-alpha-latest.json",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible"],
            summary: "attention needed",
            updatedAtMs: 450,
            interactiveTargetCount: 2,
            criticalActionExpected: true,
            criticalActionVisible: false,
            checks: [],
            reviewFileURL: nil,
            bundleFileURL: nil,
            screenshotFileURL: nil,
            visibleTextFileURL: nil,
            recentHistory: [],
            trend: nil,
            comparison: nil
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly, .capsulePlusRecent],
            selectedScope: .capsulePlusRecent,
            governanceTags: [
                SupervisorPortfolioTagPresentation(id: "safe", title: "安全", tone: .success)
            ],
            runtimeSummary: "runtime profile drifted to device-governed",
            latestUIReview: latestUIReview,
            governanceNowMs: 1_000
        )

        #expect(presentation.title == "项目细看")
        #expect(presentation.projectId == "project-alpha")
        #expect(presentation.projectName == "Project Alpha")
        #expect(presentation.scopeOptions.map(\.title) == ["项目摘要", "摘要+最近对话"])
        #expect(presentation.statusLine == "当前显示：摘要+最近对话 · 从项目看板打开 · 2 条关联引用")
        #expect(presentation.governanceTags.map(\.title) == ["安全"])
        #expect(presentation.runtimeSummary == "runtime profile drifted to device-governed")
        #expect(presentation.scopeRestrictionText == nil)
        #expect(presentation.latestUIReview?.reviewRef == "local://.xterminal/ui_review/reviews/project-alpha-latest.json")
        #expect(presentation.latestUIReview?.issueSummary == "未看到关键操作")
        #expect(presentation.sections.compactMap(\.title) == [
            "规格摘要",
            "已确认决策",
            "最新治理",
            "当前工作流",
            "最近对话",
            "关联引用"
        ])
        #expect(presentation.sections[0].lines.map(\.text) == [
            "当前动作：Validate the current implementation",
            "下一步：Approve the API contract",
            "阻塞：Awaiting a final API choice"
        ])

        let governanceSection = try #require(presentation.sections.first(where: { $0.id == "governance" }))
        #expect(governanceSection.lines.contains(where: { $0.text == "跟进节奏：review every 4h or on blocker" }))
        #expect(governanceSection.lines.contains(where: { $0.text.contains("审查：需要关注 · R2 战略 · 手动请求") }))
        #expect(governanceSection.lines.contains(where: { $0.text.contains("AI 强度：可胜任 · 置信度=82%") }))
        #expect(governanceSection.lines.contains(where: { $0.text.contains("待确认指导：优先插入 · 在安全点重规划") }))
        #expect(governanceSection.lines.contains(where: { $0.text == "指导合同：监督重规划" }))
        #expect(governanceSection.lines.contains(where: { $0.text == "阻塞：API uncertainty" }))
        #expect(governanceSection.lines.contains(where: { $0.text == "下一个安全动作：先按当前重规划处理" }))
        #expect(governanceSection.lines.contains(where: {
            $0.text == "建议动作：Freeze the API contract before adding more skills."
        }))
        #expect(governanceSection.lines.contains(where: { $0.text.contains("最新指导：上下文追加 · 在安全点建议") }))

        let workflowSection = try #require(presentation.sections.first(where: { $0.id == "active-workflow" }))
        #expect(workflowSection.lines.map(\.text) == [
            "job: Stabilize the supervisor workflow",
            "status: running",
            "plan: active",
            "1. Freeze the API contract",
            "2. Run the contract tests"
        ])
    }

    @Test
    func mapBuildsCapsuleOnlyRecentHintAndScopeRestriction() throws {
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 10,
            projectId: "project-beta",
            projectName: "Project Beta",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsuleOnly,
            grantedScope: .capsuleOnly,
            capsule: SupervisorPortfolioProjectCard(
                projectId: "project-beta",
                displayName: "Project Beta",
                projectState: .active,
                runtimeState: "active",
                currentAction: "Keep moving",
                topBlocker: "",
                nextStep: "Stay on path",
                memoryFreshness: .fresh,
                updatedAt: 9,
                recentMessageCount: 1
            ),
            specCapsule: nil,
            decisionRails: nil,
            latestReview: nil,
            latestGuidance: nil,
            pendingAckGuidance: nil,
            followUpRhythmSummary: nil,
            workflow: nil,
            recentMessages: [],
            denyReason: nil,
            refs: []
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: nil,
            latestUIReview: nil,
            governanceNowMs: 100
        )

        #expect(presentation.scopeRestrictionText == "这个项目当前只开放“项目摘要”，最近对话视图暂未开放。")
        #expect(presentation.projectId == "project-beta")
        #expect(presentation.latestUIReview == nil)
        let recentSection = try #require(presentation.sections.first(where: { $0.id == "recent-empty" }))
        #expect(recentSection.lines.map(\.text) == ["当前只展示项目摘要；切到“摘要+最近对话”后可查看最近对话。"])
        #expect(recentSection.lines.map(\.tone) == [.secondary])
    }

    @Test
    func mapHighlightsSpecGapInSpecCapsuleSection() throws {
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 20,
            projectId: "project-gap",
            projectName: "Project Gap",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsuleOnly,
            grantedScope: .capsuleOnly,
            capsule: SupervisorPortfolioProjectCard(
                projectId: "project-gap",
                displayName: "Project Gap",
                projectState: .blocked,
                runtimeState: "blocked",
                currentAction: "Clarify the formal spec",
                topBlocker: "formal_spec_missing",
                nextStep: "补齐 formal spec 字段",
                memoryFreshness: .fresh,
                updatedAt: 19,
                recentMessageCount: 0,
                missingSpecFields: [.mvpDefinition, .nonGoals, .approvedTechStack, .milestones]
            ),
            specCapsule: SupervisorProjectSpecCapsuleBuilder.build(
                projectId: "project-gap",
                goal: "Ship a governed supervisor workflow",
                mvpDefinition: "",
                nonGoals: [],
                approvedTechStack: [],
                milestoneMap: []
            ),
            decisionRails: nil,
            latestReview: nil,
            latestGuidance: nil,
            pendingAckGuidance: nil,
            followUpRhythmSummary: nil,
            workflow: nil,
            recentMessages: [],
            denyReason: nil,
            refs: []
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: nil,
            latestUIReview: nil,
            governanceNowMs: 100
        )

        let specSection = try #require(presentation.sections.first(where: { $0.id == "spec-capsule" }))
        #expect(specSection.lines.map(\.text) == [
            "目标：Ship a governed supervisor workflow",
            "MVP：（缺失）",
            "非目标：（缺失）",
            "技术栈：（缺失）",
            "里程碑：（缺失）",
            "规格缺口：MVP 定义 / 非目标 / 技术栈 / 里程碑"
        ])
        #expect(specSection.lines.map(\.tone) == [
            .primary,
            .warning,
            .warning,
            .warning,
            .warning,
            .warning
        ])
    }

    @Test
    func mapHighlightsDecisionPrecedenceAndWeakOnlyBackgroundGuard() throws {
        let approvedDecision = SupervisorDecisionTrackBuilder.build(
            decisionId: "dec-stack",
            projectId: "project-rails",
            category: .techStack,
            status: .approved,
            statement: "Use SwiftUI + Hub canonical memory.",
            source: "user",
            reversible: true,
            approvalRequired: false,
            approvedBy: "user",
            auditRef: "audit-dec-stack",
            createdAtMs: 100
        )
        let shadowedBackground = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref-stack",
            projectId: "project-rails",
            domain: .techStack,
            strength: .strong,
            statement: "Prefer cross-platform web.",
            createdAtMs: 120
        )
        let preferredBackground = SupervisorBackgroundPreferenceTrackBuilder.build(
            noteId: "pref-ux",
            projectId: "project-rails",
            domain: .uxStyle,
            strength: .medium,
            statement: "Prefer compact operational cards.",
            createdAtMs: 140
        )
        let rails = SupervisorDecisionRailResolver.resolve(
            projectId: "project-rails",
            decisions: [approvedDecision],
            backgroundNotes: [shadowedBackground, preferredBackground]
        )
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 30,
            projectId: "project-rails",
            projectName: "Project Rails",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsuleOnly,
            grantedScope: .capsuleOnly,
            capsule: nil,
            specCapsule: nil,
            decisionRails: rails,
            latestReview: nil,
            latestGuidance: nil,
            pendingAckGuidance: nil,
            followUpRhythmSummary: nil,
            workflow: nil,
            recentMessages: [],
            denyReason: nil,
            refs: []
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: nil,
            latestUIReview: nil,
            governanceNowMs: 100
        )

        let decisionSection = try #require(presentation.sections.first(where: { $0.id == "decision-rails" }))
        #expect(decisionSection.lines.map(\.text) == [
            "已批准技术栈：Use SwiftUI + Hub canonical memory.",
            "决策优先·技术栈：正式决策覆盖1 条背景偏好",
            "被覆盖背景·技术栈 [强]：Prefer cross-platform web.",
            "背景偏好·界面风格 [中]：Prefer compact operational cards.",
            "保护规则·界面风格：在正式决策前仅作弱约束"
        ])
        #expect(decisionSection.lines.map(\.tone) == [
            .primary,
            .warning,
            .secondary,
            .secondary,
            .warning
        ])
    }

    @Test
    func mapShowsStructuredDecisionAssistSection() throws {
        let assist = SupervisorDecisionBlockerAssistEngine.build(
            context: SupervisorDecisionBlockerContext(
                projectId: "project-proposal",
                blockerId: "blk-test-stack",
                category: .testStack,
                reversible: true,
                riskLevel: .low,
                timeoutEscalationAfterMs: 900_000
            ),
            nowMs: 1_778_300_000_000
        )
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 40,
            projectId: "project-proposal",
            projectName: "Project Proposal",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsuleOnly,
            grantedScope: .capsuleOnly,
            capsule: SupervisorPortfolioProjectCard(
                projectId: "project-proposal",
                displayName: "Project Proposal",
                projectState: .blocked,
                runtimeState: "blocked",
                currentAction: "默认建议待确认：swift_testing_contract_default（proposal_pending）",
                topBlocker: "default_proposal_pending:test_stack=swift_testing_contract_default",
                nextStep: "审阅待定默认建议：swift_testing_contract_default，确认后再走 governed adoption",
                memoryFreshness: .fresh,
                updatedAt: 39,
                recentMessageCount: 1,
                decisionAssist: assist
            ),
            specCapsule: nil,
            decisionRails: nil,
            latestReview: nil,
            latestGuidance: nil,
            pendingAckGuidance: nil,
            followUpRhythmSummary: nil,
            workflow: nil,
            recentMessages: [],
            denyReason: nil,
            refs: []
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: nil,
            latestUIReview: nil,
            governanceNowMs: 100
        )

        let assistSection = try #require(presentation.sections.first(where: { $0.id == "decision-assist" }))
        #expect(assistSection.lines.map(\.text) == [
            "proposal test_stack: swift_testing_contract_default",
            "mode: proposal_with_timeout_escalation",
            "status: proposal_pending",
            "escalate after: 15m",
            "why: Generated reversible low-risk proposal with timeout escalation; the recommendation remains pending until an explicit governed adoption step occurs.",
            "guard: remains pending until governed adoption"
        ])
        #expect(assistSection.lines.map(\.tone) == [
            .primary,
            .secondary,
            .secondary,
            .secondary,
            .secondary,
            .warning
        ])
    }

    @Test
    func mapShowsStructuredMemoryCompactionSection() throws {
        let rollup = SupervisorMemoryCompactionRollup(
            schemaVersion: SupervisorMemoryCompactionRollup.schemaVersion,
            projectId: "project-archive",
            periodStartMs: 10,
            periodEndMs: 40,
            rollupSummary: "rolled_up=1; archived=2; kept_decisions=1; kept_milestones=1; traceable_refs=2; archive_candidate=true",
            rolledUpNodeIds: ["obs-old"],
            archivedNodeIds: ["recent-0", "recent-1"],
            keptDecisionIds: ["dec_release_001"],
            keptMilestoneIds: ["mvp"],
            keptAuditRefs: ["audit_release_scope_001"],
            keptReleaseGateRefs: ["build/reports/xt_w3_33_release_gate_runtime_evidence.v1.json"],
            archivedRefs: [
                "audit_release_scope_001",
                "build/reports/xt_w3_33_release_gate_runtime_evidence.v1.json"
            ],
            archiveCandidate: true,
            policyReasons: ["completed_project_is_archive_candidate"],
            decisionNodeLoss: 0,
            updatedAtMs: 40
        )
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 40,
            projectId: "project-archive",
            projectName: "Project Archive",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsuleOnly,
            grantedScope: .capsuleOnly,
            capsule: SupervisorPortfolioProjectCard(
                projectId: "project-archive",
                displayName: "Project Archive",
                projectState: .completed,
                runtimeState: "completed",
                currentAction: "记忆收口：rolled_up=1; archived=2; kept_decisions=1",
                topBlocker: "",
                nextStep: "审阅 archive rollup：关键 decision/milestone/gate refs 已保留，可按 archive 模式收口",
                memoryFreshness: .fresh,
                updatedAt: 39,
                recentMessageCount: 0
            ),
            specCapsule: nil,
            decisionRails: nil,
            latestReview: nil,
            latestGuidance: nil,
            pendingAckGuidance: nil,
            followUpRhythmSummary: nil,
            memoryCompactionRollup: rollup,
            workflow: nil,
            recentMessages: [],
            denyReason: nil,
            refs: []
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: nil,
            latestUIReview: nil,
            governanceNowMs: 100
        )

        let compactionSection = try #require(presentation.sections.first(where: { $0.id == "memory-compaction" }))
        #expect(compactionSection.title == "记忆收口")
        #expect(compactionSection.lines.map(\.text) == [
            "summary: rolled_up=1; archived=2; kept_decisions=1; kept_milestones=1; traceable_refs=2; archive_candidate=true",
            "mode: archive candidate",
            "rolled up: obs-old",
            "archived: recent-0, recent-1",
            "kept decisions: dec_release_001",
            "kept milestones: mvp",
            "release refs: build/reports/xt_w3_33_release_gate_runtime_evidence.v1.json",
            "audit refs: audit_release_scope_001"
        ])
        #expect(compactionSection.lines.map(\.tone) == [
            .primary,
            .warning,
            .secondary,
            .secondary,
            .secondary,
            .secondary,
            .secondary,
            .secondary
        ])
    }

    @Test
    func mapBuildsDeniedSection() throws {
        let snapshot = SupervisorProjectDrillDownSnapshot.denied(
            projectId: "project-gamma",
            projectName: "Project Gamma",
            status: .deniedScope,
            requestedScope: .capsulePlusRecent,
            denyReason: "scope-safe rules denied recent access",
            updatedAt: 0
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: "",
            latestUIReview: nil,
            governanceNowMs: 0
        )

        #expect(presentation.sections.count == 1)
        #expect(presentation.projectId == "project-gamma")
        #expect(presentation.sections[0].title == nil)
        #expect(presentation.sections[0].lines.map(\.text) == ["scope-safe rules denied recent access"])
        #expect(presentation.sections[0].lines.map(\.tone) == [.warning])
        #expect(presentation.latestUIReview == nil)
    }

    @Test
    func mapHumanizesStructuredGuidanceFallbackWhenContractResolutionFails() throws {
        let pollutedGuidance = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-polluted",
            reviewId: "review-polluted",
            projectId: "project-delta",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: "收到，我会按《Release Runtime》这条指导继续推进：verdict=watchsummary=当前没有待处理的 Hub 授权。effective_supervisor_tier=s3_strategic_coacheffective_work_order_depth=execution_readywork_order_ref=plan:plan-release-runtime-v1",
            ackStatus: .pending,
            ackRequired: true,
            effectiveSupervisorTier: .s3StrategicCoach,
            effectiveWorkOrderDepth: .executionReady,
            workOrderRef: "plan:plan-release-runtime-v1",
            ackNote: "",
            injectedAtMs: 500,
            ackUpdatedAtMs: 500,
            expiresAtMs: 0,
            retryAtMs: 0,
            retryCount: 0,
            maxRetryCount: 0,
            auditRef: "audit-guidance-polluted"
        )
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 500,
            projectId: "project-delta",
            projectName: "Project Delta",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsuleOnly,
            grantedScope: .capsuleOnly,
            capsule: nil,
            specCapsule: nil,
            decisionRails: nil,
            latestReview: nil,
            latestGuidance: pollutedGuidance,
            pendingAckGuidance: pollutedGuidance,
            followUpRhythmSummary: nil,
            memoryCompactionRollup: nil,
            workflow: nil,
            recentMessages: [],
            denyReason: nil,
            refs: []
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: nil,
            latestUIReview: nil,
            governanceNowMs: 1_000
        )

        let governanceSection = try #require(presentation.sections.first(where: { $0.id == "governance" }))
        #expect(governanceSection.lines.contains(where: { $0.text.contains("当前没有待处理的 Hub 授权。") }))
        #expect(!governanceSection.lines.contains(where: { $0.text.contains("verdict=") }))
        #expect(!governanceSection.lines.contains(where: { $0.text.contains("effective_supervisor_tier") }))
    }

    @Test
    func mapResolvesWrappedStructuredGuidanceContractBeforeFallback() throws {
        let wrappedGuidance = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-wrapped-contract",
            reviewId: "review-wrapped-contract",
            projectId: "project-epsilon",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: """
收到，我会按《Release Runtime》这条指导继续推进：summary=当前没有待处理的 Hub 授权。
contract_kind=grant_resolution
primary_blocker=grant_required
next_safe_action=open_hub_grants
recommended_actions=Open Hub grant approval for this project | Retry the governed step after grant approval
""",
            ackStatus: .pending,
            ackRequired: true,
            effectiveSupervisorTier: .s3StrategicCoach,
            effectiveWorkOrderDepth: .executionReady,
            workOrderRef: "plan:grant-wrapped-1",
            ackNote: "",
            injectedAtMs: 500,
            ackUpdatedAtMs: 500,
            expiresAtMs: 0,
            retryAtMs: 0,
            retryCount: 0,
            maxRetryCount: 0,
            auditRef: "audit-guidance-wrapped-contract"
        )
        let snapshot = SupervisorProjectDrillDownSnapshot(
            updatedAt: 500,
            projectId: "project-epsilon",
            projectName: "Project Epsilon",
            openedReason: "explicit_portfolio_drilldown",
            status: .allowed,
            requestedScope: .capsuleOnly,
            grantedScope: .capsuleOnly,
            capsule: nil,
            specCapsule: nil,
            decisionRails: nil,
            latestReview: nil,
            latestGuidance: wrappedGuidance,
            pendingAckGuidance: wrappedGuidance,
            followUpRhythmSummary: nil,
            memoryCompactionRollup: nil,
            workflow: nil,
            recentMessages: [],
            denyReason: nil,
            refs: []
        )

        let presentation = SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: [.capsuleOnly],
            selectedScope: .capsuleOnly,
            governanceTags: [],
            runtimeSummary: nil,
            latestUIReview: nil,
            governanceNowMs: 1_000
        )

        let governanceSection = try #require(presentation.sections.first(where: { $0.id == "governance" }))
        #expect(governanceSection.lines.contains(where: { $0.text == "指导合同：授权处理" }))
        #expect(governanceSection.lines.contains(where: { $0.text == "摘要：当前没有待处理的 Hub 授权。" }))
        #expect(governanceSection.lines.contains(where: { $0.text == "阻塞：Hub 授权未完成（grant_required）" }))
        #expect(governanceSection.lines.contains(where: { $0.text == "下一个安全动作：打开 Hub 授权面板" }))
        #expect(governanceSection.lines.contains(where: {
            $0.text == "建议动作：Open Hub grant approval for this project | Retry the governed step after grant approval"
        }))
        #expect(!governanceSection.lines.contains(where: { $0.text.contains("收到，我会按《Release Runtime》这条指导继续推进") }))
    }
}
