import SwiftUI

struct SupervisorProjectCreationBoardSection: View {
    let presentation: SupervisorProjectCreationStatusPresentation
    let onQuickPrompt: (String) -> Void
    let onQuickSend: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "plus.rectangle.on.folder.fill")
                    .foregroundColor(presentation.priorityTone.color)
                Text("项目创建状态")
                    .font(.headline)

                Spacer()

                Text("诊断码：\(presentation.reasonCode)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            SupervisorSignalSummaryCard(
                badgeText: presentation.priority.label,
                badgeTone: presentation.priorityTone,
                eyebrowText: "Project Creation Readiness",
                headlineText: presentation.headlineText,
                headlineTone: presentation.priorityTone,
                headlineFont: .subheadline.weight(.semibold),
                detailText: presentation.detailText,
                metadataText: presentation.metadataText,
                backgroundColor: presentation.priorityTone.color.opacity(0.08),
                borderColor: presentation.priorityTone.color.opacity(0.18)
            )

            if hasContextDetails {
                VStack(alignment: .leading, spacing: 6) {
                    if let projectNameText = normalizedLine(presentation.projectNameText) {
                        detailRow(label: "项目名", value: projectNameText)
                    }
                    if let goalText = normalizedLine(presentation.goalText) {
                        detailRow(label: "目标", value: goalText)
                    }
                    if let trackText = normalizedLine(presentation.trackText) {
                        detailRow(label: "形态", value: trackText)
                    }
                }
            }

            if !presentation.recommendedCommands.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("建议下一句")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(presentation.recommendedCommands, id: \.self) { command in
                        HStack(spacing: 8) {
                            Text(command)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 6) {
                                Button("使用这句") {
                                    onQuickPrompt(command)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(presentation.priorityTone.color)
                                .help("先把这句填入输入框，你可以再补充或改写后发送。")

                                Button("立即发送") {
                                    onQuickSend(command)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(presentation.priorityTone.color)
                                .help("直接把这句发给 Supervisor；如果输入框里还有别的草稿，会保留原草稿。")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var hasContextDetails: Bool {
        normalizedLine(presentation.projectNameText) != nil
            || normalizedLine(presentation.goalText) != nil
            || normalizedLine(presentation.trackText) != nil
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func normalizedLine(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
