import Foundation

extension SupervisorManager {
    @discardableResult
    func serviceOperatorChannelXTCommandsForTesting(
        _ snapshot: HubIPCClient.OperatorChannelXTCommandSnapshot,
        resultsSnapshot: HubIPCClient.OperatorChannelXTCommandResultSnapshot? = nil,
        now: Date = Date()
    ) -> [HubIPCClient.OperatorChannelXTCommandResultItem] {
        serviceOperatorChannelXTCommands(
            snapshot,
            resultsSnapshot: resultsSnapshot,
            now: now
        )
    }

    func executeOperatorChannelXTCommandForTesting(
        _ command: HubIPCClient.OperatorChannelXTCommandItem,
        project: AXProjectEntry,
        now: Date = Date()
    ) -> HubIPCClient.OperatorChannelXTCommandResultItem {
        executeOperatorChannelXTCommand(
            command,
            projectMap: [project.projectId: project],
            now: now
        )
    }

    @discardableResult
    func serviceOperatorChannelXTCommands(
        _ snapshot: HubIPCClient.OperatorChannelXTCommandSnapshot,
        resultsSnapshot: HubIPCClient.OperatorChannelXTCommandResultSnapshot?,
        now: Date = Date()
    ) -> [HubIPCClient.OperatorChannelXTCommandResultItem] {
        let snapshotUpdatedAtSec: TimeInterval = {
            let ms = max(0, snapshot.updatedAtMs)
            if ms > 0 {
                return ms / 1000.0
            }
            return now.timeIntervalSince1970
        }()
        if snapshotUpdatedAtSec > 0, now.timeIntervalSince1970 - snapshotUpdatedAtSec > schedulerSnapshotStaleSec {
            return []
        }

        let completedCommandIDs = Set(
            (resultsSnapshot?.items ?? []).map { $0.commandId.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let projectMap = knownProjects().reduce(into: [String: AXProjectEntry]()) { partialResult, project in
            partialResult[project.projectId] = project
        }
        guard !projectMap.isEmpty else { return [] }

        let commands = snapshot.items.sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs {
                return lhs.createdAtMs < rhs.createdAtMs
            }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        var outputs: [HubIPCClient.OperatorChannelXTCommandResultItem] = []
        for command in commands {
            let commandID = command.commandId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !commandID.isEmpty else { continue }
            guard !completedCommandIDs.contains(commandID) else { continue }

            let result = executeOperatorChannelXTCommand(
                command,
                projectMap: projectMap,
                now: now
            )
            outputs.append(result)
            _ = HubIPCClient.appendOperatorChannelXTCommandResult(result)
        }

        return outputs
    }

    func executeOperatorChannelXTCommand(
        _ command: HubIPCClient.OperatorChannelXTCommandItem,
        projectMap: [String: AXProjectEntry],
        now: Date
    ) -> HubIPCClient.OperatorChannelXTCommandResultItem {
        let commandID = command.commandId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = command.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionName = command.actionName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let projectID = command.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDeviceID = command.resolvedDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAtMs = max(0, command.createdAtMs)
        let completedAtMs = now.timeIntervalSince1970 * 1000.0
        let auditRef = command.auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "audit-operator-channel-xt-command-\(commandID)"
            : command.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)

        func finalize(
            status: String,
            denyCode: String = "",
            detail: String,
            runId: String = ""
        ) -> HubIPCClient.OperatorChannelXTCommandResultItem {
            HubIPCClient.OperatorChannelXTCommandResultItem(
                commandId: commandID,
                requestId: requestID,
                actionName: actionName,
                projectId: projectID,
                resolvedDeviceId: resolvedDeviceID,
                status: status,
                denyCode: denyCode,
                detail: detail,
                runId: runId,
                createdAtMs: createdAtMs,
                completedAtMs: completedAtMs,
                auditRef: auditRef
            )
        }

        guard actionName == "deploy.plan" else {
            let result = finalize(
                status: "failed",
                denyCode: "xt_command_action_not_supported_yet",
                detail: "xt command action not supported yet"
            )
            announceOperatorChannelXTCommandResult(
                command,
                result: result,
                projectName: nil
            )
            return result
        }

        guard let project = projectMap[projectID],
              let ctx = projectContext(from: project) else {
            let result = finalize(
                status: "failed",
                denyCode: "project_context_missing",
                detail: "project context missing"
            )
            announceOperatorChannelXTCommandResult(
                command,
                result: result,
                projectName: nil
            )
            return result
        }

        do {
            let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            let boundDeviceID = config.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !boundDeviceID.isEmpty, boundDeviceID == resolvedDeviceID else {
                let result = finalize(
                    status: "failed",
                    denyCode: "trusted_automation_project_not_bound",
                    detail: "trusted automation project not bound to routed device"
                )
                AXProjectStore.appendRawLog(
                    [
                        "type": "operator_channel_xt_command",
                        "phase": "failed",
                        "created_at": now.timeIntervalSince1970,
                        "command_id": commandID,
                        "request_id": requestID,
                        "action_name": actionName,
                        "provider": command.provider,
                        "conversation_id": command.conversationId,
                        "thread_key": command.threadKey,
                        "resolved_device_id": resolvedDeviceID,
                        "deny_code": result.denyCode,
                        "detail": result.detail,
                        "audit_ref": auditRef
                    ],
                    for: ctx
                )
                appendRecentEvent(
                    "operator channel xt command failed: \(project.projectId) -> \(actionName) (\(result.denyCode))",
                    project: project
                )
                announceOperatorChannelXTCommandResult(
                    command,
                    result: result,
                    projectName: project.displayName
                )
                return result
            }

            let request = try makeOperatorChannelDeployPlanRequest(
                for: project,
                ctx: ctx,
                command: command
            )
            let prepared = try prepareAutomationRun(
                for: ctx,
                request: request,
                emitSystemMessage: false
            )
            let result = finalize(
                status: "prepared",
                detail: "automation prepared",
                runId: prepared.launchRef
            )
            AXProjectStore.appendRawLog(
                [
                    "type": "operator_channel_xt_command",
                    "phase": "prepared",
                    "created_at": now.timeIntervalSince1970,
                    "command_id": commandID,
                    "request_id": requestID,
                    "action_name": actionName,
                    "provider": command.provider,
                    "conversation_id": command.conversationId,
                    "thread_key": command.threadKey,
                    "resolved_device_id": resolvedDeviceID,
                    "run_id": prepared.launchRef,
                    "audit_ref": auditRef
                ],
                for: ctx
            )
            appendRecentEvent(
                "operator channel xt command prepared: \(project.projectId) -> \(prepared.launchRef)",
                project: project
            )
            announceOperatorChannelXTCommandResult(
                command,
                result: result,
                projectName: project.displayName
            )
            return result
        } catch {
            let denyCode = operatorChannelXTCommandReasonCode(from: error)
            let result = finalize(
                status: "failed",
                denyCode: denyCode,
                detail: denyCode
            )
            AXProjectStore.appendRawLog(
                [
                    "type": "operator_channel_xt_command",
                    "phase": "failed",
                    "created_at": now.timeIntervalSince1970,
                    "command_id": commandID,
                    "request_id": requestID,
                    "action_name": actionName,
                    "provider": command.provider,
                    "conversation_id": command.conversationId,
                    "thread_key": command.threadKey,
                    "resolved_device_id": resolvedDeviceID,
                    "deny_code": denyCode,
                    "detail": String(describing: error),
                    "audit_ref": auditRef
                ],
                for: ctx
            )
            appendRecentEvent(
                "operator channel xt command failed: \(project.projectId) -> \(actionName) (\(denyCode))",
                project: project
            )
            announceOperatorChannelXTCommandResult(
                command,
                result: result,
                projectName: project.displayName
            )
            return result
        }
    }

    func announceOperatorChannelXTCommandResult(
        _ command: HubIPCClient.OperatorChannelXTCommandItem,
        result: HubIPCClient.OperatorChannelXTCommandResultItem,
        projectName: String?
    ) {
        let provider = operatorChannelProviderDisplayName(command.provider)
        let action = operatorChannelActionDisplayName(command.actionName)
        let projectToken = operatorChannelProjectDisplayName(projectName, projectID: result.projectId)
        let denyDisplay = operatorChannelXTCommandReasonDisplayName(
            result.denyCode.isEmpty ? result.detail : result.denyCode
        )

        let systemMessage: String
        let voiceText: String
        let title: String
        let body: String
        let voiceTrigger: SupervisorVoiceJobTrigger
        let voicePriority: SupervisorVoiceJobPriority

        switch result.status {
        case "prepared":
            let runToken = result.runId.trimmingCharacters(in: .whitespacesAndNewlines)
            systemMessage = "已接收来自 \(provider) 的 XT 指令：\(projectToken) -> \(action) 已准备执行（run=\(runToken.isEmpty ? "n/a" : runToken)）。"
            voiceText = "\(provider) 的 XT 指令我已经备好了。\(projectToken) 的\(action)马上就能接着跑。"
            title = "🛰️ \(provider) 指令已在 XT 准备"
            body = """
项目=\(projectToken)
动作=\(action)
状态=\(result.status)
运行=\(runToken.isEmpty ? "n/a" : runToken)
审计=\(result.auditRef)
"""
            voiceTrigger = .completed
            voicePriority = .normal
        default:
            let denyToken = result.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let denySummary = annotatedUserVisibleReason(
                raw: denyToken.isEmpty ? result.detail : denyToken,
                display: denyDisplay,
                fallback: "未知原因"
            )
            systemMessage = "来自 \(provider) 的 XT 指令失败闭锁：\(projectToken) -> \(action)。原因：\(denySummary)。"
            voiceText = "\(provider) 的 XT 指令我先按失败闭锁拦下了。\(projectToken) 暂时不能做\(action)。原因：\(denyDisplay)。"
            title = "⛔️ \(provider) 指令在 XT 失败闭锁"
            body = """
项目=\(projectToken)
动作=\(action)
状态=\(result.status)
原因=\(denySummary)
详情=\(result.detail)
审计=\(result.auditRef)
"""
            voiceTrigger = .blocked
            voicePriority = .interrupt
        }

        guard projectVisibleInCurrentSupervisorJurisdiction(projectId: result.projectId) else { return }

        addSystemMessage(
            systemMessage,
            projectId: result.projectId,
            projectName: projectName,
            requiresKnownProjectMatch: true
        )
        _ = speakOperatorChannelXTCommandUpdate(
            text: voiceText,
            trigger: voiceTrigger,
            priority: voicePriority,
            commandId: result.commandId,
            detailToken: result.status == "prepared"
                ? result.runId
                : (result.denyCode.isEmpty ? result.detail : result.denyCode)
        )

        guard backgroundSupervisorServicesEnabled else { return }
        let dedupeKey = "x_terminal_operator_channel_xt_command_\(result.commandId)_\(result.status)_\(result.denyCode)"
        let actionURL = resumeProjectActionURL(projectId: result.projectId)
        guard shouldMirrorNotificationToHub(actionURL: actionURL) else {
            HubIPCClient.removeNotification(dedupeKey: dedupeKey)
            return
        }
        HubIPCClient.pushNotification(
            source: "X-Terminal",
            title: title,
            body: body,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            unread: true
        )
    }

    @discardableResult
    func speakOperatorChannelXTCommandUpdate(
        text: String,
        trigger: SupervisorVoiceJobTrigger,
        priority: SupervisorVoiceJobPriority,
        commandId: String,
        detailToken: String
    ) -> SupervisorSpeechSynthesizer.Outcome {
        let script = conciseVoiceReplyScript(text)
        guard !script.isEmpty else { return .suppressed("empty_script") }
        let detail = detailToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let dedupeKey = "operator-xt-command:\(commandId):\(trigger.rawValue):\(detail.isEmpty ? "none" : detail)"
        let job = SupervisorVoiceTTSJob(
            trigger: trigger,
            priority: priority,
            script: script,
            dedupeKey: dedupeKey
        )
        return dispatchSupervisorVoiceJob(
            job,
            preferences: currentVoicePreferences(),
            source: "operator_xt_command:\(commandId)",
            suppressRapidSameSourceRepeat: true,
            cancelPendingHeartbeat: true
        )
    }

    func operatorChannelXTCommandReasonCode(from error: Error) -> String {
        let upstream = automationExternalTriggerReasonCode(from: error)
        if upstream != "automation_external_trigger_failed_closed" {
            return upstream
        }
        return "operator_channel_xt_command_failed_closed"
    }

    func makeOperatorChannelDeployPlanRequest(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        command: HubIPCClient.OperatorChannelXTCommandItem
    ) throws -> XTAutomationRunRequest {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let recipe = config.activeAutomationRecipe else {
            throw XTAutomationRunCoordinatorError.activeRecipeMissing
        }
        let trustedAutomationStatus = config.trustedAutomationStatus(
            forProjectRoot: ctx.root,
            permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness.current(),
            requiredDeviceToolGroups: recipe.requiredDeviceToolGroups
        )

        let now = Date()
        let commandToken = xtAutomationActionToken(command.commandId, fallback: "operator_command")
        let actionToken = xtAutomationActionToken(command.actionName, fallback: "deploy_plan")
        let requiresGrant = !recipe.grantPolicyRef.isEmpty
        let policyRef = requiresGrant ? recipe.grantPolicyRef : ""
        let routedDeviceToken = xtAutomationActionToken(
            command.resolvedDeviceId,
            fallback: "device"
        )

        return XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "manual/operator_channel/\(actionToken)",
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "hub://operator_channel/\(commandToken)",
                    requiresGrant: requiresGrant,
                    policyRef: policyRef,
                    dedupeKey: "operator_channel|\(project.projectId)|\(command.commandId)"
                )
            ],
            trustedAutomationReady: trustedAutomationStatus.trustedAutomationReady,
            permissionOwnerReady: trustedAutomationStatus.permissionOwnerReady,
            currentOwner: trustedAutomationStatus.permissionOwnerReady ? "XT-TRUSTED" : "XT-L2",
            blockedTaskID: "XT-OP-CHANNEL-\(actionToken.uppercased())",
            operatorConsoleEvidenceRef: "build/reports/xt_operator_channel_\(actionToken)_operator_console.v1.json",
            latestDeltaRef: "build/reports/xt_operator_channel_\(actionToken)_delta.v1.json",
            deliveryRef: "build/reports/xt_operator_channel_\(actionToken)_delivery.v1.json",
            additionalEvidenceRefs: [
                "operator_channel://\(command.commandId)",
                "operator_channel_action://\(actionToken)",
                "operator_channel_route://\(xtAutomationActionToken(command.routeId, fallback: "route"))",
                "operator_channel_device://\(routedDeviceToken)",
                "operator_channel_binding://\(xtAutomationActionToken(command.bindingId, fallback: "binding"))",
                "operator_channel_thread://\(xtAutomationActionToken(command.threadKey, fallback: "thread"))"
            ] + trustedAutomationStatus.missingPrerequisites.map {
                "trusted_automation_issue://\($0)"
            },
            now: now
        )
    }
}
