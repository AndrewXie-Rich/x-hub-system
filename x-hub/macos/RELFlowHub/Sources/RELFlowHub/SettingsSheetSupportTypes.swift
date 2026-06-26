import SwiftUI
import AppKit
import RELFlowHubCore

struct RemoteModelSignalVisual: Identifiable {
    let title: String
    let systemName: String
    let tint: Color

    var id: String { title }
}
enum ModelResourcePoolKind: Equatable {
    case local
    case provider
}

struct ModelResourcePoolSummary: Identifiable {
    let id: String
    let kind: ModelResourcePoolKind
    let vendorKey: String
    let title: String
    let subtitle: String
    let statusText: String
    let badgeText: String
    let systemName: String
    let tint: Color
    let accountText: String
    let quotaText: String
    let modelText: String
    let detailText: String
    let models: [String]
    let hiddenModelCount: Int
    let usageWindows: [ProviderKeyUsageWindow]
}

enum TerminalAccessExampleKind: String, CaseIterable, Identifiable {
    case shell
    case python
    case node
    case curl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shell:
            return "Shell"
        case .python:
            return "Python"
        case .node:
            return "Node"
        case .curl:
            return "curl"
        }
    }

    var blockTitle: String {
        "\(title) 接入示例"
    }

    var copyButtonTitle: String {
        "复制\(title)示例"
    }

    var tint: Color {
        switch self {
        case .shell:
            return .teal
        case .python:
            return .blue
        case .node:
            return .orange
        case .curl:
            return .green
        }
    }
}

enum RemoteQuotaConsumerFilter: String, CaseIterable, Identifiable {
    case all
    case xt
    case terminal
    case risk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .xt:
            return "XT"
        case .terminal:
            return "Terminal"
        case .risk:
            return "风险"
        }
    }
}

enum RemoteQuotaVendorFilter: String, CaseIterable, Identifiable {
    case all
    case risk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .risk:
            return "风险"
        }
    }
}

enum RemoteQuotaUserFilter: String, CaseIterable, Identifiable {
    case all
    case risk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .risk:
            return "风险"
        }
    }
}

struct ProviderKeyVendorInventorySummary: Identifiable {
    let vendorKey: String
    let displayName: String
    let pools: [ProviderKeyPoolSnapshot]
    let spotlightUsers: [ProviderKeyVendorUserSpotlight]
    let spotlightConsumers: [ProviderKeyVendorConsumerSpotlight]
    let providerDisplayNames: [String]
    let providerHosts: [String]
    let familyKeys: [String]
    let familyDisplayNames: [String]
    let coveredUserCount: Int
    let coveredConsumerCount: Int
    let coveredUnlimitedConsumerCount: Int
    let coveredFamilyCount: Int
    let poolCount: Int
    let totalAccounts: Int
    let readyAccounts: Int
    let cooldownAccounts: Int
    let blockedAccounts: Int
    let disabledAccounts: Int
    let staleAccounts: Int
    let totalDailyTokenCap: Int64
    let totalDailyTokensUsed: Int64
    let totalDailyTokensRemaining: Int64
    let totalTokensUsed: Int64
    let assignedDailyTokenBudget: Int64
    let observedFamilyTokensUsed: Int64
    let allocationHeadroom: Int64
    let oversubscribedFamilyCount: Int
    let hotPoolCount: Int

    var id: String { vendorKey }
}

struct ProviderKeyVendorUserSpotlight: Identifiable {
    let user: RemoteQuotaCenterUserProjection
    let vendorObservedDailyTokensUsed: Int64

    var id: String { user.id }
}

struct ProviderKeyVendorConsumerSpotlight: Identifiable {
    let consumer: RemoteQuotaCenterClientProjection
    let vendorObservedDailyTokensUsed: Int64

    var id: String { consumer.id }
}

struct ProviderKeyFamilyInventorySummary: Identifiable {
    let familyProjection: RemoteQuotaCenterFamilyProjection
    let coveredUserCount: Int
    let assignedConsumers: [RemoteQuotaCenterClientProjection]
    let assignedDailyTokenBudget: Int64
    let unlimitedBudgetConsumerCount: Int
    let connectedAssignedConsumerCount: Int
    let observedDailyTokensUsed: Int64

    var id: String { familyProjection.id }
    var familyKey: String { familyProjection.familyKey }
    var displayName: String { familyProjection.displayName }
    var quotaPool: ProviderQuotaPoolSnapshot { familyProjection.quotaPool }
    var combinedDailyTokenCap: Int64 { familyProjection.combinedDailyTokenCap }
    var combinedDailyTokensUsed: Int64 { familyProjection.combinedDailyTokensUsed }
    var combinedDailyTokensRemaining: Int64 { familyProjection.combinedDailyTokensRemaining }
    var assignedClientCount: Int { assignedConsumers.count }
    var assignedClients: [RemoteQuotaCenterClientProjection] { assignedConsumers }
    var isOversubscribed: Bool {
        combinedDailyTokenCap > 0 && assignedDailyTokenBudget > combinedDailyTokenCap
    }
}

struct ProviderKeyScopeOverview {
    let focusedUser: RemoteQuotaCenterUserProjection?
    let focusedVendorDisplayName: String?
    let userCount: Int
    let consumerCount: Int
    let connectedConsumerCount: Int
    let xtConsumerCount: Int
    let terminalConsumerCount: Int
    let allocatedDailyTokenBudget: Int64
    let unlimitedBudgetConsumerCount: Int
    let observedConsumerTokensUsed: Int64
    let oversubscribedFamilyCount: Int
}

