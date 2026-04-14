import SwiftUI

struct ProjectSupervisorTierView: View {
    let currentExecutionTier: AXProjectExecutionTier
    let configuredTier: AXProjectSupervisorInterventionTier
    let effectiveTier: AXProjectSupervisorInterventionTier
    let effectiveReviewMemoryCeiling: XTMemoryServingProfile
    let inlineMessage: String
    let inlineMessageIsError: Bool
    let onSelectTier: (AXProjectSupervisorInterventionTier) -> Void

    private let summaryColumns = [
        GridItem(.adaptive(minimum: 170), spacing: 10)
    ]

    var body: some View {
        GroupBox("S-Tier") {
            VStack(alignment: .leading, spacing: 14) {
                Text("S-Tier 只回答一件事：Supervisor 会盯多深、介入多积极。它不额外放行 repo、browser 或 device 权限，只决定 review、纠偏和救援强度；真正 fail-closed 仍来自 grant、runtime、policy、TTL、kill-switch。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                    summaryMetric(
                        title: "当前 A-Tier",
                        value: currentExecutionTier.localizedDisplayLabel,
                        tone: executionTierTint(currentExecutionTier)
                    )
                    summaryMetric(
                        title: "推荐 S-Tier",
                        value: currentExecutionTier.defaultSupervisorInterventionTier.localizedDisplayLabel,
                        tone: .orange
                    )
                    summaryMetric(
                        title: "风险参考线",
                        value: currentExecutionTier.minimumSafeSupervisorTier.localizedDisplayLabel,
                        tone: .red
                    )
                    summaryMetric(
                        title: "审查上下文深度",
                        value: effectiveReviewMemoryCeiling.rawValue,
                        tone: .blue
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AXProjectSupervisorInterventionTier.allCases, id: \.self) { tier in
                        supervisorTierCard(tier)
                    }
                }

                if !inlineMessage.isEmpty {
                    Text(inlineMessage)
                        .font(.caption)
                        .foregroundStyle(inlineMessageIsError ? .red : .orange)
                }
            }
            .padding(8)
        }
    }

    private func supervisorTierCard(_ tier: AXProjectSupervisorInterventionTier) -> some View {
        let tint = supervisorTierTint(tier)
        let isSelected = configuredTier == tier
        let presentation = ProjectSupervisorTierCardPresentation(
            tier: tier,
            currentExecutionTier: currentExecutionTier,
            configuredTier: configuredTier,
            effectiveTier: effectiveTier
        )

        return Button {
            onSelectTier(tier)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tier.localizedDisplayLabel)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(tier.oneLineSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(presentation.statusBadges, id: \.label) { badge in
                            badgeView(badge.label, tint: badgeTint(badge.tone, tierTint: tint))
                        }
                    }
                }

                LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                    summaryMetric(
                        title: "审查上下文",
                        value: tier.defaultReviewMemoryCeiling.rawValue,
                        tone: .blue
                    )
                    summaryMetric(
                        title: "指导方式",
                        value: ProjectGovernanceActivityDisplay.displayValue(label: "intervention", value: tier.defaultInterventionMode.displayName),
                        tone: tint
                    )
                    summaryMetric(
                        title: "工单深度",
                        value: ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: tier.defaultWorkOrderDepth.displayName),
                        tone: .teal
                    )
                    summaryMetric(
                        title: "确认要求",
                        value: tier.defaultAckRequired ? "需要确认" : "可选确认",
                        tone: tier.defaultAckRequired ? .orange : .secondary
                    )
                }

                tierTagGroup(
                    title: "行为特点",
                    labels: tier.behaviorHighlights.map(localizedSupervisorHighlight),
                    tint: tint
                )

                tierTagGroup(
                    title: "适用场景",
                    labels: tier.typicalUseCases.map(localizedSupervisorHighlight),
                    tint: .secondary
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(tint.opacity(isSelected ? 0.14 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor(isSelected: isSelected, tint: tint), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.localizedDisplayLabel)")
        .accessibilityValue(presentation.accessibilityStateLabel)
    }

    private func tierTagGroup(title: String, labels: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            SupervisorTierTagWrapView(labels: labels, tint: tint)
        }
    }

    private func summaryMetric(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tone.opacity(0.10))
        )
    }

    private func badgeView(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func borderColor(isSelected: Bool, tint: Color) -> Color {
        isSelected ? tint.opacity(0.9) : Color.secondary.opacity(0.18)
    }

    private func badgeTint(_ tone: ProjectGovernanceStatusBadgeTone, tierTint: Color) -> Color {
        switch tone {
        case .current, .configured:
            return tierTint
        case .effective, .recommended:
            return .orange
        case .safeFloor, .belowSafeFloor:
            return .red
        }
    }

    private func executionTierTint(_ tier: AXProjectExecutionTier) -> Color {
        ProjectGovernanceComposerAccentTone.forExecutionTier(tier).color
    }

    private func supervisorTierTint(_ tier: AXProjectSupervisorInterventionTier) -> Color {
        ProjectGovernanceComposerAccentTone.forSupervisorTier(tier).color
    }

    private func localizedSupervisorHighlight(_ value: String) -> String {
        switch value {
        case "只读 heartbeat / audit":
            return "只读心跳 / 审计"
        case "默认 observe only":
            return "默认仅观察"
        case "只在 kill-switch / 越界时出手":
            return "只在紧急回收 / 越界时出手"
        case "里程碑 review":
            return "里程碑审查"
        case "safe point 给建议":
            return "在安全点给建议"
        case "brief 级 work order":
            return "简要级工单"
        case "定时 pulse review":
            return "定时脉冲审查"
        case "suggest at safe point":
            return "在安全点建议"
        case "milestone contract depth":
            return "里程碑合同深度"
        case "replan at safe point":
            return "在安全点重规划"
        case "execution ready depth":
            return "执行就绪深度"
        case "高频 review":
            return "高频审查"
        case "step-locked rescue":
            return "锁步救援"
        case "强 ack / 强纠偏":
            return "强确认 / 强纠偏"
        case "A2 Repo Auto":
            return "A2 仓库自动推进"
        case "A3 Deliver Auto":
            return "A3 交付自动推进"
        default:
            return value
        }
    }
}

private struct SupervisorTierTagWrapView: View {
    let labels: [String]
    let tint: Color

    var body: some View {
        ViewThatFits(in: .vertical) {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    tag(label)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    tag(label)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
