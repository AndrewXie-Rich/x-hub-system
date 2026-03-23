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
            GroupBox("Heartbeat & Review") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("这里单独治理进度心跳、Supervisor review cadence、事件触发和 safe-point guidance。A-tier 决定哪些 review checkpoint 是硬性存在的，但 heartbeat / review 频率仍然独立配置；Recent Project Dialogue / Supervisor Recent Raw Context 不在这里调。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                        summaryMetric(
                            title: "Configured Policy",
                            value: configuredReviewPolicyMode.displayName,
                            tone: reviewPolicyTint(configuredReviewPolicyMode)
                        )
                        summaryMetric(
                            title: "Effective Review",
                            value: resolvedGovernance.effectiveBundle.reviewPolicyMode.displayName,
                            tone: reviewPolicyTint(resolvedGovernance.effectiveBundle.reviewPolicyMode)
                        )
                        summaryMetric(
                            title: "Coder Serving",
                            value: resolvedGovernance.projectMemoryCeiling.rawValue,
                            tone: .blue
                        )
                        summaryMetric(
                            title: "Review Serving",
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
                        title: "Progress Heartbeat",
                        subtitle: "Heartbeat 只负责看进度，不做战略纠偏。它可以比 review 更频繁，也不要求 guidance ack。"
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
                            leadingTitle: "Last Heartbeat",
                            leadingValue: activityPresentation.schedule.lastHeartbeatText,
                            trailingTitle: "Next Heartbeat",
                            trailingValue: activityPresentation.schedule.nextHeartbeatText
                        )

                        triggerInfoRow(
                            trigger: .periodicHeartbeat,
                            status: "Always derived from heartbeat cadence",
                            note: AXProjectReviewTrigger.periodicHeartbeat.governanceSummary
                        )
                    }

                    configurationSection(
                        title: "Supervisor Review",
                        subtitle: "Pulse / Brainstorm / event-driven review 共同决定 Supervisor 多久看一次方向，以及哪些时机会插入建议。"
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
                             ? "Pulse review 当前可用，适合轻量周期复盘。"
                             : "当前策略不启用 pulse cadence；如需周期复盘，请切到 Periodic / Hybrid / Aggressive。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        schedulePair(
                            leadingTitle: "Last Pulse",
                            leadingValue: activityPresentation.schedule.lastPulseReviewText,
                            trailingTitle: "Next Pulse",
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
                            Text("Brainstorm 复盘：\(governanceDurationLabel(brainstormReviewSeconds))")
                        }
                        .disabled(!configuredReviewPolicyMode.supportsBrainstormCadence)

                        Text(configuredReviewPolicyMode.supportsBrainstormCadence
                             ? "Brainstorm review 会围绕 no-progress window 做更深的方向复盘。"
                             : "当前策略不启用 brainstorm cadence；如需战略复盘，请切到 Hybrid / Aggressive。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        schedulePair(
                            leadingTitle: "Last Brainstorm",
                            leadingValue: activityPresentation.schedule.lastBrainstormReviewText,
                            trailingTitle: "Next Brainstorm",
                            trailingValue: activityPresentation.schedule.nextBrainstormReviewText
                        )

                        Toggle(
                            "开启事件驱动 review",
                            isOn: Binding(
                                get: { eventDrivenReviewEnabled },
                                set: { onSetEventDrivenReviewEnabled($0) }
                            )
                        )
                        .toggleStyle(.switch)
                        .disabled(!configuredReviewPolicyMode.supportsEventDrivenReview)

                        Text(configuredReviewPolicyMode.supportsEventDrivenReview
                             ? (eventDrivenReviewEnabled
                                ? "当前会监听 blocker / drift / high-risk 等事件；A-tier 强制 checkpoint 始终保留。"
                                : "当前只保留 A-tier 强制 checkpoint；下面的可选事件会先保存，重新开启后生效。")
                             : "Off 模式不会启用事件驱动 review，但 manual request / user override 仍可触发。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        triggerGroup(
                            title: "Locked By A-tier",
                            subtitle: "这些 checkpoint 由当前 A-tier 决定，不能在这里关闭。",
                            triggers: pagePresentation.mandatoryTriggers,
                            accent: executionTierTint(configuredExecutionTier)
                        ) { trigger in
                            triggerInfoRow(
                                trigger: trigger,
                                status: "Locked by \(configuredExecutionTier.shortToken)",
                                note: trigger.governanceSummary
                            )
                        }

                        triggerGroup(
                            title: "Optional Event Triggers",
                            subtitle: "这些事件是额外放开的 review 入口，只影响 event-driven review。",
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
                            title: "Always On / Derived",
                            subtitle: "这些 review 入口来自 cadence 或人工操作，不需要单独勾选。",
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
                        title: "Guidance & Safe Point",
                        subtitle: "这里展示当前治理下，Supervisor 默认会怎样把 review 结论注入给 coder，包括 intervention、safe point、ack 和 work-order 深度。"
                    ) {
                        LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 10) {
                            summaryMetric(
                                title: "Intervention",
                                value: pagePresentation.baselineDecision.interventionMode.displayName,
                                tone: guidanceTint(pagePresentation.baselineDecision.interventionMode)
                            )
                            summaryMetric(
                                title: "Safe Point",
                                value: pagePresentation.baselineDecision.safePointPolicy.displayName,
                                tone: .teal
                            )
                            summaryMetric(
                                title: "Ack",
                                value: pagePresentation.baselineDecision.ackRequired ? "Required" : "Optional",
                                tone: pagePresentation.baselineDecision.ackRequired ? .orange : .secondary
                            )
                            summaryMetric(
                                title: "Work Order",
                                value: resolvedGovernance.supervisorAdaptation.effectiveWorkOrderDepth.displayName,
                                tone: .indigo
                            )
                        }

                        Text("Baseline sample：\(pagePresentation.baselineDecisionSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Guidance 注入：\(governancePresentation.guidanceSummary) · \(governancePresentation.guidanceAckSummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("Follow-up rhythm：\(activityPresentation.followUpRhythmSummary)")
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
                    capabilityBadge("Pulse", active: mode.supportsPulseCadence, tint: tint)
                    capabilityBadge("Brainstorm", active: mode.supportsBrainstormCadence, tint: .indigo)
                    capabilityBadge("Events", active: mode.supportsEventDrivenReview, tint: .teal)
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
                Text("(none)")
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
            badges.append(("Current", reviewPolicyTint(mode)))
        } else {
            if configuredReviewPolicyMode == mode {
                badges.append(("Configured", reviewPolicyTint(mode)))
            }
            if resolvedGovernance.effectiveBundle.reviewPolicyMode == mode {
                badges.append(("Effective", .orange))
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
            return "Always allowed"
        case .userOverride:
            return "Always allowed"
        case .periodicPulse:
            return "Derived from pulse cadence"
        case .noProgressWindow:
            return "Derived from brainstorm cadence"
        default:
            return "Derived"
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
            return "current"
        case (true, false):
            return "configured"
        case (false, true):
            return "effective"
        default:
            return "available"
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
