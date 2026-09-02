import Foundation

extension SupervisorManager {
    func focusedSupervisorProjectRetrievalBlock(
        selection: SupervisorFocusedProjectSelection?,
        userMessage: String,
        servingProfile: XTMemoryServingProfile?
    ) async -> String {
        guard let selection,
              shouldRequestSupervisorProjectMemoryRetrieval(
                userMessage: userMessage,
                servingProfile: servingProfile
              ) else {
            return ""
        }

        let project = selection.project
        let ctx = supervisorMemoryContext(for: project)
        let response = await HubIPCClient.requestProjectMemoryRetrieval(
            requesterRole: .supervisor,
            useMode: .supervisorOrchestration,
            projectId: project.projectId,
            projectRoot: ctx.root.path,
            displayName: project.displayName,
            latestUser: userMessage,
            reason: "supervisor_focused_project_review",
            requestedKinds: requestedSupervisorProjectMemoryRetrievalKinds(
                userText: userMessage,
                servingProfile: servingProfile
            ),
            explicitRefs: [],
            maxSnippets: supervisorProjectMemoryRetrievalMaxSnippets(servingProfile: servingProfile),
            maxSnippetChars: supervisorProjectMemoryRetrievalMaxSnippetChars(servingProfile: servingProfile),
            timeoutSec: 1.0
        )
        return formattedFocusedSupervisorProjectRetrievalBlock(
            selection: selection,
            response: response,
            servingProfile: servingProfile
        )
    }

    func formattedFocusedSupervisorProjectRetrievalBlock(
        selection: SupervisorFocusedProjectSelection,
        response: HubIPCClient.MemoryRetrievalResponsePayload?,
        servingProfile: XTMemoryServingProfile?
    ) -> String {
        let project = selection.project
        guard let response else {
            return """
focus_project=\(project.displayName) (\(project.projectId))
focus_source=\(selection.source)
status=unavailable
reason_code=no_response
"""
        }

        let items = response.snippets
            .prefix(supervisorProjectMemoryRetrievalMaxSnippets(servingProfile: servingProfile))
            .map { snippet in
                """
                - [\(snippet.sourceKind)] \(sanitizeSupervisorPromptIdentifiers(capped(snippet.title, maxChars: 120)))
                  ref: \(sanitizeSupervisorPromptIdentifiers(capped(snippet.ref, maxChars: 180)))
                  \(sanitizeSupervisorPromptIdentifiers(capped(snippet.text, maxChars: 220)))
                """
            }
            .joined(separator: "\n")
        let trimmedItems = items.trimmingCharacters(in: .whitespacesAndNewlines)
        let denyCode = response.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reasonCode = response.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = response.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedStatus = response.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let status: String
        if normalizedStatus == "error" {
            status = "unavailable"
        } else if normalizedStatus == "denied" || !denyCode.isEmpty {
            status = "denied"
        } else if normalizedStatus == "truncated" || response.truncatedItems > 0 {
            status = "truncated"
        } else if trimmedItems.isEmpty {
            status = "empty"
        } else {
            status = "ok"
        }

        var lines = [
            "focus_project=\(project.displayName) (\(project.projectId))",
            "focus_source=\(selection.source)",
            "status=\(status)",
            "audit_ref=\(response.auditRef)",
            "retrieval_source=\(response.source)"
        ]
        if let requestId = response.requestId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestId.isEmpty {
            lines.append("request_id=\(requestId)")
        }
        if let resolvedScope = response.resolvedScope?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolvedScope.isEmpty {
            lines.append("resolved_scope=\(resolvedScope)")
        }
        if !reasonCode.isEmpty {
            lines.append("reason_code=\(reasonCode)")
        }
        if !detail.isEmpty {
            lines.append("detail=\(sanitizeSupervisorPromptIdentifiers(capped(detail, maxChars: 240)))")
        }
        if !denyCode.isEmpty {
            lines.append("deny_code=\(denyCode)")
        }
        if response.truncatedItems > 0 {
            lines.append("truncated_items=\(response.truncatedItems)")
        }
        if response.redactedItems > 0 {
            lines.append("redacted_items=\(response.redactedItems)")
        }
        if !trimmedItems.isEmpty {
            lines.append(trimmedItems)
        }
        return lines.joined(separator: "\n")
    }

