import SwiftUI
import RELFlowHubCore

struct ModelsDrawerLocalModelSnapshot: Equatable {
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

struct ModelsDrawerResourcePoolSummary: Identifiable, Equatable {
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

    static func == (lhs: ModelsDrawerResourcePoolSummary, rhs: ModelsDrawerResourcePoolSummary) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.statusText == rhs.statusText
            && lhs.systemName == rhs.systemName
            && lhs.modelText == rhs.modelText
            && lhs.accountText == rhs.accountText
            && lhs.quotaText == rhs.quotaText
            && lhs.models == rhs.models
            && lhs.usageWindows == rhs.usageWindows
            && lhs.detailText == rhs.detailText
            && lhs.isLocal == rhs.isLocal
    }
}

struct ModelsDrawerRouteMatrixRow: Identifiable, Equatable {
    var id: String
    var title: String
    var modelName: String
    var provider: String
    var statusText: String
    var statusColor: Color
    var reason: String

    static func == (lhs: ModelsDrawerRouteMatrixRow, rhs: ModelsDrawerRouteMatrixRow) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.modelName == rhs.modelName
            && lhs.provider == rhs.provider
            && lhs.statusText == rhs.statusText
            && lhs.reason == rhs.reason
    }
}

struct ModelsDrawerRoleRouteSummary: Identifiable, Equatable {
    var id: String
    var title: String
    var systemName: String
    var modelName: String
    var statusText: String
    var statusColor: Color
    var detail: String

    static func == (lhs: ModelsDrawerRoleRouteSummary, rhs: ModelsDrawerRoleRouteSummary) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.systemName == rhs.systemName
            && lhs.modelName == rhs.modelName
            && lhs.statusText == rhs.statusText
            && lhs.detail == rhs.detail
    }
}

struct ModelsDrawerRouteModelOption: Identifiable, Equatable {
    var id: String
    var title: String
}

struct ModelsDrawerTaskRouteControlSnapshot: Identifiable, Equatable {
    var id: String
    var task: HubTaskType
    var decision: HubTaskRouteDecision
    var preferredModelId: String
    var tint: Color
    var systemName: String
    var purposeText: String
    var detailText: String
    var stateText: String
    var preferenceLabel: String
    var availableModels: [ModelsDrawerRouteModelOption]

    static func == (
        lhs: ModelsDrawerTaskRouteControlSnapshot,
        rhs: ModelsDrawerTaskRouteControlSnapshot
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.task == rhs.task
            && lhs.decision == rhs.decision
            && lhs.preferredModelId == rhs.preferredModelId
            && lhs.systemName == rhs.systemName
            && lhs.purposeText == rhs.purposeText
            && lhs.detailText == rhs.detailText
            && lhs.stateText == rhs.stateText
            && lhs.preferenceLabel == rhs.preferenceLabel
            && lhs.availableModels == rhs.availableModels
    }
}

struct ModelsDrawerLibraryItem: Identifiable, Equatable {
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

    static func == (lhs: ModelsDrawerLibraryItem, rhs: ModelsDrawerLibraryItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.provider == rhs.provider
            && lhs.detail == rhs.detail
            && lhs.statusText == rhs.statusText
            && lhs.tags == rhs.tags
            && lhs.isLocal == rhs.isLocal
            && lhs.isReady == rhs.isReady
            && lhs.modelId == rhs.modelId
            && lhs.remoteEntry == rhs.remoteEntry
    }
}

struct RemoteDrawerGroup: Identifiable, Equatable {
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

    static func == (lhs: RemoteDrawerGroup, rhs: RemoteDrawerGroup) -> Bool {
        lhs.id == rhs.id
            && lhs.keyReference == rhs.keyReference
            && lhs.title == rhs.title
            && lhs.summary == rhs.summary
            && lhs.detail == rhs.detail
            && lhs.statusText == rhs.statusText
            && lhs.availableCount == rhs.availableCount
            && lhs.needsSetupCount == rhs.needsSetupCount
            && lhs.enabledModelIDs == rhs.enabledModelIDs
            && lhs.loadableModelIDs == rhs.loadableModelIDs
            && lhs.models == rhs.models
    }
}

struct RemoteDrawerModel: Identifiable, Equatable {
    let entry: RemoteModelEntry
    let title: String
    let subtitle: String
    let detail: String?
    let statusText: String
    let statusColor: Color
    let isLoaded: Bool
    let canLoad: Bool

    var id: String { entry.id }

    static func == (lhs: RemoteDrawerModel, rhs: RemoteDrawerModel) -> Bool {
        lhs.entry == rhs.entry
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.detail == rhs.detail
            && lhs.statusText == rhs.statusText
            && lhs.isLoaded == rhs.isLoaded
            && lhs.canLoad == rhs.canLoad
    }
}
