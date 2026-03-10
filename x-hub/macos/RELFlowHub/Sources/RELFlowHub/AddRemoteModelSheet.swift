import SwiftUI
import RELFlowHubCore

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
    @State private var idPrefix: String = ""
    @State private var localIdSuffix: String = ""
    @State private var note: String = ""

    @State private var discoveredModelIds: [String] = []
    @State private var importAllDiscovered: Bool = false
    @State private var isFetchingModels: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Remote Model")
                .font(.headline)

            TextField("Model ID (required if not importing discovered list)", text: $modelId)
                .textFieldStyle(.roundedBorder)

            TextField("Display name", text: $modelName)
                .textFieldStyle(.roundedBorder)

            Picker("Backend", selection: $backend) {
                Text("OpenAI").tag("openai")
                Text("Anthropic").tag("anthropic")
                Text("Gemini").tag("gemini")
                Text("OpenCode Zen").tag("opencode_zen")
                Text("OpenAI-compatible").tag("openai_compatible")
                Text("Other").tag("remote")
            }
            .pickerStyle(.menu)

            TextField("Base URL (optional)", text: $baseURL)
                .textFieldStyle(.roundedBorder)

            SecureField("API Key (required for remote)", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            TextField("API Key name/ref (optional; used for key sharing/switching)", text: $apiKeyRef)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button(isFetchingModels ? "Fetching…" : "Fetch Models") {
                    fetchModels()
                }
                .disabled(isFetchingModels)

                if !discoveredModelIds.isEmpty {
                    Text("Found \(discoveredModelIds.count) model(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if !discoveredModelIds.isEmpty {
                Toggle("Import all discovered models", isOn: $importAllDiscovered)
                if !importAllDiscovered {
                    Picker("Discovered", selection: $modelId) {
                        ForEach(discoveredModelIds, id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            TextField("Model ID prefix (optional, e.g. openai/)", text: $idPrefix)
                .textFieldStyle(.roundedBorder)

            TextField("Local ID suffix (optional, e.g. -work; enables multiple keys for the same upstream model)", text: $localIdSuffix)
                .textFieldStyle(.roundedBorder)

            TextField("Context length (e.g. 8192)", text: $contextLength)
                .textFieldStyle(.roundedBorder)

            TextField("Note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)

            Toggle("Enabled (show as Loaded)", isOn: $enabled)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    addRemoteModels()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isFetchingModels)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear {
            idPrefix = defaultPrefix(for: backend)
            if apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                apiKeyRef = defaultAPIKeyRef(backend: backend, baseURL: baseURL)
            }
        }
        .onChange(of: backend) { newValue in
            let current = normalizedPrefix(idPrefix)
            let knownDefaults: Set<String> = ["", "openai/", "anthropic/", "gemini/", "opencode/"]
            if knownDefaults.contains(current) {
                idPrefix = defaultPrefix(for: newValue)
            }
            // Only auto-update apiKeyRef when it still matches the previous default-ish value.
            let curRef = apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines)
            if curRef.isEmpty || curRef.hasPrefix("openai:") || curRef.hasPrefix("anthropic:") || curRef.hasPrefix("gemini:") || curRef.hasPrefix("opencode:") {
                apiKeyRef = defaultAPIKeyRef(backend: newValue, baseURL: baseURL)
            }
        }
    }

    private func fetchModels() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = "API Key is required to fetch model list."
            return
        }

        errorText = ""
        isFetchingModels = true

        // Keep Bridge window enabled so model/provider fetches can be audited/gated consistently.
        // In single-app mode this controls the embedded Bridge service.
        let bridgeStatus = BridgeSupport.shared.statusSnapshot()
        if !bridgeStatus.enabled {
            BridgeSupport.shared.enable(seconds: 30 * 60)
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
                    errorText = ids.isEmpty ? "Provider returned an empty model list." : ""
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

    private func addRemoteModels() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = "API Key is required for remote models."
            return
        }

        let ctx = Int(contextLength.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8192
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let refRaw = apiKeyRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = refRaw.isEmpty ? defaultAPIKeyRef(backend: backend, baseURL: base) : refRaw
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = sanitizeSuffix(localIdSuffix)

        let selectedUpstreamIds: [String] = {
            if importAllDiscovered, !discoveredModelIds.isEmpty {
                return discoveredModelIds
            }
            let one = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            return one.isEmpty ? [] : [one]
        }()

        guard !selectedUpstreamIds.isEmpty else {
            errorText = "Please input a model id or fetch models first."
            return
        }

        var entries: [RemoteModelEntry] = []
        let customName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        for raw in selectedUpstreamIds {
            let upstream = normalizeUpstreamModelId(raw)
            if upstream.isEmpty { continue }
            let baseId = makeLocalModelId(upstream: upstream)
            let localId = suffix.isEmpty ? baseId : (baseId + suffix)
            let displayName: String
            if selectedUpstreamIds.count == 1, !customName.isEmpty {
                displayName = customName
            } else {
                displayName = upstream
            }
            let entry = RemoteModelEntry(
                id: localId,
                name: displayName,
                backend: backend,
                contextLength: max(512, ctx),
                enabled: enabled,
                baseURL: base.isEmpty ? nil : base,
                apiKeyRef: ref,
                upstreamModelId: upstream,
                apiKey: key,
                note: noteText.isEmpty ? nil : noteText
            )
            entries.append(entry)
        }

        guard !entries.isEmpty else {
            errorText = "No valid model id to import."
            return
        }

        onAdd(entries)
        dismiss()
    }

    private func normalizeUpstreamModelId(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let b = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if b == "gemini" || b == "opencode" || b == "opencode_zen" {
            return RemoteProviderEndpoints.stripModelRef(trimmed)
        }
        if b == "openai", trimmed.lowercased().hasPrefix("openai/") {
            return String(trimmed.dropFirst("openai/".count))
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

    private func defaultPrefix(for backend: String) -> String {
        switch backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "openai":
            return "openai/"
        case "anthropic":
            return "anthropic/"
        case "gemini":
            return "gemini/"
        case "opencode", "opencode_zen":
            return "opencode/"
        default:
            return ""
        }
    }

    private func defaultAPIKeyRef(backend: String, baseURL: String) -> String {
        let b = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let u = URL(string: baseURL), let host = u.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return "\(b):\(host)"
        }
        if b == "openai" {
            return "openai:api.openai.com"
        }
        if b == "anthropic" {
            return "anthropic:api.anthropic.com"
        }
        if b == "gemini" {
            return "gemini:generativelanguage.googleapis.com"
        }
        if b == "opencode" || b == "opencode_zen" {
            return "opencode:default"
        }
        return b.isEmpty ? UUID().uuidString : b
    }
}
