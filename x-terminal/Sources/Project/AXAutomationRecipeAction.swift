import Foundation

struct XTAutomationRecipeVerificationSpec: Codable, Equatable, Sendable {
    var expectedState: String
    var verifyMethod: String
    var retryPolicy: String
    var holdPolicy: String
    var evidenceRequired: Bool?
    var verifyCommands: [String]

    enum CodingKeys: String, CodingKey {
        case expectedState = "expected_state"
        case verifyMethod = "verify_method"
        case retryPolicy = "retry_policy"
        case holdPolicy = "hold_policy"
        case evidenceRequired = "evidence_required"
        case verifyCommands = "verify_commands"
    }

    init(
        expectedState: String = "post_change_verification_passes",
        verifyMethod: String = "",
        retryPolicy: String = "project_default_retry_policy",
        holdPolicy: String = "block_run_and_emit_structured_blocker",
        evidenceRequired: Bool? = nil,
        verifyCommands: [String] = []
    ) {
        self.expectedState = expectedState
        self.verifyMethod = verifyMethod
        self.retryPolicy = retryPolicy
        self.holdPolicy = holdPolicy
        self.evidenceRequired = evidenceRequired
        self.verifyCommands = verifyCommands
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expectedState = (try? c.decode(String.self, forKey: .expectedState)) ?? "post_change_verification_passes"
        verifyMethod = (try? c.decode(String.self, forKey: .verifyMethod)) ?? ""
        retryPolicy = (try? c.decode(String.self, forKey: .retryPolicy)) ?? "project_default_retry_policy"
        holdPolicy = (try? c.decode(String.self, forKey: .holdPolicy)) ?? "block_run_and_emit_structured_blocker"
        evidenceRequired = try? c.decode(Bool.self, forKey: .evidenceRequired)
        verifyCommands = (try? c.decode([String].self, forKey: .verifyCommands)) ?? []
    }

    func normalized() -> XTAutomationRecipeVerificationSpec {
        var out = self
        let trimmedExpectedState = out.expectedState.trimmingCharacters(in: .whitespacesAndNewlines)
        out.expectedState = trimmedExpectedState.isEmpty ? "post_change_verification_passes" : trimmedExpectedState
        out.verifyMethod = out.verifyMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRetryPolicy = out.retryPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        out.retryPolicy = trimmedRetryPolicy.isEmpty ? "project_default_retry_policy" : trimmedRetryPolicy
        let trimmedHoldPolicy = out.holdPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        out.holdPolicy = trimmedHoldPolicy.isEmpty ? "block_run_and_emit_structured_blocker" : trimmedHoldPolicy
        out.verifyCommands = xtAutomationNormalizedRecipeVerificationCommands(out.verifyCommands)
        return out
    }

    func resolvedContract(
        actionID: String,
        projectVerifyCommands: [String],
        overrideUsed: Bool,
        automationSelfIterateEnabled: Bool
    ) -> XTAutomationVerificationContract {
        let localCommands = xtAutomationNormalizedRecipeVerificationCommands(verifyCommands)
        let fallbackProjectCommands = xtAutomationNormalizedRecipeVerificationCommands(projectVerifyCommands)
        let resolvedCommands = localCommands.isEmpty ? fallbackProjectCommands : localCommands
        let explicitMethod = verifyMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMethod: String = {
            if !explicitMethod.isEmpty, !xtAutomationDerivedRecipeVerificationMethodTokens.contains(explicitMethod) {
                return explicitMethod
            }
            if !localCommands.isEmpty {
                return resolvedCommands.isEmpty
                    ? "recipe_action_verify_commands_missing"
                    : "recipe_action_verify_commands"
            }
            return resolvedCommands.isEmpty
                ? (overrideUsed ? "project_verify_commands_override_missing" : "project_verify_commands_missing")
                : (overrideUsed ? "project_verify_commands_override" : "project_verify_commands")
        }()
        let resolvedRetryPolicy: String = {
            let normalizedPolicy = retryPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPolicy.isEmpty, normalizedPolicy != "project_default_retry_policy" else {
                return automationSelfIterateEnabled
                    ? "retry_failed_verify_commands_within_budget"
                    : "manual_retry_or_replan"
            }
            return normalizedPolicy
        }()

        return XTAutomationVerificationContract(
            expectedState: expectedState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "post_change_verification_passes"
                : expectedState.trimmingCharacters(in: .whitespacesAndNewlines),
            verifyMethod: resolvedMethod,
            retryPolicy: resolvedRetryPolicy,
            holdPolicy: holdPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "block_run_and_emit_structured_blocker"
                : holdPolicy.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceRequired: evidenceRequired ?? true,
            triggerActionIDs: [actionID],
            verifyCommands: resolvedCommands
        )
    }

    static func projectDefault() -> XTAutomationRecipeVerificationSpec {
        XTAutomationRecipeVerificationSpec()
    }
}

struct XTAutomationRecipeAction: Codable, Equatable, Identifiable, Sendable {
    var actionID: String
    var title: String
    var tool: ToolName
    var args: [String: JSONValue]
    var continueOnFailure: Bool
    var successBodyContains: String
    var requiresVerification: Bool
    var verificationContract: XTAutomationRecipeVerificationSpec?

    var id: String { actionID }

