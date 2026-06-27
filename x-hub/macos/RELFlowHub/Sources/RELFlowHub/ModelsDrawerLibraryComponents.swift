import SwiftUI
import RELFlowHubCore

struct ModelsDrawerLocalModelRow: View {
    var model: HubModel
    var stateText: String
    var stateColor: Color
    var detail: String
    var tags: [String]
    var trialStatus: ModelTrialStatus?
    var healthScanInProgress: Bool
    var onQuickCheck: () -> Void
    var onPinForTask: (HubTaskType) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: model.state == .loaded ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(stateColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(stateText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stateColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(stateColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ModelsDrawerChipList(chips: tags, tint: .indigo)

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ModelsDrawerIconButton(
                    title: "轻量预检",
                    systemName: "heart.text.square",
                    disabled: healthScanInProgress,
                    action: onQuickCheck
                )

                ModelsDrawerTaskPinMenu(
                    disabled: false,
                    onPinForTask: onPinForTask
                )
            }
            .fixedSize()
        }
    }
}

struct ModelsDrawerLibraryRow: View {
    var item: ModelsDrawerLibraryItem
    var trialStatus: ModelTrialStatus?
    var onPinForTask: (HubTaskType) -> Void
    var onTest: () -> Void
    var onSetRemoteEnabled: (Bool) -> Void
    var onRemoveRemoteModel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.isLocal ? "internaldrive" : "cloud")
                .foregroundStyle(item.isLocal ? Color.indigo : Color.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(item.statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(item.statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text("\(item.provider) · \(item.detail)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ModelsDrawerChipList(chips: item.tags, tint: item.isLocal ? .indigo : .blue)

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ModelsDrawerTaskPinMenu(
                    disabled: !item.isReady,
                    onPinForTask: onPinForTask
                )
                ModelsDrawerIconButton(
                    title: "测试",
                    systemName: "waveform.path.ecg",
                    disabled: !item.isReady,
                    action: onTest
                )
                if let remoteEntry = item.remoteEntry {
                    if remoteEntry.enabled {
                        ModelsDrawerIconButton(
                            title: "停用",
                            systemName: "pause",
                            disabled: false
                        ) {
                            onSetRemoteEnabled(false)
                        }
                    } else {
                        ModelsDrawerIconButton(
                            title: "启用",
                            systemName: "play",
                            disabled: !item.isReady
                        ) {
                            onSetRemoteEnabled(true)
                        }
                    }

                    ModelsDrawerIconButton(
                        title: "移除",
                        systemName: "trash",
                        disabled: false,
                        action: onRemoveRemoteModel
                    )
                }
            }
            .fixedSize()
        }
    }
}
