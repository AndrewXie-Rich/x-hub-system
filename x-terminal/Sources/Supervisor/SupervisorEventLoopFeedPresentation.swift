import Foundation

enum SupervisorEventLoopTone: String, Equatable {
    case neutral
    case info
    case running
    case success
    case warning
}

struct SupervisorEventLoopRowPresentation: Equatable, Identifiable {
    var id: String
    var triggerLabel: String
    var projectLabel: String
    var statusLabel: String
    var statusTone: SupervisorEventLoopTone
    var triggerText: String?
    var resultText: String?
    var blockedSummaryText: String?
    var governanceTruthText: String?
    var governanceReasonText: String?
    var policyReasonText: String?
    var policyText: String?
    var contractText: String?
    var nextSafeActionText: String?
    var reasonText: String
    var dedupeKeyText: String
    var ageText: String
    var actionDescriptors: [SupervisorCardActionDescriptor]
}

struct SupervisorEventLoopBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var emptyStateText: String?
    var rows: [SupervisorEventLoopRowPresentation]

    var isEmpty: Bool {
        rows.isEmpty
    }
}

enum SupervisorEventLoopFeedPresentation {
    static func board(
        items: [SupervisorManager.SupervisorEventLoopActivity],
        recentSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity] = [],
        statusLine: String,
        limit: Int = 6,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> SupervisorEventLoopBoardPresentation {
        let displayedItems = Array(items.suffix(limit).reversed())
        return SupervisorEventLoopBoardPresentation(
            iconName: displayedItems.isEmpty ? "arrow.triangle.branch" : "arrow.triangle.branch.fill",
            iconTone: displayedItems.isEmpty ? .neutral : .accent,
            title: "自动跟进记录：\(items.count)",
            statusLine: statusLine,
            emptyStateText: displayedItems.isEmpty
                ? "当前还没有自动跟进事件。技能回调、授权处理、心跳或异常触发后，这里会显示最近的事件循环记录。"
                : nil,
            rows: displayedItems.map { item in
                row(
                    item,
                    relatedSkillActivity: relatedSkillActivity(
                        for: item,
                        recentSkillActivities: recentSkillActivities
                    ),
                    now: now
                )
            }
        )
    }

    static func row(
        _ item: SupervisorManager.SupervisorEventLoopActivity,
        relatedSkillActivity: SupervisorManager.SupervisorRecentSkillActivity? = nil,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> SupervisorEventLoopRowPresentation {
        let projectLabel = normalizedScalar(item.projectName).isEmpty
            ? (normalizedScalar(item.projectId).isEmpty ? "全局" : normalizedScalar(item.projectId))
            : normalizedScalar(item.projectName)
        let action = SupervisorEventLoopActionPresentation.action(for: item)
        let contract = guidanceContract(item)
        let blockedSummaryText = firstNonEmpty([
            nonEmpty(item.blockedSummary).map { "阻塞说明： \($0)" },
            relatedSkillActivity.flatMap(SupervisorSkillActivityPresentation.blockedSummaryLine(for:))
        ])
        let governanceTruthText = firstNonEmpty([
            nonEmpty(item.governanceTruth).map(XTGovernanceTruthPresentation.displayText),
            relatedSkillActivity.flatMap(SupervisorSkillActivityPresentation.displayGovernanceTruthLine(for:))
        ])
        let governanceReasonText = relatedSkillActivity
            .flatMap(SupervisorSkillActivityPresentation.governanceReasonText(for:))
            .map { "治理原因： \($0)" }
        let reasonText = userVisibleReasonText(item.reasonCode)
        return SupervisorEventLoopRowPresentation(
            id: item.id,
            triggerLabel: triggerLabel(item.triggerSource),
            projectLabel: projectLabel,
            statusLabel: statusLabel(item.status),
            statusTone: statusTone(item.status),
            triggerText: nonEmpty(item.triggerSummary).map { "触发：\($0)" },
            resultText: nonEmpty(item.resultSummary).map { "结果：\($0)" },
            blockedSummaryText: blockedSummaryText,
            governanceTruthText: governanceTruthText,
            governanceReasonText: governanceReasonText,
            policyReasonText: nonEmpty(item.policyReason).map { "策略原因： \($0)" },
            policyText: nonEmpty(item.policySummary),
            contractText: contract.map(SupervisorGuidanceContractLinePresentation.contractLine),
            nextSafeActionText: contract.map(SupervisorGuidanceContractLinePresentation.nextSafeActionLine),
            reasonText: "原因：\(reasonText)",
            dedupeKeyText: "去重键：\(item.dedupeKey)",
            ageText: relativeTimeText(item.updatedAt, now: now),
            actionDescriptors: SupervisorCardActionResolver.eventLoopActions(item, action: action)
        )
    }

    static func triggerLabel(_ raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "heartbeat":
            return "心跳"
        case "skill_callback":
            return "技能回调"
        case "official_skills_channel":
            return "官方技能"
        case "guidance_ack":
            return "指导确认"
        case "automation_safe_point":
            return "安全点"
        case "incident":
            return "异常事件"
        case "external_trigger_ingress":
            return "外部触发"
        case "grant_resolution":
            return "授权处理"
        case "approval_resolution":
            return "审批处理"
        default:
            return "用户轮次"
        }
    }

