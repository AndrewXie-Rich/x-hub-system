import SwiftUI

struct SupervisorRuntimeActivityBoardSection: View {
    let presentation: SupervisorRuntimeActivityBoardPresentation
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.rows) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(entry.timeText)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            Text(entry.text)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            if let contractText = entry.contractText {
                                Text(contractText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if let nextSafeActionText = entry.nextSafeActionText {
                                Text(nextSafeActionText)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            if !entry.actionDescriptors.isEmpty {
                                HStack(spacing: 8) {
                                    Spacer(minLength: 0)
                                    SupervisorInlineActionStrip(
                                        actions: entry.actionDescriptors,
                                        style: .borderlessCaption,
                                        onAction: onAction
                                    )
                                }
                            }
                        }
                        if entry.showsDivider {
                            Divider()
                        }
                    }
                }
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
