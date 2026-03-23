import Foundation

struct XTProjectMappedSkillDispatch: Equatable, Sendable {
    var skillId: String
    var toolCall: ToolCall
    var toolName: String
}

struct XTProjectSkillMappingFailure: Error, Equatable, Sendable {
    var reasonCode: String
}

enum XTProjectSkillRouter {
    static func loadRegistrySnapshot(
        projectId: String,
        projectName: String?
    ) -> SupervisorSkillRegistrySnapshot? {
        let normalizedProjectId = normalized(projectId)
        guard !normalizedProjectId.isEmpty else { return nil }
        return AXSkillsLibrary.supervisorSkillRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
            hubBaseDir: HubPaths.baseDir()
        )
    }

    static func map(
        call: GovernedSkillCall,
        projectId: String,
        projectName: String?,
        registrySnapshot: SupervisorSkillRegistrySnapshot? = nil
    ) -> Result<XTProjectMappedSkillDispatch, XTProjectSkillMappingFailure> {
        let normalizedProjectId = normalized(projectId)
        guard !normalizedProjectId.isEmpty else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "skill_registry_unavailable"))
        }

        let normalizedSkillId = normalized(
            AXSkillsLibrary.canonicalSupervisorSkillID(call.skill_id)
        )
        guard !normalizedSkillId.isEmpty else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "skill_id_missing"))
        }

        let snapshot = registrySnapshot ?? loadRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: projectName
        )
        guard let item = snapshot?.items.first(where: {
            normalized(AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId)) == normalizedSkillId
        }) else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "skill_not_registered"))
        }

        if let mappedVariant = mappedGovernedDispatchVariant(
            item: item,
            payload: call.payload,
            requestId: call.id
        ) {
            return mappedVariant
        }

        guard let dispatch = item.governedDispatch else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "skill_mapping_missing"))
        }
        return mappedGovernedDispatch(
            skillId: normalizedSkillId,
            dispatch: dispatch,
            payload: call.payload,
            requestId: call.id,
            actionOverride: nil
        )
    }

    static func failureMessage(
        skillId: String,
        failure: XTProjectSkillMappingFailure
    ) -> String {
        switch failure.reasonCode {
        case "skill_registry_unavailable":
            return "当前 project 没有可用的技能注册表，无法解析 \(skillId)。"
        case "skill_not_registered":
            return "技能 \(skillId) 不在当前 project scope 的 Hub registry 中。"
        case "skill_mapping_missing":
            return "技能 \(skillId) 还没有接到受治理 runtime。"
        case "payload.action_unsupported":
            return "技能 \(skillId) 收到了不支持的 action。"
        case "payload.command_not_allowed":
            return "技能 \(skillId) 请求的命令不在受治理 allowlist 内。"
        default:
            return "技能 \(skillId) payload 校验失败（\(failure.reasonCode)）。"
        }
    }

    private static func mappedGovernedDispatchVariant(
        item: SupervisorSkillRegistryItem,
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<XTProjectMappedSkillDispatch, XTProjectSkillMappingFailure>? {
        guard !item.governedDispatchVariants.isEmpty else { return nil }
        let requestedAction = firstNonEmptyString(
            payload["action"]?.stringValue,
            payload["operation"]?.stringValue,
            payload["mode"]?.stringValue
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
        guard !requestedAction.isEmpty else { return nil }

        guard let variant = item.governedDispatchVariants.first(where: { variant in
            variant.actions.contains {
                normalized($0) == requestedAction
            }
        }) else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "payload.action_unsupported"))
        }

        let actionOverride: (key: String, value: String)? = {
            let cleanedKey = normalized(variant.actionArg)
            guard !cleanedKey.isEmpty else { return nil }
            let mapped = variant.actionMap.first(where: {
                normalized($0.key) == requestedAction
            })?.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedAction = normalized(mapped).isEmpty ? requestedAction : normalized(mapped)
            guard !resolvedAction.isEmpty else { return nil }
            return (cleanedKey, resolvedAction)
        }()

        return mappedGovernedDispatch(
            skillId: item.skillId,
            dispatch: variant.dispatch,
            payload: payload,
            requestId: requestId,
            actionOverride: actionOverride
        )
    }

    private static func mappedGovernedDispatch(
        skillId: String,
        dispatch: SupervisorGovernedSkillDispatch,
        payload: [String: JSONValue],
        requestId: String,
        actionOverride: (key: String, value: String)?
    ) -> Result<XTProjectMappedSkillDispatch, XTProjectSkillMappingFailure> {
        let toolToken = normalized(dispatch.tool)
        guard let toolName = ToolName.allCases.first(where: { $0.rawValue == toolToken }) else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "governed_dispatch_tool_invalid"))
        }

        var args = dispatch.fixedArgs
        if let actionOverride {
            args[actionOverride.key] = .string(actionOverride.value)
        }

        let canonicalKeys = Set(dispatch.passthroughArgs).union(dispatch.argAliases.keys)
        for canonicalKey in canonicalKeys.sorted() {
            if let value = resolvedGovernedDispatchPayloadValue(
                payload: payload,
                canonicalKey: canonicalKey,
                aliases: dispatch.argAliases[canonicalKey] ?? []
            ) {
                args[canonicalKey] = value
            }
        }

        for group in dispatch.requiredAny {
            let presentCount = group.filter { governedDispatchHasValue(args[$0]) }.count
            guard presentCount > 0 else {
                return .failure(XTProjectSkillMappingFailure(reasonCode: governedDispatchMissingReasonCode(for: group)))
            }
        }

        for group in dispatch.exactlyOneOf {
            let presentCount = group.filter { governedDispatchHasValue(args[$0]) }.count
            guard presentCount == 1 else {
                return .failure(
                    XTProjectSkillMappingFailure(
                        reasonCode: governedDispatchExclusiveReasonCode(for: group, presentCount: presentCount)
                    )
                )
            }
        }

        return .success(
            XTProjectMappedSkillDispatch(
                skillId: skillId,
                toolCall: ToolCall(id: requestId, tool: toolName, args: args),
                toolName: toolName.rawValue
            )
        )
    }

    private static func resolvedGovernedDispatchPayloadValue(
        payload: [String: JSONValue],
        canonicalKey: String,
        aliases: [String]
    ) -> JSONValue? {
        let candidates = [canonicalKey] + aliases
        for candidate in candidates {
            let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            guard let value = payload[key], governedDispatchHasValue(value) else { continue }
            return value
        }
        return nil
    }

    private static func governedDispatchHasValue(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .null:
            return false
        case .string(let string):
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let array):
            return !array.isEmpty
        case .object(let object):
            return !object.isEmpty
        case .number, .bool:
            return true
        }
    }

    private static func governedDispatchMissingReasonCode(for group: [String]) -> String {
        let normalizedGroup = group
            .map { normalized($0) }
            .filter { !$0.isEmpty }
        if normalizedGroup.count == 1, let first = normalizedGroup.first {
            return "payload.\(first)_missing"
        }
        return "payload.required_args_missing"
    }

    private static func governedDispatchExclusiveReasonCode(for group: [String], presentCount: Int) -> String {
        let normalizedGroup = group
            .map { normalized($0) }
            .filter { !$0.isEmpty }
        let sourceGroup = Set(["url", "path", "text"])
        if Set(normalizedGroup) == sourceGroup {
            return presentCount == 0 ? "payload.source_missing" : "payload.multiple_sources"
        }
        if normalizedGroup.count == 1, let first = normalizedGroup.first {
            return "payload.\(first)_missing"
        }
        return presentCount == 0 ? "payload.required_args_missing" : "payload.mutually_exclusive_args"
    }

    private static func firstNonEmptyString(_ values: String?...) -> String? {
        for value in values {
            let trimmed = normalized(value)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func normalized(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