    static func statusLabel(_ raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "queued":
            return "排队中"
        case "running":
            return "进行中"
        case "completed":
            return "已完成"
        case "completed_empty":
            return "无动作"
        case "deduped":
            return "已去重"
        default:
            return raw
        }
    }

    static func statusTone(_ raw: String) -> SupervisorEventLoopTone {
        switch normalizedScalar(raw).lowercased() {
        case "queued":
            return .info
        case "running":
            return .running
        case "completed":
            return .success
        case "completed_empty":
            return .neutral
        case "deduped":
            return .warning
        default:
            return .neutral
        }
    }

    static func relativeTimeText(
        _ timestamp: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> String {
        let elapsed = max(0, Int(now - timestamp))
        if elapsed < 90 { return "刚刚" }
        let mins = elapsed / 60
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }

    static func guidanceContract(
        _ item: SupervisorManager.SupervisorEventLoopActivity
    ) -> SupervisorGuidanceContractSummary? {
        let policyTokens = policyTokenMap(item.policySummary)
        let nextSafeAction = nonEmpty(policyTokens["next"] ?? "")
        let repairToken = nonEmpty(policyTokens["repair"] ?? "")
        let reasonCode = normalizedScalar(item.reasonCode)
        let reviewSummary = nonEmpty(policyTokens["review"] ?? "")
        let contractKind: SupervisorGuidanceContractSummary.Kind?
        if nextSafeAction == "open_ui_review" || repairToken != nil {
            contractKind = .uiReviewRepair
        } else if nextSafeAction == "open_hub_grants"
            || (reasonCode.contains("grant") && reviewSummary != nil) {
            contractKind = .grantResolution
        } else if reasonCode.contains("instruction") || nextSafeAction == "clarify_with_user" {
            contractKind = .awaitingInstruction
        } else if reasonCode.contains("incident") || reasonCode.contains("runtime_error") {
            contractKind = .incidentRecovery
        } else if nextSafeAction != nil {
            contractKind = .supervisorReplan
        } else {
            contractKind = nil
        }
        guard let contractKind else { return nil }

        let summary = firstNonEmpty([
            nonEmpty(item.resultSummary),
            nonEmpty(item.triggerSummary),
            reviewSummary
        ]) ?? ""
        let recommendedActions = [
            nonEmpty(policyTokens["action"] ?? ""),
            nonEmpty(policyTokens["actions"] ?? "")
        ]
        .compactMap { $0 }
        .flatMap { raw in
            raw.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if contractKind == .uiReviewRepair {
            let (repairAction, repairFocus) = repairToken.map(repairSummaryParts) ?? (nil, nil)
            return SupervisorGuidanceContractSummary(
                kind: .uiReviewRepair,
                trigger: triggerLabel(item.triggerSource),
                reviewLevel: nonEmpty(policyTokens["tier"] ?? "") ?? "",
                verdict: reviewSummary ?? "",
                summary: summary,
                primaryBlocker: "",
                currentState: "",
                nextStep: "",
                nextSafeAction: nextSafeAction ?? inferredNextSafeAction(for: .uiReviewRepair),
                recommendedActions: recommendedActions,
                workOrderRef: nonEmpty(policyTokens["work_order_ref"] ?? "") ?? "",
                effectiveSupervisorTier: nonEmpty(policyTokens["tier"] ?? "") ?? "",
                effectiveWorkOrderDepth: nonEmpty(policyTokens["depth"] ?? "") ?? "",
                uiReviewRepair: SupervisorGuidanceContractSummary.UIReviewRepairDetails(
                    instruction: "",
                    repairAction: repairAction ?? "",
                    repairFocus: repairFocus ?? "",
                    nextSafeAction: nextSafeAction ?? inferredNextSafeAction(for: .uiReviewRepair),
                    uiReviewRef: nonEmpty(policyTokens["ui_review_ref"] ?? "") ?? "",
                    uiReviewReviewId: nonEmpty(policyTokens["ui_review_review_id"] ?? "") ?? "",
                    uiReviewVerdict: nonEmpty(policyTokens["ui_review_verdict"] ?? "") ?? "",
                    uiReviewIssueCodes: nonEmpty(policyTokens["ui_review_issue_codes"] ?? "") ?? "",
                    uiReviewSummary: nonEmpty(policyTokens["ui_review_summary"] ?? "") ?? "",
                    skillResultSummary: nonEmpty(item.resultSummary) ?? ""
                )
            )
        }

        return SupervisorGuidanceContractSummary(
            kind: contractKind,
            trigger: triggerLabel(item.triggerSource),
            reviewLevel: nonEmpty(policyTokens["tier"] ?? "") ?? "",
            verdict: reviewSummary ?? "",
            summary: summary,
            primaryBlocker: reasonCode,
            currentState: "",
            nextStep: "",
            nextSafeAction: nextSafeAction ?? inferredNextSafeAction(for: contractKind),
            recommendedActions: recommendedActions,
            workOrderRef: nonEmpty(policyTokens["work_order_ref"] ?? "") ?? "",
            effectiveSupervisorTier: nonEmpty(policyTokens["tier"] ?? "") ?? "",
            effectiveWorkOrderDepth: nonEmpty(policyTokens["depth"] ?? "") ?? ""
        )
    }

    private static func relatedSkillActivity(
        for item: SupervisorManager.SupervisorEventLoopActivity,
        recentSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    ) -> SupervisorManager.SupervisorRecentSkillActivity? {
        guard let requestId = SupervisorEventLoopActionPresentation.requestId(for: item) else {
            return nil
        }
        return SupervisorFocusPresentation.matchingRecentSkillActivity(
            projectId: normalizedScalar(item.projectId),
            requestId: requestId,
            recentActivities: recentSkillActivities
        )
    }

    private static func policyTokenMap(_ raw: String) -> [String: String] {
        let tokens = raw
            .split(separator: "·")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var out: [String: String] = [:]
        for token in tokens {
            guard let idx = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(token[token.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    private static func repairSummaryParts(
        _ raw: String
    ) -> (action: String?, focus: String?) {
        let trimmed = normalizedScalar(raw)
        guard !trimmed.isEmpty else { return (nil, nil) }
        if let idx = trimmed.firstIndex(of: "@") {
            let action = String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let focus = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                action.isEmpty ? nil : action,
                focus.isEmpty ? nil : focus
            )
        }
        return (trimmed, nil)
    }

    private static func normalizedScalar(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ raw: String) -> String? {
        let trimmed = normalizedScalar(raw)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func userVisibleReasonText(_ raw: String) -> String {
        let trimmed = normalizedScalar(raw)
        guard !trimmed.isEmpty else { return raw }
        return XTRouteTruthPresentation.userVisibleReasonText(trimmed) ?? trimmed
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let value {
                return value
            }
        }
        return nil
    }

    private static func inferredNextSafeAction(
        for kind: SupervisorGuidanceContractSummary.Kind
    ) -> String {
        switch kind {
        case .uiReviewRepair:
            return "repair_before_execution"
        case .grantResolution:
            return "open_hub_grants"
        case .awaitingInstruction:
            return "clarify_with_user"
        case .incidentRecovery:
            return "inspect_incident_and_replan"
        case .supervisorReplan:
            return "apply_supervisor_replan"
        }
    }
}
