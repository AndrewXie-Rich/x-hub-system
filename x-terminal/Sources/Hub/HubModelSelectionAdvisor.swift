import Foundation

struct HubModelAvailabilityAssessment: Equatable {
    var requestedId: String
    var exactMatch: HubModel?
    var nonInteractiveExactMatch: HubModel?
    var loadedCandidates: [HubModel]
    var inventoryCandidates: [HubModel]

    var isExactMatchLoaded: Bool {
        exactMatch?.state == .loaded
    }

    var isKnownButNotLoaded: Bool {
        guard let exactMatch else { return false }
        return exactMatch.state != .loaded
    }

    var isMissingFromInventory: Bool {
        exactMatch == nil && nonInteractiveExactMatch == nil
    }

    var interactiveRoutingBlockedReason: String? {
        nonInteractiveExactMatch?.interactiveRoutingDisabledReason
    }
}

struct HubGlobalRoleModelIssue: Equatable, Identifiable {
    var role: AXRole
    var configuredModelId: String
    var message: String
    var suggestedModelId: String?

    var id: String { role.rawValue }
}

struct HubLocalTaskModelResolution: Equatable {
    var taskKind: String
    var explicitModelId: String?
    var preferredModelId: String?
    var requestedModelId: String?
    var resolvedModel: HubModel?
    var reasonCode: String
    var fallbackUsed: Bool
}

enum HubModelSelectionAdvisor {
    static func allModels(in snapshot: ModelStateSnapshot) -> [HubModel] {
        sortedModels(snapshot.models)
    }

    static func loadedModels(in snapshot: ModelStateSnapshot) -> [HubModel] {
        sortedModels(snapshot.models.filter { $0.state == .loaded })
    }

    static func assess(
        requestedId rawRequestedId: String?,
        snapshot: ModelStateSnapshot,
        candidateLimit: Int = 3
    ) -> HubModelAvailabilityAssessment? {
        let requestedId = normalize(rawRequestedId)
        guard !requestedId.isEmpty else { return nil }

        let allModels = allModels(in: snapshot)
        let resolvedExactMatch = exactModelMatch(for: requestedId, in: allModels)
        let exactMatch = resolvedExactMatch?.isSelectableForInteractiveRouting == true ? resolvedExactMatch : nil
        let nonInteractiveExactMatch = resolvedExactMatch?.isSelectableForInteractiveRouting == false
            ? resolvedExactMatch
            : nil
        let ranked = rankedCandidates(
            for: requestedId,
            in: allModels.filter { model in
                model.isSelectableForInteractiveRouting
                    && isInventoryRunnableCandidate(model)
            }
        )
            .filter { candidate in
                guard let resolvedExactMatch else { return true }
                return normalizedModelID(candidate.id) != normalizedModelID(resolvedExactMatch.id)
            }

        let loadedCandidates = preferredLoadedCandidates(
            requestedId: requestedId,
            ranked: ranked,
            allModels: allModels,
            resolvedExactMatch: resolvedExactMatch,
            limit: candidateLimit
        )
        let inventoryCandidates = Array(ranked.prefix(candidateLimit))

        return HubModelAvailabilityAssessment(
            requestedId: requestedId,
            exactMatch: exactMatch,
            nonInteractiveExactMatch: nonInteractiveExactMatch,
            loadedCandidates: loadedCandidates,
            inventoryCandidates: inventoryCandidates
        )
    }

