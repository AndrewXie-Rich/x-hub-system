import SwiftUI

struct OperatorChannelFirstUseFlowView: View {
    let flow: HubOperatorChannelFirstUseFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(flow.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !flow.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.currentNextStep(flow.nextAction))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(flow.steps.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(HubUIStrings.Settings.numberedItem(index + 1, title: step.title))
                            .font(.caption.weight(.semibold))
                        Spacer()
                        stateBadge(step.state)
                    }
                    Text(step.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !step.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(step.evidence)
                            .font(.caption2)
                            .foregroundStyle(step.state == .attention ? .orange : .secondary)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func stateBadge(_ state: HubOperatorChannelFirstUseStepState) -> some View {
        let tint: Color = {
            switch state {
            case .complete:
                return .green
            case .attention:
                return .orange
            case .pending:
                return .secondary
            }
        }()

        return Text(state.title)
            .font(.caption2.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
