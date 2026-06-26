import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RELFlowHubCore

enum AddRemoteModelImportBehavior {
    static func shouldPreserveExistingAPIKeyOnConfigImport(
        currentAPIKey: String,
        importedAPIKey: String
    ) -> Bool {
        let current = currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let imported = importedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, !imported.isEmpty else { return false }
        return current != imported
    }

    static func shouldPreserveExistingBaseURLOnAuthImport(
        existingBaseURL: String,
        rawCredentialBaseURL: String
    ) -> Bool {
        let existing = existingBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = rawCredentialBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !existing.isEmpty && raw.isEmpty
    }
}

struct AddRemoteModelSheet: View {
    let onAdd: ([RemoteModelEntry]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var modelId: String = ""
    @State private var modelName: String = ""
    @State private var backend: String = "openai"
    @State private var contextLength: String = "8192"
    @State private var enabled: Bool = true
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var apiKeyRef: String = ""
    @State private var wireAPI: String = ""
    @State private var idPrefix: String = ""
    @State private var localIdSuffix: String = ""
    @State private var note: String = ""
    @State private var importedCredentialVariants: [CodexProviderImportResolver.ResolvedCredentialVariant] = []
    @State private var importedCredentialFingerprint: String = ""
    @State private var importedProviderKeyImportSource: ProviderKeyImportSource?

    @State private var discoveredModelIds: [String] = []
    @State private var importAllDiscovered: Bool = false
    @State private var isFetchingModels: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    providerCard
                    authCard
                    discoveryCard
                    identityCard
                    importOptionsCard

                    if !errorText.isEmpty {
                        issueBanner(errorText, tint: .red)
                    }
                }
                .padding(.bottom, 6)
            }

            HStack(spacing: 10) {
                Button(HubUIStrings.Models.AddRemote.cancel) { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()

                Button(HubUIStrings.Models.AddRemote.add) {
                    addRemoteModels()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isFetchingModels)
                .buttonStyle(.plain)
                .foregroundStyle(isFetchingModels ? .secondary : Color.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isFetchingModels ? Color.white.opacity(0.06) : Color.accentColor.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFetchingModels ? Color.white.opacity(0.08) : Color.accentColor.opacity(0.98), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(18)
        .frame(width: 620, height: 700)
        .onAppear {
            idPrefix = defaultPrefix(for: backend)
            if apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                apiKeyRef = defaultAPIKeyRef(backend: backend, baseURL: baseURL)
            }
        }
        .onChange(of: backend) { newValue in
            let current = normalizedPrefix(idPrefix)
            if current.isEmpty || current == "openai/" || current == "anthropic/" || current == "gemini/" || RemoteProviderEndpoints.isRemoteCatalogModelPrefix(current) {
                idPrefix = defaultPrefix(for: newValue)
            }
            // Only auto-update apiKeyRef when it still matches the previous default-ish value.
            let curRef = apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines)
            if curRef.isEmpty || curRef.hasPrefix("openai:") || curRef.hasPrefix("anthropic:") || curRef.hasPrefix("gemini:") || RemoteProviderEndpoints.isRemoteCatalogAPIKeyRefPrefix(curRef) {
                apiKeyRef = defaultAPIKeyRef(backend: newValue, baseURL: baseURL)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HubUIStrings.Models.AddRemote.title)
                    .font(.headline)
                Text(HubUIStrings.Models.AddRemote.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isFetchingModels {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(HubUIStrings.Models.AddRemote.fetching)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                summaryPill(HubUIStrings.Models.AddRemote.summaryProvider, value: backendDisplayTitle, tint: backendTint)
                summaryPill(HubUIStrings.Models.AddRemote.summaryEndpoint, value: endpointSummaryText, tint: .blue)
                summaryPill(HubUIStrings.Models.AddRemote.summaryImportTarget, value: importTargetSummary, tint: importTargetTint)
            }

            HStack(spacing: 6) {
                summaryTag(keyReferenceSummary)
                if activeImportedCredentialVariantCount > 1 {
                    summaryTag("同目录 key \(activeImportedCredentialVariantCount)")
                }
                summaryTag(HubUIStrings.Models.AddRemote.summaryContext(normalizedContextLengthText))
                summaryTag(HubUIStrings.Models.AddRemote.summaryEnabled(enabled))
                if !normalizedPrefix(idPrefix).isEmpty {
                    summaryTag(HubUIStrings.Models.AddRemote.summaryPrefix(normalizedPrefix(idPrefix)))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var providerCard: some View {
        sectionCard(
            title: HubUIStrings.Models.AddRemote.providerSection,
            subtitle: backendSubtitle
        ) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddRemote.backend)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(HubUIStrings.Models.AddRemote.backend, selection: $backend) {
                        Text(HubUIStrings.Models.AddRemote.backendOptionOpenAI).tag("openai")
                        Text(HubUIStrings.Models.AddRemote.backendOptionAnthropic).tag("anthropic")
                        Text(HubUIStrings.Models.AddRemote.backendOptionGemini).tag("gemini")
                        Text(HubUIStrings.Models.AddRemote.backendOptionRemoteCatalog).tag("remote_catalog")
                        Text(HubUIStrings.Models.AddRemote.backendOptionOpenAICompatible).tag("openai_compatible")
                        Text(HubUIStrings.Models.AddRemote.backendOptionCustomRemote).tag("remote")
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddRemote.baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(HubUIStrings.Models.AddRemote.baseURLPlaceholder, text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    Text(endpointHintText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var authCard: some View {
        sectionCard(
            title: HubUIStrings.Models.AddRemote.authSection,
            subtitle: HubUIStrings.Models.AddRemote.authSubtitle
        ) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddRemote.apiKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField(HubUIStrings.Models.AddRemote.apiKeyPlaceholder, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddRemote.apiKeyReference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(HubUIStrings.Models.AddRemote.apiKeyReferencePlaceholder, text: $apiKeyRef)
                        .textFieldStyle(.roundedBorder)
                    Text(HubUIStrings.Models.AddRemote.apiKeyReferenceDefaultHint(defaultAPIKeyRef(backend: backend, baseURL: baseURL)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    utilityButton(HubUIStrings.Models.AddRemote.importAuthJSON, systemName: "key.horizontal") {
                        importAuthJSON()
                    }
                    .disabled(isFetchingModels)

                    utilityButton(HubUIStrings.Models.AddRemote.importProviderConfig, systemName: "square.and.arrow.down") {
                        importProviderConfig()
                    }
                    .disabled(isFetchingModels)
                }
            }
        }
    }

    private var discoveryCard: some View {
        sectionCard(
            title: HubUIStrings.Models.AddRemote.discoverySection,
            subtitle: HubUIStrings.Models.AddRemote.discoverySubtitle
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    utilityButton(isFetchingModels ? HubUIStrings.Models.AddRemote.fetchingModels : HubUIStrings.Models.AddRemote.fetchModels, systemName: "arrow.triangle.2.circlepath") {
                        fetchModels()
                    }
                    .disabled(isFetchingModels)

                    if !discoveredModelIds.isEmpty {
                        Text(HubUIStrings.Models.AddRemote.discoveredCount(discoveredModelIds.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if !discoveredModelIds.isEmpty {
                    Toggle(HubUIStrings.Models.AddRemote.importAllDiscovered, isOn: $importAllDiscovered)

                    if importAllDiscovered {
                        Text(HubUIStrings.Models.AddRemote.importAllHint(discoveredModelIds.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(HubUIStrings.Models.AddRemote.discoveredModels)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker(HubUIStrings.Models.AddRemote.discoveredModels, selection: $modelId) {
                                ForEach(discoveredModelIds, id: \.self) { id in
                                    Text(id).tag(id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                } else {
                    Text(HubUIStrings.Models.AddRemote.noDiscoveryResults)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var identityCard: some View {
        sectionCard(
            title: HubUIStrings.Models.AddRemote.identitySection,
            subtitle: HubUIStrings.Models.AddRemote.identitySubtitle
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Models.AddRemote.modelID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(HubUIStrings.Models.AddRemote.modelIDPlaceholder, text: $modelId)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Models.AddRemote.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(HubUIStrings.Models.AddRemote.displayNamePlaceholder, text: $modelName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Models.AddRemote.modelIDPrefix)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(HubUIStrings.Models.AddRemote.modelIDPrefixPlaceholder, text: $idPrefix)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Models.AddRemote.localIDSuffix)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(HubUIStrings.Models.AddRemote.localIDSuffixPlaceholder, text: $localIdSuffix)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private var importOptionsCard: some View {
        sectionCard(
            title: HubUIStrings.Models.AddRemote.importOptionsSection,
            subtitle: HubUIStrings.Models.AddRemote.importOptionsSubtitle
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Models.AddRemote.contextLength)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(HubUIStrings.Models.AddRemote.contextLengthPlaceholder, text: $contextLength)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Models.AddRemote.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(HubUIStrings.Models.AddRemote.notePlaceholder, text: $note)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Toggle(HubUIStrings.Models.AddRemote.enableAfterImport, isOn: $enabled)
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryPill(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func summaryTag(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
    }

    private func issueBanner(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tint == .red ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func utilityButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .imageScale(.small)
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var canonicalBackend: String {
        RemoteProviderEndpoints.canonicalBackend(backend)
    }

    private var backendDisplayTitle: String {
        HubUIStrings.Models.AddRemote.backendDisplayTitle(canonicalBackend)
    }

    private var backendSubtitle: String {
        HubUIStrings.Models.AddRemote.backendSubtitle(canonicalBackend)
    }

    private var backendTint: Color {
        switch canonicalBackend {
        case "openai", "openai_compatible":
            return .blue
        case "anthropic":
            return .orange
        case "gemini":
            return .mint
        case "remote_catalog":
            return .purple
        default:
            return .secondary
        }
    }

    private var endpointSummaryText: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return HubUIStrings.Models.AddRemote.endpointSummaryFallback(canonicalBackend)
    }

    private var endpointHintText: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return HubUIStrings.Models.AddRemote.endpointHintText(
            canonicalBackend: canonicalBackend,
            hasCustomBaseURL: !trimmed.isEmpty
        )
    }

    private var keyReferenceSummary: String {
        let trimmed = apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultAPIKeyRef(backend: backend, baseURL: baseURL) : trimmed
    }

    private var normalizedContextLengthText: String {
        let value = Int(contextLength.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8192
        return "\(max(512, value))"
    }

    private var activeImportedCredentialVariantCount: Int {
        activeCredentialVariants().count
    }

    private var importTargetSummary: String {
        if importAllDiscovered, !discoveredModelIds.isEmpty {
            return HubUIStrings.Models.AddRemote.importTargetAll(discoveredModelIds.count)
        }
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if !discoveredModelIds.isEmpty {
            return HubUIStrings.Models.AddRemote.importTargetPickOne
        }
        return HubUIStrings.Models.AddRemote.importTargetFillModelID
    }

    private var importTargetTint: Color {
        if importAllDiscovered, !discoveredModelIds.isEmpty {
            return .blue
        }
        if !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .green
        }
        return .orange
    }

    private func fetchModels() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = HubUIStrings.Models.AddRemote.fetchRequiresAPIKey
            return
        }

        errorText = ""
        isFetchingModels = true

        // Keep Bridge window enabled so model/provider fetches can be audited/gated consistently.
        // In single-app mode this controls the embedded Bridge service.
        let bridgeStatus = BridgeSupport.shared.statusSnapshot()
        if !bridgeStatus.alive || !bridgeStatus.enabled {
            BridgeSupport.shared.restore(seconds: 30 * 60)
        }

        Task {
            do {
                let ids = try await RemoteProviderClient.fetchModelIds(
                    backend: backend,
                    apiKey: key,
                    baseURL: baseURL,
                    timeoutSec: 15.0
                )
                await MainActor.run {
                    discoveredModelIds = ids
                    if modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = ids.first {
                        modelId = first
                    }
                    importAllDiscovered = ids.count > 1
                    errorText = ids.isEmpty ? HubUIStrings.Models.AddRemote.providerReturnedEmptyModelList : ""
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    discoveredModelIds = []
                    importAllDiscovered = false
                    errorText = error.localizedDescription
                    isFetchingModels = false
                }
            }
        }
    }

    private func importAuthJSON() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = HubUIStrings.Models.AddRemote.importPanelPrompt
        panel.title = HubUIStrings.Models.AddRemote.importAuthPanelTitle

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let resolved = try CodexProviderImportResolver.resolveAuthImport(from: url)
            let rawImported = try ProviderAuthImport.load(from: url)
            let imported = resolved.credentials ?? rawImported
            apiKey = imported.apiKey
            let importedBase = imported.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawImportedBase = rawImported.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let preserveExistingBase = AddRemoteModelImportBehavior.shouldPreserveExistingBaseURLOnAuthImport(
                existingBaseURL: existingBase,
                rawCredentialBaseURL: rawImportedBase
            )
            let effectiveBase = preserveExistingBase
                ? existingBase
                : (importedBase.isEmpty ? existingBase : importedBase)
            let effectiveBackend: String
            if preserveExistingBase || (importedBase.isEmpty && !existingBase.isEmpty) {
                effectiveBackend = backend
            } else {
                effectiveBackend = imported.backend
            }
            let importedWireAPI = normalizedWireAPI(imported.wireAPI)
            backend = effectiveBackend
            baseURL = effectiveBase
            if !importedWireAPI.isEmpty {
                wireAPI = importedWireAPI
            }
            let importedKeyRef = imported.apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines)
            if preserveExistingBase {
                let existingRef = apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines)
                apiKeyRef = existingRef.isEmpty
                    ? defaultAPIKeyRef(backend: effectiveBackend, baseURL: effectiveBase)
                    : existingRef
            } else {
                apiKeyRef = importedKeyRef.isEmpty
                    ? defaultAPIKeyRef(backend: effectiveBackend, baseURL: effectiveBase)
                    : importedKeyRef
            }
            idPrefix = defaultPrefix(for: effectiveBackend)
            if let providerConfig = resolved.providerConfig {
                let preferredModelID = providerConfig.preferredModelID
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !preferredModelID.isEmpty {
                    modelId = preferredModelID
                }
            }
            if importedBase.isEmpty, effectiveBase.isEmpty {
                errorText = HubUIStrings.Models.AddRemote.importedAPIKeyMissingBaseURL
            } else {
                errorText = ""
            }
            importedCredentialVariants = preserveExistingBase ? [] : resolved.credentialVariants
            importedCredentialFingerprint = credentialFingerprint(
                backend: effectiveBackend,
                baseURL: effectiveBase,
                apiKey: imported.apiKey,
                apiKeyRef: apiKeyRef,
                wireAPI: importedWireAPI
            )
            importedProviderKeyImportSource = ProviderKeyImportSource(
                kind: "auth_dir",
                sourceRef: url.deletingLastPathComponent().path
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func importProviderConfig() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "toml") ?? .plainText, .plainText]
        panel.prompt = HubUIStrings.Models.AddRemote.importPanelPrompt
        panel.title = HubUIStrings.Models.AddRemote.importProviderConfigPanelTitle

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let resolved = try CodexProviderImportResolver.resolveConfigImport(from: url)
            let imported = try (resolved.providerConfig ?? ProviderConfigImport.load(from: url))
            let shouldPreserveCurrentKey = AddRemoteModelImportBehavior.shouldPreserveExistingAPIKeyOnConfigImport(
                currentAPIKey: apiKey,
                importedAPIKey: resolved.credentials?.apiKey ?? ""
            )
            backend = imported.backend
            baseURL = imported.baseURL
            apiKeyRef = imported.apiKeyRef
            wireAPI = normalizedWireAPI(imported.wireAPI)
            idPrefix = defaultPrefix(for: imported.backend)
            if !imported.preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelId = imported.preferredModelID
            }
            if let credentials = resolved.credentials, !shouldPreserveCurrentKey {
                apiKey = credentials.apiKey
            }
            importedCredentialVariants = shouldPreserveCurrentKey ? [] : resolved.credentialVariants
            importedCredentialFingerprint = credentialFingerprint(
                backend: imported.backend,
                baseURL: imported.baseURL,
                apiKey: shouldPreserveCurrentKey ? apiKey : (resolved.credentials?.apiKey ?? ""),
                apiKeyRef: imported.apiKeyRef,
                wireAPI: normalizedWireAPI(imported.wireAPI)
            )
            importedProviderKeyImportSource = ProviderKeyImportSource(
                kind: "config_path",
                sourceRef: url.path
            )
            errorText = ""
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func addRemoteModels() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = HubUIStrings.Models.AddRemote.addRequiresAPIKey
            return
        }

        let ctx = Int(contextLength.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8192
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let refRaw = apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = refRaw.isEmpty ? defaultAPIKeyRef(backend: backend, baseURL: base) : refRaw
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = sanitizeSuffix(localIdSuffix)
        let normalizedWireAPIValue = normalizedStoredWireAPI()
        let credentialVariants = activeCredentialVariants().isEmpty
            ? [
                CodexProviderImportResolver.ResolvedCredentialVariant(
                    credentials: ProviderAuthImport.ImportedCredentials(
                        backend: backend,
                        apiKey: key,
                        refreshToken: "",
                        baseURL: base,
                        apiKeyRef: ref,
                        wireAPI: normalizedWireAPIValue ?? "",
                        authType: "api_key",
                        expiresAtMs: 0,
                        email: "",
                        accountID: "",
                        oauthSourceKey: "",
                        authIndex: 0,
                        kind: .apiKey
                    ),
                    sourceURL: nil
                )
            ]
            : activeCredentialVariants()

        let selectedUpstreamIds: [String] = {
            if importAllDiscovered, !discoveredModelIds.isEmpty {
                return discoveredModelIds
            }
            let one = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            return one.isEmpty ? [] : [one]
        }()

        guard !selectedUpstreamIds.isEmpty else {
            errorText = HubUIStrings.Models.AddRemote.missingModelID
            return
        }

        var entries: [RemoteModelEntry] = []
        let customGroupName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        for credentialVariant in credentialVariants {
            let credential = credentialVariant.credentials
            let entryBackend = credential.backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? backend
                : credential.backend
            let entryBase = credential.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let entryRef = credential.apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ref
                : credential.apiKeyRef
            let entryWireAPI = normalizedCredentialWireAPI(credential.wireAPI, fallback: normalizedWireAPIValue)

            for raw in selectedUpstreamIds {
                let upstream = normalizeUpstreamModelId(raw)
                if upstream.isEmpty { continue }
                let baseId = makeLocalModelId(upstream: upstream)
                let localId = suffix.isEmpty ? baseId : (baseId + suffix)
                let entry = RemoteModelEntry(
                    id: localId,
                    name: upstream,
                    groupDisplayName: customGroupName.isEmpty ? nil : customGroupName,
                    backend: entryBackend,
                    contextLength: max(512, ctx),
                    enabled: enabled,
                    baseURL: entryBase.isEmpty ? (base.isEmpty ? nil : base) : entryBase,
                    apiKeyRef: entryRef,
                    upstreamModelId: upstream,
                    wireAPI: entryWireAPI,
                    apiKey: credential.apiKey,
                    note: noteText.isEmpty ? nil : noteText
                )
                entries.append(entry)
            }
        }

        guard !entries.isEmpty else {
            errorText = HubUIStrings.Models.AddRemote.noValidModelIDs
            return
        }

        let providerKeySync = syncProviderKeyStore(
            credentialVariants: credentialVariants,
            selectedUpstreamIDs: selectedUpstreamIds,
            noteText: noteText
        )
        guard providerKeySync.ok else {
            errorText = providerKeySync.errors.isEmpty
                ? "无法写入正式 Provider Key 存储。"
                : providerKeySync.errors.joined(separator: "\n")
            return
        }

        onAdd(entries)
        dismiss()
    }

    private func normalizeUpstreamModelId(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let b = RemoteProviderEndpoints.canonicalBackend(backend)
        if b == "gemini" || b == "remote_catalog" {
            return RemoteProviderEndpoints.stripModelRef(trimmed)
        }
        if b == "openai" {
            return RemoteProviderEndpoints.normalizedOpenAIModelID(trimmed)
        }
        if b == "anthropic", trimmed.lowercased().hasPrefix("anthropic/") {
            return String(trimmed.dropFirst("anthropic/".count))
        }
        return trimmed
    }

    private func makeLocalModelId(upstream: String) -> String {
        let prefix = normalizedPrefix(idPrefix)
        if prefix.isEmpty { return upstream }
        if upstream.lowercased().hasPrefix(prefix.lowercased()) {
            return upstream
        }
        return prefix + upstream
    }

    private func normalizedPrefix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if !s.hasSuffix("/") {
            s += "/"
        }
        return s
    }

    private func sanitizeSuffix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        // Keep ids filesystem/URL-friendly: drop path separators and whitespace.
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "\\", with: "_")
        s = s.replacingOccurrences(of: " ", with: "_")
        s = s.replacingOccurrences(of: "\t", with: "_")
        s = s.replacingOccurrences(of: "\n", with: "")
        s = s.replacingOccurrences(of: "\r", with: "")
        return s
    }

    private func normalizedWireAPI(_ raw: String) -> String {
        RemoteProviderEndpoints.normalizedWireAPI(raw)?.rawValue ?? ""
    }

    private func normalizedStoredWireAPI() -> String? {
        let canonicalBackend = RemoteProviderEndpoints.canonicalBackend(backend)
        switch canonicalBackend {
        case "anthropic", "gemini":
            return nil
        default:
            let normalized = normalizedWireAPI(wireAPI)
            return normalized.isEmpty ? nil : normalized
        }
    }

    private func normalizedCredentialWireAPI(_ raw: String, fallback: String?) -> String? {
        let normalized = normalizedWireAPI(raw)
        if !normalized.isEmpty {
            return normalized
        }
        return fallback
    }

    private func activeCredentialVariants() -> [CodexProviderImportResolver.ResolvedCredentialVariant] {
        guard !importedCredentialVariants.isEmpty else { return [] }
        guard credentialFingerprint() == importedCredentialFingerprint else { return [] }
        return importedCredentialVariants
    }

    private func activeProviderKeyImportSource() -> ProviderKeyImportSource? {
        guard !activeCredentialVariants().isEmpty else { return nil }
        return importedProviderKeyImportSource
    }

    private func syncProviderKeyStore(
        credentialVariants: [CodexProviderImportResolver.ResolvedCredentialVariant],
        selectedUpstreamIDs: [String],
        noteText: String
    ) -> ProviderKeyImportSyncResult {
        let inputs = credentialVariants.map { variant in
            let credential = variant.credentials
            let provider = providerKeyProvider(for: credential)
            let trimmedSourceRef = variant.sourceURL?.path.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sourceType = trimmedSourceRef.isEmpty ? "" : "auth_file"
            let notes = noteText.isEmpty
                ? "Imported via Add Remote Model"
                : noteText
            return ProviderKeyImportedAccountInput(
                provider: provider,
                email: credential.email,
                apiKey: credential.apiKey,
                refreshToken: credential.refreshToken,
                baseURL: credential.baseURL,
                proxyURL: "",
                enabled: enabled,
                authType: credential.authType,
                wireAPI: credential.wireAPI,
                expiresAtMs: credential.expiresAtMs,
                tier: "",
                customHeaders: [:],
                models: selectedUpstreamIDs,
                notes: notes,
                priority: 0,
                accountID: credential.accountID,
                sourceType: sourceType,
                sourceRef: trimmedSourceRef,
                oauthSourceKey: credential.oauthSourceKey,
                authIndex: credential.authIndex,
                sourceOwners: []
            )
        }

        return ProviderKeyStorage.syncImportedAccounts(
            inputs,
            importSource: activeProviderKeyImportSource()
        )
    }

    private func providerKeyProvider(for credential: ProviderAuthImport.ImportedCredentials) -> String {
        if credential.kind == .chatGPTTokenBundle {
            return "codex"
        }

        switch RemoteProviderEndpoints.canonicalBackend(credential.backend) {
        case "anthropic":
            return "claude"
        case "gemini":
            return "gemini"
        case "openai", "openai_compatible", "remote_catalog":
            return "openai"
        case "qwen":
            return "qwen"
        case "iflow":
            return "iflow"
        case "kimi":
            return "kimi"
        case "antigravity":
            return "antigravity"
        default:
            return "custom"
        }
    }

    private func credentialFingerprint(
        backend: String? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        apiKeyRef: String? = nil,
        wireAPI: String? = nil
    ) -> String {
        [
            RemoteProviderEndpoints.canonicalBackend(backend ?? self.backend),
            (baseURL ?? self.baseURL).trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            (apiKey ?? self.apiKey).trimmingCharacters(in: .whitespacesAndNewlines),
            (apiKeyRef ?? self.apiKeyRef).trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            normalizedWireAPI(wireAPI ?? self.wireAPI)
        ].joined(separator: "\u{1F}")
    }

    private func defaultPrefix(for backend: String) -> String {
        switch RemoteProviderEndpoints.canonicalBackend(backend) {
        case "openai":
            return "openai/"
        case "anthropic":
            return "anthropic/"
        case "gemini":
            return "gemini/"
        case "remote_catalog":
            return "remote_catalog/"
        default:
            return ""
        }
    }

    private func defaultAPIKeyRef(backend: String, baseURL: String) -> String {
        let b = RemoteProviderEndpoints.canonicalBackend(backend)
        if let u = URL(string: baseURL), let host = u.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return "\(b):\(host)"
        }
        if b == "openai" {
            return "openai:api.openai.com"
        }
        if b == "openai_compatible" {
            return "openai_compatible:default"
        }
        if b == "anthropic" {
            return "anthropic:api.anthropic.com"
        }
        if b == "gemini" {
            return "gemini:generativelanguage.googleapis.com"
        }
        if b == "remote_catalog" {
            return "remote_catalog:default"
        }
        return b.isEmpty ? UUID().uuidString : b
    }
}