    func shouldRequestSupervisorProjectMemoryRetrieval(
        userMessage: String,
        servingProfile: XTMemoryServingProfile?
    ) -> Bool {
        if let servingProfile, servingProfile.rank >= XTMemoryServingProfile.m2PlanReview.rank {
            return true
        }
        let normalized = userMessage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let keywords = [
            "审查", "审阅", "review", "上下文", "记忆", "执行方案", "重构建议",
            "项目结构", "架构", "技术栈", "历史决策", "blocker", "spec", "decision"
        ]
        return keywords.contains { normalized.contains($0) }
    }

    func requestedSupervisorProjectMemoryRetrievalKinds(
        userText: String,
        servingProfile: XTMemoryServingProfile?
    ) -> [String] {
        let normalized = userText.lowercased()
        var kinds = ["project_spec_capsule", "decision_track", "background_preferences"]
        if normalized.contains("blocker")
            || normalized.contains("blocked")
            || normalized.contains("retry")
            || normalized.contains("recover")
            || normalized.contains("recovery")
            || normalized.contains("checkpoint")
            || normalized.contains("verify")
            || normalized.contains("verification")
            || normalized.contains("阻塞")
            || normalized.contains("卡住")
            || normalized.contains("重试")
            || normalized.contains("恢复")
            || normalized.contains("检查点")
            || normalized.contains("验证") {
            kinds.append("automation_execution_report")
            kinds.append("automation_checkpoint")
            kinds.append("automation_retry_package")
            kinds.append("heartbeat_projection")
            kinds.append("guidance_injection")
        }
        if normalized.contains("guidance")
            || normalized.contains("review")
            || normalized.contains("ack")
            || normalized.contains("safe point")
            || normalized.contains("指导")
            || normalized.contains("复盘")
            || normalized.contains("审查")
            || normalized.contains("确认")
            || normalized.contains("安全点") {
            kinds.append("guidance_injection")
            kinds.append("automation_execution_report")
        }
        if normalized.contains("heartbeat")
            || normalized.contains("cadence")
            || normalized.contains("anomaly")
            || normalized.contains("risk")
            || normalized.contains("心跳")
            || normalized.contains("节奏")
            || normalized.contains("异常")
            || normalized.contains("风险") {
            kinds.append("heartbeat_projection")
            kinds.append("automation_retry_package")
        }
        if normalized.contains("历史")
            || normalized.contains("上下文")
            || normalized.contains("记忆")
            || normalized.contains("history")
            || normalized.contains("context") {
            kinds.append("recent_context")
        }
        if normalized.contains("技术栈")
            || normalized.contains("tech")
            || normalized.contains("stack")
            || normalized.contains("spec")
            || normalized.contains("架构") {
            kinds.append("canonical_memory")
        }
        if let servingProfile, servingProfile.rank >= XTMemoryServingProfile.m3DeepDive.rank {
            kinds.append("recent_context")
            kinds.append("canonical_memory")
            kinds.append("automation_execution_report")
            kinds.append("automation_checkpoint")
            kinds.append("automation_retry_package")
            kinds.append("heartbeat_projection")
            kinds.append("guidance_injection")
        }
        return Array(NSOrderedSet(array: kinds)) as? [String] ?? kinds
    }

    func supervisorProjectMemoryRetrievalMaxSnippets(
        servingProfile: XTMemoryServingProfile?
    ) -> Int {
        switch servingProfile {
        case .m3DeepDive, .m4FullScan:
            return supervisorDeepDiveRetrievalMaxSnippets
        default:
            return supervisorReviewRetrievalMaxSnippets
        }
    }

    func supervisorProjectMemoryRetrievalMaxSnippetChars(
        servingProfile: XTMemoryServingProfile?
    ) -> Int {
        switch servingProfile {
        case .m3DeepDive, .m4FullScan:
            return supervisorDeepDiveRetrievalMaxSnippetChars
        default:
            return supervisorReviewRetrievalMaxSnippetChars
        }
    }
}
