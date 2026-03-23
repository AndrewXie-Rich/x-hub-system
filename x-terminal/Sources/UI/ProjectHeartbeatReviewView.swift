import SwiftUI

struct ProjectHeartbeatReviewView: View {
    let ctx: AXProjectContext?
    let configuredExecutionTier: AXProjectExecutionTier
    let configuredReviewPolicyMode: AXProjectReviewPolicyMode
    let progressHeartbeatSeconds: Int
    let reviewPulseSeconds: Int
    let brainstormReviewSeconds: Int
    let eventDrivenReviewEnabled: Bool
    let eventReviewTriggers: [AXProjectReviewTrigger]
    let resolvedGovernance: AXProjectResolvedGovernanceState
    let governancePresentation: ProjectGovernancePresentation
    let inlineMessage: String
    let inlineMessageIsError: Bool
    let onSelectReviewPolicy: (AXProjectReviewPolicyMode) -> Void
    let onUpdateProgressHeartbeatSeconds: (Int) -> Void
    let onUpdateReviewPulseSeconds: (Int) -> Void
    let onUpdateBrainstormReviewSeconds: (Int) -> Void
    let onSetEventDrivenReviewEnabled: (Bool) -> Void
    let onSetEventReviewTriggers: ([AXProjectReviewTrigger]) -> Void
    var showActivityTimeline: Bool = true

    @State private var activityPresentation: ProjectGovernanceActivityPresentation = .empty

