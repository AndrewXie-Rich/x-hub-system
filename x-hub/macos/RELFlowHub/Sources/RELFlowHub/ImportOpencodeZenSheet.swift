import SwiftUI
import RELFlowHubCore

struct ImportOpencodeZenResult: Equatable {
    var apiKey: String
    var modelIds: [String]
    var idPrefix: String
    var replaceExisting: Bool
    var enabled: Bool
}

struct ImportOpencodeZenSheet: View {
    let onImport: (ImportOpencodeZenResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var idPrefix: String = "opencode/"
    @State private var replaceExisting: Bool = true
    @State private var enabled: Bool = true

    @State private var isImporting: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import OpenCode Zen Models")
                .font(.headline)

            Text("Fetches the curated model list from OpenCode Zen and registers them as remote models in REL Flow Hub.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Base URL: \(OpencodeZenClient.defaultBaseURL.absoluteString)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TextField("Model ID prefix (e.g. opencode/)", text: $idPrefix)
                .textFieldStyle(.roundedBorder)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            Toggle("Enable imported models (show as Loaded)", isOn: $enabled)
            Toggle("Replace existing OpenCode Zen models", isOn: $replaceExisting)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isImporting)
                Button(isImporting ? "Importing…" : "Import") {
                    startImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting)
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func startImport() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = "API Key is required."
            return
        }

        errorText = ""
        isImporting = true

        Task {
            do {
                let ids = try await OpencodeZenClient.fetchModelIds(apiKey: key)
                await MainActor.run {
                    let res = ImportOpencodeZenResult(
                        apiKey: key,
                        modelIds: ids,
                        idPrefix: idPrefix,
                        replaceExisting: replaceExisting,
                        enabled: enabled
                    )
                    onImport(res)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorText = String(describing: error)
                    isImporting = false
                }
            }
        }
    }
}

