import SwiftUI

struct StatusExplanation: Codable, Equatable, Identifiable {
    var id: String { "\(state.rawValue)|\(machineStatusRef)" }

    let state: XTUISurfaceState
    let headline: String
    let whatHappened: String
    let whyItHappened: String
    let userAction: String
    let machineStatusRef: String
    let hardLine: String?
    let highlights: [String]

    enum CodingKeys: String, CodingKey {
        case state
        case headline
        case whatHappened = "what_happened"
        case whyItHappened = "why_it_happened"
        case userAction = "user_action"
        case machineStatusRef = "machine_status_ref"
        case hardLine = "hard_line"
        case highlights
    }
}

struct StatusExplanationCard: View {
    let explanation: StatusExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: explanation.state.iconName)
                    .font(.title3)
                    .foregroundStyle(explanation.state.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(explanation.headline)
                        .font(UIThemeTokens.sectionFont())
                    Text(explanation.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
            }

            detailLine(title: "发生了什么", text: explanation.whatHappened)
            detailLine(title: "原因", text: explanation.whyItHappened)
            detailLine(title: "下一步", text: explanation.userAction)

            if !explanation.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("观测信号")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(explanation.highlights, id: \.self) { highlight in
                        Text("• \(highlight)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let hardLine = explanation.hardLine, !hardLine.isEmpty {
                Text("硬边界 · \(hardLine)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(explanation.state.tint)
            }

            Text("machine_status_ref: \(explanation.machineStatusRef)")
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.stateBackground(for: explanation.state))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(explanation.state.tint.opacity(0.24), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailLine(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.primary)
        }
    }
}
