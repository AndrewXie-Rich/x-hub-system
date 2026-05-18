import SwiftUI
import RELFlowHubCore

@MainActor
struct EditRolesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: HubModel
    @State private var isGeneral: Bool = true
    @State private var isSupervisor: Bool = false
    @State private var isCoder: Bool = false
    @State private var isReviewer: Bool = false
    @State private var customRolesText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(HubUIStrings.Models.EditRoles.title)
                .font(.headline)

            Text(model.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(HubUIStrings.Models.EditRoles.general, isOn: $isGeneral)
                Toggle(HubUIStrings.Models.EditRoles.supervisor, isOn: $isSupervisor)
                Toggle(HubUIStrings.Models.EditRoles.coder, isOn: $isCoder)
                Toggle(HubUIStrings.Models.EditRoles.reviewer, isOn: $isReviewer)
                TextField(HubUIStrings.Models.EditRoles.customRolesPlaceholder, text: $customRolesText)
            }

            Text(HubUIStrings.Models.EditRoles.routingHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(HubUIStrings.Models.EditRoles.cancel) { dismiss() }
                Button(HubUIStrings.Models.EditRoles.save) { save() }
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear {
            let roles = (model.roles ?? []).map { HubModelRolePresentation.canonicalRoleToken($0) }
            isGeneral = roles.isEmpty || roles.contains("general")
            isSupervisor = roles.contains("supervisor")
            isCoder = roles.contains("coder")
            isReviewer = roles.contains("reviewer")
            let known: Set<String> = ["general", "supervisor", "coder", "reviewer"]
            let custom = roles.filter { !known.contains($0) }
            customRolesText = custom.joined(separator: ",")
        }
    }

    private func save() {
        var roles: [String] = []
        if isGeneral { roles.append("general") }
        if isSupervisor { roles.append("supervisor") }
        if isCoder { roles.append("coder") }
        if isReviewer { roles.append("reviewer") }
        let extra = customRolesText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        roles.append(contentsOf: extra)

        // De-dup while preserving order.
        var uniq: [String] = []
        var seen: Set<String> = []
        for r in roles {
            if seen.contains(r) { continue }
            seen.insert(r)
            uniq.append(r)
        }

        ModelStore.shared.updateRoles(modelId: model.id, roles: uniq)
        dismiss()
    }
}