    static func globalAssignmentIssue(
        for role: AXRole,
        configuredModelId rawConfiguredModelId: String?,
        snapshot: ModelStateSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> HubGlobalRoleModelIssue? {
        let configuredModelId = normalize(rawConfiguredModelId)
        guard !configuredModelId.isEmpty,
              let assessment = assess(
                requestedId: configuredModelId,
                snapshot: snapshot
              ),
              !assessment.isExactMatchLoaded else {
            return nil
        }

        let suggestions = suggestedModelIDs(from: assessment)
        let suggestedModelId = suggestions.first

        if let blocked = assessment.nonInteractiveExactMatch {
            let reason = assessment.interactiveRoutingBlockedReason
                ?? XTL10n.text(
                    language,
                    zhHans: "这个模型属于非对话能力，不适合作为当前角色的工作模型。",
                    en: "This model is reserved for non-chat capabilities and is not a good fit for this role's working model."
                )
            let message: String
            if let suggestedModelId {
                message = XTL10n.text(
                    language,
                    zhHans: "\(role.displayName(in: language)) 当前配的是 `\(blocked.id)`，但它不能直接用于对话执行。\(reason) 可先改用 `\(suggestedModelId)`。",
                    en: "\(role.displayName(in: language)) is currently set to `\(blocked.id)`, but it cannot be used directly for interactive execution. \(reason) Switch to `\(suggestedModelId)` first."
                )
            } else {
                message = XTL10n.text(
                    language,
                    zhHans: "\(role.displayName(in: language)) 当前配的是 `\(blocked.id)`，但它不能直接用于对话执行。\(reason)",
                    en: "\(role.displayName(in: language)) is currently set to `\(blocked.id)`, but it cannot be used directly for interactive execution. \(reason)"
                )
            }
            return HubGlobalRoleModelIssue(
                role: role,
                configuredModelId: configuredModelId,
                message: message,
                suggestedModelId: suggestedModelId
            )
        }

        if let exact = assessment.exactMatch {
            let message: String
            if let suggestedModelId {
                message = XTL10n.text(
                    language,
                    zhHans: "\(role.displayName(in: language)) 当前配的是 `\(exact.id)`，但它现在是 \(stateLabel(exact.state, language: language))；继续用可能会回退到本地，可先改用 `\(suggestedModelId)`。",
                    en: "\(role.displayName(in: language)) is currently set to `\(exact.id)`, but it is \(stateLabel(exact.state, language: language)) right now. Continuing may fall back to local, so switch to `\(suggestedModelId)` first."
                )
            } else {
                message = XTL10n.text(
                    language,
                    zhHans: "\(role.displayName(in: language)) 当前配的是 `\(exact.id)`，但它现在是 \(stateLabel(exact.state, language: language))；继续用可能会回退到本地。",
                    en: "\(role.displayName(in: language)) is currently set to `\(exact.id)`, but it is \(stateLabel(exact.state, language: language)) right now. Continuing may fall back to local."
                )
            }
            return HubGlobalRoleModelIssue(
                role: role,
                configuredModelId: configuredModelId,
                message: message,
                suggestedModelId: suggestedModelId
            )
        }

        let message: String
        if let suggestedModelId {
            message = XTL10n.text(
                language,
                zhHans: "\(role.displayName(in: language)) 当前配的是 `\(configuredModelId)`，但当前 inventory 里没有精确匹配；可先改用 `\(suggestedModelId)`。",
                en: "\(role.displayName(in: language)) is currently set to `\(configuredModelId)`, but there is no exact match in the current inventory. Switch to `\(suggestedModelId)` first."
            )
        } else {
            message = XTL10n.text(
                language,
                zhHans: "\(role.displayName(in: language)) 当前配的是 `\(configuredModelId)`，但当前 inventory 里没有精确匹配。",
                en: "\(role.displayName(in: language)) is currently set to `\(configuredModelId)`, but there is no exact match in the current inventory."
            )
        }
        return HubGlobalRoleModelIssue(
            role: role,
            configuredModelId: configuredModelId,
            message: message,
            suggestedModelId: suggestedModelId
        )
    }

    private static func preferredLoadedCandidates(
        requestedId: String,
        ranked: [HubModel],
        allModels: [HubModel],
        resolvedExactMatch: HubModel?,
        limit: Int
    ) -> [HubModel] {
        if shouldPreferRemoteLoadedFallback(
            requestedId: requestedId,
            resolvedExactMatch: resolvedExactMatch
        ) {
            let remotePreferred = remoteLoadedFallbackCandidates(
                requestedId: requestedId,
                snapshot: ModelStateSnapshot(models: allModels, updatedAt: 0),
                excludingModelIDs: [resolvedExactMatch?.id ?? ""],
                candidateLimit: limit
            )
            if !remotePreferred.isEmpty {
                return remotePreferred
            }
        }

        let rankedLoaded = Array(ranked.filter { $0.state == .loaded }.prefix(limit))
        guard !rankedLoaded.isEmpty else {
            return genericLoadedFallbackCandidates(
                allModels: allModels,
                excluding: resolvedExactMatch,
                limit: limit
            )
        }
        return rankedLoaded
    }

    private static func genericLoadedFallbackCandidates(
        allModels: [HubModel],
        excluding resolvedExactMatch: HubModel?,
        limit: Int
    ) -> [HubModel] {
        Array(
            allModels
                .filter { model in
                    model.state == .loaded
                        && model.isSelectableForInteractiveRouting
                        && normalizedModelID(model.id)
                            != normalizedModelID(resolvedExactMatch?.id ?? "")
                }
                .prefix(limit)
        )
    }

    private static func isInventoryRunnableCandidate(_ model: HubModel) -> Bool {
        if model.state == .loaded {
            return true
        }
        if model.isLocalModel {
            return model.offlineReady
        }
        return true
    }

    static func displayName(_ model: HubModel) -> String {
        let name = normalize(model.name)
        if name.isEmpty {
            return model.id
        }
        return "\(name) (\(model.id))"
    }

    static func stateLabel(_ state: HubModelState) -> String {
        stateLabel(state, language: .defaultPreference)
    }

    static func stateLabel(
        _ state: HubModelState,
        language: XTInterfaceLanguage
    ) -> String {
        switch state {
        case .loaded:
            return XTL10n.HubModelStateCopy.label(.loaded, language: language)
        case .available:
            return XTL10n.HubModelStateCopy.label(.available, language: language)
        case .sleeping:
            return XTL10n.HubModelStateCopy.label(.sleeping, language: language)
        }
    }

    static func compactSuggestionLabel(_ model: HubModel) -> String {
        let name = normalize(model.name)
        if name.isEmpty || name.caseInsensitiveCompare(model.id) == .orderedSame {
            return model.id
        }
        return "\(name) · \(model.id)"
    }

    static func suggestedModelIDs(
        from assessment: HubModelAvailabilityAssessment,
        limit: Int = 3
    ) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        var seen: Set<String> = []
        var result: [String] = []
        for model in source {
            let id = normalize(model.id)
            guard !id.isEmpty,
                  seen.insert(normalizedModelID(id)).inserted else { continue }
            result.append(id)
            if result.count >= limit { break }
        }
        return result
    }

