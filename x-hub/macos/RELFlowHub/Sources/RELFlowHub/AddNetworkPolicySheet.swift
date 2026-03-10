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
            Text("Add Network Policy")
                .font(.headline)

            TextField("App (e.g. X-Terminal or *)", text: $appId)
                .textFieldStyle(.roundedBorder)

            TextField("Project (user name or *)", text: $projectId)
                .textFieldStyle(.roundedBorder)

            Picker("Mode", selection: $mode) {
                Text("Manual").tag(HubNetworkPolicyMode.manual)
                Text("Auto-approve").tag(HubNetworkPolicyMode.autoApprove)
                Text("Always-on").tag(HubNetworkPolicyMode.alwaysOn)
                Text("Deny").tag(HubNetworkPolicyMode.deny)
            }
            .pickerStyle(.menu)

            TextField("Max minutes (optional)", text: $maxMinutes)
                .textFieldStyle(.roundedBorder)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let app = appId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let proj = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if app.isEmpty || proj.isEmpty {
                        errorText = "App and Project are required (use * for wildcard)."
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
