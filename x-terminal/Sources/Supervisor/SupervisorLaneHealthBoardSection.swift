import SwiftUI

struct SupervisorLaneHealthBoardSection: View {
    let presentation: SupervisorLaneHealthBoardPresentation
    @Binding var filter: SupervisorLaneHealthFilter
    let onAction: (SupervisorLaneHealthRowAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Picker("Lane 状态过滤", selection: $filter) {
                ForEach(SupervisorLaneHealthFilter.allCases, id: \.self) { currentFilter in
                    Text(currentFilter.label).tag(currentFilter)
                }
            }
            .pickerStyle(.segmented)

            Text(presentation.summaryLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !presentation.rows.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(presentation.rows.prefix(8))) { row in
                            SupervisorLaneHealthRowView(
                                presentation: row,
                                onAction: onAction
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 168)
            } else if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorLaneHealthTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .info:
            return .blue
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

private struct SupervisorLaneHealthRowView: View {
    let presentation: SupervisorLaneHealthRowPresentation
    let onAction: (SupervisorLaneHealthRowAction) -> Void

    var body: some View {
        let statusColor = toneColor(presentation.statusTone)
        let reasonColor = toneColor(presentation.reasonTone)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: presentation.statusIconName)
                    .foregroundColor(statusColor)
                Text(presentation.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer(minLength: 8)

                Text(presentation.heartbeatSequenceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(presentation.heartbeatAgeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.reasonLine)
                .font(.caption2)
                .foregroundStyle(reasonColor)
                .lineLimit(2)

            if let contractText = presentation.contractText {
                Text(contractText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let nextSafeActionText = presentation.nextSafeActionText {
                Text(nextSafeActionText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(presentation.taskText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(presentation.splitPlanText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let waitText = presentation.waitText {
                    Text(waitText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let openAction = presentation.openAction {
                    Button(openAction.label) {
                        onAction(openAction.action)
                    }
                    .buttonStyle(.borderless)
                }

                Button(presentation.focusAction.label) {
                    onAction(presentation.focusAction.action)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(presentation.isFocused ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(presentation.isFocused ? Color.accentColor.opacity(0.42) : .clear, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func toneColor(_ tone: SupervisorLaneHealthTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .info:
            return .blue
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}