    static func remoteLoadedFallbackCandidates(
        requestedId rawRequestedId: String?,
        snapshot: ModelStateSnapshot,
        excludingModelIDs rawExcludedModelIDs: [String] = [],
        candidateLimit: Int = 3
    ) -> [HubModel] {
        let requestedId = normalize(rawRequestedId)
        guard !requestedId.isEmpty else { return [] }

        let excluded = Set(rawExcludedModelIDs.map(normalizedModelID))
        let rankedRemote = rankedCandidates(for: requestedId, in: allModels(in: snapshot))
            .filter { model in
                model.state == .loaded
                    && isRemoteModel(model)
                    && model.isSelectableForInteractiveRouting
                    && normalizedModelID(model.id) != normalizedModelID(requestedId)
                    && !excluded.contains(normalizedModelID(model.id))
            }

        let sameProvider = rankedRemote.filter { candidate in
            sameProviderNamespace(candidate.id, requestedId)
        }
        let ordered = sameProvider.isEmpty ? rankedRemote : sameProvider
        return Array(ordered.prefix(candidateLimit))
    }

    static func resolveLocalTaskModel(
        taskKind rawTaskKind: String,
        explicitModelId rawExplicitModelId: String? = nil,
        preferredModelId rawPreferredModelId: String? = nil,
        snapshot: ModelStateSnapshot
    ) -> HubLocalTaskModelResolution {
        let taskKind = normalize(rawTaskKind).lowercased()
        let explicitModelId: String? = {
            let value = normalize(rawExplicitModelId)
            return value.isEmpty ? nil : value
        }()
        let preferredModelId: String? = {
            let value = normalize(rawPreferredModelId)
            return value.isEmpty ? nil : value
        }()
        let requestedModelId = explicitModelId ?? preferredModelId
        let localModels = allModels(in: snapshot).filter(\.isLocalModel)
        let runnableCandidates = rankedRunnableLocalTaskCandidates(
            taskKind: taskKind,
            in: localModels
        )

        if let explicitModelId {
            guard let exact = exactModelMatch(for: explicitModelId, in: localModels) else {
                return HubLocalTaskModelResolution(
                    taskKind: taskKind,
                    explicitModelId: explicitModelId,
                    preferredModelId: preferredModelId,
                    requestedModelId: requestedModelId,
                    resolvedModel: nil,
                    reasonCode: "explicit_model_not_found",
                    fallbackUsed: false
                )
            }
            guard supportsLocalTaskKind(taskKind, model: exact) else {
                return HubLocalTaskModelResolution(
                    taskKind: taskKind,
                    explicitModelId: explicitModelId,
                    preferredModelId: preferredModelId,
                    requestedModelId: requestedModelId,
                    resolvedModel: nil,
                    reasonCode: "explicit_model_task_unsupported",
                    fallbackUsed: false
                )
            }
            guard isRunnableLocalTaskCandidate(exact) else {
                return HubLocalTaskModelResolution(
                    taskKind: taskKind,
                    explicitModelId: explicitModelId,
                    preferredModelId: preferredModelId,
                    requestedModelId: requestedModelId,
                    resolvedModel: nil,
                    reasonCode: "explicit_model_not_runnable",
                    fallbackUsed: false
                )
            }
            return HubLocalTaskModelResolution(
                taskKind: taskKind,
                explicitModelId: explicitModelId,
                preferredModelId: preferredModelId,
                requestedModelId: requestedModelId,
                resolvedModel: exact,
                reasonCode: "explicit_model_exact",
                fallbackUsed: false
            )
        }

        if let preferredModelId {
            let preferredMatch = exactModelMatch(for: preferredModelId, in: localModels)
            if let preferredMatch,
               supportsLocalTaskKind(taskKind, model: preferredMatch),
               isRunnableLocalTaskCandidate(preferredMatch) {
                return HubLocalTaskModelResolution(
                    taskKind: taskKind,
                    explicitModelId: nil,
                    preferredModelId: preferredModelId,
                    requestedModelId: requestedModelId,
                    resolvedModel: preferredMatch,
                    reasonCode: "preferred_model_exact",
                    fallbackUsed: false
                )
            }

            if let fallback = runnableCandidates.first {
                return HubLocalTaskModelResolution(
                    taskKind: taskKind,
                    explicitModelId: nil,
                    preferredModelId: preferredModelId,
                    requestedModelId: requestedModelId,
                    resolvedModel: fallback,
                    reasonCode: "preferred_model_fallback_task_kind",
                    fallbackUsed: normalizedModelID(fallback.id) != normalizedModelID(preferredModelId)
                )
            }

            let failureReason: String
            if let preferredMatch {
                failureReason = supportsLocalTaskKind(taskKind, model: preferredMatch)
                    ? "preferred_model_not_runnable"
                    : "preferred_model_task_unsupported"
            } else {
                failureReason = "preferred_model_not_found"
            }
            return HubLocalTaskModelResolution(
                taskKind: taskKind,
                explicitModelId: nil,
                preferredModelId: preferredModelId,
                requestedModelId: requestedModelId,
                resolvedModel: nil,
                reasonCode: failureReason,
                fallbackUsed: false
            )
        }

        if let fallback = runnableCandidates.first {
            return HubLocalTaskModelResolution(
                taskKind: taskKind,
                explicitModelId: nil,
                preferredModelId: nil,
                requestedModelId: nil,
                resolvedModel: fallback,
                reasonCode: "task_kind_auto",
                fallbackUsed: false
            )
        }

        return HubLocalTaskModelResolution(
            taskKind: taskKind,
            explicitModelId: nil,
            preferredModelId: nil,
            requestedModelId: nil,
            resolvedModel: nil,
            reasonCode: "no_runnable_local_model_for_task_kind",
            fallbackUsed: false
        )
    }

