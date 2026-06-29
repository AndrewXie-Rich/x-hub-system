import Foundation

extension SupervisorManager {
    func heartbeatProjectCreationSummaryText(
        _ presentation: SupervisorProjectCreationStatusPresentation
    ) -> String {
        var lines: [String] = []
        let detail = presentation.detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            lines.append(detail)
        }
        if let metadata = heartbeatProjectCreationSanitizedMetadataText(presentation),
           !metadata.isEmpty {
            lines.append(metadata)
        }
        if let projectName = heartbeatProjectCreationTrimmedText(presentation.projectNameText) {
            lines.append("项目名：\(capped(projectName, maxChars: 40))")
        }
        if let goal = heartbeatProjectCreationTrimmedText(presentation.goalText) {
            lines.append("目标：\(capped(goal, maxChars: 60))")
        }
        if let track = heartbeatProjectCreationTrimmedText(presentation.trackText) {
            lines.append("形态：\(track)")
        }
        if !presentation.recommendedCommands.isEmpty {
            let commands = presentation.recommendedCommands.map { "“\($0)”" }.joined(separator: " / ")
            lines.append("可直接说：\(commands)")
        }
        return SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: lines.joined(separator: "\n"),
            emptyPlaceholder: "（无）"
        )
    }

    func heartbeatProjectCreationWhyImportantText(
        _ presentation: SupervisorProjectCreationStatusPresentation
    ) -> String {
        if heartbeatProjectCreationRepresentsCreatedProjectAwaitingGoal(presentation) {
            return "项目已经先建好，但当前还不能把一个没有明确交付目标的项目当成可继续自动推进。"
        }
        switch presentation.reasonCode {
        case "create_bootstrap_in_progress":
            return "上一轮创建已经在处理中，重复触发只会制造重复执行或重复提醒。"
        case "create_trigger_required_pending_intake",
                "create_trigger_required_recovered_proposal":
            return "当前不会误把“已理解需求”当成“已真正创建项目”。"
        case "create_goal_missing":
            return "当前不会把一句泛化的“建项目/立项”误判成真正可推进的项目创建，避免在项目名和目标都不清楚时误建空壳。"
        default:
            return "项目创建还没进入真正执行，系统会先守住治理边界。"
        }
    }

    func heartbeatProjectCreationWhatChangedText(
        _ presentation: SupervisorProjectCreationStatusPresentation
    ) -> String {
        if heartbeatProjectCreationRepresentsCreatedProjectAwaitingGoal(presentation) {
            return "项目已创建，待补交付目标。"
        }
        switch presentation.reasonCode {
        case "create_bootstrap_in_progress":
            return "上一轮项目创建流程仍在处理中。"
        case "create_trigger_required_pending_intake":
            return "项目创建还差一句触发。"
        case "create_trigger_required_recovered_proposal":
            return "项目创建待确认，系统已恢复最近 proposal。"
        case "create_goal_missing":
            return "项目创建还缺项目名或明确交付目标。"
        default:
            return presentation.headlineText
        }
    }

    func heartbeatProjectCreationActionText(
        _ presentation: SupervisorProjectCreationStatusPresentation
    ) -> String {
        if heartbeatProjectCreationRepresentsCreatedProjectAwaitingGoal(presentation) {
            return "直接说“我要用默认的MVP”，或说“第一版先做成最小可运行版本”"
        }
        switch presentation.reasonCode {
        case "create_bootstrap_in_progress":
            return "等这轮创建完成"
        case "create_trigger_required_pending_intake":
            return "直接说立项，或说创建一个project"
        case "create_trigger_required_recovered_proposal":
            return "直接说立项，或说就按这个建"
        case "create_goal_missing":
            return "直接给项目名，或先补一句要做什么"
        default:
            return "先回到 Supervisor 看当前创建状态"
        }
    }

    func heartbeatProjectCreationRepresentsCreatedProjectAwaitingGoal(
        _ presentation: SupervisorProjectCreationStatusPresentation
    ) -> Bool {
        presentation.reasonCode == "create_goal_missing"
            && heartbeatProjectCreationTrimmedText(presentation.projectNameText) != nil
            && heartbeatProjectCreationTrimmedText(presentation.goalText) == nil
    }

    func heartbeatProjectCreationOperationHint(
        _ presentation: SupervisorProjectCreationStatusPresentation
    ) -> String {
        switch presentation.reasonCode {
        case "create_bootstrap_in_progress":
            return "点开这条提醒会直接进入 Supervisor，并定位到项目创建板，查看这轮建项目流程是否已收口。"
        default:
            return "点开这条提醒会直接进入 Supervisor，并定位到项目创建板，查看当前项目创建状态和下一句建议。"
        }
    }

    func heartbeatProjectCreationSanitizedMetadataText(
        _ presentation: SupervisorProjectCreationStatusPresentation
    ) -> String? {
        let segments = presentation.metadataText
            .split(separator: "·")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { segment in
                let normalized = heartbeatProjectCreationNormalizedMetadataSegment(segment)
                return !normalized.isEmpty
                    && !normalized.hasPrefix(
                        heartbeatProjectCreationNormalizedMetadataSegment("诊断码：")
                    )
                    && !normalized.hasPrefix(
                        heartbeatProjectCreationNormalizedMetadataSegment("diagnostic code:")
                    )
                    && !normalized.hasPrefix(
                        heartbeatProjectCreationNormalizedMetadataSegment("reason code:")
                    )
            }
        let joined = segments.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    func heartbeatProjectCreationTrimmedText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func heartbeatProjectCreationNormalizedMetadataSegment(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}
