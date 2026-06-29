import Foundation

extension SupervisorManager {
    func paidModelAccessResolution(from error: Error) -> XTPaidModelAccessResolution? {
        guard let hubError = error as? HubAIError,
              case let .responseDoneNotOk(failure) = hubError else {
            return nil
        }
        return XTPaidModelAccessExplainability.resolve(
            rawReasonCode: failure.reason,
            deviceName: failure.deviceName,
            modelId: failure.modelId ?? "unknown_model"
        )
    }

    func paidModelPolicyDisplayLabel(
        _ raw: String?,
        trustProfilePresent: Bool,
        resolution: XTPaidModelAccessResolution
    ) -> String {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "all_paid_models":
            return "全部付费模型"
        case "custom_selected_models":
            return "指定付费模型"
        case "off":
            return "已关闭"
        case "legacy_grant":
            return "旧版授权"
        default:
            if !trustProfilePresent || resolution.state == .legacyGrantFlowRequired {
                return "旧版授权"
            }
            return "未回报"
        }
    }

    func primaryRepairStep(for resolution: XTPaidModelAccessResolution) -> String {
        switch resolution.state {
        case .allowedByDevicePolicy:
            return "当前设备策略已允许该模型，直接重试当前请求即可。"
        case .blockedPaidModelDisabled:
            return "到 X-Hub → Pairing & Device Trust 为这台设备开启 paid model 访问。"
        case .blockedModelNotInCustomAllowlist:
            return "到 X-Hub → Pairing & Device Trust 把 \(resolution.modelId) 加入该设备 allowlist。"
        case .blockedDailyBudgetExceeded:
            return "到 X-Hub → Models & Paid Access 提升 daily token limit，或等待下一配额窗口。"
        case .blockedSingleRequestBudgetExceeded:
            return "缩小这次请求，或到 X-Hub → Models & Paid Access 提升 single request token limit。"
        case .legacyGrantFlowRequired:
            return "临时放行：到 X-Hub → Grants & Permissions 完成一次 legacy grant。"
        }
    }

    func secondaryRepairStep(for resolution: XTPaidModelAccessResolution) -> String {
        switch resolution.state {
        case .allowedByDevicePolicy:
            return "如果仍失败，改查 Hub 当前模型库存与桥接连通性，而不是重复授权。"
        case .blockedPaidModelDisabled, .blockedModelNotInCustomAllowlist:
            return "如果暂时不改设备策略，可先切到本地模型或已授权模型后再试。"
        case .blockedDailyBudgetExceeded, .blockedSingleRequestBudgetExceeded:
            return "如果暂时不改预算，可先切到本地模型或缩短上下文后再试。"
        case .legacyGrantFlowRequired:
            return "长期修复：到 X-Hub → Pairing & Device Trust 把这台设备升级到新 trust profile。"
        }
    }

    func conciseSupervisorFailureReason(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return firstNonEmptyLine(in: localized)
        }
        let fallback = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "未知错误" : firstNonEmptyLine(in: fallback)
    }

    func firstNonEmptyLine(in text: String) -> String {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                return line
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func firstNonEmptyLine(items: [String]) -> String {
        for item in items {
            let line = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                return line
            }
        }
        return ""
    }

    func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let cleaned = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
    }

    func firstNonEmptyValue(_ preferred: String, _ fallback: String?) -> String {
        let primary = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty {
            return primary
        }
        return (fallback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func firstMeaningfulDigestValue(
        _ values: [String?],
        treatContinueCurrentTaskAsPlaceholder: Bool = false,
        treatNoValueAsPlaceholder: Bool = true
    ) -> String {
        for raw in values {
            let cleaned = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !isDigestPlaceholder(
                cleaned,
                treatContinueCurrentTaskAsPlaceholder: treatContinueCurrentTaskAsPlaceholder,
                treatNoValueAsPlaceholder: treatNoValueAsPlaceholder
            ) {
                return cleaned
            }
        }
        return ""
    }

    func isDigestPlaceholder(
        _ text: String,
        treatContinueCurrentTaskAsPlaceholder: Bool = false,
        treatNoValueAsPlaceholder: Bool = true
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        let lowered = trimmed.lowercased()
        var placeholders = Set(["(暂无)", "(none)", "none", "n/a", "na"].map { $0.lowercased() })
        if treatNoValueAsPlaceholder {
            placeholders.formUnion(["(无)", "无"].map { $0.lowercased() })
        }
        if treatContinueCurrentTaskAsPlaceholder {
            placeholders.insert("继续当前任务")
        }
        return placeholders.contains(lowered)
    }

    func hasDurableSupervisorProjectMemory(_ memory: AXMemory?) -> Bool {
        guard let memory else { return false }
        if !memory.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !memory.requirements.isEmpty ||
            !memory.currentState.isEmpty ||
            !memory.decisions.isEmpty ||
            !memory.nextSteps.isEmpty ||
            !memory.openQuestions.isEmpty ||
            !memory.risks.isEmpty ||
            !memory.recommendations.isEmpty
    }
}
