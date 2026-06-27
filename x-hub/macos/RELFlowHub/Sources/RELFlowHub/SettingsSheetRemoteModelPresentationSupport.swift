import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func remoteModelStatusText(_ state: RemoteModelLoadState) -> String {
        switch state {
        case .loaded:
            return HubUIStrings.Settings.RemoteModels.loaded
        case .available:
            return HubUIStrings.Settings.RemoteModels.available
        case .needsSetup:
            return HubUIStrings.Settings.RemoteModels.needsSetup
        }
    }

    func remoteModelStatusTint(_ state: RemoteModelLoadState) -> Color {
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
    func remoteModelChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    func remoteModelSignalBadge(_ signal: RemoteModelSignalVisual) -> some View {
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
    func remoteModelStatusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    func remoteModelGlyphName(for model: RemoteModelEntry) -> String {
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

    func remoteModelGlyphTint(for model: RemoteModelEntry) -> Color {
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

    func remoteModelSignals(for model: RemoteModelEntry) -> [RemoteModelSignalVisual] {
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

    func remoteModelMetadataTags(for model: RemoteModelEntry) -> [String] {
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

    func remoteModelDetailLine(_ model: RemoteModelEntry) -> String? {
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

    func remoteModelSubtitle(_ model: RemoteModelEntry) -> String {
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

    func remoteModelEndpointHost(_ model: RemoteModelEntry) -> String? {
        guard let raw = model.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return url.host ?? url.absoluteString
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
}
