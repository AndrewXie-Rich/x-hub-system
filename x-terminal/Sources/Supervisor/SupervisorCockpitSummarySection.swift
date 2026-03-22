import SwiftUI

struct SupervisorCockpitSummarySection: View {
    let primarySignalPresentation: SupervisorPrimarySignalPresentation?
    @ObservedObject var supervisorManager: SupervisorManager
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
