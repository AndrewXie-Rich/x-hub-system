import SwiftUI

struct SupervisorAutomationRuntimeBoardSection: View {
    let presentation: SupervisorAutomationRuntimePresentation
    let selfIterateEnabled: Binding<Bool>
    let maxAutoRetryDepth: Binding<Int>
    let onAction: (SupervisorAutomationRuntimeAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

                Button(action: { onAction(presentation.statusAction.action) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(!presentation.statusAction.isEnabled)
                .help(presentation.statusAction.helpText)
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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

                if let projectLine = presentation.projectLine {
                    SupervisorAutomationRuntimeLineView(projectLine)
                }
                if let recipeLine = presentation.recipeLine {
                    SupervisorAutomationRuntimeLineView(recipeLine)
                }
                if let goalLine = presentation.goalLine {
                    SupervisorAutomationRuntimeLineView(goalLine)
                }
                if let controls = presentation.controls {
                    SupervisorAutomationRuntimeLineView(controls.summaryLine)

                    HStack(spacing: 12) {
                        Toggle("自动自迭代", isOn: selfIterateEnabled)
                            .toggleStyle(.switch)
                            .font(.caption2)

                        Stepper(value: maxAutoRetryDepth, in: 1...8) {
                            Text("最大深度 \(controls.maxAutoRetryDepth)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 220, alignment: .leading)
                    }

                    SupervisorAutomationRuntimeLineView(controls.boundedRetryLine)
                }

                ForEach(presentation.detailRows) { row in
                    SupervisorAutomationRuntimeLineView(row)
                }

                HStack(spacing: 12) {
                    ForEach(presentation.primaryActions) { action in
                        Button(action.label) {
                            onAction(action.action)
                        }
                        .disabled(!action.isEnabled)
                        .help(action.helpText)
                    }

                    Menu("推进到") {
                        ForEach(presentation.advanceActions) { action in
                            Button(action.label) {
                                onAction(action.action)
                            }
                            .disabled(!action.isEnabled)
                            .help(action.helpText)
                        }
                    }
                    .disabled(!presentation.advanceActions.contains(where: { $0.isEnabled }))

                    Spacer(minLength: 8)
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

private struct SupervisorAutomationRuntimeLineView: View {
    let row: SupervisorAutomationRuntimeLinePresentation

    init(_ row: SupervisorAutomationRuntimeLinePresentation) {
        self.row = row
    }

    var body: some View {
        let text = Text(row.text)
            .font(row.style == .caption ? .caption : .caption2)
            .foregroundStyle(toneColor(row.tone))
            .lineLimit(row.lineLimit)

        if row.isSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private func toneColor(_ tone: SupervisorAutomationRuntimeTextTone) -> Color {
        switch tone {
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}
