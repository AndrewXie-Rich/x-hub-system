import Testing
@testable import XTerminal
import Foundation

struct SupervisorSkillActivityPresentationTests {

    @Test
    func awaitingAuthorizationBodyDistinguishesHubGrantAndLocalApproval() {
        let hubGrantRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-hub-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: ["url": .string("https://example.com")],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-1",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-hub"
        )
        let localApprovalRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-local-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-2",
            skillId: "code-review",
            toolName: ToolName.run_command.rawValue,
            status: .awaitingAuthorization,
            payload: ["command": .string("swift test")],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "local_approval_required",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-local"
        )

        let hubGrantItem = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: hubGrantRecord,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-hub-1",
                tool: .deviceBrowserControl,
                args: ["url": .string("https://example.com")]
            ),
            toolSummary: "https://example.com",
            actionURL: "x-terminal://project/project-alpha"
        )
        let localApprovalItem = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: localApprovalRecord,
            tool: .run_command,
            toolCall: ToolCall(
                id: "skill-local-1",
                tool: .run_command,
                args: ["command": .string("swift test")]
            ),
            toolSummary: "swift test",
            actionURL: "x-terminal://project/project-alpha"
        )

        let hubBody = SupervisorSkillActivityPresentation.body(for: hubGrantItem)
        let localBody = SupervisorSkillActivityPresentation.body(for: localApprovalItem)

        #expect(hubBody.contains("Hub 授权"))
        #expect(hubBody.contains("联网访问"))
        #expect(localBody.contains("本地审批"))
        #expect(!SupervisorSkillActivityPresentation.isAwaitingLocalApproval(hubGrantItem))
        #expect(SupervisorSkillActivityPresentation.isAwaitingLocalApproval(localApprovalItem))
    }

    @Test
    func awaitingAuthorizationTitleUsesHumanCapabilityLabel() {
        let hubGrantRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-hub-title-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-title-1",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-title"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: hubGrantRecord,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "https://example.com",
            actionURL: nil
        )

        let title = SupervisorSkillActivityPresentation.title(for: item)

        #expect(title.contains("等待 Hub 授权"))
        #expect(title.contains("联网访问"))
    }

    @Test
    func awaitingAuthorizationReadinessOverridesMissingCapabilityForHubGrantUI() {
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "agent-browser",
            packageSHA256: String(repeating: "g", count: 64),
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.navigate"],
            capabilityFamilies: ["browser.interact"],
            capabilityProfiles: ["browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            runnableNow: false,
            denyCode: "grant_required",
            reasonCode: "grant floor privileged requires hub grant",
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            requiredGrantCapabilities: ["browser.interact"],
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(
                XTSkillExecutionReadinessState.grantRequired.rawValue
            ),
            installHint: "",
            unblockActions: ["request_hub_grant"],
            auditRef: "audit-title-grant-readiness",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-title-grant-readiness",
            grantSnapshotRef: ""
        )
        let hubGrantRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-hub-title-2",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            readiness: readiness,
            requiredCapability: nil,
            grantRequestId: "grant-title-2",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-title-2"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: hubGrantRecord,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "https://example.com",
            actionURL: nil
        )

        #expect(SupervisorSkillActivityPresentation.title(for: item) == "等待 Hub 授权")
        #expect(SupervisorSkillActivityPresentation.iconName(for: item) == "lock.shield.fill")
        #expect(SupervisorSkillActivityPresentation.actionButtonTitle(for: item) == "打开授权")
        #expect(SupervisorSkillActivityPresentation.body(for: item).contains("Hub 授权"))
        #expect(!SupervisorSkillActivityPresentation.isAwaitingLocalApproval(item))
    }

    @Test
    func persistedDeltaAndReadinessSurfaceInBodyDiagnosticsAndFullRecord() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_profile_harmony_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let requestId = "skill-profile-h-1"
        let resultEvidenceRef = SupervisorSkillResultEvidenceStore.resultEvidenceRef(requestId: requestId)
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            projectName: "Project Alpha",
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["web.navigate", "web.dom.write"],
            deltaCapabilityFamilies: ["web.navigate", "web.dom.write"],
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requestedTTLSeconds: 900,
            reason: "waiting for local governed approval",
            summary: "当前可直接运行：observe_only；本次请求：browser_operator；新增放开：browser_operator；grant=none；approval=local_approval",
            disposition: "pending",
            auditRef: "audit-delta-h-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.operate"],
            capabilityFamilies: ["web.navigate", "web.dom.write"],
            capabilityProfiles: ["browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            runnableNow: false,
            denyCode: "local_approval_required",
            reasonCode: "approval floor local_approval requires local confirmation",
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredGrantCapabilities: [],
            requiredRuntimeSurfaces: ["device_browser_runtime"],
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(XTSkillExecutionReadinessState.localApprovalRequired.rawValue),
            installHint: "",
            unblockActions: ["approve_local_skill_request"],
            auditRef: "audit-readiness-h-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-h-1",
            grantSnapshotRef: ""
        )
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            jobId: "job-h-1",
            planId: "plan-h-1",
            stepId: "step-h-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "browser.open converged to guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: ["action": .string("open"), "url": .string("https://example.com")],
            currentOwner: "supervisor",
            resultSummary: "waiting for local governed approval",
            denyCode: "local_approval_required",
            resultEvidenceRef: resultEvidenceRef,
            profileDeltaRef: "\(resultEvidenceRef)#profile_delta",
            deltaApproval: deltaApproval,
            readinessRef: "\(resultEvidenceRef)#readiness",
            readiness: readiness,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-skill-h-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: requestId,
                tool: .deviceBrowserControl,
                args: ["action": .string("open"), "url": .string("https://example.com")]
            ),
            toolSummary: "https://example.com",
            actionURL: nil
        )

        let body = SupervisorSkillActivityPresentation.body(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(body.contains("能力增量："))
        #expect(body.contains("browser_operator"))
        #expect(body.contains("执行就绪：等待本地审批"))
        #expect(body.contains("运行面：设备浏览器运行面（device_browser_runtime）"))
        #expect(body.contains("解阻动作：批准本地技能请求（approve_local_skill_request）"))
        #expect(diagnostics.contains("profile_delta_ref=\(resultEvidenceRef)#profile_delta"))
        #expect(diagnostics.contains("approval_summary=当前可直接运行：observe_only"))
        #expect(diagnostics.contains("requested_profiles=browser_operator"))
        #expect(diagnostics.contains("execution_readiness=local_approval_required"))
        #expect(diagnostics.contains("unblock_actions=approve_local_skill_request"))

        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)
        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: item.toolCall,
            rawOutput: nil,
            triggerSource: "user_turn",
            ctx: ctx
        )

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: requestId
            )
        )

        #expect(fullRecord.approvalFields.contains(where: { $0.label == "profile_delta_ref" && $0.value == "\(resultEvidenceRef)#profile_delta" }))
        #expect(fullRecord.approvalFields.contains(where: { $0.label == "approval_summary" && $0.value.contains("browser_operator") }))
        #expect(fullRecord.approvalFields.contains(where: { $0.label == "requested_profiles" && $0.value == "browser_operator" }))
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "intent_families" && $0.value == "browser.operate" }))
        #expect(fullRecord.requestMetadata.contains(where: {
            $0.label == "capability_families" && $0.value == "web.navigate, web.dom.write"
        }))
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "capability_profiles" && $0.value == "browser_operator" }))
        #expect(fullRecord.resultFields.contains(where: { $0.label == "readiness_ref" && $0.value == "\(resultEvidenceRef)#readiness" }))
        #expect(fullRecord.resultFields.contains(where: { $0.label == "execution_readiness" && $0.value == XTSkillExecutionReadinessState.localApprovalRequired.rawValue }))
        #expect(fullRecord.resultFields.contains(where: { $0.label == "unblock_actions" && $0.value == "approve_local_skill_request" }))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("approval_summary=当前可直接运行：observe_only"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("execution_readiness=local_approval_required"))
    }

    @Test
    func governedHelpersBridgeSupervisorActivityIntoPendingApprovalContract() {
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: "skill-governed-summary-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only", "browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["repo.read", "browser.interact"],
            deltaCapabilityFamilies: ["browser.interact"],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requestedTTLSeconds: 900,
            reason: "waiting for local governed approval",
            summary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=local_approval",
            disposition: "pending",
            auditRef: "audit-governed-summary-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: String(repeating: "d", count: 64),
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.navigate", "research.lookup"],
            capabilityFamilies: ["repo.read", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            runnableNow: false,
            denyCode: "local_approval_required",
            reasonCode: "approval floor local_approval requires local confirmation",
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredGrantCapabilities: [],
            requiredRuntimeSurfaces: ["device_browser_runtime"],
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(XTSkillExecutionReadinessState.localApprovalRequired.rawValue),
            installHint: "",
            unblockActions: ["approve_local_skill_request"],
            auditRef: "audit-governed-readiness-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-governed-summary-1",
            grantSnapshotRef: ""
        )
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-governed-summary-1",
            projectId: "project-alpha",
            jobId: "job-governed-1",
            planId: "plan-governed-1",
            stepId: "step-governed-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [
                "action": .string("open"),
                "url": .string("https://example.com/dashboard")
            ],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "local_approval_required",
            resultEvidenceRef: nil,
            deltaApproval: deltaApproval,
            readiness: readiness,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            hubStateDirPath: "/tmp/xhub-governed-state",
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-governed-summary-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-governed-summary-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("open_url"),
                    "url": .string("https://example.com/dashboard")
                ]
            ),
            toolSummary: "https://example.com/dashboard",
            actionURL: nil
        )

        let shortSummary = SupervisorSkillActivityPresentation.governedShortSummary(for: item)
        let detailLines = SupervisorSkillActivityPresentation.governedDetailLines(for: item)
        let preferredCardSummary = SupervisorSkillActivityPresentation.preferredCardSummary(for: item)

        #expect(shortSummary == "browser.open -> guarded-automation · 等待本地审批")
        #expect(preferredCardSummary == "browser.open -> guarded-automation · 等待本地审批")
        #expect(detailLines.contains("生效技能：guarded-automation"))
        #expect(detailLines.contains("请求技能：browser.open"))
        #expect(detailLines.contains("执行就绪：等待本地审批"))
        #expect(detailLines.contains("治理闸门：高权限 grant · 本地审批"))
        #expect(detailLines.contains(where: {
            $0.hasPrefix("意图族：") && $0.contains("browser.navigate") && $0.contains("research.lookup")
        }))
        #expect(detailLines.contains(where: {
            $0.hasPrefix("能力族：") && $0.contains("repo.read") && $0.contains("browser.interact")
        }))
        #expect(detailLines.contains("能力档位：observe_only、browser_operator"))
        #expect(detailLines.contains("恢复上下文：已保存 Hub 执行上下文，可在批准后继续恢复执行。"))
    }

    @Test
    func preferredCardSummaryFallsBackToRoutingSummaryWithoutGovernedGateContext() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-card-summary-1",
            projectId: "project-alpha",
            jobId: "job-card-1",
            planId: "plan-card-1",
            stepId: "step-card-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .running,
            payload: [
                "action": .string("open"),
                "url": .string("https://example.com/login")
            ],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-card-summary-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-card-summary-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("open"),
                    "url": .string("https://example.com/login")
                ]
            ),
            toolSummary: "https://example.com/login",
            actionURL: nil
        )

        let preferredCardSummary = SupervisorSkillActivityPresentation.preferredCardSummary(for: item)
        let governedCardLines = SupervisorSkillActivityPresentation.cardGovernedDetailLines(for: item)

        #expect(preferredCardSummary == "browser.open -> guarded-automation · action=open")
        #expect(governedCardLines.isEmpty)
    }

    @Test
    func cardGovernedDetailLinesPrioritizeReadinessAndGateForNonBlockingUpdates() {
        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: "skill-card-governed-lines-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only", "browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["repo.read", "browser.interact"],
            deltaCapabilityFamilies: ["browser.interact"],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requestedTTLSeconds: 900,
            reason: "running with governed context",
            summary: "current run continues under governed compatibility",
            disposition: "active",
            auditRef: "audit-card-governed-lines-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "project-alpha",
            skillId: "guarded-automation",
            packageSHA256: String(repeating: "e", count: 64),
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.navigate"],
            capabilityFamilies: ["repo.read", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.degraded.rawValue,
            runnableNow: true,
            denyCode: "",
            reasonCode: "running with degraded runtime coverage",
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredGrantCapabilities: [],
            requiredRuntimeSurfaces: ["device_browser_runtime"],
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(XTSkillExecutionReadinessState.degraded.rawValue),
            installHint: "",
            unblockActions: [],
            auditRef: "audit-card-governed-readiness-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-card-governed-lines-1",
            grantSnapshotRef: ""
        )
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-card-governed-lines-1",
            projectId: "project-alpha",
            jobId: "job-card-lines-1",
            planId: "plan-card-lines-1",
            stepId: "step-card-lines-1",
            skillId: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .running,
            payload: ["action": .string("open")],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "",
            resultEvidenceRef: nil,
            deltaApproval: deltaApproval,
            readiness: readiness,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            hubStateDirPath: "/tmp/xhub-running-state",
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-card-governed-lines-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "https://example.com/dashboard",
            actionURL: nil
        )

        let governedCardLines = SupervisorSkillActivityPresentation.cardGovernedDetailLines(for: item)

        #expect(governedCardLines == [
            "执行就绪：降级可用",
            "治理闸门：高权限 grant · 本地审批"
        ])
    }

    @Test
    func workflowAndGovernanceSummariesAreStructuredAndActionLabelTracksState() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-governance-1",
            projectId: "project-alpha",
            jobId: "job-7",
            planId: "plan-9",
            stepId: "step-3",
            skillId: "self-improving-agent",
            toolName: ToolName.run_command.rawValue,
            status: .completed,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "Applied the next guarded iteration.",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-governance-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .run_command,
            toolCall: nil,
            toolSummary: "swift test --filter smoke",
            actionURL: "x-terminal://project/project-alpha",
            governance: .init(
                latestReviewId: "review-9",
                latestReviewVerdict: .betterPathFound,
                latestReviewLevel: .r2Strategic,
                configuredExecutionTier: .a2RepoAuto,
                effectiveExecutionTier: .a3DeliverAuto,
                configuredSupervisorTier: .s2PeriodicReview,
                effectiveSupervisorTier: .s3StrategicCoach,
                reviewPolicyMode: .hybrid,
                progressHeartbeatSeconds: 300,
                reviewPulseSeconds: 600,
                brainstormReviewSeconds: 1_800,
                compatSource: .explicitDualDial,
                effectiveWorkOrderDepth: .executionReady,
                followUpRhythmSummary: "cadence=active · blocker cooldown≈180s",
                workOrderRef: "wo-9",
                latestGuidanceId: "guidance-9",
                latestGuidanceDeliveryMode: .priorityInsert,
                latestGuidanceSummary: "先核对最新浏览器证据，再推进下一步。",
                pendingGuidanceId: "guidance-9",
                pendingGuidanceAckStatus: .pending,
                pendingGuidanceRequired: true,
                pendingGuidanceSummary: "先核对最新浏览器证据，再推进下一步。"
            )
        )
        let approvalRecord = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-governance-2",
            projectId: "project-alpha",
            jobId: "",
            planId: "",
            stepId: "",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .awaitingAuthorization,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-2",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-governance-2"
        )
        let approvalItem = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: approvalRecord,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "",
            actionURL: "x-terminal://supervisor"
        )

        let workflowLine = SupervisorSkillActivityPresentation.workflowLine(for: item)
        let blockedSummaryLine = SupervisorSkillActivityPresentation.blockedSummaryLine(for: approvalItem)
        let governanceTruthLine = SupervisorSkillActivityPresentation.governanceTruthLine(for: item)
        let displayGovernanceTruthLine = SupervisorSkillActivityPresentation.displayGovernanceTruthLine(for: item)
        let governanceLine = SupervisorSkillActivityPresentation.governanceLine(for: item)
        let followUpLine = SupervisorSkillActivityPresentation.followUpRhythmLine(for: item)
        let guidanceLine = SupervisorSkillActivityPresentation.pendingGuidanceLine(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(workflowLine?.contains("job=job-7") == true)
        #expect(workflowLine?.contains("plan=plan-9") == true)
        #expect(blockedSummaryLine?.contains("Hub 授权") == true)
        #expect(governanceTruthLine?.contains("A3/S3") == true)
        #expect(governanceTruthLine?.contains("审查 Hybrid") == true)
        #expect(displayGovernanceTruthLine?.contains("审查 混合") == true)
        #expect(governanceTruthLine?.contains("心跳 5m") == true)
        #expect(governanceLine?.contains("发现更优路径") == true)
        #expect(governanceLine?.contains("R2 战略") == true)
        #expect(governanceLine?.contains("work_order=wo-9") == true)
        #expect(followUpLine?.contains("节奏=活跃") == true)
        #expect(followUpLine?.contains("阻塞冷却≈180秒") == true)
        #expect(guidanceLine?.contains("待确认") == true)
        #expect(guidanceLine?.contains("必答") == true)
        #expect(guidanceLine?.contains("优先插入") == true)
        #expect(guidanceLine?.contains("先核对最新浏览器证据，再推进下一步。") == true)
        #expect(guidanceLine?.contains("summary=") == false)
        #expect(diagnostics.contains("governance_truth=治理真相：预设 A2/S2 · 当前生效 A3/S3"))
        #expect(diagnostics.contains("guidance_summary=先核对最新浏览器证据，再推进下一步。"))
        #expect(SupervisorSkillActivityPresentation.actionButtonTitle(for: item) == "打开项目")
        #expect(SupervisorSkillActivityPresentation.actionButtonTitle(for: approvalItem) == "打开授权")
    }

    @Test
    func recentActivityPrefersPersistedGovernanceEvidence() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-persisted-feed-1",
            projectId: "project-alpha",
            jobId: "job-8",
            planId: "plan-8",
            stepId: "step-8",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "derived summary should not win",
            denyCode: "governance_capability_denied",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-persisted-feed-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: nil,
            governanceEvidence: .init(
                policyReason: "runtime_surface_effective=guided",
                governanceReason: "persisted supervisor governance reason",
                blockedSummary: "persisted supervisor blocked summary",
                governanceTruth: "persisted supervisor governance truth",
                repairAction: "persisted supervisor repair action"
            ),
            governance: .init(
                configuredExecutionTier: .a1Plan,
                effectiveExecutionTier: .a1Plan,
                configuredSupervisorTier: .s2PeriodicReview,
                effectiveSupervisorTier: .s2PeriodicReview,
                reviewPolicyMode: .periodic,
                progressHeartbeatSeconds: 900,
                reviewPulseSeconds: 1800
            )
        )

        #expect(SupervisorSkillActivityPresentation.governanceReasonText(for: item) == "persisted supervisor governance reason")
        #expect(SupervisorSkillActivityPresentation.blockedSummaryText(for: item) == "persisted supervisor blocked summary")
        #expect(SupervisorSkillActivityPresentation.governanceTruthLine(for: item) == "persisted supervisor governance truth")
        #expect(SupervisorSkillActivityPresentation.body(for: item).contains("persisted supervisor blocked summary"))
        #expect(SupervisorSkillActivityPresentation.body(for: item).contains("persisted supervisor governance truth"))
        #expect(SupervisorSkillActivityPresentation.diagnostics(for: item).contains("repair_action=persisted supervisor repair action"))
        #expect(item.policyReason == "runtime_surface_effective=guided")
    }

    @Test
    func guidanceContractLinesExposeBlockerAndNextSafeAction() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-contract-1",
            projectId: "project-alpha",
            jobId: "job-11",
            planId: "plan-11",
            stepId: "step-11",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "Blocked pending governance resolution.",
            denyCode: "grant_required",
            resultEvidenceRef: nil,
            requiredCapability: "web.fetch",
            grantRequestId: "grant-11",
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-contract-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open project dashboard",
            actionURL: nil,
            governance: .init(
                latestReviewId: "review-11",
                latestReviewVerdict: .watch,
                latestReviewLevel: .r2Strategic,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                followUpRhythmSummary: "cadence=active",
                workOrderRef: "wo-11",
                latestGuidanceId: "guidance-11",
                latestGuidanceDeliveryMode: .priorityInsert,
                pendingGuidanceId: "guidance-11",
                pendingGuidanceAckStatus: .pending,
                pendingGuidanceRequired: true,
                guidanceContract: SupervisorGuidanceContractSummary(
                    kind: .grantResolution,
                    trigger: "Grant Resolution",
                    reviewLevel: "R2 Strategic",
                    verdict: "Watch",
                    summary: "Hub grant is still pending.",
                    primaryBlocker: "Hub grant pending",
                    currentState: "device action paused",
                    nextStep: "approve grant",
                    nextSafeAction: "open_hub_grants",
                    recommendedActions: ["Approve the pending hub grant", "Retry the blocked skill"],
                    workOrderRef: "wo-11",
                    effectiveSupervisorTier: "S3 Strategic Coach",
                    effectiveWorkOrderDepth: "Execution Ready"
                )
            )
        )

        let contractLine = SupervisorSkillActivityPresentation.guidanceContractLine(for: item)
        let nextSafeActionLine = SupervisorSkillActivityPresentation.guidanceNextSafeActionLine(for: item)
        let blockedSummaryLine = SupervisorSkillActivityPresentation.blockedSummaryLine(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(contractLine == "合同： 授权处理 · blocker=Hub grant pending")
        #expect(blockedSummaryLine?.contains("Hub 授权") == true)
        #expect(nextSafeActionLine?.contains("安全下一步： 打开 Hub 授权面板") == true)
        #expect(nextSafeActionLine?.contains("Approve the pending hub grant") == true)
        #expect(diagnostics.contains("guidance_contract=grant_resolution"))
        #expect(diagnostics.contains("primary_blocker=Hub grant pending"))
        #expect(diagnostics.contains("next_safe_action=open_hub_grants"))
        #expect(diagnostics.contains("blocked_summary="))
    }

    @Test
    func uiReviewGuidanceContractLineUsesRepairSummary() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-contract-ui-1",
            projectId: "project-alpha",
            jobId: "job-12",
            planId: "plan-12",
            stepId: "step-12",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "UI repair required before continuing.",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-contract-ui-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "browser snapshot",
            actionURL: nil,
            governance: .init(
                guidanceContract: SupervisorGuidanceContractSummary(
                    kind: .uiReviewRepair,
                    trigger: "",
                    reviewLevel: "",
                    verdict: "",
                    summary: "Primary CTA is missing from the current screen.",
                    primaryBlocker: "",
                    currentState: "",
                    nextStep: "",
                    nextSafeAction: "repair_before_execution",
                    recommendedActions: [],
                    workOrderRef: "wo-ui-1",
                    effectiveSupervisorTier: "S4 Tight Supervision",
                    effectiveWorkOrderDepth: "Execution Ready",
                    uiReviewRepair: .init(
                        instruction: "Fix the CTA before continuing automation.",
                        repairAction: "Expose the primary CTA",
                        repairFocus: "Landing hero actions",
                        nextSafeAction: "repair_before_execution",
                        uiReviewRef: "local://.xterminal/ui_review/reviews/project-alpha-latest.json",
                        uiReviewReviewId: "ui-review-1",
                        uiReviewVerdict: "attention_needed",
                        uiReviewIssueCodes: "critical_action_not_visible",
                        uiReviewSummary: "Primary CTA is missing from the current screen.",
                        skillResultSummary: "Browser snapshot captured."
                    )
                )
            )
        )

        let contractLine = SupervisorSkillActivityPresentation.guidanceContractLine(for: item)
        let nextSafeActionLine = SupervisorSkillActivityPresentation.guidanceNextSafeActionLine(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(contractLine?.contains("合同： UI 审查修复") == true)
        #expect(contractLine?.contains("repair_action=Expose the primary CTA") == true)
        #expect(contractLine?.contains("repair_focus=Landing hero actions") == true)
        #expect(nextSafeActionLine == "安全下一步： 先完成当前修复，再继续执行")
        #expect(diagnostics.contains("guidance_contract=ui_review_repair"))
        #expect(diagnostics.contains("repair_action=Expose the primary CTA"))
        #expect(diagnostics.contains("repair_focus=Landing hero actions"))
    }

    @Test
    func routingLineAndDiagnosticsExposeRequestedWrapperBuiltinResolution() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-routing-1",
            projectId: "project-alpha",
            jobId: "job-8",
            planId: "plan-5",
            stepId: "step-4",
            skillId: "guarded-automation",
            requestedSkillId: "browser.runtime.inspect",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.runtime.inspect converged to preferred builtin guarded-automation · resolved action snapshot",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: [
                "action": .string("snapshot"),
                "url": .string("https://example.com/dashboard")
            ],
            currentOwner: "supervisor",
            resultSummary: "Captured runtime snapshot",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-routing-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-routing-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("snapshot"),
                    "url": .string("https://example.com/dashboard")
                ]
            ),
            toolSummary: "https://example.com/dashboard",
            actionURL: nil
        )

        let routingLine = SupervisorSkillActivityPresentation.routingLine(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(routingLine?.contains("browser.runtime.inspect -> guarded-automation") == true)
        #expect(routingLine?.contains("action=snapshot") == true)
        #expect(diagnostics.contains("requested_skill_id=browser.runtime.inspect"))
        #expect(diagnostics.contains("路由： browser.runtime.inspect -> guarded-automation"))
        #expect(diagnostics.contains("routing_reason_code=preferred_builtin_selected"))
        #expect(diagnostics.contains("routing_explanation=requested entrypoint browser.runtime.inspect converged to preferred builtin guarded-automation"))
    }

    @Test
    func routingNarrativeUsesGovernedBuiltinLanguageWhenPreferredBuiltinSelected() {
        let narrative = SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: "browser.open",
            effectiveSkillId: "guarded-automation",
            payload: ["action": .string("open")],
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
        )

        #expect(narrative == "浏览器入口会先收敛到受治理内建 guarded-automation 再执行")
    }

    @Test
    func routingNarrativeUsesCanonicalizationLanguageWhenAliasNormalized() {
        let narrative = SupervisorSkillActivityPresentation.routingNarrative(
            requestedSkillId: "trusted-automation",
            effectiveSkillId: "guarded-automation",
            routingReasonCode: "requested_alias_normalized",
            routingExplanation: "alias trusted-automation normalized to guarded-automation"
        )

        #expect(narrative == "系统先把 trusted-automation 规范成 guarded-automation")
    }

    @Test
    func routingReasonTextLocalizesKnownReasonCodes() {
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("preferred_builtin_selected")
                == "系统优先切到受治理内建"
        )
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("requested_alias_normalized")
                == "请求技能先归一到标准技能"
        )
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("compatible_builtin_selected")
                == "系统改由兼容内建承接"
        )
        #expect(
            SupervisorSkillActivityPresentation.routingReasonText("requested_skill_routed")
                == "系统把请求路由到兼容技能"
        )
    }

    @Test
    func displayRequestMetadataFieldsLocalizeRoutingFieldsForUserFacingSections() {
        let fields = [
            ProjectSkillRecordField(label: "requested_skill_id", value: "browser.open"),
            ProjectSkillRecordField(label: "skill_id", value: "guarded-automation"),
            ProjectSkillRecordField(label: "intent_families", value: "browser.navigate, research.lookup"),
            ProjectSkillRecordField(label: "capability_families", value: "repo.read, browser.interact"),
            ProjectSkillRecordField(label: "capability_profiles", value: "observe_only, browser_operator"),
            ProjectSkillRecordField(label: "routing_resolution", value: "browser.open -> guarded-automation"),
            ProjectSkillRecordField(label: "routing_reason_code", value: "preferred_builtin_selected"),
            ProjectSkillRecordField(
                label: "routing_explanation",
                value: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
            ),
            ProjectSkillRecordField(label: "tool_name", value: "device.browser.control"),
            ProjectSkillRecordField(label: "latest_status", value: "completed")
        ]

        let localized = SupervisorSkillActivityPresentation.displayRequestMetadataFields(fields)

        #expect(localized.contains(where: { $0.label == "请求技能" && $0.value == "browser.open" }))
        #expect(localized.contains(where: { $0.label == "生效技能" && $0.value == "guarded-automation" }))
        #expect(localized.contains(where: { $0.label == "意图族" && $0.value == "browser.navigate、research.lookup" }))
        #expect(localized.contains(where: { $0.label == "能力族" && $0.value.contains("repo.read") && $0.value.contains("browser.interact") }))
        #expect(localized.contains(where: { $0.label == "能力档位" && $0.value == "observe_only、browser_operator" }))
        #expect(localized.contains(where: { $0.label == "路由" && $0.value == "browser.open -> guarded-automation" }))
        #expect(localized.contains(where: { $0.label == "路由判定" && $0.value == "系统优先切到受治理内建" }))
        #expect(localized.contains(where: {
            $0.label == "路由说明" && $0.value == "浏览器入口会先收敛到受治理内建 guarded-automation 再执行"
        }))
        #expect(localized.contains(where: { $0.label == "工具" && $0.value == "device.browser.control" }))
        #expect(localized.contains(where: { $0.label == "最新状态" && $0.value == "已完成" }))
    }

    @Test
    func displayMetadataFieldsLocalizeCommonSupervisorFieldLabels() {
        let fields = [
            ProjectSkillRecordField(label: "deny_code", value: "local_approval_required"),
            ProjectSkillRecordField(label: "required_capability", value: "web.fetch"),
            ProjectSkillRecordField(label: "execution_readiness", value: "local_approval_required"),
            ProjectSkillRecordField(label: "current_runnable_profiles", value: "observe_only"),
            ProjectSkillRecordField(label: "requested_profiles", value: "observe_only, browser_operator"),
            ProjectSkillRecordField(label: "delta_profiles", value: "browser_operator"),
            ProjectSkillRecordField(label: "current_runnable_capability_families", value: "repo.read"),
            ProjectSkillRecordField(label: "requested_capability_families", value: "repo.read, browser.interact"),
            ProjectSkillRecordField(label: "delta_capability_families", value: "browser.interact"),
            ProjectSkillRecordField(label: "grant_floor", value: "privileged"),
            ProjectSkillRecordField(label: "approval_floor", value: "local_approval"),
            ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
            ProjectSkillRecordField(label: "governance_reason", value: "当前项目 A-Tier 不允许浏览器自动化。"),
            ProjectSkillRecordField(label: "blocked_summary", value: "当前项目 A-Tier 不允许浏览器自动化。"),
            ProjectSkillRecordField(label: "governance_truth", value: "当前生效 A1/S2 · 审查 Periodic。"),
            ProjectSkillRecordField(label: "review_verdict", value: "better_path_found"),
            ProjectSkillRecordField(label: "review_level", value: "R2 Strategic"),
            ProjectSkillRecordField(label: "supervisor_tier", value: "S3 Strategic Coach"),
            ProjectSkillRecordField(label: "work_order_depth", value: "execution_ready"),
            ProjectSkillRecordField(label: "latest_guidance_delivery", value: "priority_insert"),
            ProjectSkillRecordField(label: "pending_guidance_ack", value: "Pending · required"),
            ProjectSkillRecordField(label: "follow_up_rhythm", value: "cadence=active · blocker cooldown≈180s"),
            ProjectSkillRecordField(label: "result_status", value: "completed"),
            ProjectSkillRecordField(label: "result_evidence_ref", value: "local://supervisor_skill_results/skill-1.json"),
            ProjectSkillRecordField(label: "audit_ref", value: "audit-skill-1")
        ]

        let localized = SupervisorSkillActivityPresentation.displayMetadataFields(fields)

        #expect(localized.contains(where: { $0.label == "拒绝原因" && $0.value.contains("本地审批") && $0.value.contains("local_approval_required") }))
        #expect(localized.contains(where: { $0.label == "所需能力" && $0.value == "联网访问（web.fetch）" }))
        #expect(localized.contains(where: { $0.label == "执行就绪" && $0.value == "等待本地审批" }))
        #expect(localized.contains(where: { $0.label == "当前可直接运行档位" && $0.value == "observe_only" }))
        #expect(localized.contains(where: { $0.label == "本次请求档位" && $0.value == "observe_only、browser_operator" }))
        #expect(localized.contains(where: { $0.label == "新增放开档位" && $0.value == "browser_operator" }))
        #expect(localized.contains(where: { $0.label == "当前可直接运行能力族" && $0.value.contains("repo.read") }))
        #expect(localized.contains(where: { $0.label == "本次请求能力族" && $0.value.contains("browser.interact") }))
        #expect(localized.contains(where: { $0.label == "新增放开能力族" && $0.value.contains("browser.interact") }))
        #expect(localized.contains(where: { $0.label == "授权门槛" && $0.value == "高权限 grant" }))
        #expect(localized.contains(where: { $0.label == "审批门槛" && $0.value == "本地审批" }))
        #expect(localized.contains(where: { $0.label == "策略原因" && $0.value == "execution_tier_missing_browser_runtime" }))
        #expect(localized.contains(where: { $0.label == "治理原因" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。" }))
        #expect(localized.contains(where: { $0.label == "阻塞说明" && $0.value == "当前项目 A-Tier 不允许浏览器自动化。" }))
        #expect(localized.contains(where: { $0.label == "治理真相" && $0.value == "当前生效 A1/S2 · 审查 周期。" }))
        #expect(localized.contains(where: { $0.label == "审查结论" && $0.value == "发现更优路径" }))
        #expect(localized.contains(where: { $0.label == "审查层级" && $0.value == "R2 战略" }))
        #expect(localized.contains(where: { $0.label == "Supervisor 层级" && $0.value == "S3 战略教练" }))
        #expect(localized.contains(where: { $0.label == "工单深度" && $0.value == "执行就绪" }))
        #expect(localized.contains(where: { $0.label == "最新指导交付" && $0.value == "优先插入" }))
        #expect(localized.contains(where: { $0.label == "待确认指导状态" && $0.value == "待确认 · 必答" }))
        #expect(localized.contains(where: { $0.label == "跟进节奏" && $0.value == "节奏=活跃 · 阻塞冷却≈180秒" }))
        #expect(localized.contains(where: { $0.label == "结果状态" && $0.value == "已完成" }))
        #expect(localized.contains(where: { $0.label == "结果证据引用" && $0.value == "local://supervisor_skill_results/skill-1.json" }))
        #expect(localized.contains(where: { $0.label == "审计引用" && $0.value == "audit-skill-1" }))
    }

    @Test
    func displayMetadataFieldsUseRequiredCapabilityForGrantRequiredCopy() {
        let fields = [
            ProjectSkillRecordField(label: "deny_code", value: "grant_required"),
            ProjectSkillRecordField(label: "required_capability", value: "web.fetch")
        ]

        let localized = SupervisorSkillActivityPresentation.displayMetadataFields(fields)

        #expect(localized.contains(where: {
            $0.label == "拒绝原因"
                && $0.value.contains("联网访问")
                && $0.value.contains("Hub 授权")
                && $0.value.contains("grant_required")
        }))
        #expect(localized.contains(where: { $0.label == "所需能力" && $0.value == "联网访问（web.fetch）" }))
    }

    @Test
    func displayFullRecordTextUsesLocalizedRoutingSummaryAndKeepsRawRoutingAppendix() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-routing-copy-1",
            projectName: "Project Alpha",
            title: "browser.open -> guarded-automation · action=open",
            latestStatus: "completed",
            latestStatusLabel: "已完成",
            requestMetadata: [
                ProjectSkillRecordField(label: "requested_skill_id", value: "browser.open"),
                ProjectSkillRecordField(label: "skill_id", value: "guarded-automation"),
                ProjectSkillRecordField(label: "routing_resolution", value: "browser.open -> guarded-automation"),
                ProjectSkillRecordField(label: "routing_reason_code", value: "preferred_builtin_selected"),
                ProjectSkillRecordField(
                    label: "routing_explanation",
                    value: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
                )
            ],
            approvalFields: [
                ProjectSkillRecordField(label: "policy_reason", value: "execution_tier_missing_browser_runtime"),
                ProjectSkillRecordField(label: "governance_reason", value: "当前项目 A-Tier 不允许浏览器自动化。")
            ],
            governanceFields: [
                ProjectSkillRecordField(label: "work_order_depth", value: "execution_ready")
            ],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [
                ProjectSkillRecordField(label: "result_status", value: "completed"),
                ProjectSkillRecordField(label: "result_summary", value: "Opened login page")
            ],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [
                ProjectSkillRecordField(label: "result_evidence_ref", value: "local://supervisor_skill_results/skill-routing-copy-1.json")
            ],
            approvalHistory: [],
            timeline: [],
            uiReviewAgentEvidenceFields: [],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil,
            guidanceContract: nil
        )

        let text = SupervisorSkillActivityPresentation.displayFullRecordText(record)

        #expect(text.contains("项目：Project Alpha"))
        #expect(text.contains("请求单号：req-routing-copy-1"))
        #expect(text.contains("最新状态：已完成"))
        #expect(text.contains("请求技能：browser.open"))
        #expect(text.contains("生效技能：guarded-automation"))
        #expect(text.contains("路由判定：系统优先切到受治理内建"))
        #expect(text.contains("路由说明：浏览器入口会先收敛到受治理内建 guarded-automation 再执行"))
        #expect(text.contains("策略原因：execution_tier_missing_browser_runtime"))
        #expect(text.contains("治理原因：当前项目 A-Tier 不允许浏览器自动化。"))
        #expect(text.contains("工单深度：执行就绪"))
        #expect(text.contains("结果状态：已完成"))
        #expect(text.contains("结果摘要：Opened login page"))
        #expect(text.contains("结果证据引用：local://supervisor_skill_results/skill-routing-copy-1.json"))
        #expect(text.contains("== 路由诊断原文 =="))
        #expect(text.contains("routing_reason_code=preferred_builtin_selected"))
        #expect(text.contains("routing_explanation=requested entrypoint browser.open converged to preferred builtin guarded-automation"))
    }

    @Test
    func displayFullRecordTextLocalizesGovernedSupervisorSkillFields() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-governed-copy-1",
            projectName: "Project Alpha",
            title: "browser.open -> guarded-automation",
            latestStatus: "awaiting_authorization",
            latestStatusLabel: "等待审批",
            requestMetadata: [
                ProjectSkillRecordField(label: "requested_skill_id", value: "browser.open"),
                ProjectSkillRecordField(label: "skill_id", value: "guarded-automation"),
                ProjectSkillRecordField(label: "intent_families", value: "browser.navigate, research.lookup"),
                ProjectSkillRecordField(label: "capability_families", value: "repo.read, browser.interact"),
                ProjectSkillRecordField(label: "capability_profiles", value: "observe_only, browser_operator")
            ],
            approvalFields: [
                ProjectSkillRecordField(label: "execution_readiness", value: "local_approval_required"),
                ProjectSkillRecordField(label: "requested_profiles", value: "observe_only, browser_operator"),
                ProjectSkillRecordField(label: "delta_profiles", value: "browser_operator"),
                ProjectSkillRecordField(label: "requested_capability_families", value: "repo.read, browser.interact"),
                ProjectSkillRecordField(label: "grant_floor", value: "privileged"),
                ProjectSkillRecordField(label: "approval_floor", value: "local_approval")
            ],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [
                ProjectSkillRecordField(label: "required_runtime_surfaces", value: "managed_browser_runtime"),
                ProjectSkillRecordField(label: "unblock_actions", value: "request_local_approval")
            ],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [
                ProjectSkillRecordTimelineEntry(
                    id: "approval-governed-1",
                    status: "awaiting_authorization",
                    statusLabel: "等待审批",
                    timestamp: "2026-03-24T10:00:00.000Z",
                    summary: "等待审批",
                    detail: """
                    requested_skill_id=browser.open
                    intent_families=browser.navigate,research.lookup
                    capability_families=repo.read,browser.interact
                    capability_profiles=observe_only,browser_operator
                    execution_readiness=local_approval_required
                    grant_floor=privileged
                    approval_floor=local_approval
                    """,
                    rawJSON: #"{"status":"awaiting_authorization"}"#
                )
            ],
            timeline: [],
            uiReviewAgentEvidenceFields: [],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil,
            guidanceContract: nil
        )

        let text = SupervisorSkillActivityPresentation.displayFullRecordText(record)

        #expect(text.contains("请求技能：browser.open"))
        #expect(text.contains("意图族：browser.navigate、research.lookup"))
        #expect(text.contains("能力族：") == true)
        #expect(text.contains("repo.read"))
        #expect(text.contains("browser.interact"))
        #expect(text.contains("能力档位：observe_only、browser_operator"))
        #expect(text.contains("执行就绪：等待本地审批"))
        #expect(text.contains("本次请求档位：observe_only、browser_operator"))
        #expect(text.contains("新增放开档位：browser_operator"))
        #expect(text.contains("本次请求能力族：") == true)
        #expect(text.contains("授权门槛：高权限 grant"))
        #expect(text.contains("审批门槛：本地审批"))
        #expect(text.contains("所需运行面：受治理浏览器运行面（managed_browser_runtime）"))
        #expect(text.contains("解阻动作：请求本地审批（request_local_approval）"))
    }

    @Test
    func displayFullRecordTextHumanizesTimelineDetailForSupervisorCopy() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-timeline-copy-1",
            projectName: "Project Alpha",
            title: "agent-browser",
            latestStatus: "blocked",
            latestStatusLabel: "受阻",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [
                ProjectSkillRecordTimelineEntry(
                    id: "approval-1",
                    status: "blocked",
                    statusLabel: "受阻",
                    timestamp: "2026-03-24T10:00:00.000Z",
                    summary: "Supervisor skill blocked",
                    detail: "deny_code=local_approval_required\nrequired_capability=web.fetch",
                    rawJSON: #"{"status":"blocked"}"#
                )
            ],
            timeline: [],
            uiReviewAgentEvidenceFields: [],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil,
            guidanceContract: nil
        )

        let text = SupervisorSkillActivityPresentation.displayFullRecordText(record)

        #expect(text.contains("项目：Project Alpha"))
        #expect(text.contains("请求单号：req-timeline-copy-1"))
        #expect(text.contains("最新状态：受阻"))
        #expect(text.contains("状态：受阻"))
        #expect(text.contains("拒绝原因：继续这个动作前，仍然需要本地审批。（local_approval_required）"))
        #expect(text.contains("所需能力：联网访问（web.fetch）"))
    }

    @Test
    func displayFullRecordTextUsesRequiredCapabilityForGrantRequiredTimelineCopy() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-timeline-grant-1",
            projectName: "Project Alpha",
            title: "agent-browser",
            latestStatus: "blocked",
            latestStatusLabel: "受阻",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [
                ProjectSkillRecordTimelineEntry(
                    id: "approval-grant-1",
                    status: "blocked",
                    statusLabel: "受阻",
                    timestamp: "2026-03-24T10:00:00.000Z",
                    summary: "Supervisor skill blocked",
                    detail: "deny_code=grant_required\nrequired_capability=web.fetch",
                    rawJSON: #"{"status":"blocked"}"#
                )
            ],
            timeline: [],
            uiReviewAgentEvidenceFields: [],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil,
            guidanceContract: nil
        )

        let text = SupervisorSkillActivityPresentation.displayFullRecordText(record)

        #expect(text.contains("拒绝原因：继续这个动作前，仍然需要先通过 联网访问 的 Hub 授权。（grant_required）"))
        #expect(text.contains("所需能力：联网访问（web.fetch）"))
    }

    @Test
    func fullRecordDisplayUsesLocalizedGeneratedTimelineSummaries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_timeline_summary_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"supervisor_skill_call","action":"awaiting_authorization","request_id":"skill-timeline-localized","project_id":"project-alpha","skill_id":"agent-browser","tool_name":"device.browser.control","status":"awaiting_authorization","timestamp_ms":1000}
        {"type":"supervisor_skill_call","action":"queued","request_id":"skill-timeline-localized","project_id":"project-alpha","skill_id":"agent-browser","tool_name":"device.browser.control","status":"queued","timestamp_ms":2000}
        {"type":"supervisor_skill_call","action":"running","request_id":"skill-timeline-localized","project_id":"project-alpha","skill_id":"agent-browser","tool_name":"device.browser.control","status":"running","timestamp_ms":3000}
        {"type":"supervisor_skill_call","action":"blocked","request_id":"skill-timeline-localized","project_id":"project-alpha","skill_id":"agent-browser","tool_name":"device.browser.control","status":"blocked","deny_code":"local_approval_required","timestamp_ms":4000}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-timeline-localized"
            )
        )

        let text = SupervisorSkillActivityPresentation.displayFullRecordText(fullRecord)

        #expect(text.contains("摘要：等待本地审批"))
        #expect(text.contains("摘要：已进入受治理执行队列"))
        #expect(text.contains("摘要：正在执行浏览器控制"))
        #expect(text.contains("摘要：Supervisor 技能受阻"))
    }

    @Test
    func queuedBodyUsesRequestedWrapperBuiltinDisplaySummary() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-routing-body-1",
            projectId: "project-alpha",
            jobId: "job-12",
            planId: "plan-12",
            stepId: "step-12",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .queued,
            payload: [
                "action": .string("open"),
                "url": .string("https://example.com/login")
            ],
            currentOwner: "supervisor",
            resultSummary: "",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-routing-body-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .deviceBrowserControl,
            toolCall: ToolCall(
                id: "skill-routing-body-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("open"),
                    "url": .string("https://example.com/login")
                ]
            ),
            toolSummary: "https://example.com/login",
            actionURL: nil
        )

        let displaySkill = SupervisorSkillActivityPresentation.displaySkillSummary(for: item)
        let body = SupervisorSkillActivityPresentation.body(for: item)

        #expect(displaySkill == "browser.open -> guarded-automation · action=open")
        #expect(body.contains("技能 browser.open -> guarded-automation · action=open"))
    }

    @Test
    func fullRecordBuildsStructuredSupervisorEvidenceSections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .planDrift, .preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)
        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: "review-7",
                projectId: "project-alpha",
                trigger: .manualRequest,
                reviewLevel: .r2Strategic,
                verdict: .betterPathFound,
                targetRole: .supervisor,
                deliveryMode: .replanRequest,
                ackRequired: true,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                projectAIStrengthBand: .strong,
                projectAIStrengthConfidence: 0.91,
                projectAIStrengthAuditRef: "audit-strength-7",
                workOrderRef: "wo-7",
                summary: "Keep the browser skill aligned with the guarded work order.",
                recommendedActions: ["Verify the browser result before expanding scope."],
                anchorGoal: "Capture browser evidence safely",
                anchorDoneDefinition: "The run stores evidence and links back to governance.",
                anchorConstraints: ["No raw secret leakage."],
                currentState: "Browser automation just completed.",
                nextStep: "Inspect the structured evidence record.",
                blocker: "",
                createdAtMs: 2_000,
                auditRef: "audit-review-7"
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-7",
                reviewId: "review-7",
                projectId: "project-alpha",
                targetRole: .supervisor,
                deliveryMode: .priorityInsert,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "收到，我会按《Guarded Browser》这条指导继续推进：verdict=watchsummary=先核对浏览器证据，再下发下一步导航。effective_supervisor_tier=s3_strategic_coacheffective_work_order_depth=execution_readywork_order_ref=wo-7",
                ackStatus: .pending,
                ackRequired: true,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                workOrderRef: "wo-7",
                ackNote: "",
                injectedAtMs: 2_200,
                ackUpdatedAtMs: 2_200,
                expiresAtMs: 4_000_000_000_000,
                retryAtMs: 0,
                retryCount: 0,
                maxRetryCount: 0,
                auditRef: "audit-guidance-7"
            ),
            for: ctx
        )

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-7",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ],
            currentOwner: "supervisor",
            resultSummary: "Navigation completed",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 3_000,
            auditRef: "audit-skill-7"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)

        let toolCall = ToolCall(
            id: "skill-7",
            tool: .deviceBrowserControl,
            args: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ]
        )
        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: toolCall,
            rawOutput: "Opened https://example.com and captured screenshot.png",
            triggerSource: "user_turn",
            ctx: ctx
        )

        let raw = """
        {"type":"supervisor_skill_call","action":"dispatch","request_id":"skill-7","project_id":"project-alpha","job_id":"job-1","plan_id":"plan-1","step_id":"step-1","skill_id":"agent-browser","tool_name":"device.browser.control","status":"queued","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"timestamp_ms":1000,"audit_ref":"audit-skill-7","trigger_source":"user_turn"}
        {"type":"supervisor_skill_call","action":"completed","request_id":"skill-7","project_id":"project-alpha","job_id":"job-1","plan_id":"plan-1","step_id":"step-1","skill_id":"agent-browser","tool_name":"device.browser.control","status":"completed","result_summary":"Navigation completed","result_evidence_ref":"local://supervisor_skill_results/skill-7.json","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"timestamp_ms":3000,"audit_ref":"audit-skill-7","trigger_source":"user_turn"}
        {"type":"supervisor_skill_result","request_id":"skill-7","project_id":"project-alpha","job_id":"job-1","plan_id":"plan-1","step_id":"step-1","skill_id":"agent-browser","tool_name":"device.browser.control","status":"completed","result_summary":"Navigation completed","result_evidence_ref":"local://supervisor_skill_results/skill-7.json","raw_output_ref":"local://supervisor_skill_results/skill-7.json#raw_output","raw_output_chars":55,"tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"updated_at_ms":3000,"audit_ref":"audit-skill-7","trigger_source":"user_turn"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-7"
            )
        )

        #expect(fullRecord.title == "agent-browser")
        #expect(fullRecord.latestStatusLabel == "已完成")
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "project_name" && $0.value == "Project Alpha" }))
        #expect(fullRecord.toolArgumentsText?.contains("\"url\"") == true)
        #expect(fullRecord.skillPayloadText?.contains("\"action\"") == true)
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "supervisor_tier" && $0.value == "S3 Strategic Coach" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "work_order_ref" && $0.value == "wo-7" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "pending_guidance_id" && $0.value == "guidance-7" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "guidance_summary" && $0.value == "先核对浏览器证据，再下发下一步导航。" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "follow_up_rhythm" && $0.value.contains("blocker cooldown") }))
        #expect(fullRecord.resultFields.contains(where: { $0.label == "result_summary" && $0.value == "Navigation completed" }))
        #expect(fullRecord.rawOutputPreview?.contains("screenshot.png") == true)
        #expect(fullRecord.evidenceFields.contains(where: { $0.label == "audit_ref" && $0.value == "audit-skill-7" }))
        #expect(fullRecord.timeline.count == 3)
        #expect(fullRecord.supervisorEvidenceJSON?.contains("\"trigger_source\"") == true)
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("Supervisor 技能完整记录"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== 治理上下文 =="))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== 技能载荷 =="))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("guidance_summary=先核对浏览器证据，再下发下一步导航。"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("收到，我会按《Guarded Browser》这条指导继续推进") == false)
    }

    @Test
    func blockedPayloadAllowlistBodyUsesHumanGuidance() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-blocked-1",
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-backup",
            toolName: ToolName.run_command.rawValue,
            status: .blocked,
            payload: ["command": .string("rm -rf . && tar czf backup.tgz .")],
            currentOwner: "supervisor",
            resultSummary: "repo command rejected by governed allowlist",
            denyCode: "payload.command_not_allowed",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-blocked-1"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .run_command,
            toolCall: ToolCall(
                id: "skill-blocked-1",
                tool: .run_command,
                args: ["command": .string("rm -rf . && tar czf backup.tgz .")]
            ),
            toolSummary: "rm -rf . && tar czf backup.tgz .",
            actionURL: nil
        )

        let body = SupervisorSkillActivityPresentation.body(for: item)

        #expect(body.contains("不在受治理白名单里"))
        #expect(body.contains("更新技能契约"))
    }

    @Test
    func blockedGovernanceBodyAndDiagnosticsUsePolicyContext() {
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-blocked-2",
            projectId: "project-alpha",
            jobId: "job-9",
            planId: "plan-4",
            stepId: "step-2",
            skillId: "open-index-html",
            toolName: ToolName.process_start.rawValue,
            status: .blocked,
            payload: ["name": .string("open-index-html")],
            currentOwner: "supervisor",
            resultSummary: "project governance blocks process_start under A-Tier a0_observe",
            denyCode: "governance_capability_denied",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_managed_processes",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-blocked-2"
        )
        let item = SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: .process_start,
            toolCall: ToolCall(
                id: "skill-blocked-2",
                tool: .process_start,
                args: ["name": .string("open-index-html")]
            ),
            toolSummary: "open-index-html",
            actionURL: nil
        )

        let body = SupervisorSkillActivityPresentation.body(for: item)
        let diagnostics = SupervisorSkillActivityPresentation.diagnostics(for: item)

        #expect(body.contains("不允许受治理的后台进程"))
        #expect(body.contains("打开项目设置 -> A-Tier"))
        #expect(body.contains("A2 Repo Auto"))
        #expect(diagnostics.contains("policy_source=project_governance"))
        #expect(diagnostics.contains("policy_reason=execution_tier_missing_managed_processes"))
        #expect(diagnostics.contains("governance_reason=当前项目 A-Tier 不允许受治理的后台进程。"))
    }

    @Test
    func fullRecordRetainsPolicyContextForBlockedSkill() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_policy_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-policy-1",
            projectId: "project-alpha",
            jobId: "job-3",
            planId: "plan-2",
            stepId: "step-8",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: ["action": .string("open_url")],
            currentOwner: "supervisor",
            resultSummary: "browser automation blocked by governance",
            denyCode: "governance_capability_denied",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-policy-1"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)
        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: ToolCall(
                id: "skill-policy-1",
                tool: .deviceBrowserControl,
                args: ["action": .string("open_url")]
            ),
            rawOutput: nil,
            triggerSource: "user_turn",
            ctx: ctx
        )
        let raw = """
        {"type":"supervisor_skill_call","action":"blocked","request_id":"skill-policy-1","project_id":"project-alpha","job_id":"job-3","plan_id":"plan-2","step_id":"step-8","skill_id":"agent-browser","tool_name":"device.browser.control","status":"blocked","result_summary":"browser automation blocked by governance","deny_code":"governance_capability_denied","policy_source":"project_governance","policy_reason":"execution_tier_missing_browser_runtime","execution_tier":"\(AXProjectExecutionTier.a1Plan.rawValue)","effective_execution_tier":"\(AXProjectExecutionTier.a1Plan.rawValue)","supervisor_intervention_tier":"\(AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue)","effective_supervisor_intervention_tier":"\(AXProjectSupervisorInterventionTier.s2PeriodicReview.rawValue)","review_policy_mode":"\(AXProjectReviewPolicyMode.periodic.rawValue)","progress_heartbeat_sec":900,"review_pulse_sec":1800,"brainstorm_review_sec":0,"governance_compat_source":"\(AXProjectGovernanceCompatSource.explicitDualDial.rawValue)","timestamp_ms":2000,"audit_ref":"audit-policy-1"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-policy-1"
            )
        )

        #expect(fullRecord.governanceFields.contains(where: { $0.label == "policy_source" && $0.value == "project_governance" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "policy_reason" && $0.value == "execution_tier_missing_browser_runtime" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "governance_reason" && $0.value.contains("不允许浏览器自动化") }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "blocked_summary" && $0.value.contains("不允许浏览器自动化") }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "governance_truth" && $0.value.contains("当前生效 A1/S2") }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "repair_action" && $0.value.contains("打开 A-Tier：") }))
        #expect(!fullRecord.approvalFields.contains(where: {
            ["policy_source", "policy_reason", "governance_reason", "blocked_summary", "repair_action"].contains($0.label)
        }))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("governance_reason=当前项目 A-Tier 不允许浏览器自动化。"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("policy_reason=execution_tier_missing_browser_runtime"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("blocked_summary=当前项目 A-Tier 不允许浏览器自动化。"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("governance_truth=当前生效 A1/S2 · 审查 Periodic · 节奏 心跳 15m / 脉冲 30m / 脑暴 off"))
    }

    @Test
    func fullRecordPrefersRuntimeSurfacePolicyReasonAliasForSupervisorView() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_runtime_policy_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-runtime-1",
            projectId: "project-alpha",
            jobId: "job-4",
            planId: "plan-4",
            stepId: "step-4",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .blocked,
            payload: ["action": .string("open_url")],
            currentOwner: "supervisor",
            resultSummary: "device action blocked by runtime surface",
            denyCode: "autonomy_policy_denied",
            policySource: "project_autonomy_policy",
            policyReason: nil,
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-runtime-1"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)

        let raw = """
        {"type":"supervisor_skill_call","action":"blocked","request_id":"skill-runtime-1","project_id":"project-alpha","job_id":"job-4","plan_id":"plan-4","step_id":"step-4","skill_id":"agent-browser","tool_name":"device.browser.control","status":"blocked","result_summary":"device action blocked by runtime surface","deny_code":"autonomy_policy_denied","policy_source":"project_autonomy_policy","runtime_surface_policy_reason":"runtime_surface_effective=guided","execution_tier":"\(AXProjectExecutionTier.a4OpenClaw.rawValue)","effective_execution_tier":"\(AXProjectExecutionTier.a4OpenClaw.rawValue)","supervisor_intervention_tier":"\(AXProjectSupervisorInterventionTier.s3StrategicCoach.rawValue)","effective_supervisor_intervention_tier":"\(AXProjectSupervisorInterventionTier.s3StrategicCoach.rawValue)","review_policy_mode":"\(AXProjectReviewPolicyMode.hybrid.rawValue)","progress_heartbeat_sec":300,"review_pulse_sec":600,"brainstorm_review_sec":1800,"governance_compat_source":"\(AXProjectGovernanceCompatSource.explicitDualDial.rawValue)","timestamp_ms":2000,"audit_ref":"audit-runtime-1"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-runtime-1"
            )
        )

        #expect(fullRecord.governanceFields.contains(where: { $0.label == "policy_reason" && $0.value == "runtime_surface_effective=guided" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "governance_reason" && $0.value == "当前运行面仍然关闭了设备级动作。" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "governance_truth" && $0.value.contains("当前生效 A4/S3") }))
        #expect(!fullRecord.approvalFields.contains(where: { ["policy_reason", "governance_reason"].contains($0.label) }))
    }

    @Test
    func fullRecordPrefersPersistedGovernanceEvidenceFromRawLog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_persisted_governance_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let raw = """
        {"type":"supervisor_skill_call","action":"blocked","request_id":"skill-persisted-supervisor-1","project_id":"project-alpha","skill_id":"agent-browser","tool_name":"device.browser.control","status":"blocked","deny_code":"governance_capability_denied","policy_source":"project_governance","policy_reason":"execution_tier_missing_browser_runtime","governance_reason":"persisted supervisor governance reason","blocked_summary":"persisted supervisor blocked summary","governance_truth":"persisted supervisor governance truth","repair_action":"persisted supervisor repair action","timestamp_ms":2000,"audit_ref":"audit-persisted-supervisor-1"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-persisted-supervisor-1"
            )
        )

        #expect(fullRecord.governanceFields.contains(where: { $0.label == "governance_reason" && $0.value == "persisted supervisor governance reason" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "blocked_summary" && $0.value == "persisted supervisor blocked summary" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "governance_truth" && $0.value == "persisted supervisor governance truth" }))
        #expect(fullRecord.governanceFields.contains(where: { $0.label == "repair_action" && $0.value == "persisted supervisor repair action" }))
    }

    @Test
    func fullRecordIncludesRequestedSkillAndRoutingResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_routing_record_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-routing-record-1",
            projectId: "project-alpha",
            jobId: "job-10",
            planId: "plan-10",
            stepId: "step-1",
            skillId: "guarded-automation",
            requestedSkillId: "browser.open",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: [
                "action": .string("open"),
                "url": .string("https://example.com/login")
            ],
            currentOwner: "supervisor",
            resultSummary: "Opened login page",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 2_000,
            auditRef: "audit-routing-record-1"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)
        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: ToolCall(
                id: "skill-routing-record-1",
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("open_url"),
                    "url": .string("https://example.com/login")
                ]
            ),
            rawOutput: "Opened login page",
            triggerSource: "user_turn",
            ctx: ctx
        )

        let raw = """
        {"type":"supervisor_skill_call","action":"dispatch","request_id":"skill-routing-record-1","project_id":"project-alpha","job_id":"job-10","plan_id":"plan-10","step_id":"step-1","requested_skill_id":"browser.open","skill_id":"guarded-automation","routing_reason_code":"preferred_builtin_selected","routing_explanation":"requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open","tool_name":"device.browser.control","status":"queued","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com/login"},"timestamp_ms":1000,"audit_ref":"audit-routing-record-1","trigger_source":"user_turn"}
        {"type":"supervisor_skill_result","request_id":"skill-routing-record-1","project_id":"project-alpha","job_id":"job-10","plan_id":"plan-10","step_id":"step-1","requested_skill_id":"browser.open","skill_id":"guarded-automation","routing_reason_code":"preferred_builtin_selected","routing_explanation":"requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open","tool_name":"device.browser.control","status":"completed","result_summary":"Opened login page","result_evidence_ref":"local://supervisor_skill_results/skill-routing-record-1.json","tool":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com/login"},"updated_at_ms":2000,"audit_ref":"audit-routing-record-1","trigger_source":"user_turn"}
        """
        try #require(raw.data(using: .utf8)).write(to: ctx.rawLogURL, options: .atomic)

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-routing-record-1"
            )
        )

        #expect(fullRecord.title == "browser.open -> guarded-automation · action=open")
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "requested_skill_id" && $0.value == "browser.open" }))
        #expect(fullRecord.requestMetadata.contains(where: {
            $0.label == "routing_resolution" && $0.value.contains("browser.open -> guarded-automation")
        }))
        #expect(fullRecord.requestMetadata.contains(where: { $0.label == "routing_reason_code" && $0.value == "preferred_builtin_selected" }))
        #expect(fullRecord.requestMetadata.contains(where: {
            $0.label == "routing_explanation" && $0.value.contains("requested entrypoint browser.open converged to preferred builtin guarded-automation")
        }))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("requested_skill_id=browser.open"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("routing_resolution=browser.open -> guarded-automation"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("routing_reason_code=preferred_builtin_selected"))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("routing_explanation=requested entrypoint browser.open converged to preferred builtin guarded-automation"))
    }

    @Test
    func fullRecordLoadsUIReviewAgentEvidenceFromToolResultOutput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_skill_ui_review_evidence_\(UUID().uuidString)", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let snapshot = XTUIReviewAgentEvidenceSnapshot(
            schemaVersion: XTUIReviewAgentEvidenceSnapshot.currentSchemaVersion,
            reviewID: "review-ui-1",
            projectID: "project-alpha",
            bundleID: "bundle-ui-1",
            auditRef: "audit-ui-review-1",
            reviewRef: "local://.xterminal/ui_review/reviews/review-ui-1.json",
            bundleRef: "local://.xterminal/ui_observation/bundles/bundle-ui-1.json",
            updatedAtMs: 3_000,
            verdict: .ready,
            confidence: .high,
            sufficientEvidence: true,
            objectiveReady: true,
            issueCodes: ["critical_action_visible"],
            summary: "Primary CTA is visible and the browser state is ready for the next agent step.",
            artifactRefs: ["screenshot_ref=local://.xterminal/ui_observation/artifacts/bundle-ui-1/full.png"],
            artifactPaths: ["/tmp/bundle-ui-1/full.png"],
            checks: ["critical_action=pass :: Primary CTA visible above the fold."],
            trend: ["status=stable"],
            comparison: ["critical_action_visible=stable"],
            recentHistory: ["review_id=review-ui-0 verdict=ready"]
        )
        try XTUIReviewAgentEvidenceStore.write(snapshot, for: ctx)
        let evidenceRef = XTUIReviewAgentEvidenceStore.reviewRef(reviewID: snapshot.reviewID)

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: "skill-ui-review-1",
            projectId: "project-alpha",
            jobId: "job-ui-1",
            planId: "plan-ui-1",
            stepId: "step-ui-1",
            skillId: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: .completed,
            payload: ["action": .string("snapshot")],
            currentOwner: "supervisor",
            resultSummary: "Captured a governed browser snapshot.",
            denyCode: "",
            resultEvidenceRef: nil,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 3_000,
            auditRef: "audit-skill-ui-review-1"
        )
        try SupervisorProjectSkillCallStore.upsert(record, for: ctx)

        _ = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: ToolCall(
                id: "skill-ui-review-1",
                tool: .deviceBrowserControl,
                args: ["action": .string("snapshot")]
            ),
            rawOutput: """
            {"ok":true,"ui_review_agent_evidence_ref":"\(evidenceRef)","ui_review_summary":"Primary CTA visible and ready"}
            """,
            triggerSource: "user_turn",
            ctx: ctx
        )

        let fullRecord = try #require(
            SupervisorSkillActivityPresentation.fullRecord(
                ctx: ctx,
                projectName: "Project Alpha",
                requestID: "skill-ui-review-1"
            )
        )

        #expect(fullRecord.uiReviewAgentEvidenceFields.contains(where: {
            $0.label == "ui_review_agent_evidence_ref" && $0.value == evidenceRef
        }))
        #expect(fullRecord.uiReviewAgentEvidenceFields.contains(where: {
            $0.label == "verdict" && $0.value == "ready"
        }))
        #expect(fullRecord.uiReviewAgentEvidenceFields.contains(where: {
            $0.label == "summary" && $0.value.contains("Primary CTA is visible")
        }))
        #expect(fullRecord.uiReviewAgentEvidenceText?.contains("verdict=ready") == true)
        #expect(fullRecord.uiReviewAgentEvidenceText?.contains("issue_codes=critical_action_visible") == true)
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== UI 审查代理证据 =="))
        #expect(SupervisorSkillActivityPresentation.fullRecordText(fullRecord).contains("== UI 审查代理证据详情 =="))
    }
}
