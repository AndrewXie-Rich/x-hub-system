import SwiftUI

struct SupervisorVoiceEvidenceSummaryRowView: View {
    let title: String
    let state: XTUISurfaceState
    let headline: String
    let summary: String
    let detail: String?

    @State private var diagnosticsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: state.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.tint)
                Text(headline)
                    .font(UIThemeTokens.bodyFont().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let detail = trimmedDetail {
                DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                    Text(detail)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                } label: {
                    HStack {
                        Text("原始诊断")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(diagnosticsExpanded ? "展开中" : "已折叠")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var trimmedDetail: String? {
        let value = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
