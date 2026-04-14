import SwiftUI
import RELFlowHubCore

@MainActor
struct EditRolesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: HubModel
    @State private var isGeneral: Bool = true
    @State private var isTranslate: Bool = false
    @State private var isSummarize: Bool = false
    @State private var isExtract: Bool = false
    @State private var isRefine: Bool = false
    @State private var isClassify: Bool = false
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
                Toggle(HubUIStrings.Models.EditRoles.translate, isOn: $isTranslate)
                Toggle(HubUIStrings.Models.EditRoles.summarize, isOn: $isSummarize)
                Toggle(HubUIStrings.Models.EditRoles.extract, isOn: $isExtract)
                Toggle(HubUIStrings.Models.EditRoles.refine, isOn: $isRefine)
                Toggle(HubUIStrings.Models.EditRoles.classify, isOn: $isClassify)
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
            let roles = (model.roles ?? []).map { $0.lowercased() }
            isGeneral = roles.isEmpty || roles.contains("general")
            isTranslate = roles.contains("translate")
            isSummarize = roles.contains("summarize")
            isExtract = roles.contains("extract")
            isRefine = roles.contains("refine")
            isClassify = roles.contains("classify")
            let known: Set<String> = ["general", "translate", "summarize", "extract", "refine", "classify"]
            let custom = roles.filter { !known.contains($0) }
            customRolesText = custom.joined(separator: ",")
        }
    }

    private func save() {
        var roles: [String] = []
        if isGeneral { roles.append("general") }
        if isTranslate { roles.append("translate") }
        if isSummarize { roles.append("summarize") }
        if isExtract { roles.append("extract") }
        if isRefine { roles.append("refine") }
        if isClassify { roles.append("classify") }
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
