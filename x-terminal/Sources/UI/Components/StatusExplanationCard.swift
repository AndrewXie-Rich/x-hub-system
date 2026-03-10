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

            detailLine(title: "What happened", text: explanation.whatHappened)
            detailLine(title: "Why", text: explanation.whyItHappened)
            detailLine(title: "Next action", text: explanation.userAction)

            if !explanation.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signals")
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
                Text("Hard line · \(hardLine)")
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