    private let summaryColumns = [
        GridItem(.adaptive(minimum: 170), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("心跳与审查（Heartbeat & Review）") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("这里单独治理进度心跳、Supervisor 审查节奏、事件触发和安全点指导。A-tier 决定哪些审查检查点必须存在，但心跳 / 审查频率仍然独立配置；`Recent Project Dialogue / Supervisor Recent Raw Context` 不在这里调整。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                        summaryMetric(
                            title: "已配置策略",
                            value: configuredReviewPolicyMode.displayName,
                            tone: reviewPolicyTint(configuredReviewPolicyMode)
                        )
                        summaryMetric(
                            title: "当前生效",
                            value: resolvedGovernance.effectiveBundle.reviewPolicyMode.displayName,
                            tone: reviewPolicyTint(resolvedGovernance.effectiveBundle.reviewPolicyMode)
                        )
                        summaryMetric(
                            title: "Coder 上下文",
                            value: resolvedGovernance.projectMemoryCeiling.rawValue,
                            tone: .blue
                        )
                        summaryMetric(
                            title: "审查上下文",
                            value: resolvedGovernance.supervisorReviewMemoryCeiling.rawValue,
                            tone: .indigo
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AXProjectReviewPolicyMode.allCases, id: \.self) { mode in
                            reviewPolicyCard(mode)
                        }
                    }

                    configurationSection(
                        title: "进度心跳",
                        subtitle: "进度心跳只负责看进度，不做战略纠偏。它可以比审查更频繁，也不要求指导确认。"
                    ) {
                        Stepper(
                            value: minutesBinding(
                                seconds: progressHeartbeatSeconds,
                                onUpdateSeconds: onUpdateProgressHeartbeatSeconds
                            ),
                            in: 1...240,
                            step: 5
                        ) {
                            Text("进度心跳：\(governanceDurationLabel(progressHeartbeatSeconds))")
                        }

                        schedulePair(
                            leadingTitle: "上次心跳",
                            leadingValue: activityPresentation.schedule.lastHeartbeatText,
                            trailingTitle: "下次心跳",
                            trailingValue: activityPresentation.schedule.nextHeartbeatText
                        )

                        triggerInfoRow(
                            trigger: .periodicHeartbeat,
                            status: "始终由心跳节奏派生",
                            note: AXProjectReviewTrigger.periodicHeartbeat.governanceSummary
                        )
                    }

                    configurationSection(
                        title: "Supervisor 审查",
                        subtitle: "脉冲 / 脑暴 / 事件驱动审查共同决定 Supervisor 多久看一次方向，以及哪些时机会插入建议。"
                    ) {
                        Stepper(
                            value: minutesBinding(
                                seconds: reviewPulseSeconds,
                                onUpdateSeconds: onUpdateReviewPulseSeconds,
                                allowsOff: true
                            ),
                            in: 0...240,
                            step: 5
                        ) {
                            Text("周期复盘：\(governanceDurationLabel(reviewPulseSeconds))")
                        }
                        .disabled(!configuredReviewPolicyMode.supportsPulseCadence)

                        Text(configuredReviewPolicyMode.supportsPulseCadence
                             ? "脉冲审查当前可用，适合轻量周期复盘。"
                             : "当前策略不启用脉冲节奏；如需周期复盘，请切到 `Periodic / Hybrid / Aggressive`。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        schedulePair(
                            leadingTitle: "上次脉冲审查",
                            leadingValue: activityPresentation.schedule.lastPulseReviewText,
                            trailingTitle: "下次脉冲审查",
                            trailingValue: activityPresentation.schedule.nextPulseReviewText
                        )

                        Stepper(
                            value: minutesBinding(
                                seconds: brainstormReviewSeconds,
                                onUpdateSeconds: onUpdateBrainstormReviewSeconds,
                                allowsOff: true
                            ),
                            in: 0...240,
                            step: 5
                        ) {
                            Text("脑暴复盘（Brainstorm）：\(governanceDurationLabel(brainstormReviewSeconds))")
                        }
                        .disabled(!configuredReviewPolicyMode.supportsBrainstormCadence)

                        Text(configuredReviewPolicyMode.supportsBrainstormCadence
                             ? "脑暴审查会围绕 `no-progress window` 做更深的方向复盘。"
                             : "当前策略不启用脑暴节奏；如需战略复盘，请切到 `Hybrid / Aggressive`。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        schedulePair(
                            leadingTitle: "上次脑暴审查",
                            leadingValue: activityPresentation.schedule.lastBrainstormReviewText,
                            trailingTitle: "下次脑暴审查",
                            trailingValue: activityPresentation.schedule.nextBrainstormReviewText
                        )

                        Toggle(
                            "开启事件驱动审查",
                            isOn: Binding(
                                get: { eventDrivenReviewEnabled },
                                set: { onSetEventDrivenReviewEnabled($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .disabled(!configuredReviewPolicyMode.supportsEventDrivenReview)

                        Text(configuredReviewPolicyMode.supportsEventDrivenReview
                             ? (eventDrivenReviewEnabled
                                ? "当前会监听 blocker / drift / high-risk 等事件；A-tier 强制检查点始终保留。"
                                : "当前只保留 A-tier 强制检查点；下面的可选事件会先保存，重新开启后生效。")
                             : "`Off` 模式不会启用事件驱动审查，但 `manual request / user override` 仍可触发。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        triggerGroup(
                            title: "A-tier 锁定",
                            subtitle: "这些检查点由当前 A-tier 决定，不能在这里关闭。",
                            triggers: pagePresentation.mandatoryTriggers,
                            accent: executionTierTint(configuredExecutionTier)
                        ) { trigger in
                            triggerInfoRow(
                                trigger: trigger,
                                status: "由 \(configuredExecutionTier.shortToken) 锁定",
                                note: trigger.governanceSummary
                            )
                        }

                        triggerGroup(
                            title: "可选事件触发",
                            subtitle: "这些事件是额外放开的审查入口，只影响事件驱动审查。",
                            triggers: pagePresentation.optionalTriggers,
                            accent: .teal
                        ) { trigger in
                            Toggle(
                                isOn: optionalTriggerBinding(trigger)
                            ) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trigger.displayName)
                                        .font(.caption.weight(.semibold))
                                    Text(trigger.governanceSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.switch)
                        }

                        triggerGroup(
                            title: "始终开启 / 派生",
                            subtitle: "这些审查入口来自节奏或人工操作，不需要单独勾选。",
                            triggers: pagePresentation.derivedTriggers,
                            accent: .secondary
                        ) { trigger in
                            triggerInfoRow(
                                trigger: trigger,
                                status: derivedTriggerStatus(trigger),
                                note: trigger.governanceSummary
                            )
                        }
                    }

                    configurationSection(
                        title: "指导与安全点",
                        subtitle: "这里展示当前治理下，Supervisor 默认会怎样把审查结论注入给 coder，包括干预方式、安全点、确认要求和工单深度。"
                    ) {
                        LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                            summaryMetric(
                                title: "干预方式",
                                value: ProjectGovernanceActivityDisplay.displayValue(label: "intervention", value: pagePresentation.baselineDecision.interventionMode.displayName),
                                tone: guidanceTint(pagePresentation.baselineDecision.interventionMode)
                            )
                            summaryMetric(
                                title: "安全点",
                                value: ProjectGovernanceActivityDisplay.displayValue(label: "safe_point", value: pagePresentation.baselineDecision.safePointPolicy.displayName),
                                tone: .teal
                            )
                            summaryMetric(
                                title: "确认要求",
                                value: pagePresentation.baselineDecision.ackRequired ? "需要确认" : "可选确认",
                                tone: pagePresentation.baselineDecision.ackRequired ? .orange : .secondary
                            )
                            summaryMetric(
                                title: "工单深度",
                                value: ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: resolvedGovernance.supervisorAdaptation.effectiveWorkOrderDepth.displayName),
                                tone: .indigo
                            )
                        }

                        Text("基线样例：\(localizedBaselineDecisionSummary())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("指导注入：\(governancePresentation.guidanceSummary) · \(governancePresentation.guidanceAckSummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("跟进节奏：\(localizedFollowUpRhythmSummary())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("策略来源：\(governancePresentation.compatSourceLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if !inlineMessage.isEmpty {
                        Text(inlineMessage)
                            .font(.caption)
                            .foregroundStyle(inlineMessageIsError ? .red : .orange)
                    }
                }
                .padding(8)
            }

            if showActivityTimeline, let ctx {
                ProjectGovernanceActivityView(ctx: ctx)
            }
        }
        .task(id: reloadKey) {
            reloadActivityPresentation()
        }
    }

    private var reloadKey: ProjectHeartbeatReviewReloadKey {
        ProjectHeartbeatReviewReloadKey(
            rootPath: ctx?.root.path,
            configuredExecutionTier: configuredExecutionTier,
            configuredReviewPolicyMode: configuredReviewPolicyMode,
            progressHeartbeatSeconds: progressHeartbeatSeconds,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            eventDrivenReviewEnabled: eventDrivenReviewEnabled,
            eventReviewTriggers: eventReviewTriggers
        )
    }

    private var pagePresentation: ProjectHeartbeatReviewEditorPresentation {
        ProjectHeartbeatReviewEditorPresentation(
            configuredExecutionTier: configuredExecutionTier,
            configuredReviewPolicyMode: configuredReviewPolicyMode,
            reviewPulseSeconds: reviewPulseSeconds,
            brainstormReviewSeconds: brainstormReviewSeconds,
            resolvedGovernance: resolvedGovernance
        )
    }

    private func reloadActivityPresentation() {
        guard let ctx else {
            activityPresentation = .empty
            return
        }

        activityPresentation = ProjectGovernanceActivityPresentation.load(
            for: ctx,
            resolvedGovernance: resolvedGovernance,
            now: Date()
        )
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

    private func configurationSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func schedulePair(
        leadingTitle: String,
        leadingValue: String,
        trailingTitle: String,
        trailingValue: String
    ) -> some View {
        LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
            summaryMetric(title: leadingTitle, value: leadingValue, tone: .secondary)
            summaryMetric(title: trailingTitle, value: trailingValue, tone: .secondary)
        }
    }

    private func reviewPolicyCard(_ mode: AXProjectReviewPolicyMode) -> some View {
        let tint = reviewPolicyTint(mode)
        let isConfigured = configuredReviewPolicyMode == mode
        let isEffective = resolvedGovernance.effectiveBundle.reviewPolicyMode == mode

        return Button {
            onSelectReviewPolicy(mode)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.displayName)
                            .font(.headline)
                        Text(mode.oneLineSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(policyBadges(for: mode), id: \.label) { badge in
                            badgeView(badge.label, tint: badge.tint)
                        }
                    }
                }

                HStack(spacing: 8) {
                    capabilityBadge("脉冲（Pulse）", active: mode.supportsPulseCadence, tint: tint)
                    capabilityBadge("脑暴（Brainstorm）", active: mode.supportsBrainstormCadence, tint: .indigo)
                    capabilityBadge("事件（Events）", active: mode.supportsEventDrivenReview, tint: .teal)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(tint.opacity(isConfigured ? 0.14 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isConfigured ? tint.opacity(0.9) : Color.secondary.opacity(0.18), lineWidth: isConfigured ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(accessibilityStateLabel(isConfigured: isConfigured, isEffective: isEffective))
    }

    private func triggerGroup<Row: View>(
        title: String,
        subtitle: String,
        triggers: [AXProjectReviewTrigger],
        accent: Color,
        @ViewBuilder row: @escaping (AXProjectReviewTrigger) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if triggers.isEmpty {
                Text("（无）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(triggers, id: \.self) { trigger in
                    row(trigger)
                }
            }
        }
    }

    private func triggerInfoRow(
        trigger: AXProjectReviewTrigger,
        status: String,
        note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(trigger.displayName)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
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

    private func capabilityBadge(_ label: String, active: Bool, tint: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(active ? tint : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((active ? tint : Color.secondary).opacity(active ? 0.12 : 0.08))
            .clipShape(Capsule())
    }

    private func policyBadges(
        for mode: AXProjectReviewPolicyMode
    ) -> [(label: String, tint: Color)] {
        var badges: [(String, Color)] = []
        if configuredReviewPolicyMode == mode && resolvedGovernance.effectiveBundle.reviewPolicyMode == mode {
            badges.append(("当前", reviewPolicyTint(mode)))
        } else {
            if configuredReviewPolicyMode == mode {
                badges.append(("已配置", reviewPolicyTint(mode)))
            }
            if resolvedGovernance.effectiveBundle.reviewPolicyMode == mode {
                badges.append(("生效中", .orange))
            }
        }
        return badges
    }

    private func optionalTriggerBinding(_ trigger: AXProjectReviewTrigger) -> Binding<Bool> {
        Binding(
            get: { selectedOptionalTriggers.contains(trigger) },
            set: { enabled in
                var selected = selectedOptionalTriggers
                if enabled {
                    selected.insert(trigger)
                } else {
                    selected.remove(trigger)
                }

                let orderedOptional = AXProjectReviewTrigger.governanceOptionalSelectableCases.filter {
                    selected.contains($0) && !pagePresentation.mandatoryTriggers.contains($0)
                }
                let next = AXProjectReviewTrigger.normalizedList(pagePresentation.mandatoryTriggers + orderedOptional)
                onSetEventReviewTriggers(next)
            }
        )
    }

    private var selectedOptionalTriggers: Set<AXProjectReviewTrigger> {
        let optionalSet = Set(pagePresentation.optionalTriggers)
        return Set(eventReviewTriggers.filter { optionalSet.contains($0) })
    }

    private func derivedTriggerStatus(_ trigger: AXProjectReviewTrigger) -> String {
        switch trigger {
        case .manualRequest:
            return "始终允许"
        case .userOverride:
            return "始终允许"
        case .periodicPulse:
            return "由脉冲节奏派生"
        case .noProgressWindow:
            return "由脑暴节奏派生"
        default:
            return "自动派生"
        }
    }

    private func minutesBinding(
        seconds: Int,
        onUpdateSeconds: @escaping (Int) -> Void,
        allowsOff: Bool = false
    ) -> Binding<Int> {
        Binding(
            get: {
                if allowsOff && seconds <= 0 {
                    return 0
                }
                return max(1, seconds / 60)
            },
            set: { minutes in
                if allowsOff && minutes <= 0 {
                    onUpdateSeconds(0)
                } else {
                    onUpdateSeconds(max(1, minutes) * 60)
                }
            }
        )
    }

    private func accessibilityStateLabel(isConfigured: Bool, isEffective: Bool) -> String {
        switch (isConfigured, isEffective) {
        case (true, true):
            return "当前"
        case (true, false):
            return "已配置"
        case (false, true):
            return "生效中"
        default:
            return "可用"
        }
    }

    private func reviewPolicyTint(_ mode: AXProjectReviewPolicyMode) -> Color {
        switch mode {
        case .off:
            return .gray
        case .milestoneOnly:
            return .blue
        case .periodic:
            return .teal
        case .hybrid:
            return .green
        case .aggressive:
            return .orange
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

    private func guidanceTint(_ mode: SupervisorGuidanceInterventionMode) -> Color {
        switch mode {
        case .observeOnly:
            return .secondary
        case .suggestNextSafePoint:
            return .blue
        case .replanNextSafePoint:
            return .orange
        case .stopImmediately:
            return .red
        }
    }

    private func localizedBaselineDecisionSummary() -> String {
        let reason = localizedBaselineReason(pagePresentation.baselineDecisionInput.reason)
        let trigger = ProjectGovernanceActivityDisplay.displayValue(
            label: "trigger",
            value: pagePresentation.baselineDecisionInput.trigger.displayName
        )
        let level = ProjectGovernanceActivityDisplay.displayValue(
            label: "level",
            value: pagePresentation.baselineDecision.reviewLevel.displayName
        )
        let intervention = ProjectGovernanceActivityDisplay.displayValue(
            label: "intervention",
            value: pagePresentation.baselineDecision.interventionMode.displayName
        )
        return "\(reason) -> \(trigger) · \(level) · \(intervention)"
    }

    private func localizedBaselineReason(_ raw: String) -> String {
        switch raw {
        case "brainstorm cadence":
            return "脑暴节奏"
        case "pulse cadence":
            return "脉冲节奏"
        case "manual review":
            return "手动审查"
        default:
            return raw
        }
    }

    private func localizedFollowUpRhythmSummary() -> String {
        let value = activityPresentation.followUpRhythmSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "(none)" else { return "无" }
        return ProjectGovernanceActivityDisplay.displayValue(label: "follow_up_rhythm", value: value)
    }
}

private struct ProjectHeartbeatReviewReloadKey: Equatable {
    var rootPath: String?
    var configuredExecutionTier: AXProjectExecutionTier
    var configuredReviewPolicyMode: AXProjectReviewPolicyMode
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggers: [AXProjectReviewTrigger]
}
