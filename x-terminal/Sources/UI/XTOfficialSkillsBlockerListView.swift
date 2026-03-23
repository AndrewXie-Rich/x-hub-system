import SwiftUI

struct XTOfficialSkillsBlockerListView: View {
    @Environment(\.openURL) private var openURL

    let items: [AXOfficialSkillBlockerSummaryItem]

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("需要处理的包（Packages needing attention）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(items) { item in
                        let tone = toneColor(for: item.stateLabel)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle)
                                            .font(UIThemeTokens.monoFont())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }

                                Spacer(minLength: 8)

                                Text(item.stateLabel.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(tone)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(tone.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            if !item.summaryLine.isEmpty {
                                Text(item.summaryLine)
                                    .font(UIThemeTokens.monoFont())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            if !item.timelineLine.isEmpty {
                                Text(item.timelineLine)
                                    .font(UIThemeTokens.monoFont())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            if let action = XTOfficialSkillsBlockerActionSupport.action(for: item),
                               let url = URL(string: action.url) {
                                HStack {
                                    Spacer()
                                    Button(action.label) {
                                        openURL(url)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(8)
                        .background(tone.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(tone.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private func toneColor(for stateLabel: String) -> Color {
        switch stateLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "blocked", "revoked":
            return .red
        case "degraded", "not_supported", "not supported":
            return .orange
        case "not_installed", "not installed":
            return .yellow
        default:
            return .secondary
        }
    }
}
