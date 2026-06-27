import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func remoteModelGroupCard(_ group: RemoteModelKeyGroup) -> some View {
        let usageLimitNotice = remoteKeyUsageLimitNotice(for: group)
        let healthPresentation = remoteKeyHealthPresentation(for: group, usageLimitNotice: usageLimitNotice)
        let slotPresentations = remoteKeySlotPresentations(for: group)
        let detailBinding = expansionBinding(group.id, in: $expandedRemoteModelGroupIDs)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.title)
                            .font(.callout.weight(.semibold))
                        if let healthPresentation {
                            remoteModelStatusBadge(healthPresentation.badgeText, tint: healthPresentation.tint)
                        }
                    }
                    Text(group.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let detail = group.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let healthPresentation {
                        Text(healthPresentation.detailText)
                            .font(.caption2)
                            .foregroundStyle(healthPresentation.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !slotPresentations.isEmpty {
                        remoteKeySlotStatusList(slotPresentations)
                    }
                    keychainStatusLine(model: group.primaryModel)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(HubUIStrings.Settings.RemoteModels.loadAll) {
                            setRemoteModelsEnabled(group.loadableModelIDs, enabled: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(group.loadableModelIDs.isEmpty)

                        Button(HubUIStrings.Settings.RemoteModels.unloadAll) {
                            setRemoteModelsEnabled(group.enabledModelIDs, enabled: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(group.enabledModelIDs.isEmpty)
                    }

                    Menu {
                        Button(HubUIStrings.Settings.RemoteModels.rescan) {
                            store.quickScanRemoteKeyHealth(for: [group.keyReference])
                        }
                        .disabled(store.remoteKeyHealthScanInFlight)

                        Button(group.renameActionTitle) {
                            editingRemoteModelGroup = group
                        }

                        Divider()

                        Button(HubUIStrings.Settings.RemoteModels.removeKeyGroup, role: .destructive) {
                            removeRemoteModelGroup(group)
                        }
                    } label: {
                        settingsActionChipLabel(
                            title: "管理",
                            systemName: "slider.horizontal.3",
                            tint: .secondary
                        )
                    }
                }
            }

            settingsInlineDisclosureGroup(
                systemName: "square.stack.3d.up.fill",
                title: "组内模型明细",
                summary: remoteModelGroupDisclosureSummary(group),
                badge: detailBinding.wrappedValue ? "已展开" : "折叠中",
                tint: .indigo,
                isExpanded: detailBinding
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(group.models) { model in
                        remoteModelRow(model)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

}
