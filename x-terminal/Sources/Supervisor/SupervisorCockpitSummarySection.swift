import SwiftUI

struct SupervisorCockpitSummarySection: View {
    let primarySignalPresentation: SupervisorPrimarySignalPresentation?
    let supervisorManager: SupervisorManager
    @ObservedObject var orchestrator: SupervisorOrchestrator
    @ObservedObject var monitor: ExecutionMonitor
    let onPrimarySignalAction: (SupervisorSignalCenterOverviewAction) -> Void
    let onTap: (PrimaryActionRailAction) -> Void
    let onStageTap: (SupervisorRuntimeStageItemPresentation) -> Void

    private var presentation: SupervisorCockpitPresentation {
        SupervisorCockpitPresentation.fromRuntime(
            supervisorManager: supervisorManager,
            orchestrator: orchestrator,
            monitor: monitor
        )
    }

    private var cockpitActions: [PrimaryActionRailAction] {
        guard let primarySignalAction = primarySignalPresentation?.cockpitAction else {
            return presentation.actions
        }
        return presentation.actions + [primarySignalAction]
    }

    var body: some View {
        let presentation = presentation

        return VStack(alignment: .leading, spacing: UIThemeTokens.sectionSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Supervisor 驾驶舱")
                        .font(UIThemeTokens.sectionFont())
                    Text("统一入口：任务接管、计划解释、阻塞判断、下一步建议、范围冻结")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ValidatedScopeBadge(presentation: presentation.badge)
                    .frame(maxWidth: 280)
            }

            if let primarySignalPresentation {
                primarySignalStrip(
                    primarySignalPresentation
                )
            }

            PrimaryActionRail(
                title: "驾驶舱动作",
                actions: cockpitActions,
                onTap: handleActionTap
            )

            OneShotRuntimeStageRail(
                presentation: presentation.runtimeStageRail,
                onTap: onStageTap
            )

            if let scoreReport = presentation.laneWinnerScoreReport,
               scoreReport.candidateCount > 0 {
                CockpitLaneWinnerEvidenceCard(
                    report: scoreReport,
                    onAction: handleActionTap
                )
            }

            if let reviewMemorySummary = presentation.reviewMemorySummary {
                CockpitReviewMemorySummaryCard(summary: reviewMemorySummary)
            }

            StatusExplanationCard(explanation: presentation.intakeStatus)

            VStack(alignment: .leading, spacing: 12) {
                Text("规划解释")
                    .font(UIThemeTokens.sectionFont())
                Text(presentation.plannerExplain)
                    .font(UIThemeTokens.bodyFont())
                Text("状态引用：\(presentation.plannerMachineStatusRef)")
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                    .fill(UIThemeTokens.secondaryCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                    .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
            )

            StatusExplanationCard(explanation: presentation.blockerStatus)
            StatusExplanationCard(explanation: presentation.releaseFreezeStatus)
            if supervisorManager.voiceAuthorizationResolution != nil || supervisorManager.activeVoiceChallenge != nil {
                SupervisorVoiceAuthorizationCard(supervisorManager: supervisorManager)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func primarySignalStrip(
        _ presentation: SupervisorPrimarySignalPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(presentation.badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(presentation.badgeTone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(presentation.badgeTone.color.opacity(0.14))
                    )

                Text(presentation.eyebrowText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(presentation.headlineText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(presentation.badgeTone.color)
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.detailText)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !presentation.metadataText.isEmpty {
                Text(presentation.metadataText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(presentation.badgeTone.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(presentation.badgeTone.color.opacity(0.16), lineWidth: 1)
        )
    }

    private func handleActionTap(_ action: PrimaryActionRailAction) {
        if action.id == SupervisorPrimarySignalPresentation.cockpitActionID,
           let focusAction = primarySignalPresentation?.focusAction {
            onPrimarySignalAction(focusAction.action)
            return
        }

        onTap(action)
    }
}

private struct CockpitReviewMemorySummaryCard: View {
    let summary: SupervisorMemoryAssemblyCompactSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Supervisor Review Memory")
                        .font(UIThemeTokens.sectionFont())
                    Text(summary.headlineText)
                        .font(UIThemeTokens.bodyFont().weight(.semibold))
                }

                Spacer(minLength: 12)
            }

            if let detailText = summary.detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("这里显示的是最近一次真正装给 Supervisor 的 review-memory 真相，不是治理档位本身。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
        .help(summary.helpText)
    }
}

private struct CockpitLaneWinnerEvidenceCard: View {
    let report: LaneWinnerScoreReport
    let onAction: (PrimaryActionRailAction) -> Void

    private var topCandidates: [LaneWinnerScoreCandidate] {
        Array(report.candidates.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: report.recommendedLaneID.isEmpty ? "exclamationmark.shield" : "checkmark.seal")
                    .font(.title3)
                    .foregroundStyle(report.recommendedLaneID.isEmpty ? Color.orange : Color.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Lane Winner Evidence")
                        .font(UIThemeTokens.sectionFont())
                    Text(headline)
                        .font(UIThemeTokens.bodyFont().weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text("\(report.eligibleCount)/\(report.candidateCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(report.eligibleCount > 0 ? Color.green : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((report.eligibleCount > 0 ? Color.green : Color.orange).opacity(0.14))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(topCandidates) { candidate in
                    candidateRow(candidate)
                    if candidate.id != topCandidates.last?.id {
                        Divider()
                    }
                }
            }

            Text("ref=\(report.reportRef) · policy=\(report.policySummary)")
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !report.selectionBlockers.isEmpty {
                Text("selection_blockers=\(report.selectionBlockers.joined(separator: ","))")
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .fill(UIThemeTokens.secondaryCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
        )
        .help("XT 本地 lane evidence 排序；Hub 仍负责 Memory、Skills、grant、policy 和 audit truth。")
    }

    private var headline: String {
        if report.selectionSource == "manual_override_blocked",
           let laneID = report.manualOverrideLaneID.nilIfBlank {
            return "人工选择 \(laneID) 被 fail-closed；先修复 blocker 后再合回"
        }
        if report.selectionSource == "manual_override",
           let laneID = report.recommendedLaneID.nilIfBlank {
            return "人工选择 \(laneID) 作为合回候选；后续仍走 Reviewer / Hub gates"
        }
        if report.recommendedLaneID.isEmpty {
            return "没有可合回 winner；等待 Coder evidence 或 Reviewer approved verdict"
        }
        return "推荐 \(report.recommendedLaneID) 合回；Reviewer approved 已满足"
    }

    @ViewBuilder
    private func candidateRow(_ candidate: LaneWinnerScoreCandidate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(candidate.rank)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)

                Text(candidate.laneID)
                    .font(.caption.weight(.semibold))

                Text("score \(candidate.score)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(candidate.reviewVerdict)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(candidate.eligibleForMergeback ? Color.green : Color.orange)
            }

            Text("files=\(candidate.changedFileCount) · diagnostics=\(candidate.diagnosticsRunCount) · risk=\(candidate.riskTier)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            let blockerText = candidate.blockers.prefix(3).joined(separator: ", ")
            let strengthText = candidate.strengths.prefix(3).joined(separator: ", ")
            Text(blockerText.isEmpty ? "signals=\(strengthText.isEmpty ? "none" : strengthText)" : "blockers=\(blockerText)")
                .font(.caption2)
                .foregroundStyle(blockerText.isEmpty ? .secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if candidate.eligibleForMergeback {
                    Button(action: { onAction(selectAction(for: candidate)) }) {
                        Label(candidate.selected ? "已选择" : "选为 winner", systemImage: candidate.selected ? "checkmark.seal.fill" : "checkmark.circle")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(candidate.selected && report.selectionSource == "manual_override")
                } else {
                    Button(action: { onAction(repairAction(for: candidate)) }) {
                        Label("请求修复", systemImage: "wrench.and.screwdriver")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: { onAction(focusAction(for: candidate)) }) {
                    Label("定位", systemImage: "scope")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func selectAction(for candidate: LaneWinnerScoreCandidate) -> PrimaryActionRailAction {
        PrimaryActionRailAction(
            id: "lane_winner_select:\(candidate.laneID)",
            title: "选为 winner",
            subtitle: "lane=\(candidate.laneID) · score=\(candidate.score)",
            systemImage: "checkmark.circle",
            style: .secondary
        )
    }

    private func repairAction(for candidate: LaneWinnerScoreCandidate) -> PrimaryActionRailAction {
        PrimaryActionRailAction(
            id: "lane_winner_repair:\(candidate.laneID)",
            title: "请求修复",
            subtitle: candidate.blockers.prefix(3).joined(separator: ","),
            systemImage: "wrench.and.screwdriver",
            style: .secondary
        )
    }

    private func focusAction(for candidate: LaneWinnerScoreCandidate) -> PrimaryActionRailAction {
        PrimaryActionRailAction(
            id: "lane_winner_focus:\(candidate.laneID)",
            title: "定位 lane",
            subtitle: "lane=\(candidate.laneID)",
            systemImage: "scope",
            style: .diagnostic
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
