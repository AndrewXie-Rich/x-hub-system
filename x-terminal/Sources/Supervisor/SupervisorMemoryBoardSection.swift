import SwiftUI

struct SupervisorMemoryBoardSection: View {
    let presentation: SupervisorMemoryBoardPresentation
    let onRefresh: () -> Void

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

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新 Supervisor memory 汇总")
            }

            Text(presentation.modeSourceText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(presentation.continuityStatusLine)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let continuityDetailLine = presentation.continuityDetailLine {
                Text(continuityDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            if !presentation.continuityDrillDownLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(presentation.continuityDrillDownLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let turnExplainability = presentation.turnExplainability {
                toneCard(
                    iconName: turnExplainability.iconName,
                    tone: turnExplainability.tone,
                    title: turnExplainability.title
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(turnExplainability.statusLine)
                            .font(.caption)
                            .foregroundStyle(.primary)

                        ForEach(Array(turnExplainability.detailLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let modelRoute = presentation.modelRoute {
                toneCard(
                    iconName: modelRoute.iconName,
                    tone: modelRoute.tone,
                    title: modelRoute.title
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(modelRoute.statusLine)
                            .font(.caption)
                            .foregroundStyle(.primary)

                        ForEach(Array(modelRoute.detailLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let afterTurn = presentation.afterTurn {
                toneCard(
                    iconName: afterTurn.iconName,
                    tone: afterTurn.tone,
                    title: afterTurn.title
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(afterTurn.statusLine)
                            .font(.caption)
                            .foregroundStyle(.primary)

                        ForEach(Array(afterTurn.detailLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: presentation.readinessIconName)
                    .foregroundStyle(toneColor(presentation.readinessTone))
                Text(presentation.readinessHeadline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(toneColor(presentation.readinessTone))
            }

            Text(presentation.readinessStatusLine)
                .font(.caption2)
                .foregroundStyle(toneColor(presentation.readinessTone))
                .textSelection(.enabled)
                .lineLimit(2)

            Text(presentation.assemblyStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let followUp = presentation.followUp {
                toneCard(
                    iconName: followUp.iconName,
                    tone: followUp.tone,
                    title: followUp.title
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(followUp.questionText)
                            .font(.caption)
                            .foregroundStyle(.primary)

                        Text(followUp.hintText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let assemblyDetailLine = presentation.assemblyDetailLine {
                Text(assemblyDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            if let issueSectionTitle = presentation.issueSectionTitle {
                VStack(alignment: .leading, spacing: 6) {
                    Text(issueSectionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toneColor(presentation.readinessTone))
                    ForEach(presentation.issues) { issue in
                        SupervisorMemoryIssueRow(issue: issue)
                    }
                }
            }

            Text(presentation.skillRegistryStatusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let skillRegistrySectionTitle = presentation.skillRegistrySectionTitle {
                VStack(alignment: .leading, spacing: 6) {
                    Text(skillRegistrySectionTitle)
                        .font(.caption.weight(.semibold))
                    ForEach(presentation.skillRegistryRows) { item in
                        SupervisorMemorySkillRegistryRow(item: item)
                    }
                }
            }

            if let emptyStateText = presentation.emptyStateText {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(presentation.digestRows) { digest in
                            SupervisorMemoryDigestRow(digest: digest)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 176)
            }

            if let previewExcerpt = presentation.previewExcerpt {
                Text(previewExcerpt)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(8)
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

    @ViewBuilder
    private func toneCard<Content: View>(
        iconName: String,
        tone: SupervisorHeaderControlTone,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(toneColor(tone))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(toneColor(tone))
            }

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(toneColor(tone).opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(toneColor(tone).opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SupervisorMemoryDigestRow: View {
    let digest: SupervisorMemoryDigestRowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(digest.displayName)
                    .font(.caption.weight(.semibold))
                Text(digest.runtimeState)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(digest.recentText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(digest.updatedText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(digest.sourceText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(digest.goalText)
                .font(.caption2)
                .lineLimit(2)

            Text(digest.nextText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let blockerText = digest.blockerText {
                Text(blockerText)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SupervisorMemoryIssueRow: View {
    let issue: SupervisorMemoryIssuePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(issue.severityText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(toneColor(issue.severityTone))
                Text(issue.summary)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Text(issue.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct SupervisorMemorySkillRegistryRow: View {
    let item: SupervisorMemorySkillRegistryRowPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.displayName)
                    .font(.caption.weight(.semibold))
                Text(item.skillId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(item.badgeText)
                    .font(.caption2)
                    .foregroundStyle(toneColor(item.badgeTone))
            }

            Text(item.metadataText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let routingHintText = item.routingHintText {
                Text(routingHintText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let descriptionText = item.descriptionText {
                Text(descriptionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
