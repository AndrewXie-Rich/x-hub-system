import Foundation

struct XTVisibleHubModelInventory {
    static let empty = XTVisibleHubModelInventory(
        snapshot: .empty(),
        sortedModels: [],
        modelsByNormalizedID: [:]
    )

    let snapshot: ModelStateSnapshot
    let sortedModels: [HubModel]
    private let modelsByNormalizedID: [String: HubModel]

    func model(for modelId: String?) -> HubModel? {
        let normalized = XTVisibleHubModelInventorySupport.normalizedModelID(modelId)
        guard !normalized.isEmpty else { return nil }
        return modelsByNormalizedID[normalized]
    }

    func presentation(for modelId: String?) -> ModelInfo? {
        let trimmed = XTVisibleHubModelInventorySupport.trimmedModelID(modelId)
        guard !trimmed.isEmpty else { return nil }
        return model(for: trimmed)?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: trimmed)
    }

    fileprivate init(
        snapshot: ModelStateSnapshot,
        sortedModels: [HubModel],
        modelsByNormalizedID: [String: HubModel]
    ) {
        self.snapshot = snapshot
        self.sortedModels = sortedModels
        self.modelsByNormalizedID = modelsByNormalizedID
    }
}

enum XTVisibleHubModelInventorySupport {
    static func build(snapshot: ModelStateSnapshot) -> XTVisibleHubModelInventory {
        var dedupedModels: [String: HubModel] = [:]
        for model in snapshot.models {
            let normalizedID = normalizedModelID(model.id)
            guard !normalizedID.isEmpty else { continue }
            dedupedModels[normalizedID] = model
        }

        let sortedModels = dedupedModels.values.sorted { a, b in
            let leftStateRank = stateRank(a.state)
            let rightStateRank = stateRank(b.state)
            if leftStateRank != rightStateRank {
                return leftStateRank < rightStateRank
            }

            let leftName = trimmedModelID(a.name).isEmpty ? trimmedModelID(a.id) : trimmedModelID(a.name)
            let rightName = trimmedModelID(b.name).isEmpty ? trimmedModelID(b.id) : trimmedModelID(b.name)
            let leftNormalizedName = leftName.lowercased()
            let rightNormalizedName = rightName.lowercased()
            if leftNormalizedName != rightNormalizedName {
                return leftNormalizedName < rightNormalizedName
            }

            return trimmedModelID(a.id).lowercased() < trimmedModelID(b.id).lowercased()
        }

        var modelsByNormalizedID: [String: HubModel] = [:]
        for model in sortedModels {
            let normalizedID = normalizedModelID(model.id)
            guard !normalizedID.isEmpty else { continue }
            modelsByNormalizedID[normalizedID] = model
        }

        return XTVisibleHubModelInventory(
            snapshot: ModelStateSnapshot(
                models: sortedModels,
                updatedAt: snapshot.updatedAt
            ),
            sortedModels: sortedModels,
            modelsByNormalizedID: modelsByNormalizedID
        )
    }

    static func trimmedModelID(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedModelID(_ raw: String?) -> String {
        trimmedModelID(raw).lowercased()
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
}
