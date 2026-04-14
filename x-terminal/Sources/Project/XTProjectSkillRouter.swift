import Foundation

struct XTProjectMappedSkillDispatch: Equatable, Sendable {
    var requestedSkillId: String? = nil
    var skillId: String
    var intentFamilies: [String] = []
    var capabilityFamilies: [String] = []
    var capabilityProfiles: [String] = []
    var grantFloor: String = XTSkillGrantFloor.none.rawValue
    var approvalFloor: String = XTSkillApprovalFloor.none.rawValue
    var routingReasonCode: String? = nil
    var routingExplanation: String? = nil
    var hubStateDirPath: String? = nil
    var toolCall: ToolCall
    var toolName: String
}

struct XTProjectSkillMappingFailure: Error, Equatable, Sendable {
    var reasonCode: String
}

enum XTProjectSkillRouter {
    static func loadRegistrySnapshot(
        projectId: String,
        projectName: String?,
        projectRoot: URL? = nil
    ) -> SupervisorSkillRegistrySnapshot? {
        let normalizedProjectId = normalized(projectId)
        guard !normalizedProjectId.isEmpty else { return nil }
        if let projectRoot {
            if let persistedRemoteSnapshot = AXSkillsLibrary.persistedRemoteResolvedSkillsCacheSnapshot(
                projectId: normalizedProjectId,
                projectName: projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
                projectRoot: projectRoot,
                hubBaseDir: HubPaths.baseDir()
            ) {
                return AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                    fromResolvedCache: persistedRemoteSnapshot
                )
            }
            return AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                projectId: normalizedProjectId,
                projectName: projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
                projectRoot: projectRoot,
                hubBaseDir: HubPaths.baseDir()
            )
        }
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
        registrySnapshot: SupervisorSkillRegistrySnapshot? = nil,
        projectRoot: URL? = nil,
        config: AXProjectConfig? = nil,
        hubBaseDir: URL? = nil
    ) -> Result<XTProjectMappedSkillDispatch, XTProjectSkillMappingFailure> {
        let normalizedProjectId = normalized(projectId)
        guard !normalizedProjectId.isEmpty else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "skill_registry_unavailable"))
        }

        let normalizedSkillId = normalized(
            AXSkillsLibrary.canonicalSupervisorSkillID(call.skill_id)
        )
        let snapshot = registrySnapshot ?? loadRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot
        )

        let item: SupervisorSkillRegistryItem
        let routingReasonCode: String?
        let routingExplanation: String?

        if !normalizedSkillId.isEmpty,
           let resolved = snapshot?.items.first(where: {
               normalized(AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId)) == normalizedSkillId
           }) {
            item = resolved
            routingReasonCode = nil
            routingExplanation = nil
        } else if !normalizedSkillId.isEmpty {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "skill_not_registered"))
        } else if let resolved = selectedItemByIntentFamilies(
            call.intent_families ?? [],
            snapshot: snapshot,
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            config: config,
            hubBaseDir: hubBaseDir
        ) {
            item = resolved.item
            routingReasonCode = "intent_family_fallback"
            routingExplanation = resolved.explanation
        } else {
            return .failure(
                XTProjectSkillMappingFailure(
                    reasonCode: (call.intent_families ?? []).isEmpty
                        ? "skill_id_missing"
                        : "intent_family_not_registered"
                )
            )
        }

        if let mappedVariant = mappedGovernedDispatchVariant(
            item: item,
            payload: call.payload,
            requestId: call.id,
            requestedSkillId: normalizedSkillId.isEmpty ? nil : normalizedSkillId,
            projectRoot: projectRoot,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        ) {
            return mappedVariant
        }

        guard let dispatch = item.governedDispatch else {
            return .failure(XTProjectSkillMappingFailure(reasonCode: "skill_mapping_missing"))
        }
        return mappedGovernedDispatch(
            skillId: item.skillId,
            requestedSkillId: normalizedSkillId.isEmpty ? nil : normalizedSkillId,
            dispatch: dispatch,
            item: item,
            payload: call.payload,
            requestId: call.id,
            actionOverride: nil,
            projectRoot: projectRoot,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
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
        case "intent_family_not_registered":
            return "当前 project 没有与请求 intent_families 匹配的受治理技能。"
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
        requestId: String,
        requestedSkillId: String?,
        projectRoot: URL?,
        routingReasonCode: String?,
        routingExplanation: String?
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
            requestedSkillId: requestedSkillId,
            dispatch: variant.dispatch,
            item: item,
            payload: payload,
            requestId: requestId,
            actionOverride: actionOverride,
            projectRoot: projectRoot,
            routingReasonCode: routingReasonCode,
            routingExplanation: routingExplanation
        )
    }

    private static func mappedGovernedDispatch(
        skillId: String,
        requestedSkillId: String?,
        dispatch: SupervisorGovernedSkillDispatch,
        item: SupervisorSkillRegistryItem,
        payload: [String: JSONValue],
        requestId: String,
        actionOverride: (key: String, value: String)?,
        projectRoot: URL?,
        routingReasonCode: String?,
        routingExplanation: String?
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

        enrichLocalTaskBindingArgsIfNeeded(
            toolName: toolName,
            args: &args
        )

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
                requestedSkillId: requestedSkillId,
                skillId: skillId,
                intentFamilies: item.intentFamilies,
                capabilityFamilies: item.capabilityFamilies,
                capabilityProfiles: item.capabilityProfiles,
                grantFloor: item.grantFloor,
                approvalFloor: item.approvalFloor,
                routingReasonCode: routingReasonCode,
                routingExplanation: routingExplanation,
                hubStateDirPath: mappedHubStateDirPath(projectRoot: projectRoot),
                toolCall: ToolCall(id: requestId, tool: toolName, args: args),
                toolName: toolName.rawValue
            )
        )
    }

    private static func mappedHubStateDirPath(projectRoot: URL?) -> String? {
        guard let projectRoot else { return nil }
        return normalizedHubStateDirPath(
            XTResolvedSkillsCacheStore.load(for: AXProjectContext(root: projectRoot))?.remoteStateDirPath
        )
    }

    private static func enrichLocalTaskBindingArgsIfNeeded(
        toolName: ToolName,
        args: inout [String: JSONValue]
    ) {
        guard toolName == .run_local_task else { return }
        guard !governedDispatchHasValue(args["model_id"]),
              !governedDispatchHasValue(args["preferred_model_id"]) else {
            return
        }
        let taskKind = args["task_kind"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !taskKind.isEmpty else { return }
        let snapshotURL = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return
        }
        let resolution = HubModelSelectionAdvisor.resolveLocalTaskModel(
            taskKind: taskKind,
            snapshot: snapshot
        )
        guard let resolvedModel = resolution.resolvedModel else { return }
        args["preferred_model_id"] = .string(resolvedModel.id)
    }

    private static func normalizedHubStateDirPath(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func selectedItemByIntentFamilies(
        _ intentFamilies: [String],
        snapshot: SupervisorSkillRegistrySnapshot?,
        projectId: String,
        projectName: String?,
        projectRoot: URL?,
        config: AXProjectConfig?,
        hubBaseDir: URL?
    ) -> (item: SupervisorSkillRegistryItem, explanation: String)? {
        let requested = Set(
            intentFamilies
                .map { normalized($0) }
                .filter { !$0.isEmpty }
        )
        guard !requested.isEmpty, let snapshot else { return nil }

        let matches = snapshot.items.filter { item in
            let itemIntents = Set(item.intentFamilies.map { normalized($0) }.filter { !$0.isEmpty })
            return !itemIntents.isDisjoint(with: requested)
        }
        guard !matches.isEmpty else { return nil }

        let evaluatedCandidates: [IntentFamilySelectionCandidate] = matches.compactMap { item in
            guard let projectRoot else {
                return IntentFamilySelectionCandidate(item: item, readiness: nil, selectionClass: .unknown)
            }

            let baseReadiness = AXSkillsLibrary.skillExecutionReadiness(
                skillId: item.skillId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot,
                config: config,
                registryItem: item,
                hubBaseDir: hubBaseDir
            )
            let readiness = XTSkillCapabilityProfileSupport.effectiveReadinessForRequestScopedGrantOverride(
                readiness: baseReadiness,
                registryItem: item
            )
            let selectionClass = intentSelectionClass(for: readiness.executionReadiness)
            guard selectionClass != .blocked else { return nil }
            return IntentFamilySelectionCandidate(
                item: item,
                readiness: readiness,
                selectionClass: selectionClass
            )
        }

        let candidates = evaluatedCandidates.isEmpty && projectRoot == nil
            ? matches.map { IntentFamilySelectionCandidate(item: $0, readiness: nil, selectionClass: .unknown) }
            : evaluatedCandidates
        guard !candidates.isEmpty else { return nil }

        let selected = candidates.sorted { lhs, rhs in
            if lhs.selectionClass != rhs.selectionClass {
                return lhs.selectionClass.rawValue < rhs.selectionClass.rawValue
            }

            let leftScope = skillScopePriority(lhs.item.policyScope)
            let rightScope = skillScopePriority(rhs.item.policyScope)
            if leftScope != rightScope {
                return leftScope > rightScope
            }

            let leftApproval = approvalPriority(lhs.item.approvalFloor)
            let rightApproval = approvalPriority(rhs.item.approvalFloor)
            if leftApproval != rightApproval {
                return leftApproval < rightApproval
            }

            let leftGrant = grantPriority(lhs.item.grantFloor)
            let rightGrant = grantPriority(rhs.item.grantFloor)
            if leftGrant != rightGrant {
                return leftGrant < rightGrant
            }

            if lhs.item.officialPackage != rhs.item.officialPackage {
                return lhs.item.officialPackage && !rhs.item.officialPackage
            }

            let leftPackage = selectionPackageSHA(lhs.item)
            let rightPackage = selectionPackageSHA(rhs.item)
            if leftPackage != rightPackage {
                return leftPackage < rightPackage
            }

            return lhs.item.skillId.localizedCaseInsensitiveCompare(rhs.item.skillId) == .orderedAscending
        }.first

        guard let selected else { return nil }
        let matched = selected.item.intentFamilies.filter { requested.contains(normalized($0)) }
        let readinessSuffix: String = {
            guard let readiness = selected.readiness else { return "" }
            let state = normalized(readiness.executionReadiness)
            guard !state.isEmpty else { return "" }
            return " | readiness=\(state)"
        }()
        let explanation = matched.isEmpty
            ? "根据受治理 registry 的 intent family 兜底路由到 \(selected.item.skillId)\(readinessSuffix)。"
            : "根据 intent family \(matched.joined(separator: ", ")) 路由到 \(selected.item.skillId)\(readinessSuffix)。"
        return (selected.item, explanation)
    }

    private enum IntentFamilySelectionClass: Int {
        case runnable = 0
        case requestable = 1
        case unknown = 2
        case blocked = 3
    }

    private struct IntentFamilySelectionCandidate {
        var item: SupervisorSkillRegistryItem
        var readiness: XTSkillExecutionReadiness?
        var selectionClass: IntentFamilySelectionClass
    }

    private static func intentSelectionClass(for readiness: String) -> IntentFamilySelectionClass {
        switch XTSkillCapabilityProfileSupport.readinessState(from: readiness) {
        case .ready:
            return .runnable
        case .grantRequired, .localApprovalRequired, .degraded:
            return .requestable
        case .none:
            return .unknown
        case .policyClamped,
             .runtimeUnavailable,
             .hubDisconnected,
             .quarantined,
             .revoked,
             .notInstalled,
             .unsupported:
            return .blocked
        }
    }

    private static func selectionPackageSHA(_ item: SupervisorSkillRegistryItem) -> String {
        let normalizedPackage = normalized(item.packageSHA256)
        if !normalizedPackage.isEmpty {
            return normalizedPackage
        }
        return normalized(item.skillId)
    }

    private static func skillScopePriority(_ raw: String) -> Int {
        switch normalized(raw) {
        case "project":
            return 4
        case "global":
            return 3
        case "memory_core":
            return 2
        case "xt_builtin":
            return 1
        default:
            return 0
        }
    }

    private static func approvalPriority(_ raw: String) -> Int {
        switch normalized(raw) {
        case XTSkillApprovalFloor.none.rawValue:
            return 0
        case XTSkillApprovalFloor.localApproval.rawValue:
            return 1
        case XTSkillApprovalFloor.hubGrant.rawValue:
            return 2
        case XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue:
            return 3
        case XTSkillApprovalFloor.ownerConfirmation.rawValue:
            return 4
        default:
            return 5
        }
    }

    private static func grantPriority(_ raw: String) -> Int {
        switch normalized(raw) {
        case XTSkillGrantFloor.none.rawValue:
            return 0
        case XTSkillGrantFloor.readonly.rawValue:
            return 1
        case XTSkillGrantFloor.privileged.rawValue:
            return 2
        case XTSkillGrantFloor.critical.rawValue:
            return 3
        default:
            return 4
        }
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
