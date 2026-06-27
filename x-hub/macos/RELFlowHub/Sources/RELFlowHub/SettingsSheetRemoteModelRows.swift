import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func remoteKeySlotStatusList(_ slots: [RemoteKeySlotHealthPresentation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(slots) { slot in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(slot.keyReference)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        remoteModelStatusBadge(slot.badgeText, tint: slot.tint)
                    }
                    Text(slot.detailText)
                        .font(.caption2)
                        .foregroundStyle(slot.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    func remoteModelRow(_ model: RemoteModelEntry) -> some View {
        let loadState = RemoteModelPresentationSupport.state(for: model)
        let statusText = remoteModelStatusText(loadState)
        let statusTint = remoteModelStatusTint(loadState)
        let title = model.nestedDisplayName
        let signals = remoteModelSignals(for: model)
        let metadataTags = remoteModelMetadataTags(for: model)
        let subtitle = remoteModelSubtitle(model)
        let detailLine = remoteModelDetailLine(model)
        let canLoad = loadState == .available
        let isEnabled = model.enabled

        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(remoteModelGlyphTint(for: model).opacity(0.16))
                Image(systemName: remoteModelGlyphName(for: model))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(remoteModelGlyphTint(for: model))
            }
            .frame(width: 30, height: 30)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    remoteModelStatusBadge(statusText, tint: statusTint)
                }

                Text(model.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                if !signals.isEmpty || !metadataTags.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            ForEach(signals) { signal in
                                remoteModelSignalBadge(signal)
                            }
                            ForEach(metadataTags, id: \.self) { tag in
                                remoteModelChip(tag, tint: .secondary)
                            }
                        }

                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if let detailLine {
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                if isEnabled {
                    Button(HubUIStrings.Settings.RemoteModels.unload) {
                        setRemoteModelsEnabled([model.id], enabled: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(HubUIStrings.Settings.RemoteModels.load) {
                        setRemoteModelsEnabled([model.id], enabled: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canLoad)
                }

                Button(HubUIStrings.Settings.RemoteModels.remove) {
                    removeRemoteModel(id: model.id)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(10)
        .background(isEnabled ? Color.white.opacity(0.04) : Color.white.opacity(0.025))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEnabled ? Color.white.opacity(0.08) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func keychainStatusLine(model: RemoteModelEntry) -> some View {
        let status = keychainStatus(model: model)
        Text(status.text)
            .font(.caption2)
            .foregroundStyle(status.color)
    }
}
