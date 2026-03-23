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
        GroupBox("Supervisor Tier") {
            VStack(alignment: .leading, spacing: 14) {
                Text("这里只控制 Supervisor 审查 / 指导 / 重规划的介入强度。不直接放行 repo、browser 或 device 权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                    summaryMetric(
                        title: "当前 A-tier",
                        value: currentExecutionTier.displayName,
                        tone: executionTierTint(currentExecutionTier)
                    )
                    summaryMetric(
                        title: "推荐 S 档位",
                        value: currentExecutionTier.defaultSupervisorInterventionTier.displayName,
                        tone: .orange
                    )
                    summaryMetric(
                        title: "安全下限",
                        value: currentExecutionTier.minimumSafeSupervisorTier.displayName,
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
                        Text(tier.displayName)
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
                    title: "Behavior",
                    labels: tier.behaviorHighlights,
                    tint: tint
                )

                tierTagGroup(
                    title: "Good For",
                    labels: tier.typicalUseCases,
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
        .accessibilityLabel("\(tier.displayName)")
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
        switch tier {
        case .a0Observe:
            return .gray
        case .a1Plan:
            return .blue
        case .a2RepoAuto:
            return .teal
        case .a3DeliverAuto:
            return .green
        case .a4OpenClaw:
            return .orange
        }
    }

    private func supervisorTierTint(_ tier: AXProjectSupervisorInterventionTier) -> Color {
        switch tier {
        case .s0SilentAudit:
            return .gray
        case .s1MilestoneReview:
            return .blue
        case .s2PeriodicReview:
            return .teal
        case .s3StrategicCoach:
            return .orange
        case .s4TightSupervision:
            return .red
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
