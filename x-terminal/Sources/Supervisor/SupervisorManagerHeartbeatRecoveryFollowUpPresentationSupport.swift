import Foundation

extension SupervisorManager {
    func heartbeatRecoveryFollowUpNextStepLine(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> String {
        let detail = capped(signal.detailLine, maxChars: 72)
        let priorityReasonSuffix = heartbeatRecoveryFollowUpNextStepPriorityReason(signal).map {
            "；\($0)"
        } ?? ""
        let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
        let advice: String
        switch signal.action {
        case .requestGrantFollowUp:
            advice = "建议先打开授权处理"
        case .replayFollowUp:
            advice = "建议先打开项目查看 resume / replan"
        case .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            advice = "建议先打开项目查看恢复状态"
        }
        return "Recovery 跟进：\(signal.projectName) — \(detail)\(priorityReasonSuffix)；\(advice)\(actionSuffix)"
    }

    func heartbeatRecoveryFollowUpNextStepPriorityReason(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> String? {
        guard let reason = heartbeatRecoveryFollowUpPriorityReasonText(signal) else {
            return nil
        }
        return "为什么先跟进：\(capped(reason, maxChars: 40))"
    }

    func heartbeatRecoveryFollowUpPriorityReasonText(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> String? {
        guard var reason = signal.priorityReasonLine?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else {
            return nil
        }
        reason = reason.replacingOccurrences(
            of: #"^为什么先跟进[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        reason = reason.replacingOccurrences(
            of: #"^为什么先看[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        reason = reason.replacingOccurrences(
            of: #"（优先级：.*?）$"#,
            with: "",
            options: .regularExpression
        )
        reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? nil : reason
    }

    func heartbeatRecoveryFollowUpNotificationTitle(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> String {
        switch signal.action {
        case .requestGrantFollowUp:
            return "🛂 Supervisor 心跳：授权恢复跟进待处理"
        case .replayFollowUp:
            return "♻️ Supervisor 心跳：续跑恢复跟进已激活"
        case .resumeRun:
            return "♻️ Supervisor 心跳：恢复执行已激活"
        case .repairRoute:
            return "🛠️ Supervisor 心跳：路由恢复跟进已激活"
        case .rehydrateContext:
            return "🧠 Supervisor 心跳：上下文恢复跟进已激活"
        case .queueStrategicReview:
            return "🧭 Supervisor 心跳：恢复复盘已排队"
        case .holdForUser:
            return "⏸️ Supervisor 心跳：恢复流程等待输入"
        }
    }

    func heartbeatRecoveryFollowUpWhyImportantText(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> String {
        switch signal.action {
        case .requestGrantFollowUp:
            return "系统已判断当前需要先补齐 grant / 授权跟进，不能把状态当成正常推进。"
        case .replayFollowUp:
            return "系统已判断当前要先修复挂起的 follow-up / 续跑链，不能把状态当成正常推进。"
        case .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            return "系统已判断需要恢复或补救动作，不能把当前状态当成正常推进。"
        }
    }

    func heartbeatRecoveryFollowUpDigestNextStep(
        _ signal: HeartbeatRecoveryFollowUpSignal
    ) -> String {
        let detail = signal.detailLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            return detail
        }

        switch signal.action {
        case .requestGrantFollowUp:
            return "系统会先发起所需 grant 跟进，待放行后再继续恢复执行。"
        case .replayFollowUp:
            return "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。"
        case .resumeRun:
            return "系统会先尝试受控恢复执行，再观察 lane 活性是否恢复。"
        case .repairRoute:
            return "系统会先修复当前 route / dispatch 健康，再尝试恢复执行。"
        case .rehydrateContext:
            return "系统会先重建项目上下文，再继续下一次执行尝试。"
        case .queueStrategicReview:
            return "系统会先排队一次治理复盘，再确认是否继续自动推进。"
        case .holdForUser:
            return "系统会先停在当前边界，等待你或 operator 补齐缺失输入。"
        }
    }

    func heartbeatRecoveryFollowUpOperationHint(
        _ signal: HeartbeatRecoveryFollowUpSignal,
        authorizationDestination: HeartbeatAuthorizationNotificationDestination?
    ) -> String {
        switch signal.action {
        case .requestGrantFollowUp:
            return authorizationDestination?.operationHint
                ?? "点开这条提醒会直接进入项目授权处理，优先确认缺少的 grant / capability。"
        case .replayFollowUp:
            return "点开这条提醒会直接进入项目聊天，先看当前 resume / replan 和 follow-up 恢复状态。"
        case .resumeRun:
            return "点开这条提醒会直接进入项目聊天，先看当前恢复执行进度。"
        case .repairRoute:
            return "点开这条提醒会直接进入项目聊天，先确认 route / dispatch 的修复状态。"
        case .rehydrateContext:
            return "点开这条提醒会直接进入项目聊天，先确认上下文重建是否完成。"
        case .queueStrategicReview:
            return "点开这条提醒会直接进入项目聊天，先查看恢复复盘的排队状态和后续 guidance。"
        case .holdForUser:
            return "点开这条提醒会直接进入项目聊天，先补齐当前恢复流程缺失的输入。"
        }
    }

    func heartbeatRecoveryFollowUpPriorityRecommendation(
        _ signal: HeartbeatRecoveryFollowUpSignal,
        authorizationDestination: HeartbeatAuthorizationNotificationDestination?,
        permissionHighlight: String?
    ) -> String {
        switch signal.action {
        case .requestGrantFollowUp:
            return permissionHighlight
                ?? authorizationDestination?.defaultRecommendation
                ?? "打开项目并处理缺少的授权后，再继续恢复执行。"
        case .replayFollowUp:
            return "打开项目并确认当前 resume / replan 与 follow-up 续跑链，再看是否已恢复推进。"
        case .resumeRun:
            return "打开项目并确认当前恢复执行是否已回到可继续状态。"
        case .repairRoute:
            return "打开项目并优先确认 route / dispatch 修复结果，再决定是否继续。"
        case .rehydrateContext:
            return "打开项目并确认上下文重建结果，再继续下一次执行尝试。"
        case .queueStrategicReview:
            return "打开项目并先查看恢复复盘排队结果，再决定是否继续自动推进。"
        case .holdForUser:
            return "打开项目并补齐当前恢复流程缺失的输入。"
        }
    }
}
