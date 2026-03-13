import Foundation

struct HubModelAvailabilityAssessment: Equatable {
    var requestedId: String
    var exactMatch: HubModel?
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
        exactMatch == nil
    }
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
        let exactMatch = exactModelMatch(for: requestedId, in: allModels)
        let ranked = rankedCandidates(for: requestedId, in: allModels)
            .filter { candidate in
                guard let exactMatch else { return true }
                return normalizedModelID(candidate.id) != normalizedModelID(exactMatch.id)
            }

        let loadedCandidates = Array(ranked.filter { $0.state == .loaded }.prefix(candidateLimit))
        let inventoryCandidates = Array(ranked.prefix(candidateLimit))

        return HubModelAvailabilityAssessment(
            requestedId: requestedId,
            exactMatch: exactMatch,
            loadedCandidates: loadedCandidates,
            inventoryCandidates: inventoryCandidates
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
