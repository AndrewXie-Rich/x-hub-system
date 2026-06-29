import SwiftUI
import RELFlowHubCore

extension ModelsDrawer {
    func remoteDrawerGroups(from models: [RemoteModelEntry]) -> [RemoteDrawerGroup] {
        RemoteModelPresentationSupport.groups(
            from: models,
            healthSnapshot: store.remoteKeyHealthSnapshot
        ).map { group in
            let drawerModels = group.models.map(Self.remoteDrawerModel(for:))
            return RemoteDrawerGroup(
                id: group.id,
                keyReference: group.keyReference,
                title: group.title,
                summary: remoteGroupSummary(group),
                detail: group.detail,
                statusText: remoteGroupStatusText(group),
                statusColor: remoteGroupStatusColor(group),
                availableCount: group.availableCount,
                needsSetupCount: group.needsSetupCount,
                enabledModelIDs: group.enabledModelIDs,
                loadableModelIDs: group.loadableModelIDs,
                models: drawerModels
            )
        }
    }

    private func remoteGroupSummary(_ group: RemoteModelGroupPlan) -> String {
        var parts = ["\(group.models.count) 模型"]
        if group.loadedCount > 0 {
            parts.append("\(group.loadedCount) 已启用")
        }
        if group.availableCount > 0 {
            parts.append("\(group.availableCount) 可启用")
        }
        if group.needsSetupCount > 0 {
            parts.append("\(group.needsSetupCount) 需配置")
        }
        return parts.joined(separator: " · ")
    }

    private func remoteGroupStatusText(_ group: RemoteModelGroupPlan) -> String {
        if group.loadedCount == group.models.count {
            return "已启用"
        }
        if group.needsSetupCount == group.models.count {
            return "需配置"
        }
        if group.availableCount == group.models.count {
            return "可启用"
        }
        return "混合"
    }

    private func remoteGroupStatusColor(_ group: RemoteModelGroupPlan) -> Color {
        if group.loadedCount == group.models.count {
            return .green
        }
        if group.needsSetupCount == group.models.count {
            return .orange
        }
        return .secondary
    }

    private static func remoteDrawerModel(for entry: RemoteModelEntry) -> RemoteDrawerModel {
        let loadState = RemoteModelPresentationSupport.state(for: entry)
        let canLoad = loadState == .available
        let isLoaded = loadState == .loaded
        let statusText: String
        let statusColor: Color
        switch loadState {
        case .loaded:
            statusText = "已启用"
            statusColor = .green
        case .available:
            statusText = "可启用"
            statusColor = .secondary
        case .needsSetup:
            statusText = "需配置"
            statusColor = .orange
        }

        return RemoteDrawerModel(
            entry: entry,
            title: entry.nestedDisplayName,
            subtitle: remoteModelSubtitle(for: entry),
            detail: remoteModelDetail(for: entry),
            statusText: statusText,
            statusColor: statusColor,
            isLoaded: isLoaded,
            canLoad: canLoad
        )
    }

    private static func remoteUpstreamTitle(for entry: RemoteModelEntry) -> String {
        entry.effectiveProviderModelID
    }

    private static func remoteModelSubtitle(for entry: RemoteModelEntry) -> String {
        let backend = RemoteModelPresentationSupport.backendLabel(for: entry)
        let context = remoteContextSummary(for: entry)
        return "\(entry.id) · \(backend) · \(context)"
    }

    private static func remoteModelDetail(for entry: RemoteModelEntry) -> String? {
        var parts: [String] = []

        if let host = RemoteModelPresentationSupport.endpointHost(for: entry), !host.isEmpty {
            parts.append(host)
        }

        let keyReference = RemoteModelStorage.keyReference(for: entry)
        if !keyReference.isEmpty {
            parts.append("Key \(keyReference)")
        }

        let note = (entry.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    static func remoteContextSummary(for entry: RemoteModelEntry) -> String {
        let configured = max(512, entry.contextLength)
        if let known = entry.knownContextLength, known > configured {
            return "ctx \(configured) / max \(known)"
        }
        return "ctx \(configured)"
    }
}
