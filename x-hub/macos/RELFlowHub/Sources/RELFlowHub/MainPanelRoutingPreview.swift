import SwiftUI
import AppKit
import RELFlowHubCore

private struct RouteDecision {
    var modelId: String
    var modelName: String
    var modelState: HubModelState?
    var reason: String
    var willAutoLoad: Bool
}

private struct RouteSortKey: Comparable {
    var state: Int
    var role: Int
    // Primary/secondary are negative when we want to sort descending.
    var primary: Double
    var secondary: Double
    var id: String

    static func < (lhs: RouteSortKey, rhs: RouteSortKey) -> Bool {
        if lhs.state != rhs.state { return lhs.state < rhs.state }
        if lhs.role != rhs.role { return lhs.role < rhs.role }
        if lhs.primary != rhs.primary { return lhs.primary < rhs.primary }
        if lhs.secondary != rhs.secondary { return lhs.secondary < rhs.secondary }
        return lhs.id < rhs.id
    }
}

private struct RoutingPreviewView: View {
    @ObservedObject private var modelStore = ModelStore.shared
    @EnvironmentObject private var store: HubStore
    @Binding var taskType: HubTaskType
    @Binding var preferredModelId: String
    @Binding var allowAutoLoad: Bool

    var body: some View {
        let decision = routeDecision()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Routing Preview")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("Auto-load", isOn: $allowAutoLoad)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 10) {
                Picker("Task", selection: $taskType) {
                    ForEach(HubTaskType.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 150)

                Menu {
                    Button("Auto") { preferredModelId = "" }
                    Divider()
                    ForEach(modelStore.snapshot.models) { m in
                        Button("\(m.id)") { preferredModelId = m.id }
                    }
                } label: {
                    let eff = effectivePreferredModelId()
                    Text(eff.isEmpty ? "Preferred: Auto" : "Preferred: \(eff)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.mini)
                Spacer()
            }

            RoutingDefaultsRow(taskType: taskType, preferredByTask: store.routingPreferredModelIdByTask)

            if decision.modelId.isEmpty {
                Text("No model routed (\(decision.reason)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                let st = decision.modelState.map { "\($0.rawValue)" } ?? "unknown"
                let auto = decision.willAutoLoad ? " · will auto-load" : ""
                Text("\(decision.modelName) (\(decision.modelId)) · \(st) · \(decision.reason)\(auto)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func desiredRoles(for t: HubTaskType) -> [String] {
        switch t {
        case .supervisor: return ["supervisor", "assist", "advisor", "general"]
        case .coder: return ["coder", "translate", "summarize", "extract", "refine", "classify", "general"]
        case .reviewer: return ["reviewer", "review", "general"]
        }
    }

    private func preferSpeed(for t: HubTaskType) -> Bool {
        false
    }

    private func modelRoles(_ m: HubModel) -> Set<String> {
        let rs = (m.roles ?? [])
            .map(HubModelRolePresentation.canonicalRoleToken)
            .filter { !$0.isEmpty }
        if rs.isEmpty { return ["general"] }
        return Set(rs)
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available, .sleeping: return 1
        }
    }

    private func routeDecision() -> RouteDecision {
        let models = modelStore.snapshot.models
        if models.isEmpty {
            return RouteDecision(modelId: "", modelName: "", modelState: nil, reason: "no_models_registered", willAutoLoad: false)
        }

        let effPreferred = effectivePreferredModelId()
        // Preferred model (if exists).
        if !effPreferred.isEmpty, let m = models.first(where: { $0.id == effPreferred }) {
            let willAuto = allowAutoLoad && m.state != .loaded
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "preferred_model", willAutoLoad: willAuto)
        }

        let want = desiredRoles(for: taskType)
        let primaryRole = want.first ?? "general"
        let speedFirst = preferSpeed(for: taskType)

        func roleIndex(_ m: HubModel) -> Int {
            let rs = modelRoles(m)
            for (i, r) in want.enumerated() {
                if rs.contains(r) { return i }
            }
            return 999
        }

        func tps(_ m: HubModel) -> Double {
            m.tokensPerSec ?? 0.0
        }

        func paramsB(_ m: HubModel) -> Double {
            m.paramsB
        }

        func sortKey(_ m: HubModel) -> RouteSortKey {
            let st = stateRank(m.state)
            let rr = roleIndex(m)
            if speedFirst {
                let tt = tps(m)
                let pb = paramsB(m)
                // Higher tps first; if unknown, smaller paramsB.
                return RouteSortKey(state: st, role: rr, primary: -(tt > 0 ? tt : 0.0), secondary: (pb > 0 ? pb : 9_999.0), id: m.id)
            }
            let pb = paramsB(m)
            let tt = tps(m)
            // Larger paramsB first; then higher tps.
            return RouteSortKey(state: st, role: rr, primary: -(pb > 0 ? pb : 0.0), secondary: -(tt > 0 ? tt : 0.0), id: m.id)
        }

        let sorted = models.sorted { sortKey($0) < sortKey($1) }

        // Primary role wins (even if it requires auto-load).
        if primaryRole != "general" {
            if let m = sorted.first(where: { $0.state == .loaded && modelRoles($0).contains(primaryRole) }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_loaded", willAutoLoad: false)
            }
            if allowAutoLoad, let m = sorted.first(where: { $0.state != .loaded && modelRoles($0).contains(primaryRole) }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_autoload", willAutoLoad: true)
            }
        }

        // Loaded role match.
        if let m = sorted.first(where: { $0.state == .loaded && roleIndex($0) < 999 }) {
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_loaded", willAutoLoad: false)
        }
        // Any loaded.
        if let m = sorted.first(where: { $0.state == .loaded }) {
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "fallback_loaded", willAutoLoad: false)
        }

        // Auto-load routing.
        if allowAutoLoad {
            if let m = sorted.first(where: { $0.state != .loaded && roleIndex($0) < 999 }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_autoload", willAutoLoad: true)
            }
            if let m = sorted.first(where: { $0.state != .loaded }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "fallback_autoload", willAutoLoad: true)
            }
        }

        return RouteDecision(modelId: "", modelName: "", modelState: nil, reason: "model_not_loaded", willAutoLoad: false)
    }

    private func effectivePreferredModelId() -> String {
        // UI override wins; otherwise use the persisted per-task default.
        if !preferredModelId.isEmpty {
            return preferredModelId
        }
        let k = taskType.rawValue
        return (store.routingPreferredModelIdByTask[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RoutingDefaultsRow: View {
    @EnvironmentObject private var store: HubStore
    let taskType: HubTaskType
    let preferredByTask: [String: String]

    var body: some View {
        let k = taskType.rawValue
        let cur = (preferredByTask[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        HStack {
            Text("Default")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Auto") { store.setRoutingPreferredModel(taskType: k, modelId: nil) }
                Divider()
                ForEach(ModelStore.shared.snapshot.models) { m in
                    Button("\(m.id)") { store.setRoutingPreferredModel(taskType: k, modelId: m.id) }
                }
            } label: {
                Text(cur.isEmpty ? "Auto" : cur)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func formatBytes(_ b: Int64) -> String {
    let u = ByteCountFormatter()
    u.allowedUnits = [.useGB]
    u.countStyle = .memory
    return u.string(fromByteCount: b)
}