struct ProviderKeySectionSnapshot {
    let keyPools: [ProviderKeyPoolSnapshot]
    let overview: RemoteQuotaCenterOverview
    let totalFamilyCount: Int
    let totalConsumerCount: Int
    let consumerLedgerTotalCount: Int
    let users: [RemoteQuotaCenterUserProjection]
    let focusedUser: RemoteQuotaCenterUserProjection?
    let scopedUsers: [RemoteQuotaCenterUserProjection]
    let scopedConsumers: [RemoteQuotaCenterClientProjection]
    let vendorSummaries: [ProviderKeyVendorInventorySummary]
    let filteredVendors: [ProviderKeyVendorInventorySummary]
    let filteredFamilies: [ProviderKeyFamilyInventorySummary]
    let filteredUsers: [RemoteQuotaCenterUserProjection]
    let filteredConsumers: [RemoteQuotaCenterClientProjection]
    let focusedVendor: ProviderKeyVendorInventorySummary?
    let flowChains: [ProviderKeyFlowChainSummary]
    let scopeOverview: ProviderKeyScopeOverview
    let riskVendorCount: Int
    let riskFamilyCount: Int
    let overallTrendCard: ProviderKeyTrendCardSummary?
    let vendorTrendCards: [ProviderKeyTrendCardSummary]
    let familyTrendCards: [ProviderKeyTrendCardSummary]
    let userTrendCards: [ProviderKeyTrendCardSummary]
    let consumerTrendCards: [ProviderKeyTrendCardSummary]
    let trendCardCount: Int
    let operationalTint: Color
}

struct SettingsLocalModelSnapshot {
    let models: [HubModel]
    let loadedCount: Int

    static let empty = SettingsLocalModelSnapshot(
        models: [],
        loadedCount: 0
    )

    static func build(from catalogModels: [HubModel]) -> SettingsLocalModelSnapshot {
        let models = LocalModelRuntimeActionPlanner.localModels(from: catalogModels)
        return SettingsLocalModelSnapshot(
            models: models,
            loadedCount: models.filter { $0.state == .loaded }.count
        )
    }
}

struct ProviderKeyTrendCardSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let footnote: String
    let systemName: String
    let tint: Color
    let aggregate: RemoteQuotaTrendAggregate
}

enum ProviderKeyFlowLinkKind: Int, Comparable {
    case dedicated = 0
    case shared = 1
    case elastic = 2

    static func < (lhs: ProviderKeyFlowLinkKind, rhs: ProviderKeyFlowLinkKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .dedicated:
            return "专属链路"
        case .shared:
            return "共享链路"
        case .elastic:
            return "弹性全家族"
        }
    }

    var tint: Color {
        switch self {
        case .dedicated:
            return .green
        case .shared:
            return .blue
        case .elastic:
            return .orange
        }
    }
}

struct ProviderKeyFlowChainSummary: Identifiable {
    let vendor: ProviderKeyVendorInventorySummary
    let user: RemoteQuotaCenterUserProjection
    let consumer: RemoteQuotaCenterClientProjection
    let linkKind: ProviderKeyFlowLinkKind
    let matchedFamilyCount: Int
    let vendorObservedDailyTokensUsed: Int64

    var id: String {
        "\(vendor.id)::\(user.id)::\(consumer.id)"
    }
}

struct RemoteQuotaBudgetEditorTarget: Identifiable, Equatable {
    let consumerKind: RemoteQuotaCenterConsumerKind
    let referenceID: String
    let title: String
    let subtitle: String
    let currentDailyTokenLimit: Int
    let todayUsed: Int64

    var id: String { "\(consumerKind.rawValue):\(referenceID)" }
}

enum HubSettingsPage: String, CaseIterable, Identifiable {
    case overview
    case access
    case models
    case runtime
    case integrations
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "总览"
        case .access:
            return "接入"
        case .models:
            return "模型与额度"
        case .runtime:
            return "运行时基础设施"
        case .integrations:
            return "集成"
        case .diagnostics:
            return "诊断与高级"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "先看 Hub 当前是否健康、是否可服务。"
        case .access:
            return "管理 XT、Terminal 和远程接入。"
        case .models:
            return "并排管理本地模型能力、付费模型能力与共享额度。"
        case .runtime:
            return "管理本地 runtime provider、队列、实例与任务路由。"
        case .integrations:
            return "管理 Operator、Skills 和扩展能力。"
        case .diagnostics:
            return "排障、导出、恢复与底层配置。"
        }
    }

    var systemName: String {
        switch self {
        case .overview:
            return "square.grid.2x2.fill"
        case .access:
            return "link.badge.plus"
        case .models:
            return "shippingbox.fill"
        case .runtime:
            return "cpu.fill"
        case .integrations:
            return "bolt.horizontal.circle.fill"
        case .diagnostics:
            return "stethoscope"
        }
    }

    var tint: Color {
        switch self {
        case .overview:
            return .blue
        case .access:
            return .teal
        case .models:
            return .indigo
        case .runtime:
            return .orange
        case .integrations:
            return .green
        case .diagnostics:
            return .red
        }
    }
}

struct HubSettingsMetric: Identifiable {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var id: String { "\(title)::\(value)::\(detail)" }
}

enum CLIProxyOAuthInventoryState {
    case ready
    case cooling
    case blocked
    case disabled
    case refreshing
    case waiting
}

struct CLIProxyOAuthProviderInventorySummary: Identifiable {
    let providerKey: String
    let displayName: String
    let totalCount: Int
    let readyCount: Int
    let coolingCount: Int
    let blockedCount: Int
    let disabledCount: Int
    let refreshingCount: Int
    let waitingCount: Int

    var id: String { providerKey }
}
