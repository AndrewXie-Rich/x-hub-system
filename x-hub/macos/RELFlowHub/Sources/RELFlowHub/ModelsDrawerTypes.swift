import SwiftUI
import RELFlowHubCore

struct ModelsDrawerLocalModelSnapshot {
    var models: [HubModel]
    var sections: [ModelLibrarySection]
    var loadedCount: Int

    static let empty = ModelsDrawerLocalModelSnapshot(
        models: [],
        sections: [],
        loadedCount: 0
    )

    static func build(from catalogModels: [HubModel]) -> ModelsDrawerLocalModelSnapshot {
        let models = LocalModelRuntimeActionPlanner.localModels(from: catalogModels)
        return ModelsDrawerLocalModelSnapshot(
            models: models,
            sections: ModelLibrarySectionPlanner.sections(from: models),
            loadedCount: models.filter { $0.state == .loaded }.count
        )
    }
}

struct ModelsDrawerProviderKeySnapshot: Equatable {
    var totalAccounts: Int
    var readyAccounts: Int
    var blockedAccounts: Int
    var importSources: [ProviderKeyImportSourceStatus]
    var keyPools: [ProviderKeyPoolSnapshot]
    var quotaPools: [ProviderQuotaPoolSnapshot]

    static let empty = ModelsDrawerProviderKeySnapshot(
        totalAccounts: 0,
        readyAccounts: 0,
        blockedAccounts: 0,
        importSources: [],
        keyPools: [],
        quotaPools: []
    )

    static func build(from snapshot: ProviderKeyStoreSnapshot) -> ModelsDrawerProviderKeySnapshot {
        let derived = ProviderKeyStorage.derivedSnapshot(from: snapshot)
        return ModelsDrawerProviderKeySnapshot(
            totalAccounts: derived.totalAccounts,
            readyAccounts: derived.readyAccounts,
            blockedAccounts: derived.blockedAccounts,
            importSources: snapshot.importSources,
            keyPools: derived.keyPools,
            quotaPools: derived.quotaPools
        )
    }
}

struct ModelsDrawerImportSourceRemovalTarget: Identifiable, Equatable {
    var source: ProviderKeyImportSourceStatus
    var removeOwnedAccounts: Bool

    var id: String {
        "\(source.sourceKey)#\(removeOwnedAccounts ? "owned" : "metadata")"
    }
}

struct ModelsDrawerRemoteModelRemovalTarget: Identifiable, Equatable {
    var title: String
    var modelIDs: [String]
    var keyReference: String
    var isGroup: Bool

    var id: String {
        "\(isGroup ? "group" : "model")#\(keyReference)#\(modelIDs.joined(separator: ","))"
    }

    var modelCount: Int {
        modelIDs.count
    }
}

enum ModelsDrawerLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case remote
    case local
    case ready
    case needsSetup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .remote: return "远程"
        case .local: return "本地"
        case .ready: return "可用"
        case .needsSetup: return "需配置"
        }
    }
}

struct ModelsDrawerResourcePoolSummary: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var statusText: String
    var statusColor: Color
    var systemName: String
    var modelText: String
    var accountText: String
    var quotaText: String
    var models: [String]
    var usageWindows: [ProviderKeyUsageWindow]
    var detailText: String
    var isLocal: Bool
}

struct ModelsDrawerRouteMatrixRow: Identifiable {
    var id: String
    var title: String
    var modelName: String
    var provider: String
    var statusText: String
    var statusColor: Color
    var reason: String
}

struct ModelsDrawerRoleRouteSummary: Identifiable {
    var id: String
    var title: String
    var systemName: String
    var modelName: String
    var statusText: String
    var statusColor: Color
    var detail: String
}

struct ModelsDrawerLibraryItem: Identifiable {
    var id: String
    var title: String
    var provider: String
    var detail: String
    var statusText: String
    var statusColor: Color
    var tags: [String]
    var isLocal: Bool
    var isReady: Bool
    var modelId: String
    var remoteEntry: RemoteModelEntry?
}

struct RemoteDrawerGroup: Identifiable {
    let id: String
    let keyReference: String
    let title: String
    let summary: String
    let detail: String?
    let statusText: String
    let statusColor: Color
    let availableCount: Int
    let needsSetupCount: Int
    let enabledModelIDs: [String]
    let loadableModelIDs: [String]
    let models: [RemoteDrawerModel]

    var loadedCount: Int {
        models.filter(\.isLoaded).count
    }
}

struct RemoteDrawerModel: Identifiable {
    let entry: RemoteModelEntry
    let title: String
    let subtitle: String
    let detail: String?
    let statusText: String
    let statusColor: Color
    let isLoaded: Bool
    let canLoad: Bool

    var id: String { entry.id }
}
