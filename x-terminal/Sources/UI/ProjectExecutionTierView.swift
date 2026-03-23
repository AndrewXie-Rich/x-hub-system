import SwiftUI

struct ProjectExecutionTierView: View {
    let configuredTier: AXProjectExecutionTier
    let effectiveTier: AXProjectExecutionTier
    let effectiveProjectMemoryCeiling: XTMemoryServingProfile
    let effectiveRuntimeSurfaceMode: AXProjectRuntimeSurfaceMode
    let inlineMessage: String
    let inlineMessageIsError: Bool
    let onSelectTier: (AXProjectExecutionTier) -> Void

    private let summaryColumns = [
        GridItem(.adaptive(minimum: 170), spacing: 10)
    ]

    var body: some View {
        GroupBox("Execution Tier") {
            VStack(alignment: .leading, spacing: 14) {
                Text("这里只控制项目 AI 能做多大动作，包括 repo / browser / device 的执行边界；不负责决定 Supervisor 审查多深，也不负责 Recent Project Dialogue / Context Depth。后两者请到 Project Settings 里的 Context Assembly 单独设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                    summaryMetric(
                        title: "已配置",
                        value: configuredTier.displayName,
                        tone: tierTint(configuredTier)
                    )

                    if effectiveTier != configuredTier {
                        summaryMetric(
                            title: "当前生效",
                            value: effectiveTier.displayName,
                            tone: .orange
                        )
                    }

                    summaryMetric(
                        title: "Coder 上下文",
                        value: effectiveProjectMemoryCeiling.rawValue,
                        tone: .blue
                    )

                    summaryMetric(
                        title: "执行面",
                        value: effectiveRuntimeSurfaceMode.displayName,
                        tone: .teal
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AXProjectExecutionTier.allCases, id: \.self) { tier in
                        executionTierCard(tier)
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

    private func executionTierCard(_ tier: AXProjectExecutionTier) -> some View {
        let tint = tierTint(tier)
        let isSelected = configuredTier == tier
        let presentation = ProjectExecutionTierCardPresentation(
            tier: tier,
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
                        title: "Serving Ceiling",
                        value: tier.defaultProjectMemoryCeiling.rawValue,
                        tone: tint
                    )
                    summaryMetric(
                        title: "Recommended S",
                        value: tier.defaultSupervisorInterventionTier.displayName,
                        tone: .orange
                    )
                    summaryMetric(
                        title: "Safe Floor",
                        value: tier.minimumSafeSupervisorTier.displayName,
                        tone: .red
                    )
                    summaryMetric(
                        title: "Surface Preset",
                        value: tier.defaultRuntimeSurfacePreset.displayName,
                        tone: .teal
                    )
                    summaryMetric(
                        title: "Run Budget",
                        value: tier.defaultBudgetSummary,
                        tone: .secondary
                    )
                }

                tierTagGroup(
                    title: "Allows",
                    labels: tier.allowedHighlights,
                    tint: tint
                )

                tierTagGroup(
                    title: "Blocked",
                    labels: tier.blockedHighlights,
                    tint: .secondary
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Core Capability Bundle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if tier.baseCapabilityBundle.allowedCapabilityLabels.isEmpty {
                        Text("(none)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ExecutionTierTagWrapView(
                            labels: tier.baseCapabilityBundle.allowedCapabilityLabels,
                            tint: tint
                        )
                    }
                }
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

            ExecutionTierTagWrapView(labels: labels, tint: tint)
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

    private func tierTint(_ tier: AXProjectExecutionTier) -> Color {
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
}

private struct ExecutionTierTagWrapView: View {
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
