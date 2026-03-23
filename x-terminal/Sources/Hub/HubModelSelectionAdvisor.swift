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
            in: allModels.filter(\.isSelectableForInteractiveRouting)
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
        snapshot: ModelStateSnapshot
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
                ?? "这个模型属于非对话能力，不适合作为当前角色的工作模型。"
            let message: String
            if let suggestedModelId {
                message = "\(role.displayName) 当前配的是 `\(blocked.id)`，但它不能直接用于对话执行。\(reason) 可先改用 `\(suggestedModelId)`。"
            } else {
                message = "\(role.displayName) 当前配的是 `\(blocked.id)`，但它不能直接用于对话执行。\(reason)"
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
                message = "\(role.displayName) 当前配的是 `\(exact.id)`，但它现在是 \(stateLabel(exact.state))；继续用可能会回退到本地，可先改用 `\(suggestedModelId)`。"
            } else {
                message = "\(role.displayName) 当前配的是 `\(exact.id)`，但它现在是 \(stateLabel(exact.state))；继续用可能会回退到本地。"
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
            message = "\(role.displayName) 当前配的是 `\(configuredModelId)`，但当前 inventory 里没有精确匹配；可先改用 `\(suggestedModelId)`。"
        } else {
            message = "\(role.displayName) 当前配的是 `\(configuredModelId)`，但当前 inventory 里没有精确匹配。"
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

    static func displayName(_ model: HubModel) -> String {
        let name = normalize(model.name)
        if name.isEmpty {
            return model.id
        }
        return "\(name) (\(model.id))"
    }

    static func stateLabel(_ state: HubModelState) -> String {
        switch state {
        case .loaded:
            return "已加载"
        case .available:
            return "可用未加载"
        case .sleeping:
            return "休眠"
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

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
