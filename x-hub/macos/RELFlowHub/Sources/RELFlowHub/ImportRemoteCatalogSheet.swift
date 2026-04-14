import SwiftUI
import RELFlowHubCore

struct ImportRemoteCatalogResult: Equatable {
    var apiKey: String
    var modelIds: [String]
    var idPrefix: String
    var replaceExisting: Bool
    var enabled: Bool
}

struct ImportRemoteCatalogSheet: View {
    let onImport: (ImportRemoteCatalogResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var idPrefix: String = "remote_catalog/"
    @State private var replaceExisting: Bool = true
    @State private var enabled: Bool = true

    @State private var isImporting: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HubUIStrings.Models.ImportRemoteCatalog.title)
                .font(.headline)

            Text(HubUIStrings.Models.ImportRemoteCatalog.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Models.ImportRemoteCatalog.baseURL(RemoteCatalogClient.defaultBaseURL.absoluteString))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TextField(HubUIStrings.Models.ImportRemoteCatalog.idPrefixPlaceholder, text: $idPrefix)
                .textFieldStyle(.roundedBorder)

            SecureField(HubUIStrings.Models.ImportRemoteCatalog.apiKeyPlaceholder, text: $apiKey)
                .textFieldStyle(.roundedBorder)

            Toggle(HubUIStrings.Models.ImportRemoteCatalog.enabledToggle, isOn: $enabled)
            Toggle(HubUIStrings.Models.ImportRemoteCatalog.replaceExistingToggle, isOn: $replaceExisting)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(HubUIStrings.Models.ImportRemoteCatalog.cancel) { dismiss() }
                    .disabled(isImporting)
                Button(isImporting ? HubUIStrings.Models.ImportRemoteCatalog.importing : HubUIStrings.Models.ImportRemoteCatalog.importAction) {
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
            errorText = HubUIStrings.Models.ImportRemoteCatalog.missingAPIKey
            return
        }

        errorText = ""
        isImporting = true

        Task {
            do {
                let ids = try await RemoteCatalogClient.fetchModelIds(apiKey: key)
                await MainActor.run {
                    let res = ImportRemoteCatalogResult(
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
                    errorText = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}