    private static func exactModelMatch(
        for requestedId: String,
        in models: [HubModel]
    ) -> HubModel? {
        if let exact = models.first(where: {
            normalizedModelID($0.id).caseInsensitiveCompare(normalizedModelID(requestedId)) == .orderedSame
        }) {
            return exact
        }

        let requestedBase = baseModelID(for: requestedId)
        guard !requestedBase.isEmpty else { return nil }

        let suffixMatches = models.filter { model in
            let base = baseModelID(for: model.id)
            return !base.isEmpty && base.caseInsensitiveCompare(requestedBase) == .orderedSame
        }
        if suffixMatches.count == 1 {
            return suffixMatches[0]
        }

        return nil
    }

    private static func rankedCandidates(
        for requestedId: String,
        in models: [HubModel]
    ) -> [HubModel] {
        let normalizedRequested = normalizedModelID(requestedId)

        return models
            .compactMap { model -> (HubModel, Int)? in
                let score = scoreCandidate(model, against: normalizedRequested)
                guard score > 0 else { return nil }
                return (model, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if stateRank(lhs.0.state) != stateRank(rhs.0.state) {
                    return stateRank(lhs.0.state) < stateRank(rhs.0.state)
                }
                let leftName = normalizedSortName(lhs.0)
                let rightName = normalizedSortName(rhs.0)
                if leftName != rightName { return leftName < rightName }
                return lhs.0.id.localizedCaseInsensitiveCompare(rhs.0.id) == .orderedAscending
            }
            .map(\.0)
    }

    private static func scoreCandidate(_ model: HubModel, against requestedId: String) -> Int {
        let modelID = normalizedModelID(model.id)
        let modelName = normalize(model.name).lowercased()
        let modelBase = baseModelID(for: model.id)
        let requestedBase = baseModelID(for: requestedId)

        if modelID == requestedId {
            return 1_000
        }
        if !requestedBase.isEmpty && modelBase == requestedBase {
            return 960
        }
        if modelID.hasSuffix("/\(requestedId)") || requestedId.hasSuffix("/\(modelBase)") {
            return 930
        }
        if modelID.contains(requestedId) {
            return 860
        }
        if !modelName.isEmpty && modelName.contains(requestedId) {
            return 820
        }
        if !requestedBase.isEmpty && modelID.contains(requestedBase) {
            return 760
        }
        if !requestedBase.isEmpty && !modelName.isEmpty && modelName.contains(requestedBase) {
            return 720
        }

        let overlap = tokenOverlapScore(lhs: requestedId, rhs: modelID + " " + modelName)
        if overlap > 0 {
            return 600 + overlap
        }

        return 0
    }

    private static func tokenOverlapScore(lhs: String, rhs: String) -> Int {
        let left = Set(tokenize(lhs))
        let right = Set(tokenize(rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return left.intersection(right).count * 10
    }

    private static func tokenize(_ text: String) -> [String] {
        normalize(text)
            .lowercased()
            .split(whereSeparator: { ch in
                !(ch.isLetter || ch.isNumber)
            })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func sortedModels(_ models: [HubModel]) -> [HubModel] {
        var dedup: [String: HubModel] = [:]
        for model in models {
            let key = normalizedModelID(model.id)
            guard !key.isEmpty else { continue }
            dedup[key] = model
        }
        return dedup.values.sorted { lhs, rhs in
            let leftState = stateRank(lhs.state)
            let rightState = stateRank(rhs.state)
            if leftState != rightState { return leftState < rightState }
            let leftName = normalizedSortName(lhs)
            let rightName = normalizedSortName(rhs)
            if leftName != rightName { return leftName < rightName }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    private static func normalizedSortName(_ model: HubModel) -> String {
        let name = normalize(model.name)
        return (name.isEmpty ? model.id : name).lowercased()
    }

    private static func shouldPreferRemoteLoadedFallback(
        requestedId: String,
        resolvedExactMatch: HubModel?
    ) -> Bool {
        if let resolvedExactMatch {
            return isRemoteModel(resolvedExactMatch)
        }

        let provider = providerNamespace(for: requestedId)
        if provider.isEmpty {
            return false
        }
        return provider != "mlx"
    }

    private static func isRemoteModel(_ model: HubModel) -> Bool {
        let path = normalize(model.modelPath)
        if !path.isEmpty {
            return false
        }
        return normalize(model.backend).lowercased() != "mlx"
    }

    private static func sameProviderNamespace(_ candidateID: String, _ requestedId: String) -> Bool {
        let candidateProvider = providerNamespace(for: candidateID)
        let requestedProvider = providerNamespace(for: requestedId)
        guard !candidateProvider.isEmpty, !requestedProvider.isEmpty else { return false }
        return candidateProvider == requestedProvider
    }

    private static func providerNamespace(for raw: String) -> String {
        let normalized = normalizedModelID(raw)
        return normalized.split(separator: "/").first.map(String.init) ?? ""
    }

    private static func stateRank(_ state: HubModelState) -> Int {
        switch state {
        case .loaded:
            return 0
        case .available:
            return 1
        case .sleeping:
            return 2
        }
    }

    private static func baseModelID(for raw: String) -> String {
        let normalized = normalizedModelID(raw)
        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }

    private static func normalizedModelID(_ raw: String) -> String {
        normalize(raw).lowercased()
    }

    private static func rankedRunnableLocalTaskCandidates(
        taskKind: String,
        in models: [HubModel]
    ) -> [HubModel] {
        models
            .filter { model in
                supportsLocalTaskKind(taskKind, model: model)
                    && isRunnableLocalTaskCandidate(model)
            }
            .sorted { lhs, rhs in
                let leftRank = localTaskRank(lhs, taskKind: taskKind)
                let rightRank = localTaskRank(rhs, taskKind: taskKind)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
    }

    private static func supportsLocalTaskKind(
        _ taskKind: String,
        model: HubModel
    ) -> Bool {
        let normalizedTaskKind = normalize(taskKind).lowercased()
        let taskKinds = Set(model.taskKinds.map { normalize($0).lowercased() })
        let outputModalities = Set(model.outputModalities.map { normalize($0).lowercased() })

        switch normalizedTaskKind {
        case "text_generate":
            return model.supportsInteractiveTextGeneration
        case "embedding":
            return taskKinds.contains("embedding")
                || model.isEmbeddingModel
                || outputModalities.contains("embedding")
        case "speech_to_text":
            return taskKinds.contains("speech_to_text")
        case "text_to_speech":
            return taskKinds.contains("text_to_speech")
                || model.isTextToSpeechModel
                || outputModalities.contains("audio")
        case "vision_understand":
            return taskKinds.contains("vision_understand")
        case "ocr":
            return taskKinds.contains("ocr")
        default:
            return false
        }
    }

    private static func isRunnableLocalTaskCandidate(_ model: HubModel) -> Bool {
        guard model.isLocalModel else { return false }
        if model.state == .loaded {
            return true
        }
        return model.offlineReady
    }

    private static func localTaskRank(
        _ model: HubModel,
        taskKind: String
    ) -> (Int, Int, Int, Int, String) {
        let outputModalities = Set(model.outputModalities.map { normalize($0).lowercased() })
        let taskKinds = Set(model.taskKinds.map { normalize($0).lowercased() })
        let taskSpecificRank: Int = {
            switch taskKind {
            case "embedding":
                return outputModalities.contains("embedding") ? 0 : 1
            case "speech_to_text":
                return outputModalities.contains("segments") ? 0 : 1
            case "text_to_speech":
                return outputModalities.contains("audio") ? 0 : 1
            case "ocr":
                if outputModalities.contains("spans") {
                    return 0
                }
                return outputModalities.contains("text") ? 1 : 2
            case "vision_understand":
                return outputModalities.contains("text") ? 0 : 1
            default:
                return 0
            }
        }()
        let specializationRank = taskKinds.count <= 1 ? 0 : 1
        let offlineRank = model.state == .loaded || model.offlineReady ? 0 : 1
        return (
            stateRank(model.state),
            taskSpecificRank,
            specializationRank,
            offlineRank,
            normalizedSortName(model)
        )
    }

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
