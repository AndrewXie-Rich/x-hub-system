import Foundation

enum XTAutomationVerificationContractSupport {
    static func foundationValue(_ contract: XTAutomationVerificationContract) -> [String: Any] {
        [
            "expected_state": contract.expectedState,
            "verify_method": contract.verifyMethod,
            "retry_policy": contract.retryPolicy,
            "hold_policy": contract.holdPolicy,
            "evidence_required": contract.evidenceRequired,
            "trigger_action_ids": contract.triggerActionIDs,
            "verify_commands": contract.verifyCommands,
        ]
    }

    static func contract(from value: Any?) -> XTAutomationVerificationContract? {
        guard let object = value as? [String: Any],
              let expectedState = stringValue(object["expected_state"]),
              let verifyMethod = stringValue(object["verify_method"]),
              let retryPolicy = stringValue(object["retry_policy"]),
              let holdPolicy = stringValue(object["hold_policy"]) else {
            return nil
        }

        let triggerActionIDs = (object["trigger_action_ids"] as? [Any] ?? [])
            .compactMap(stringValue)
        let verifyCommands = (object["verify_commands"] as? [Any] ?? [])
            .compactMap(stringValue)

        return XTAutomationVerificationContract(
            expectedState: expectedState,
            verifyMethod: verifyMethod,
            retryPolicy: retryPolicy,
            holdPolicy: holdPolicy,
            evidenceRequired: boolValue(object["evidence_required"]),
            triggerActionIDs: triggerActionIDs,
            verifyCommands: verifyCommands
        )
    }

    static func presentationText(
        _ contract: XTAutomationVerificationContract,
        includePrefix: Bool = true
    ) -> String {
        let evidenceText = contract.evidenceRequired ? "证据必需" : "证据可选"
        let body = "\(humanizedMethod(contract.verifyMethod)) · 目标=\(humanizedExpectedState(contract.expectedState)) · 失败后=\(humanizedRetryPolicy(contract.retryPolicy)) · \(evidenceText)"
        return includePrefix ? "验证合同：\(body)" : body
    }

    static func humanizedMethod(_ value: String) -> String {
        switch value {
        case "project_verify_commands":
            return "项目校验命令"
        case "project_verify_commands_override":
            return "覆写校验命令"
        case "project_verify_commands_missing":
            return "项目校验命令缺失"
        case "project_verify_commands_override_missing":
            return "覆写校验命令缺失"
        case "recipe_action_verify_commands":
            return "步骤自带校验命令"
        case "recipe_action_verify_commands_missing":
            return "步骤自带校验命令缺失"
        case "mixed_verify_commands":
            return "混合校验命令"
        case "mixed_verify_commands_missing":
            return "混合校验命令缺失"
        default:
            return value
        }
    }

    static func humanizedExpectedState(_ value: String) -> String {
        switch value {
        case "post_change_verification_passes":
            return "变更后验证通过"
        default:
            return value
        }
    }

    static func humanizedRetryPolicy(_ value: String) -> String {
        switch value {
        case "retry_failed_verify_commands_within_budget":
            return "预算内只重试失败验证"
        case "manual_retry_or_replan":
            return "人工重试或重规划"
        default:
            return value
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        (value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func boolValue(_ value: Any?) -> Bool {
        value as? Bool ?? false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
