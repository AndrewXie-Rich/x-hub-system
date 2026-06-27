import SwiftUI
import AppKit
import RELFlowHubCore

struct RemoteModelKeyGroup: Identifiable {
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
        models
            .filter { RemoteModelPresentationSupport.state(for: $0) == .available }
            .map(\.id)
    }

    var enabledModelIDs: [String] {
        models.filter(\.enabled).map(\.id)
    }

    var renameActionTitle: String {
        primaryModel.effectiveGroupDisplayName == nil
            ? HubUIStrings.Settings.RemoteModels.setGroupName
            : HubUIStrings.Settings.RemoteModels.renameGroup
    }

    var summary: String {
        var parts = [HubUIStrings.Settings.RemoteModels.keyGroupSummary(count: models.count, enabled: enabledCount)]
        if loadedCount > 0 {
            parts.append("\(loadedCount) \(HubUIStrings.Settings.RemoteModels.loaded)")
        }
        if availableCount > 0 {
            parts.append("\(availableCount) \(HubUIStrings.Settings.RemoteModels.available)")
        }
        if needsSetupCount > 0 {
            parts.append("\(needsSetupCount) \(HubUIStrings.Settings.RemoteModels.needsSetup)")
        }
        return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
    }
}

struct EditRemoteModelGroupDisplayNameSheet: View {
    let group: RemoteModelKeyGroup
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String

    init(group: RemoteModelKeyGroup, onSave: @escaping (String) -> Void) {
        self.group = group
        self.onSave = onSave
        _draftName = State(initialValue: group.primaryModel.effectiveGroupDisplayName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(HubUIStrings.Settings.RemoteModels.editGroupNameTitle)
                .font(.headline)

            Text(HubUIStrings.Settings.RemoteModels.editGroupNameSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(HubUIStrings.Settings.RemoteModels.editGroupNamePlaceholder, text: $draftName)
                .textFieldStyle(.roundedBorder)

            if group.primaryModel.effectiveGroupDisplayName == nil {
                Text(HubUIStrings.Settings.RemoteModels.fallbackGroupTitle(group.title))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.RemoteModels.cancel) {
                    dismiss()
                }
                Spacer()
                Button(HubUIStrings.Settings.RemoteModels.editGroupNameSave) {
                    onSave(draftName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420, height: 190)
    }
}
