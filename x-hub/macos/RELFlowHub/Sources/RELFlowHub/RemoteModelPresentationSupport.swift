import Foundation
import RELFlowHubCore

enum RemoteModelLoadState: Equatable {
    case loaded
    case available
    case needsSetup
}

struct RemoteModelGroupPlan: Identifiable, Equatable {
    let id: String
    let keyReference: String
    let title: String
    let detail: String?
    let models: [RemoteModelEntry]
    let loadedCount: Int
    let availableCount: Int
    let needsSetupCount: Int
    let enabledCount: Int

    var primaryModel: RemoteModelEntry {
        models[0]
    }

    var loadableModelIDs: [String] {
        models.filter { RemoteModelPresentationSupport.state(for: $0) == .available }.map(\.id)
    }

    var enabledModelIDs: [String] {
        models.filter(\.enabled).map(\.id)
    }
}

enum RemoteModelPresentationSupport {
    static func state(for entry: RemoteModelEntry) -> RemoteModelLoadState {
        var candidate = entry
        candidate.enabled = true
        let ready = RemoteModelStorage.isExecutionReadyRemoteModel(candidate)

        if entry.enabled && ready {
            return .loaded
        }
        if ready {
            return .available
        }
        return .needsSetup
    }

    static func groups(
        from models: [RemoteModelEntry],
        healthSnapshot: RemoteKeyHealthSnapshot? = nil
    ) -> [RemoteModelGroupPlan] {
        let sortedModels = sorted(models)
        let grouped = Dictionary(grouping: sortedModels, by: groupIdentifier(for:))
        let healthByKey = Dictionary(
            uniqueKeysWithValues: (healthSnapshot?.records ?? []).map { ($0.keyReference, $0) }
        )

        return grouped.compactMap { groupID, models in
            guard !models.isEmpty else { return nil }

            let states = models.map(state(for:))
            return RemoteModelGroupPlan(
                id: groupID,
                keyReference: RemoteModelStorage.keyReference(for: models.first),
                title: groupTitle(for: models),
                detail: groupDetail(for: models),
                models: models,
                loadedCount: states.filter { $0 == .loaded }.count,
                availableCount: states.filter { $0 == .available }.count,
                needsSetupCount: states.filter { $0 == .needsSetup }.count,
                enabledCount: models.filter(\.enabled).count
            )
        }
        .sorted { lhs, rhs in
            let lhsHealth = healthByKey[lhs.keyReference]
            let rhsHealth = healthByKey[rhs.keyReference]
            let lhsPriority = RemoteKeyHealthSupport.sortPriority(for: lhsHealth)
            let rhsPriority = RemoteKeyHealthSupport.sortPriority(for: rhsHealth)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            let lhsRecency = RemoteKeyHealthSupport.recency(for: lhsHealth)
            let rhsRecency = RemoteKeyHealthSupport.recency(for: rhsHealth)
            if lhsRecency != rhsRecency {
                return lhsRecency > rhsRecency
            }
            if lhs.loadedCount != rhs.loadedCount {
                return lhs.loadedCount > rhs.loadedCount
            }
            if lhs.availableCount != rhs.availableCount {
                return lhs.availableCount > rhs.availableCount
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func sorted(_ models: [RemoteModelEntry]) -> [RemoteModelEntry] {
        models.sorted { lhs, rhs in
            let lhsGroupTitle = (lhs.effectiveGroupDisplayName ?? backendLabel(for: lhs)).lowercased()
            let rhsGroupTitle = (rhs.effectiveGroupDisplayName ?? backendLabel(for: rhs)).lowercased()
            if lhsGroupTitle != rhsGroupTitle {
                return lhsGroupTitle < rhsGroupTitle
            }

            let lhsModelTitle = lhs.nestedDisplayName.lowercased()
            let rhsModelTitle = rhs.nestedDisplayName.lowercased()
            if lhsModelTitle != rhsModelTitle {
                return lhsModelTitle < rhsModelTitle
            }

            return lhs.id.lowercased() < rhs.id.lowercased()
        }
    }

    static func backendLabel(for entry: RemoteModelEntry) -> String {
        let backend = RemoteProviderEndpoints.canonicalBackend(entry.backend)
        switch backend {
        case "openai":
            return "OpenAI"
        case "anthropic":
            return "Anthropic"
        case "gemini":
            return "Gemini"
        case "remote_catalog":
            return "Catalog"
        default:
            return backend.isEmpty ? "Remote" : backend.uppercased()
        }
    }

    static func endpointHost(for entry: RemoteModelEntry) -> String? {
        guard let raw = entry.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return url.host ?? url.absoluteString
    }

    private static func groupIdentifier(for entry: RemoteModelEntry) -> String {
        let alias = (entry.effectiveGroupDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !alias.isEmpty {
            let keyReference = RemoteModelStorage.keyReference(for: entry)
            if !keyReference.isEmpty {
                return "alias::\(alias.lowercased())::key::\(keyReference.lowercased())"
            }
            if let host = endpointHost(for: entry), !host.isEmpty {
                return "alias::\(alias.lowercased())::host::\(host.lowercased())"
            }
            return "alias::\(alias.lowercased())::backend::\(RemoteProviderEndpoints.canonicalBackend(entry.backend).lowercased())"
        }

        let keyReference = RemoteModelStorage.keyReference(for: entry)
        if !keyReference.isEmpty {
            return "key::\(keyReference.lowercased())"
        }

        if let host = endpointHost(for: entry), !host.isEmpty {
            return "host::\(host.lowercased())"
        }

        let backend = RemoteProviderEndpoints.canonicalBackend(entry.backend)
        return "backend::\(backend.lowercased())"
    }

    private static func groupTitle(for models: [RemoteModelEntry]) -> String {
        if let alias = models.compactMap(\.effectiveGroupDisplayName).first, !alias.isEmpty {
            return alias
        }

        let keyReference = RemoteModelStorage.keyReference(for: models.first)
        if !keyReference.isEmpty {
            return keyReference
        }

        if let first = models.first, let host = endpointHost(for: first), !host.isEmpty {
            return host
        }

        if let first = models.first {
            return backendLabel(for: first)
        }

        return "Remote"
    }

    private static func groupDetail(for models: [RemoteModelEntry]) -> String? {
        guard let first = models.first else { return nil }

        var parts: [String] = [backendLabel(for: first)]

        let keyReference = RemoteModelStorage.keyReference(for: first)
        if !keyReference.isEmpty, keyReference != groupTitle(for: models) {
            parts.append(keyReference)
        }

        if let host = endpointHost(for: first), !host.isEmpty, host != groupTitle(for: models) {
            parts.append(host)
        }

        let normalized = Array(NSOrderedSet(array: parts)) as? [String] ?? parts
        guard !normalized.isEmpty else { return nil }
        return normalized.joined(separator: " · ")
    }
}
