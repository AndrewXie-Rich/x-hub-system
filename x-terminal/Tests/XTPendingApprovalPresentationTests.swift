import Foundation
import Testing
@testable import XTerminal

struct XTPendingApprovalPresentationTests {

    @Test
    func projectApprovalMessageUsesHumanPreviewForBrowserOpen() {
        let toolCall = ToolCall(
            id: "pending-browser-1",
            tool: .deviceBrowserControl,
            args: [
                "action": .string("open_url"),
                "url": .string("https://example.com")
            ]
        )

        let message = XTPendingApprovalPresentation.approvalMessage(for: toolCall)
        let summary = XTPendingApprovalPresentation.actionSummary(for: toolCall)

        #expect(message.summary.contains("本地审批"))
        #expect(message.summary.contains("https://example.com"))
        #expect(summary == "在浏览器中打开 https://example.com")
        #expect(message.nextStep?.contains("先在 X-Terminal 里批准") == true)
    }

    @Test
    func actionSummaryHumanizesCommandExecution() {
        let toolCall = ToolCall(
            id: "pending-command-1",
            tool: .run_command,
            args: [
                "command": .string("swift test --filter XTToolAuthorizationTests")
            ]
        )

        let summary = XTPendingApprovalPresentation.actionSummary(for: toolCall)
        let message = XTPendingApprovalPresentation.approvalMessage(for: toolCall)

        #expect(summary.contains("运行命令"))
        #expect(summary.contains("swift test --filter XTToolAuthorizationTests"))
        #expect(message.summary.contains("命令 swift test --filter XTToolAuthorizationTests"))
    }

    @Test
    func supplementaryReasonDropsGenericApprovalCopy() {
        let message = XTGuardrailMessage(
            summary: "运行命令（命令 swift test）前，还需要先通过本地审批。",
            nextStep: "先在 X-Terminal 里批准，让受治理工具继续执行。"
        )

        let reason = XTPendingApprovalPresentation.supplementaryReason(
            "waiting for local governed approval",
            primaryMessage: message
        )

        #expect(reason == nil)
    }

    @Test
    func supplementaryReasonKeepsUsefulOperatorContext() {
        let message = XTGuardrailMessage(
            summary: "运行浏览器控制（https://example.com）前，还需要先通过本地审批。",
            nextStep: "先在 X-Terminal 里批准，让受治理工具继续执行。"
        )

        let reason = XTPendingApprovalPresentation.supplementaryReason(
            "requested by nightly QA monitor",
            primaryMessage: message
        )

        #expect(reason == "requested by nightly QA monitor")
    }

