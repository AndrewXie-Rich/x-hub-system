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

    @ViewBuilder
    private func remoteKeySlotStatusList(_ slots: [RemoteKeySlotHealthPresentation]) -> some View {
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
    private func remoteModelRow(_ model: RemoteModelEntry) -> some View {
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
    private func keychainStatusLine(model: RemoteModelEntry) -> some View {
        let status = keychainStatus(model: model)
        Text(status.text)
            .font(.caption2)
            .foregroundStyle(status.color)
    }

    private func remoteModelStatusText(_ state: RemoteModelLoadState) -> String {
        switch state {
        case .loaded:
            return HubUIStrings.Settings.RemoteModels.loaded
        case .available:
            return HubUIStrings.Settings.RemoteModels.available
        case .needsSetup:
            return HubUIStrings.Settings.RemoteModels.needsSetup
        }
    }

    private func remoteModelStatusTint(_ state: RemoteModelLoadState) -> Color {
        switch state {
        case .loaded:
            return .green
        case .available:
            return .secondary
        case .needsSetup:
            return .orange
        }
    }

    @ViewBuilder
    private func remoteModelChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func remoteModelSignalBadge(_ signal: RemoteModelSignalVisual) -> some View {
        HStack(spacing: 5) {
            Image(systemName: signal.systemName)
                .imageScale(.small)
            Text(signal.title)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(signal.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(signal.tint.opacity(0.12))
        .overlay(
            Capsule()
                .stroke(signal.tint.opacity(0.24), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func remoteModelStatusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func remoteModelGlyphName(for model: RemoteModelEntry) -> String {
        let haystack = remoteModelSearchText(model)
        if remoteModelLooksEmbedding(haystack) {
            return "point.3.connected.trianglepath.dotted"
        }
        if remoteModelLooksVoice(haystack) {
            return "speaker.wave.2.fill"
        }
        if remoteModelLooksAudio(haystack) {
            return "waveform"
        }
        if remoteModelLooksVision(haystack) {
            return "photo.on.rectangle"
        }
        if remoteModelLooksCode(haystack) {
            return "curlybraces"
        }
        return "cloud"
    }

    private func remoteModelGlyphTint(for model: RemoteModelEntry) -> Color {
        let haystack = remoteModelSearchText(model)
        if remoteModelLooksEmbedding(haystack) {
            return .green
        }
        if remoteModelLooksVoice(haystack) {
            return .mint
        }
        if remoteModelLooksAudio(haystack) {
            return .pink
        }
        if remoteModelLooksVision(haystack) {
            return .orange
        }
        if remoteModelLooksCode(haystack) {
            return .blue
        }
        return .secondary
    }

    private func remoteModelSignals(for model: RemoteModelEntry) -> [RemoteModelSignalVisual] {
        let haystack = remoteModelSearchText(model)
        var signals: [RemoteModelSignalVisual] = [
            RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "hosted"), systemName: "cloud", tint: .blue)
        ]

        if remoteModelLooksReasoning(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "reasoning"), systemName: "sparkles", tint: .secondary))
        }
        if remoteModelLooksCode(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "code"), systemName: "curlybraces", tint: .blue))
        }
        if remoteModelLooksVision(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "vision"), systemName: "photo.on.rectangle", tint: .orange))
        }
        if remoteModelLooksEmbedding(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "embedding"), systemName: "point.3.connected.trianglepath.dotted", tint: .green))
        }
        if remoteModelLooksAudio(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "audio"), systemName: "waveform", tint: .pink))
        }
        if remoteModelLooksVoice(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "voice"), systemName: "speaker.wave.2.fill", tint: .mint))
        }

        var seen: Set<String> = []
        return signals.filter { seen.insert($0.title).inserted }
    }

    private func remoteModelMetadataTags(for model: RemoteModelEntry) -> [String] {
        var tags: [String] = []
        let backend = RemoteProviderEndpoints.canonicalBackend(model.backend).uppercased()
        if !backend.isEmpty {
            tags.append(backend)
        }
        if model.contextLength > 0 {
            tags.append(
                HubUIStrings.Settings.RemoteModels.configuredContextTag(
                    remoteModelContextSummary(model.contextLength)
                )
            )
        }
        if let knownContextLength = model.knownContextLength, knownContextLength > 0 {
            let summary = remoteModelContextSummary(knownContextLength)
            switch model.knownContextSource {
            case .providerReported:
                tags.append(HubUIStrings.Settings.RemoteModels.providerReportedContextTag(summary))
            case .catalogEstimate:
                tags.append(HubUIStrings.Settings.RemoteModels.catalogEstimatedContextTag(summary))
            case nil:
                break
            }
        }
        if let upstream = model.upstreamModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !upstream.isEmpty,
           upstream != model.id {
            tags.append(HubUIStrings.Settings.RemoteModels.aliasTag)
        }
        let normalized = Array(NSOrderedSet(array: tags)) as? [String] ?? tags
        return Array(normalized.prefix(3))
    }

    private func remoteModelDetailLine(_ model: RemoteModelEntry) -> String? {
        var parts: [String] = []
        if let host = remoteModelEndpointHost(model) {
            parts.append(HubUIStrings.Settings.RemoteModels.endpoint(host))
        }
        if let upstream = model.upstreamModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !upstream.isEmpty,
           upstream != model.id {
            parts.append(HubUIStrings.Settings.RemoteModels.upstreamModel(upstream))
        }
        let note = (model.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note)
        }
        if model.knownContextLength == nil {
            parts.append(HubUIStrings.Settings.RemoteModels.providerContextUnknown)
        } else if model.knownContextSource == .catalogEstimate {
            parts.append(HubUIStrings.Settings.RemoteModels.catalogEstimateHint)
        }
        guard !parts.isEmpty else { return nil }
        return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
    }

    private func remoteModelSubtitle(_ model: RemoteModelEntry) -> String {
        let upstream = (model.upstreamModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let keyRef = RemoteModelStorage.keyReference(for: model)
        let backend = RemoteProviderEndpoints.canonicalBackend(model.backend)
        let context = HubUIStrings.Settings.RemoteModels.detailSummary(
            remoteModelContextSummaryParts(for: model)
        )
        if upstream.isEmpty || upstream == model.id {
            return HubUIStrings.Settings.RemoteModels.subtitleNoUpstream(
                modelID: model.id,
                backend: backend,
                context: context,
                keyRef: keyRef
            )
        }
        return HubUIStrings.Settings.RemoteModels.subtitleWithUpstream(
            modelID: model.id,
            upstream: upstream,
            backend: backend,
            context: context,
            keyRef: keyRef
        )
    }

    private func remoteModelContextSummary(_ contextLength: Int) -> String {
        HubUIStrings.Settings.RemoteModels.contextLength(contextLength)
    }

    private func remoteModelContextSummaryParts(for model: RemoteModelEntry) -> [String] {
        var parts: [String] = []
        if model.contextLength > 0 {
            parts.append(
                HubUIStrings.Settings.RemoteModels.configuredContext(
                    remoteModelContextSummary(model.contextLength)
                )
            )
        }
        if let knownContextLength = model.knownContextLength, knownContextLength > 0 {
            let summary = remoteModelContextSummary(knownContextLength)
            switch model.knownContextSource {
            case .providerReported:
                parts.append(HubUIStrings.Settings.RemoteModels.providerReportedContext(summary))
            case .catalogEstimate:
                parts.append(HubUIStrings.Settings.RemoteModels.catalogEstimatedContext(summary))
            case nil:
                break
            }
        } else if model.contextLength > 0 {
            parts.append(HubUIStrings.Settings.RemoteModels.providerContextUnknown)
        }
        return parts
    }

    func remoteModelEndpointHost(_ model: RemoteModelEntry) -> String? {
        guard let raw = model.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return url.host ?? url.absoluteString
    }

    private func remoteModelSearchText(_ model: RemoteModelEntry) -> String {
        [
            model.id,
            model.name,
            model.backend,
            model.upstreamModelId ?? "",
            model.note ?? "",
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func remoteModelLooksReasoning(_ haystack: String) -> Bool {
        if remoteModelLooksEmbedding(haystack) || remoteModelLooksAudio(haystack) || remoteModelLooksVoice(haystack) {
            return false
        }
        return remoteModelContainsAny(
            haystack,
            needles: ["gpt", "claude", "gemini", "reason", "think", "sonnet", "opus", "o1", "o3", "o4", "r1", "qwq", "kimi", "qwen"]
        )
    }

    private func remoteModelLooksCode(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["coder", "codex", "codestral", "codegemma", "deepseek-coder", "qwen2.5-coder", "codeqwen"]
        )
    }

    private func remoteModelLooksVision(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["vision", "image", "vl", "llava", "pixtral", "moondream", "gpt-4o", "gemini", "claude", "see", "omni"]
        )
    }

    private func remoteModelLooksEmbedding(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["embedding", "embed", "text-embedding", "bge", "gte", "e5"]
        )
    }

    private func remoteModelLooksAudio(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["audio", "speech", "stt", "asr", "whisper", "transcribe"]
        )
    }

    private func remoteModelLooksVoice(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["tts", "voice", "text-to-speech"]
        )
    }

    private func remoteModelContainsAny(_ haystack: String, needles: [String]) -> Bool {
        needles.contains(where: { haystack.contains($0) })
    }

    private func keychainStatus(model: RemoteModelEntry) -> (text: String, color: Color) {
        let inMemory = (model.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !inMemory.isEmpty {
            if KeychainStore.hasSharedAccessGroup {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetKeychainEncrypted, .secondary)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeySetEncrypted, .secondary)
        }

        let hasEncrypted = !(model.apiKeyCiphertext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let acct = RemoteModelStorage.keyReference(for: model)

        // Avoid triggering repeated Keychain prompts in ad-hoc/dev builds (no shared access group).
        if !KeychainStore.hasSharedAccessGroup {
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedLocked, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyUnset, .red)
        }

        switch KeychainStore.read(account: acct) {
        case .value:
            return (HubUIStrings.Settings.RemoteModels.apiKeySetKeychain, .secondary)
        case .notFound:
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedLocked, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyUnset, .red)
        case .error(let msg):
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedKeychainError, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyKeychainError(msg), .red)
        }
    }

    private func remoteKeyUsageLimitNotice(for group: RemoteModelKeyGroup) -> RemoteKeyUsageLimitNotice? {
        RemoteModelTrialIssueSupport.latestUsageLimitNotice(
            in: group.models.compactMap { store.remoteModelTrialStatus(for: $0.id) }
        )
    }

    private func remoteKeyHealthPresentation(
        for group: RemoteModelKeyGroup,
        usageLimitNotice: RemoteKeyUsageLimitNotice?
    ) -> RemoteKeyHealthPresentation? {
        RemoteKeyHealthPresentationSupport.presentation(
            health: store.remoteKeyHealth(for: group.keyReference),
            usageLimitNotice: usageLimitNotice,
            isScanning: store.isRemoteKeyHealthScanInProgress(for: group.keyReference)
        )
    }

    private func remoteKeySlotPresentations(for group: RemoteModelKeyGroup) -> [RemoteKeySlotHealthPresentation] {
        RemoteKeyHealthPresentationSupport.slotPresentations(
            models: group.models,
            healthSnapshot: store.remoteKeyHealthSnapshot,
            isScanning: { keyReference in
                store.isRemoteKeyHealthScanInProgress(for: keyReference)
            }
        )
    }
}
