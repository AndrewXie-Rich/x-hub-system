import Foundation
import RELFlowHubCore

enum LocalModelRuntimeActionRoute: Equatable {
    case legacyModelCommand(action: String)
    case providerLifecycleCommand(action: String)
    case immediateFailure(message: String)
}

struct LocalModelRuntimePresentation: Equatable {
    var providerID: String
    var controlMode: AIRuntimeProviderHubControlMode
    var lifecycleMode: String
    var residencyScope: String
    var providerReady: Bool
    var supportsWarmup: Bool
    var supportsUnload: Bool
    var supportsBench: Bool

    var badgeTitle: String {
        switch controlMode {
        case .mlxLegacy:
            return HubUIStrings.Models.Runtime.ActionPlanner.mlxLegacyBadge
        case .warmable:
            return HubUIStrings.Models.Runtime.ActionPlanner.warmableBadge
        case .ephemeralOnDemand:
            return HubUIStrings.Models.Runtime.ActionPlanner.onDemandBadge
        }
    }

    var badgeSystemName: String {
        switch controlMode {
        case .mlxLegacy:
            return "cpu"
        case .warmable:
            return "flame"
        case .ephemeralOnDemand:
            return "bolt.horizontal"
        }
    }
}

struct LocalModelRuntimeTargetOption: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case auto
        case pairedDevice = "paired_device"
        case loadedInstance = "loaded_instance"
    }

    var kind: Kind
    var deviceID: String
    var instanceKey: String
    var title: String
    var detail: String

    var id: String {
        "\(kind.rawValue)::\(deviceID)::\(instanceKey)"
    }

    var isAuto: Bool {
        kind == .auto
    }
}

struct ModelCapacitySnapshot: Equatable {
    var usedMemoryBytes: Int64
    var budgetMemoryBytes: Int64

    static let empty = ModelCapacitySnapshot(
        usedMemoryBytes: 0,
        budgetMemoryBytes: 1
    )

    var percent: Double {
        let used = Double(max(0, usedMemoryBytes))
        let budget = Double(max(1, budgetMemoryBytes))
        return max(0.0, min(1.0, used / budget))
    }
}
