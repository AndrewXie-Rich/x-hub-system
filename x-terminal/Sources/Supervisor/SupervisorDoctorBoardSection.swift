import SwiftUI

struct SupervisorDoctorBoardSection: View {
    let presentation: SupervisorDoctorBoardPresentation
    let suggestionCards: [SupervisorDoctorSuggestionCard]
    let canOpenCanonicalMemorySyncStatusFile: Bool
    let onRefreshDoctor: () -> Void
    let onRetryCanonicalMemorySync: () -> Void
    let onOpenCanonicalMemorySyncStatusFile: () -> Void

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

                Button(action: onRefreshDoctor) {
                    Image(systemName: "stethoscope")
                }
                .buttonStyle(.borderless)
                .help("重新运行 Doctor + Secrets dry-run 预检")

                Button(action: onRetryCanonicalMemorySync) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("重推当前 Supervisor portfolio 和项目 capsule 的 canonical memory")

                Button(action: onOpenCanonicalMemorySyncStatusFile) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(!canOpenCanonicalMemorySyncStatusFile)
                .help("打开 canonical memory sync 状态文件")
            }

            Text(presentation.releaseBlockLine)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let skillDoctorTruthStatusLine = presentation.skillDoctorTruthStatusLine {
                Text(skillDoctorTruthStatusLine)
                    .font(.caption2)
                    .foregroundStyle(toneColor(presentation.skillDoctorTruthTone))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let skillDoctorTruthDetailLine = presentation.skillDoctorTruthDetailLine {
                Text(skillDoctorTruthDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Text(presentation.memoryReadinessLine)
                .font(.caption2)
                .foregroundStyle(toneColor(presentation.memoryReadinessTone))
                .textSelection(.enabled)

            if let memoryIssueSummaryLine = presentation.memoryIssueSummaryLine {
                Text(memoryIssueSummaryLine)
                    .font(.caption2)
                    .foregroundStyle(toneColor(presentation.memoryReadinessTone))
                    .lineLimit(2)
            }

            if let memoryIssueDetailLine = presentation.memoryIssueDetailLine {
                Text(memoryIssueDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            if let projectMemoryAdvisoryLine = presentation.projectMemoryAdvisoryLine {
                Text(projectMemoryAdvisoryLine)
                    .font(.caption2)
                    .foregroundStyle(toneColor(presentation.projectMemoryAdvisoryTone))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let projectMemoryAdvisoryDetailLine = presentation.projectMemoryAdvisoryDetailLine {
                Text(projectMemoryAdvisoryDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            if let memoryContinuitySummaryLine = presentation.memoryContinuitySummaryLine {
                Text(memoryContinuitySummaryLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let memoryContinuityDetailLine = presentation.memoryContinuityDetailLine {
                Text(memoryContinuityDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            if let canonicalRetryStatusLine = presentation.canonicalRetryStatusLine {
                Text(canonicalRetryStatusLine)
                    .font(.caption2)
                    .foregroundStyle(toneColor(presentation.canonicalRetryTone))
                    .lineLimit(2)
            }

            if let canonicalRetryMetaLine = presentation.canonicalRetryMetaLine {
                Text(canonicalRetryMetaLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let canonicalRetryDetailLine = presentation.canonicalRetryDetailLine {
                Text(canonicalRetryDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestionCards.prefix(4)) { card in
                            SupervisorDoctorSuggestionCardView(card: card)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 154)
            }

            if let reportLine = presentation.reportLine {
                Text(reportLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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

private struct SupervisorDoctorSuggestionCardView: View {
    let card: SupervisorDoctorSuggestionCard
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("[\(card.priority.rawValue.uppercased())] \(card.title)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer(minLength: 8)
            }

            Text(card.why)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let first = card.actions.first, !first.isEmpty {
                Text("建议：\(first)")
                    .font(.caption)
            }
            if let verify = card.verifyHint, !verify.isEmpty {
                Text("验证：\(verify)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let actionLabel = card.actionLabel,
               let rawURL = card.actionURL,
               let url = URL(string: rawURL) {
                Button(actionLabel) {
                    openURL(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}