    @Test
    func approvalMessageIncludesProfileDeltaSummaryAndLocalApprovalNextStep() {
        let toolCall = ToolCall(
            id: "pending-browser-delta-1",
            tool: .deviceBrowserControl,
            args: [
                "action": .string("open_url"),
                "url": .string("https://example.com/dashboard")
            ]
        )
        let activity = ProjectSkillActivityItem(
            requestID: "pending-browser-delta-1",
            skillID: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 1.0,
            resolutionSource: "",
            toolArgs: toolCall.args,
            routingReasonCode: "",
            routingExplanation: "",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            approvalSummary: "当前可直接运行：observe_only；本次请求：observe_only, browser_operator；新增放开：browser_operator；grant=privileged；approval=local_approval",
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only", "browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["repo.read", "browser.interact"],
            deltaCapabilityFamilies: ["browser.interact"],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let message = XTPendingApprovalPresentation.approvalMessage(
            for: toolCall,
            activity: activity
        )
        let lines = XTPendingApprovalPresentation.approvalProfileDeltaLines(for: activity)

        #expect(message.summary.contains("新增放开：browser_operator"))
        #expect(message.nextStep == "这次审批通过后，会按当前受治理路径继续执行。")
        #expect(lines.contains("当前可直接运行：observe_only"))
        #expect(lines.contains("本次请求：observe_only, browser_operator"))
        #expect(lines.contains("新增放开：browser_operator"))
        #expect(lines.contains("授权门槛：高权限 grant · 审批门槛：本地审批"))
    }

    @Test
    func approvalMessageUsesGrantSpecificNextStepWhenReadinessRequiresGrant() {
        let toolCall = ToolCall(
            id: "pending-delivery-1",
            tool: .git_push,
            args: [
                "remote": .string("origin"),
                "branch": .string("main")
            ]
        )
        let activity = ProjectSkillActivityItem(
            requestID: "pending-delivery-1",
            skillID: "repo.git.push",
            toolName: ToolName.git_push.rawValue,
            status: "awaiting_approval",
            createdAt: 2.0,
            resolutionSource: "",
            toolArgs: toolCall.args,
            routingReasonCode: "",
            routingExplanation: "",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            approvalSummary: "",
            currentRunnableProfiles: [],
            requestedProfiles: [],
            deltaProfiles: [],
            currentRunnableCapabilityFamilies: [],
            requestedCapabilityFamilies: [],
            deltaCapabilityFamilies: [],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let message = XTPendingApprovalPresentation.approvalMessage(
            for: toolCall,
            activity: activity
        )

        #expect(message.summary.contains("Hub 授权"))
        #expect(message.nextStep == "先完成 Hub grant，再恢复这次受治理技能调用。")
    }

    @Test
    func approvalMessageUsesGrantSummaryWhenReadinessRequiresGrantWithoutCapabilityOrDenyCode() {
        let toolCall = ToolCall(
            id: "pending-web-1",
            tool: .web_search,
            args: [
                "query": .string("governed skill chain")
            ]
        )
        let activity = ProjectSkillActivityItem(
            requestID: "pending-web-1",
            skillID: "tavily-websearch",
            toolName: ToolName.web_search.rawValue,
            status: "awaiting_approval",
            createdAt: 2.1,
            resolutionSource: "",
            toolArgs: toolCall.args,
            routingReasonCode: "",
            routingExplanation: "",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            approvalSummary: "",
            currentRunnableProfiles: [],
            requestedProfiles: [],
            deltaProfiles: [],
            currentRunnableCapabilityFamilies: [],
            requestedCapabilityFamilies: [],
            deltaCapabilityFamilies: [],
            grantFloor: XTSkillGrantFloor.readonly.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let message = XTPendingApprovalPresentation.approvalMessage(
            for: toolCall,
            activity: activity
        )

        #expect(message.summary.contains("Hub 授权"))
        #expect(message.summary.contains("本地审批") == false)
    }

    @Test
    func approvalMessageUsesLocalApprovalWhenReadinessOverridesCapabilityFallback() {
        let toolCall = ToolCall(
            id: "pending-browser-local-override-1",
            tool: .deviceBrowserControl,
            args: [
                "url": .string("https://example.com/admin")
            ]
        )
        let activity = ProjectSkillActivityItem(
            requestID: "pending-browser-local-override-1",
            skillID: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 2.2,
            resolutionSource: "",
            toolArgs: toolCall.args,
            routingReasonCode: "",
            routingExplanation: "",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            approvalSummary: "",
            currentRunnableProfiles: [],
            requestedProfiles: [],
            deltaProfiles: [],
            currentRunnableCapabilityFamilies: [],
            requestedCapabilityFamilies: [],
            deltaCapabilityFamilies: [],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredCapability: "browser.interact",
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let message = XTPendingApprovalPresentation.approvalMessage(
            for: toolCall,
            activity: activity
        )

        #expect(message.summary.contains("本地审批"))
        #expect(message.summary.contains("Hub 授权") == false)
    }

    @Test
    func governedSkillHelpersSummarizeGovernanceContextAndResumeSupport() {
        let activity = ProjectSkillActivityItem(
            requestID: "pending-browser-governed-1",
            skillID: "guarded-automation",
            requestedSkillID: "browser.open",
            intentFamilies: ["browser.navigate", "research.lookup"],
            capabilityFamilies: ["repo.read", "browser.interact"],
            capabilityProfiles: ["observe_only", "browser_operator"],
            requiredRuntimeSurfaces: ["managed_browser_runtime"],
            unblockActions: ["request_local_approval"],
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "awaiting_approval",
            createdAt: 3.0,
            resolutionSource: "primary",
            toolArgs: [
                "action": .string("open_url"),
                "url": .string("https://example.com/dashboard")
            ],
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to guarded-automation",
            hubStateDirPath: "/tmp/xhub-governed-state",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            approvalSummary: "",
            currentRunnableProfiles: [],
            requestedProfiles: [],
            deltaProfiles: [],
            currentRunnableCapabilityFamilies: [],
            requestedCapabilityFamilies: [],
            deltaCapabilityFamilies: [],
            grantFloor: XTSkillGrantFloor.privileged.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredCapability: "",
            resultSummary: "",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let shortSummary = XTPendingApprovalPresentation.governedSkillShortSummary(for: activity)
        let detailLines = XTPendingApprovalPresentation.governedSkillDetailLines(for: activity)

        #expect(shortSummary == "browser.open -> guarded-automation · 等待本地审批")
        #expect(detailLines.contains("生效技能：guarded-automation"))
        #expect(detailLines.contains("请求技能：browser.open"))
        #expect(detailLines.contains("执行就绪：等待本地审批"))
        #expect(detailLines.contains("治理闸门：高权限 grant · 本地审批"))
        #expect(detailLines.contains(where: { $0.hasPrefix("意图族：") && $0.contains("browser.navigate") && $0.contains("research.lookup") }))
        #expect(detailLines.contains(where: { $0.hasPrefix("能力族：") && $0.contains("repo.read") && $0.contains("browser.interact") }))
        #expect(detailLines.contains("能力档位：observe_only、browser_operator"))
        #expect(detailLines.contains("运行面：受治理浏览器运行面（managed_browser_runtime）"))
        #expect(detailLines.contains("解阻动作：请求本地审批（request_local_approval）"))
        #expect(detailLines.contains("恢复上下文：已保存 Hub 执行上下文，可在批准后继续恢复执行。"))
    }

    @Test
    func governedSkillHelpersHumanizeLocalModelRuntimeSurfacesAndRecoveryActions() {
        let activity = ProjectSkillActivityItem(
            requestID: "pending-local-vision-1",
            skillID: "local-vision-reader",
            intentFamilies: ["ai.vision.local"],
            capabilityFamilies: ["ai.vision.local"],
            capabilityProfiles: ["observe_only"],
            requiredRuntimeSurfaces: ["local_vision_runtime"],
            unblockActions: ["open_model_settings"],
            toolName: ToolName.summarize.rawValue,
            status: "blocked",
            createdAt: 3.1,
            resolutionSource: "primary",
            toolArgs: [:],
            routingReasonCode: "",
            routingExplanation: "",
            executionReadiness: XTSkillExecutionReadinessState.runtimeUnavailable.rawValue,
            approvalSummary: "",
            currentRunnableProfiles: [],
            requestedProfiles: [],
            deltaProfiles: [],
            currentRunnableCapabilityFamilies: [],
            requestedCapabilityFamilies: [],
            deltaCapabilityFamilies: [],
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.none.rawValue,
            requiredCapability: "",
            resultSummary: "",
            detail: "",
            denyCode: "runtime_surface_not_ready",
            authorizationDisposition: ""
        )

        let detailLines = XTPendingApprovalPresentation.governedSkillDetailLines(for: activity)

        #expect(detailLines.contains("执行就绪：执行面暂不可用"))
        #expect(detailLines.contains("运行面：本地图像理解运行面（local_vision_runtime）"))
        #expect(detailLines.contains("解阻动作：打开模型设置（open_model_settings）"))
        #expect(detailLines.contains(where: { $0.hasPrefix("能力族：") && $0.contains("本地图像理解调用") }))
    }

    @Test
    func pendingBatchPresentationKeepsApproveAndExecuteForRunnablePendingCalls() {
        let localApprovalCall = ToolCall(
            id: "pending-local-1",
            tool: .deviceBrowserControl,
            args: ["url": .string("https://example.com")]
        )
        let plainPendingCall = ToolCall(
            id: "pending-plain-1",
            tool: .run_command,
            args: ["command": .string("swift build")]
        )
        let activityByRequestID = [
            localApprovalCall.id: pendingActivity(
                requestID: localApprovalCall.id,
                tool: .deviceBrowserControl,
                readiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue
            )
        ]

        let batch = XTPendingApprovalPresentation.pendingBatchPresentation(
            calls: [localApprovalCall, plainPendingCall],
            activityByRequestID: activityByRequestID
        )

        #expect(batch.primaryAction == .approveAndExecute)
        #expect(batch.primaryActionTitle == "批准并执行")
        #expect(batch.primaryActionSystemImage == "checkmark")
        #expect(batch.subtitle == "2 个工具调用等待你确认，其中 1 个来自受治理 skill")
        #expect(batch.footerNote.contains("批准后会立即执行当前这些待处理动作"))
        #expect(batch.hubDisconnectedNote == "Hub 未连接，连上后才能批准并执行。")
    }

    @Test
    func pendingBatchPresentationUsesRunnableSubsetCopyForMixedLocalAndGrantBlockedCalls() {
        let localApprovalCall = ToolCall(
            id: "pending-mixed-local-1",
            tool: .deviceBrowserControl,
            args: ["url": .string("https://example.com/dashboard")]
        )
        let grantRequiredCall = ToolCall(
            id: "pending-mixed-grant-1",
            tool: .git_push,
            args: ["branch": .string("main")]
        )
        let activityByRequestID = [
            localApprovalCall.id: pendingActivity(
                requestID: localApprovalCall.id,
                tool: .deviceBrowserControl,
                readiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue
            ),
            grantRequiredCall.id: pendingActivity(
                requestID: grantRequiredCall.id,
                tool: .git_push,
                readiness: XTSkillExecutionReadinessState.grantRequired.rawValue
            )
        ]

        let batch = XTPendingApprovalPresentation.pendingBatchPresentation(
            calls: [localApprovalCall, grantRequiredCall],
            activityByRequestID: activityByRequestID
        )

        #expect(batch.primaryAction == .approveRunnableSubset)
        #expect(batch.primaryActionTitle == "批准可放行项")
        #expect(batch.primaryActionSystemImage == "checkmark.circle")
        #expect(batch.subtitle.contains("2 个工具调用等待处理"))
        #expect(batch.subtitle.contains("1 个仍需先完成 Hub grant"))
        #expect(batch.footerNote.contains("仍需 Hub grant"))
        #expect(batch.hubDisconnectedNote == "Hub 未连接，连上后才能继续处理并放行可执行项。")
    }

    @Test
    func pendingBatchPresentationUsesGrantStatusCopyWhenOnlyGrantBlockedCallsRemain() {
        let grantRequiredCall = ToolCall(
            id: "pending-grant-only-1",
            tool: .web_search,
            args: ["query": .string("governed skill chain")]
        )
        let activityByRequestID = [
            grantRequiredCall.id: pendingActivity(
                requestID: grantRequiredCall.id,
                tool: .web_search,
                readiness: XTSkillExecutionReadinessState.grantRequired.rawValue
            )
        ]

        let batch = XTPendingApprovalPresentation.pendingBatchPresentation(
            calls: [grantRequiredCall],
            activityByRequestID: activityByRequestID
        )

        #expect(batch.primaryAction == .reviewGrantStatus)
        #expect(batch.primaryActionTitle == "继续检查授权状态")
        #expect(batch.primaryActionSystemImage == "arrow.clockwise")
        #expect(batch.subtitle == "1 个待处理项都来自受治理 skill，当前仍在等待 Hub grant")
        #expect(batch.footerNote.contains("本地批准不会直接放行"))
        #expect(batch.footerNote.contains("Hub / Supervisor"))
        #expect(batch.hubDisconnectedNote == "Hub 未连接，连上后才能检查 grant 状态并继续处理。")
    }

    @Test
    func pendingBatchDeltaLinesSummarizeUnionProfilesAndGateFloors() {
        let localApprovalCall = ToolCall(
            id: "pending-delta-local-1",
            tool: .deviceBrowserControl,
            args: ["url": .string("https://example.com/dashboard")]
        )
        let grantRequiredCall = ToolCall(
            id: "pending-delta-grant-1",
            tool: .git_push,
            args: ["branch": .string("main")]
        )
        let activityByRequestID = [
            localApprovalCall.id: pendingActivity(
                requestID: localApprovalCall.id,
                tool: .deviceBrowserControl,
                readiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
                currentRunnableProfiles: ["observe_only"],
                requestedProfiles: ["observe_only", "browser_operator"],
                deltaProfiles: ["browser_operator"],
                deltaCapabilityFamilies: ["browser.interact"],
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: XTSkillApprovalFloor.localApproval.rawValue
            ),
            grantRequiredCall.id: pendingActivity(
                requestID: grantRequiredCall.id,
                tool: .git_push,
                readiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                currentRunnableProfiles: ["observe_only"],
                requestedProfiles: ["observe_only", "delivery_operator"],
                deltaProfiles: ["delivery_operator"],
                deltaCapabilityFamilies: ["repo.write"],
                grantFloor: XTSkillGrantFloor.readonly.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue
            )
        ]

        let lines = XTPendingApprovalPresentation.pendingBatchDeltaLines(
            calls: [localApprovalCall, grantRequiredCall],
            activityByRequestID: activityByRequestID
        )

        #expect(lines.contains("当前项目可直接运行：observe_only"))
        #expect(lines.contains("本批请求涉及：observe_only, browser_operator, delivery_operator"))
        #expect(lines.contains("本批新增放开：browser_operator, delivery_operator"))
        #expect(lines.contains(where: { $0.hasPrefix("本批新增能力族：") && $0.contains("browser.interact") && $0.contains("repo.write") }))
        #expect(lines.contains(where: { $0.hasPrefix("涉及授权门槛：") && $0.contains("高权限 grant") && $0.contains("只读 grant") && $0.contains("本地审批") && $0.contains("Hub grant") }))
    }

    @Test
    func pendingBatchAssistantStubSummarizesGovernedDeltaAndGrantState() {
        let localApprovalCall = ToolCall(
            id: "pending-assistant-local-1",
            tool: .deviceBrowserControl,
            args: ["url": .string("https://example.com/dashboard")]
        )
        let grantRequiredCall = ToolCall(
            id: "pending-assistant-grant-1",
            tool: .git_push,
            args: ["branch": .string("main")]
        )
        let activityByRequestID = [
            localApprovalCall.id: pendingActivity(
                requestID: localApprovalCall.id,
                tool: .deviceBrowserControl,
                readiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
                currentRunnableProfiles: ["observe_only"],
                requestedProfiles: ["observe_only", "browser_operator"],
                deltaProfiles: ["browser_operator"],
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: XTSkillApprovalFloor.localApproval.rawValue
            ),
            grantRequiredCall.id: pendingActivity(
                requestID: grantRequiredCall.id,
                tool: .git_push,
                readiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                currentRunnableProfiles: ["observe_only"],
                requestedProfiles: ["observe_only", "delivery_operator"],
                deltaProfiles: ["delivery_operator"],
                grantFloor: XTSkillGrantFloor.readonly.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue
            )
        ]

        let stub = XTPendingApprovalPresentation.pendingBatchAssistantStub(
            calls: [localApprovalCall, grantRequiredCall],
            activityByRequestID: activityByRequestID,
            isRemaining: true
        )

        #expect(stub.hasPrefix("仍有待审批的工具操作："))
        #expect(stub.contains("1 个仍需先完成 Hub grant"))
        #expect(stub.contains("本批新增放开：browser_operator, delivery_operator"))
    }

    @Test
    func pendingBatchAssistantStubFallsBackForPlainPendingCalls() {
        let plainCall = ToolCall(
            id: "pending-assistant-plain-1",
            tool: .run_command,
            args: ["command": .string("swift build")]
        )

        let stub = XTPendingApprovalPresentation.pendingBatchAssistantStub(
            calls: [plainCall],
            activityByRequestID: [:]
        )

        #expect(stub == "有待审批的工具操作（本页处理，或从首页打开对应项目）。")
    }
}

private func pendingActivity(
    requestID: String,
    tool: ToolName,
    readiness: String,
    currentRunnableProfiles: [String] = [],
    requestedProfiles: [String] = [],
    deltaProfiles: [String] = [],
    currentRunnableCapabilityFamilies: [String] = [],
    requestedCapabilityFamilies: [String] = [],
    deltaCapabilityFamilies: [String] = [],
    grantFloor: String = "",
    approvalFloor: String = ""
) -> ProjectSkillActivityItem {
    ProjectSkillActivityItem(
        requestID: requestID,
        skillID: "test.skill",
        toolName: tool.rawValue,
        status: "awaiting_approval",
        createdAt: 1.0,
        resolutionSource: "primary",
        toolArgs: [:],
        routingReasonCode: "",
        routingExplanation: "",
        executionReadiness: readiness,
        approvalSummary: "",
        currentRunnableProfiles: currentRunnableProfiles,
        requestedProfiles: requestedProfiles,
        deltaProfiles: deltaProfiles,
        currentRunnableCapabilityFamilies: currentRunnableCapabilityFamilies,
        requestedCapabilityFamilies: requestedCapabilityFamilies,
        deltaCapabilityFamilies: deltaCapabilityFamilies,
        grantFloor: grantFloor,
        approvalFloor: approvalFloor,
        resultSummary: "",
        detail: "",
        denyCode: "",
        authorizationDisposition: ""
    )
}
