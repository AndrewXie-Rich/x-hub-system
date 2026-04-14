import SwiftUI
import RELFlowHubCore

struct AddNetworkPolicySheet: View {
    let onAdd: (HubNetworkPolicyRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var appId: String = ""
    @State private var projectId: String = ""
    @State private var mode: HubNetworkPolicyMode = .manual
    @State private var maxMinutes: String = ""
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HubUIStrings.Settings.NetworkPolicySheet.title)
                .font(.headline)

            TextField(HubUIStrings.Settings.NetworkPolicySheet.appPlaceholder, text: $appId)
                .textFieldStyle(.roundedBorder)

            TextField(HubUIStrings.Settings.NetworkPolicySheet.projectPlaceholder, text: $projectId)
                .textFieldStyle(.roundedBorder)

            Picker(HubUIStrings.Settings.NetworkPolicySheet.mode, selection: $mode) {
                Text(HubUIStrings.Settings.NetworkPolicySheet.manual).tag(HubNetworkPolicyMode.manual)
                Text(HubUIStrings.Settings.NetworkPolicySheet.autoApprove).tag(HubNetworkPolicyMode.autoApprove)
                Text(HubUIStrings.Settings.NetworkPolicySheet.alwaysOn).tag(HubNetworkPolicyMode.alwaysOn)
                Text(HubUIStrings.Settings.NetworkPolicySheet.deny).tag(HubNetworkPolicyMode.deny)
            }
            .pickerStyle(.menu)

            TextField(HubUIStrings.Settings.NetworkPolicySheet.maxMinutesPlaceholder, text: $maxMinutes)
                .textFieldStyle(.roundedBorder)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(HubUIStrings.Settings.NetworkPolicySheet.cancel) { dismiss() }
                Button(HubUIStrings.Settings.NetworkPolicySheet.add) {
                    let app = appId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let proj = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if app.isEmpty || proj.isEmpty {
                        errorText = HubUIStrings.Settings.NetworkPolicySheet.missingRequiredFields
                        return
                    }
                    let mins = Int(maxMinutes.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    let maxSec = mins > 0 ? mins * 60 : nil
                    let rule = HubNetworkPolicyRule(
                        appId: app,
                        projectId: proj,
                        mode: mode,
                        maxSeconds: maxSec
                    )
                    onAdd(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