    enum CodingKeys: String, CodingKey {
        case actionID = "action_id"
        case title
        case tool
        case args
        case continueOnFailure = "continue_on_failure"
        case successBodyContains = "success_body_contains"
        case requiresVerification = "requires_verification"
        case verificationContract = "verification_contract"
    }

    init(
        actionID: String = "",
        title: String = "",
        tool: ToolName,
        args: [String: JSONValue] = [:],
        continueOnFailure: Bool = false,
        successBodyContains: String = "",
        requiresVerification: Bool = false,
        verificationContract: XTAutomationRecipeVerificationSpec? = nil
    ) {
        self.actionID = actionID
        self.title = title
        self.tool = tool
        self.args = args
        self.continueOnFailure = continueOnFailure
        self.successBodyContains = successBodyContains
        self.requiresVerification = requiresVerification || verificationContract != nil
        self.verificationContract = verificationContract?.normalized()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actionID = (try? c.decode(String.self, forKey: .actionID)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        tool = try c.decode(ToolName.self, forKey: .tool)
        args = (try? c.decode([String: JSONValue].self, forKey: .args)) ?? [:]
        continueOnFailure = (try? c.decode(Bool.self, forKey: .continueOnFailure)) ?? false
        successBodyContains = (try? c.decode(String.self, forKey: .successBodyContains)) ?? ""
        let legacyRequiresVerification = (try? c.decode(Bool.self, forKey: .requiresVerification)) ?? false
        verificationContract = (try? c.decode(XTAutomationRecipeVerificationSpec.self, forKey: .verificationContract))?.normalized()
        requiresVerification = legacyRequiresVerification || verificationContract != nil
    }

    func normalized(defaultActionID: String) -> XTAutomationRecipeAction {
        var out = self
        out.actionID = xtAutomationActionToken(
            actionID.trimmingCharacters(in: .whitespacesAndNewlines),
            fallback: defaultActionID
        )
        out.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        out.successBodyContains = successBodyContains.trimmingCharacters(in: .whitespacesAndNewlines)
        out.args = out.args.reduce(into: [:]) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = item.value
        }
        if out.verificationContract == nil, out.requiresVerification {
            out.verificationContract = .projectDefault()
        } else {
            out.verificationContract = out.verificationContract?.normalized()
        }
        if out.verificationContract != nil {
            out.requiresVerification = true
        }
        return out
    }

    func effectiveRequiresVerification(projectVerifyAfterChanges: Bool) -> Bool {
        if verificationContract != nil || requiresVerification {
            return true
        }
        guard projectVerifyAfterChanges else { return false }
        return xtAutomationDefaultVerificationTriggerTools.contains(tool)
    }

    func resolvedVerificationContract(
        projectVerifyAfterChanges: Bool,
        projectVerifyCommands: [String],
        verifyCommandsOverrideUsed: Bool,
        automationSelfIterateEnabled: Bool
    ) -> XTAutomationVerificationContract? {
        if let verificationContract {
            return verificationContract.resolvedContract(
                actionID: actionID,
                projectVerifyCommands: projectVerifyCommands,
                overrideUsed: verifyCommandsOverrideUsed,
                automationSelfIterateEnabled: automationSelfIterateEnabled
            )
        }
        if requiresVerification {
            return XTAutomationRecipeVerificationSpec.projectDefault().resolvedContract(
                actionID: actionID,
                projectVerifyCommands: projectVerifyCommands,
                overrideUsed: verifyCommandsOverrideUsed,
                automationSelfIterateEnabled: automationSelfIterateEnabled
            )
        }
        guard projectVerifyAfterChanges, xtAutomationDefaultVerificationTriggerTools.contains(tool) else {
            return nil
        }
        return XTAutomationRecipeVerificationSpec.projectDefault().resolvedContract(
            actionID: actionID,
            projectVerifyCommands: projectVerifyCommands,
            overrideUsed: verifyCommandsOverrideUsed,
            automationSelfIterateEnabled: automationSelfIterateEnabled
        )
    }
}

func xtAutomationActionToken(_ raw: String, fallback: String) -> String {
    let source = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : raw
    let lowered = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !lowered.isEmpty else { return "action" }

    var buffer = ""
    var previousWasUnderscore = false
    for scalar in lowered.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            buffer.unicodeScalars.append(scalar)
            previousWasUnderscore = false
        } else if !previousWasUnderscore {
            buffer.append("_")
            previousWasUnderscore = true
        }
    }
    let trimmed = buffer.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "action" : trimmed
}

private let xtAutomationDefaultVerificationTriggerTools: Set<ToolName> = [
    .write_file,
    .git_apply,
]

private let xtAutomationDerivedRecipeVerificationMethodTokens: Set<String> = [
    "project_verify_commands",
    "project_verify_commands_override",
    "project_verify_commands_missing",
    "project_verify_commands_override_missing",
    "recipe_action_verify_commands",
    "recipe_action_verify_commands_missing",
    "mixed_verify_commands",
    "mixed_verify_commands_missing",
]

private func xtAutomationNormalizedRecipeVerificationCommands(_ commands: [String]) -> [String] {
    var seen = Set<String>()
    var normalized: [String] = []
    for command in commands {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
        normalized.append(trimmed)
    }
    return normalized
}
