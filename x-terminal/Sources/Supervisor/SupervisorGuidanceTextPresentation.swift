import Foundation

enum SupervisorGuidanceTextPresentation {
    private static let knownFieldKeys = [
        "source",
        "contract_kind",
        "summary",
        "verdict",
        "effective_supervisor_tier",
        "effective_work_order_depth",
        "work_order_ref",
        "actions",
        "recommended_actions",
        "next_safe_action",
        "repair_action",
        "repair_focus",
        "instruction",
        "ui_review_ref",
        "ui_review_review_id",
        "ui_review_verdict",
        "ui_review_issue_codes",
        "ui_review_summary",
        "skill_result_summary",
        "current_state",
        "next_step",
        "blocker",
        "primary_blocker",
        "trigger",
        "review_level"
    ]

    static func summary(
        _ guidanceText: String,
        maxChars: Int
    ) -> String {
        let stripped = normalizedText(guidanceText)
        let fields = parsedFields(in: stripped)
        let summary = preferredSummaryText(fields: fields, rawText: stripped) ?? stripped
        let normalized = normalizedDisplayText(summary)
        if normalized.isEmpty {
            return capped(normalizedDisplayText(stripped), maxChars: maxChars)
        }
        return capped(normalized, maxChars: maxChars)
    }

    static func normalizedText(
        _ guidanceText: String
    ) -> String {
        strippedAckWrapper(guidanceText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fields(
        _ guidanceText: String
    ) -> [String: String] {
        parsedFields(in: normalizedText(guidanceText))
    }

    static func fieldValue(
        _ key: String,
        in guidanceText: String
    ) -> String? {
        fields(guidanceText)[key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    static func actionDisplayText(
        _ raw: String?,
        includeRawToken: Bool = false
    ) -> String? {
        guard let raw else { return nil }
        let trimmed = normalizedDisplayText(raw)
        guard !trimmed.isEmpty else { return nil }

        let display = humanizedActionToken(trimmed)
        guard includeRawToken else { return display }
        guard display != trimmed else { return display }
        return "\(display)（\(trimmed)）"
    }

    static func actionsDisplayText(
        _ rawActions: [String]
    ) -> String? {
        let items = rawActions
            .compactMap { actionDisplayText($0) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        return items.joined(separator: " | ")
    }

    private static func strippedAckWrapper(
        _ guidanceText: String
    ) -> String {
        var stripped = guidanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return stripped }

        for _ in 0..<4 {
            guard let wrapperRange = stripped.range(of: "这条指导") else { break }
            let suffix = stripped[wrapperRange.upperBound...]
            guard let delimiter = suffix.firstIndex(where: { $0 == "：" || $0 == ":" }) else { break }
            let candidate = String(
                suffix[suffix.index(after: delimiter)...]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty, candidate.count < stripped.count else { break }
            stripped = candidate
        }

        return stripped
    }

    private static func parsedFields(
        in text: String
    ) -> [String: String] {
        guard !text.isEmpty else { return [:] }
        let tokens = tokenizedFields(in: text)
        guard !tokens.isEmpty else { return [:] }

        var fields: [String: String] = [:]
        for (offset, token) in tokens.enumerated() {
            let valueStart = token.range.upperBound
            let valueEnd = offset + 1 < tokens.count
                ? tokens[offset + 1].range.lowerBound
                : text.endIndex
            let value = normalizedDisplayText(String(text[valueStart..<valueEnd]))
            guard !value.isEmpty else { continue }
            fields[token.key] = value
        }
        return fields
    }

    private static func firstPlainLine(
        in text: String
    ) -> String? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines {
            if tokenRange(in: line, from: line.startIndex)?.range.lowerBound == line.startIndex {
                continue
            }
            return line
        }
        return nil
    }

    private static func preferredSummaryText(
        fields: [String: String],
        rawText: String
    ) -> String? {
        let prioritizedFieldKeys = [
            "summary",
            "ui_review_summary",
            "instruction",
            "skill_result_summary",
            "current_state",
            "next_step",
            "repair_action",
            "next_safe_action",
            "recommended_actions",
            "actions"
        ]

        for key in prioritizedFieldKeys {
            guard let value = humanizedSummaryValue(
                for: key,
                raw: fields[key]
            ) else {
                continue
            }
            return value
        }

        return firstPlainLine(in: rawText)
    }

    private static func tokenizedFields(
        in text: String
    ) -> [(key: String, range: Range<String.Index>)] {
        var tokens: [(key: String, range: Range<String.Index>)] = []
        var cursor = text.startIndex

        while let token = tokenRange(in: text, from: cursor) {
            tokens.append(token)
            cursor = token.range.upperBound
        }

        return tokens
    }

    private static func tokenRange(
        in text: String,
        from startIndex: String.Index
    ) -> (key: String, range: Range<String.Index>)? {
        guard startIndex < text.endIndex else { return nil }

        var bestMatch: (key: String, range: Range<String.Index>)?
        let searchRange = startIndex..<text.endIndex

        for key in knownFieldKeys {
            guard let range = text.range(
                of: "\(key)=",
                options: [.caseInsensitive],
                range: searchRange
            ) else {
                continue
            }

            if let currentBest = bestMatch {
                if range.lowerBound < currentBest.range.lowerBound {
                    bestMatch = (key, range)
                } else if range.lowerBound == currentBest.range.lowerBound,
                          key.count > currentBest.key.count {
                    bestMatch = (key, range)
                }
            } else {
                bestMatch = (key, range)
            }
        }

        return bestMatch
    }

    private static func normalizedDisplayText(
        _ text: String
    ) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func humanizedSummaryValue(
        for key: String,
        raw: String?
    ) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        switch key {
        case "recommended_actions", "actions":
            return actionsDisplayText(
                trimmed
                .split(separator: "|")
                .map(String.init)
            )
        case "next_safe_action", "repair_action":
            return actionDisplayText(trimmed)
        default:
            return normalizedDisplayText(trimmed)
        }
    }

    private static func humanizedActionToken(
        _ raw: String
    ) -> String {
        let trimmed = normalizedDisplayText(raw)
        guard !trimmed.isEmpty else { return "" }

        let normalizedToken = trimmed
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalizedToken {
        case "open_hub_grants":
            return "打开 Hub 授权面板"
        case "repair_before_execution":
            return "先完成当前修复，再继续执行"
        case "inspect_incident_and_replan":
            return "先检查当前异常，再决定是否重规划"
        case "apply_supervisor_replan":
            return "先按当前重规划处理"
        case "wait_for_grant":
            return "先等待授权处理完成"
        case "wait_grant":
            return "等待授权结果"
        case "hold_for_manual_review":
            return "先停在当前节点，等待人工确认"
        case "clarify_with_user":
            return "先向用户确认"
        case "replan_before_execution":
            return "先重规划，再继续执行"
        case "open_ui_review":
            return "打开 UI 审查"
        case "open_candidate_review_board":
            return "打开候选记忆审查面板"
        case "stage_to_review":
            return "转入审查"
        case "continue_review":
            return "继续审查"
        case "follow_writeback_boundary":
            return "沿写回边界继续推进"
        case "inspect_rejection":
            return "检查退回原因"
        case "verify_promotion":
            return "确认提升结果"
        case "pause_lane":
            return "暂停当前泳道"
        case "notify_user":
            return "通知用户"
        case "approve_hub_grant":
            return "处理当前 Hub 授权"
        case "open_diagnostics_and_reassemble_hidden_project_memory":
            return "打开诊断并重建 hidden project 记忆"
        default:
            return trimmed.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func capped(
        _ text: String,
        maxChars: Int
    ) -> String {
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
