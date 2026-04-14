import Foundation
import RELFlowHubCore

enum HubTaskType: String, CaseIterable, Identifiable {
    case assist
    case translate
    case summarize
    case extract
    case refine
    case classify

    var id: String { rawValue }

    var label: String {
        switch self {
        case .assist: return HubUIStrings.Models.TaskType.assist
        case .translate: return HubUIStrings.Models.TaskType.translate
        case .summarize: return HubUIStrings.Models.TaskType.summarize
        case .extract: return HubUIStrings.Models.TaskType.extract
        case .refine: return HubUIStrings.Models.TaskType.refine
        case .classify: return HubUIStrings.Models.TaskType.classify
        }
    }

    var desiredTaskKinds: [String] {
        ["text_generate"]
    }

    var desiredRoles: [String] {
        switch self {
        case .translate: return ["translate", "general"]
        case .summarize: return ["summarize", "general"]
        case .extract: return ["extract", "general"]
        case .refine: return ["refine", "general"]
        case .classify: return ["classify", "general"]
        case .assist: return ["general"]
        }
    }

    var preferSpeed: Bool {
        switch self {
        case .translate, .classify:
            return true
        default:
            return false
        }
    }
}

struct HubTaskRouteDecision {
    var modelId: String
    var modelName: String
    var modelState: HubModelState?
    var reason: String
    var willAutoLoad: Bool
}

private struct HubTaskRouteSortKey: Comparable {
    var state: Int
    var task: Int
    var role: Int
    // Primary/secondary are negative when we want to sort descending.
    var primary: Double
    var secondary: Double
    var id: String

    static func < (lhs: HubTaskRouteSortKey, rhs: HubTaskRouteSortKey) -> Bool {
        if lhs.state != rhs.state { return lhs.state < rhs.state }
        if lhs.task != rhs.task { return lhs.task < rhs.task }
        if lhs.role != rhs.role { return lhs.role < rhs.role }
        if lhs.primary != rhs.primary { return lhs.primary < rhs.primary }
        if lhs.secondary != rhs.secondary { return lhs.secondary < rhs.secondary }
        return lhs.id < rhs.id
    }
}

enum HubTaskRoutingPolicy {
    static func decision(
        taskType: HubTaskType,
        models: [HubModel],
        preferredModelId: String,
        allowAutoLoad: Bool
    ) -> HubTaskRouteDecision {
        guard !models.isEmpty else {
            return HubTaskRouteDecision(
                modelId: "",
                modelName: "",
                modelState: nil,
                reason: "no_models_registered",
                willAutoLoad: false
            )
        }

        let normalizedPreferredModelId = preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedPreferredModelId.isEmpty,
           let model = models.first(where: { $0.id == normalizedPreferredModelId }) {
            return HubTaskRouteDecision(
                modelId: model.id,
                modelName: model.name,
                modelState: model.state,
                reason: "preferred_model",
                willAutoLoad: allowAutoLoad && model.state != .loaded
            )
        }

        let sorted = models.sorted { sortKey(for: $0, taskType: taskType) < sortKey(for: $1, taskType: taskType) }

        if let model = sorted.first(where: { $0.state == .loaded && supports(taskType: taskType, model: $0) }) {
            return HubTaskRouteDecision(
                modelId: model.id,
                modelName: model.name,
                modelState: model.state,
                reason: "task_match_loaded",
                willAutoLoad: false
            )
        }

        if allowAutoLoad,
           let model = sorted.first(where: { $0.state != .loaded && supports(taskType: taskType, model: $0) }) {
            return HubTaskRouteDecision(
                modelId: model.id,
                modelName: model.name,
                modelState: model.state,
                reason: "task_match_autoload",
                willAutoLoad: true
            )
        }

        if let model = sorted.first(where: { $0.state == .loaded }) {
            return HubTaskRouteDecision(
                modelId: model.id,
                modelName: model.name,
                modelState: model.state,
                reason: "fallback_loaded",
                willAutoLoad: false
            )
        }

        if allowAutoLoad,
           let model = sorted.first(where: { $0.state != .loaded }) {
            return HubTaskRouteDecision(
                modelId: model.id,
                modelName: model.name,
                modelState: model.state,
                reason: "fallback_autoload",
                willAutoLoad: true
            )
        }

        return HubTaskRouteDecision(
            modelId: "",
            modelName: "",
            modelState: nil,
            reason: "model_not_loaded",
            willAutoLoad: false
        )
    }

    static func eligibleModels(for taskType: HubTaskType, within models: [HubModel]) -> [HubModel] {
        models.filter { supports(taskType: taskType, model: $0) }
    }

    static func supports(taskType: HubTaskType, model: HubModel) -> Bool {
        taskIndex(for: model, taskType: taskType) < .max
    }

    static func capabilityTags(for model: HubModel, limit: Int = 3) -> [String] {
        let descriptors = LocalTaskRoutingCatalog.supportedDescriptors(in: model.taskKinds)
        if !descriptors.isEmpty {
            return Array(descriptors.map(\.shortTitle).prefix(max(1, limit)))
        }

        let normalizedRoles = normalizedRoles(for: model)
        if !normalizedRoles.isEmpty {
            return Array(normalizedRoles.prefix(max(1, limit)))
        }

        return []
    }

    private static func sortKey(for model: HubModel, taskType: HubTaskType) -> HubTaskRouteSortKey {
        let state = stateRank(model.state)
        let task = taskIndex(for: model, taskType: taskType)
        let role = roleIndex(for: model, taskType: taskType)

        if taskType.preferSpeed {
            let tokensPerSecond = model.tokensPerSec ?? 0.0
            let paramsB = model.paramsB
            return HubTaskRouteSortKey(
                state: state,
                task: task,
                role: role,
                primary: -(tokensPerSecond > 0 ? tokensPerSecond : 0.0),
                secondary: (paramsB > 0 ? paramsB : 9_999.0),
                id: model.id
            )
        }

        let paramsB = model.paramsB
        let tokensPerSecond = model.tokensPerSec ?? 0.0
        return HubTaskRouteSortKey(
            state: state,
            task: task,
            role: role,
            primary: -(paramsB > 0 ? paramsB : 0.0),
            secondary: -(tokensPerSecond > 0 ? tokensPerSecond : 0.0),
            id: model.id
        )
    }

    private static func taskIndex(for model: HubModel, taskType: HubTaskType) -> Int {
        let supportedTaskKinds = supportedTaskKinds(for: model)
        for (index, taskKind) in taskType.desiredTaskKinds.enumerated() {
            if supportedTaskKinds.contains(taskKind) {
                return index
            }
        }
        return .max
    }

    private static func roleIndex(for model: HubModel, taskType: HubTaskType) -> Int {
        let roles = Set(normalizedRoles(for: model))
        for (index, role) in taskType.desiredRoles.enumerated() {
            if roles.contains(role) {
                return index
            }
        }
        return .max
    }

    private static func normalizedRoles(for model: HubModel) -> [String] {
        let roles = (model.roles ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if roles.isEmpty {
            return ["general"]
        }
        return roles
    }

    private static func supportedTaskKinds(for model: HubModel) -> Set<String> {
        let supported = LocalTaskRoutingCatalog.supportedTaskKinds(in: model.taskKinds)
        if !supported.isEmpty {
            return Set(supported)
        }
        return ["text_generate"]
    }

    private static func stateRank(_ state: HubModelState) -> Int {
        switch state {
        case .loaded: return 0
        case .available, .sleeping: return 1
        }
    }
}
