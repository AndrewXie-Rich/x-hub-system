import SwiftUI

struct SupervisorInfrastructureFeedBoardSection: View {
    let presentation: SupervisorInfrastructureFeedBoardPresentation
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.items) { item in
                            SupervisorInfrastructureFeedRow(
                                item: item,
                                onAction: onAction
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 176)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

private struct SupervisorInfrastructureFeedRow: View {
    let item: SupervisorInfrastructureFeedPresentation.Item
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        let resolvedToneColor = toneColor(item.tone)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.iconName)
                    .foregroundStyle(resolvedToneColor)
                Text(item.title)
                    .font(.caption.weight(.semibold))

                Spacer(minLength: 8)

                Text(item.badgeText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(resolvedToneColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(resolvedToneColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !item.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.summary)
                    .font(.caption)
                    .lineLimit(2)
            }

            if !item.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let contractText = item.contractText {
                Text(contractText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let nextSafeActionText = item.nextSafeActionText {
                Text(nextSafeActionText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let timestamp = item.timestamp {
                    Text(SupervisorEventLoopFeedPresentation.relativeTimeText(timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                SupervisorInlineActionStrip(
                    actions: SupervisorCardActionResolver.infrastructureActions(item),
                    style: .borderlessCaption,
                    onAction: onAction
                )
            }
        }
        .padding(10)
        .background(resolvedToneColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(resolvedToneColor.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func toneColor(_ tone: SupervisorInfrastructureFeedPresentation.Tone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .attention:
            return .orange
        case .critical:
            return .red
        case .success:
            return .green
        }
    }
}
