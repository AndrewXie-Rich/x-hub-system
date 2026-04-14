import SwiftUI

struct ProjectGovernanceThreeAxisOverviewPresentation: Equatable, Sendable {
    struct Dial: Equatable, Sendable {
        let destination: XTProjectGovernanceDestination
        let title: String
        let titleDetail: String
        let token: String
        let label: String
        let summary: String
        let detail: String
        let markerTokens: [String]
        let selectedIndex: Int
    }

    struct RhythmCard: Equatable, Sendable, Identifiable {
        enum Emphasis: Equatable, Sendable {
            case heartbeat
            case review
            case guidance
            case event
        }

        let title: String
        let value: String
        let detail: String
        let emphasis: Emphasis

        var id: String { title }
    }

    struct MemoryLane: Equatable, Sendable, Identifiable {
        enum Role: Equatable, Sendable {
            case projectAI
            case supervisor
        }

        let role: Role
        let title: String
        let token: String
        let summary: String
        let detail: String
        let ceiling: String

        var id: String { title }
    }

    struct RuntimeLoop: Equatable, Sendable, Identifiable {
        enum Role: Equatable, Sendable {
            case projectCoder
            case supervisor
            case scheduler
        }

        let role: Role
        let title: String
        let token: String
        let summary: String
        let detail: String

        var id: String { title }
    }

    struct GuidanceStep: Equatable, Sendable, Identifiable {
        let title: String
        let token: String
        let detail: String

        var id: String { title }
    }

    let principleLines: [String]
    let coordinationSummary: String
    let executionDial: Dial
    let supervisorDial: Dial
    let bridgeTitle: String
    let bridgeLabel: String
    let bridgeDetail: String
    let rhythmCards: [RhythmCard]
    let memoryLanes: [MemoryLane]
    let runtimeLoops: [RuntimeLoop]
    let runtimeSummary: String
    let guidanceSteps: [GuidanceStep]
    let guidanceFlowSummary: String
    let memorySummary: String
    let memoryRuleSummary: String
    let boundaryTokens: [String]
    let boundarySummary: String
    let callout: String?
    let calloutTone: ProjectGovernanceCalloutTone

    init(presentation: ProjectGovernancePresentation) {
        let displayedExecutionTier = presentation.effectiveExecutionTier ?? presentation.executionTier
        let displayedSupervisorTier = presentation.effectiveSupervisorInterventionTier ?? presentation.supervisorInterventionTier

        principleLines = [
            "A-Tier 决定项目 AI 能动多大",
            "S-Tier 决定 Supervisor 管多深",
            "Heartbeat / Review 决定多久看一次、什么时候插手"
        ]
        coordinationSummary = "A 管手和脚，S 管盯盘和纠偏，Heartbeat / Review 管节奏。"

        executionDial = Dial(
            destination: .executionTier,
            title: "A-Tier",
            titleDetail: "Project AI 最大执行边界",
            token: displayedExecutionTier.shortToken,
            label: displayedExecutionTier.localizedShortLabel,
            summary: displayedExecutionTier.oneLineSummary,
            detail: Self.executionDialDetail(
                configured: presentation.executionTier,
                effective: displayedExecutionTier
            ),
            markerTokens: AXProjectExecutionTier.allCases.map(\.shortToken),
            selectedIndex: displayedExecutionTier.dialIndex
        )

        supervisorDial = Dial(
            destination: .supervisorTier,
            title: "S-Tier",
            titleDetail: "Supervisor 监督深度",
            token: displayedSupervisorTier.shortToken,
            label: displayedSupervisorTier.localizedShortLabel,
            summary: displayedSupervisorTier.oneLineSummary,
            detail: Self.supervisorDialDetail(
                configured: presentation.supervisorInterventionTier,
                effective: displayedSupervisorTier,
                recommended: presentation.recommendedSupervisorInterventionTier
            ),
            markerTokens: AXProjectSupervisorInterventionTier.allCases.map(\.shortToken),
            selectedIndex: displayedSupervisorTier.dialIndex
        )

        let combination = Self.combinationLine(
            executionTier: displayedExecutionTier,
            supervisorTier: displayedSupervisorTier,
            presentation: presentation
        )
        bridgeTitle = combination.title
        bridgeLabel = combination.label
        bridgeDetail = combination.detail

        rhythmCards = [
            RhythmCard(
                title: "Heartbeat",
                value: governanceDisplayDurationLabel(presentation.progressHeartbeatSeconds),
                detail: "只看进度，不做战略纠偏",
                emphasis: .heartbeat
            ),
            RhythmCard(
                title: "Review",
                value: presentation.displayReviewPolicyName,
                detail: "脉冲 \(governanceDisplayDurationLabel(presentation.reviewPulseSeconds)) · 脑暴 \(governanceDisplayDurationLabel(presentation.brainstormReviewSeconds))",
                emphasis: .review
            ),
            RhythmCard(
                title: "插手方式",
                value: presentation.guidanceSummary,
                detail: "\(presentation.guidanceAckSummary) · 默认 safe point 注入",
                emphasis: .guidance
            ),
            RhythmCard(
                title: "事件触发",
                value: presentation.eventDrivenReviewEnabled ? "已开启" : "已关闭",
                detail: Self.eventSummary(presentation),
                emphasis: .event
            )
        ]

        memoryLanes = [
            MemoryLane(
                role: .projectAI,
                title: "Project AI",
                token: "P",
                summary: "Recent Project Dialogue + Project Context Depth",
                detail: "A-Tier 只提供 project-memory ceiling；实际上下文深度仍由 role-aware resolver 按当前 trigger 和执行状态单独计算。",
                ceiling: presentation.projectMemoryCeiling.rawValue
            ),
            MemoryLane(
                role: .supervisor,
                title: "Supervisor",
                token: "S",
                summary: "Recent Raw Context + Review Memory Depth",
                detail: "S-Tier 只提供 review-memory ceiling；实际 review-memory 深度仍由 role-aware resolver 按 review purpose 和风险单独计算。",
                ceiling: presentation.supervisorReviewMemoryCeiling.rawValue
            )
        ]

        runtimeLoops = [
            RuntimeLoop(
                role: .projectCoder,
                title: "Project Coder Loop",
                token: "Exec",
                summary: "持续执行",
                detail: "负责推进 step、调用工具、产出 evidence；阻塞时等待 guidance、grant 或 takeover。"
            ),
            RuntimeLoop(
                role: .supervisor,
                title: "Supervisor Governance Loop",
                token: "Review",
                summary: "旁路治理",
                detail: "负责 review、纠偏、重规划、总结，并在 safe point 注入 guidance。"
            ),
            RuntimeLoop(
                role: .scheduler,
                title: "Hub Run Scheduler",
                token: "Truth",
                summary: "全局主链",
                detail: "负责 run truth、grant、audit、wake、clamp / TTL / kill authority。"
            )
        ]

        runtimeSummary = "A4 不是去掉 Supervisor；Project Coder 持续执行，Supervisor 旁路 review，Hub 持有 truth、grant 与 kill authority。"

        guidanceSteps = [
            GuidanceStep(
                title: "Review Note",
                token: "1",
                detail: "Supervisor 每次 review 先形成结构化结论。"
            ),
            GuidanceStep(
                title: "Guidance Injection",
                token: "2",
                detail: "真正发给 Project AI 的指导对象，而不是松散聊天。"
            ),
            GuidanceStep(
                title: "Safe Point",
                token: "3",
                detail: "默认在 tool call / step / checkpoint 结束后插入；高风险时才 immediate。"
            ),
            GuidanceStep(
                title: "Ack",
                token: "4",
                detail: "Project AI 必须接受、延后或拒绝，并说明理由。"
            )
        ]

        guidanceFlowSummary = "默认模式不是每步审批，而是连续推进 -> review -> guidance -> safe point -> ack。"

        memorySummary = "Project ceiling：\(presentation.projectMemoryCeiling.rawValue) · Review ceiling：\(presentation.supervisorReviewMemoryCeiling.rawValue)"
        memoryRuleSummary = "四根记忆拨盘独立工作：Project AI 看 Recent Project Dialogue / Project Context Depth，Supervisor 看 Recent Raw Context / Review Memory Depth；configured / recommended / effective 由 resolver 单独计算，不直接等于 A/S。"
        boundaryTokens = ["grant", "runtime", "policy", "TTL", "kill-switch", "clamp"]
        boundarySummary = "真正 fail-closed 的是 grant、runtime、policy、TTL、kill-switch，不是单纯 A/S 组合。"
        callout = presentation.compactCalloutMessage
        calloutTone = Self.calloutTone(for: presentation)
    }

    private static func executionDialDetail(
        configured: AXProjectExecutionTier,
        effective: AXProjectExecutionTier
    ) -> String {
        if configured == effective {
            return "当前生效 = 已配置 \(effective.localizedDisplayLabel)"
        }
        return "已配置 \(configured.localizedDisplayLabel) -> 当前生效 \(effective.localizedDisplayLabel)"
    }

    private static func supervisorDialDetail(
        configured: AXProjectSupervisorInterventionTier,
        effective: AXProjectSupervisorInterventionTier,
        recommended: AXProjectSupervisorInterventionTier?
    ) -> String {
        var parts: [String] = []
        if configured == effective {
            parts.append("当前生效 = 已配置 \(effective.localizedDisplayLabel)")
        } else {
            parts.append("已配置 \(configured.localizedDisplayLabel) -> 当前生效 \(effective.localizedDisplayLabel)")
        }
        if let recommended {
            parts.append("推荐至少 \(recommended.localizedDisplayLabel)")
        }
        return parts.joined(separator: " · ")
    }

    private static func combinationLine(
        executionTier: AXProjectExecutionTier,
        supervisorTier: AXProjectSupervisorInterventionTier,
        presentation: ProjectGovernancePresentation
    ) -> (title: String, label: String, detail: String) {
        let label = "\(executionTier.shortToken) + \(supervisorTier.shortToken)"
        if executionTier == .a4OpenClaw && supervisorTier == .s3StrategicCoach {
            return (
                "推荐主档",
                label,
                "高自治执行 + 旁路战略监督。A4 不是去掉 Supervisor，而是在持续监督下放大执行面。"
            )
        }

        if supervisorTier < executionTier.minimumSafeSupervisorTier || presentation.hasHighRiskWarning {
            return (
                "高风险组合",
                label,
                "系统允许保存，但 drift、高风险动作前纠偏、完成前复核更容易来不及。"
            )
        }

        return (
            "当前组合",
            label,
            "执行边界、监督强度、Heartbeat / Review 节奏三轴分离；不会再揉成一个 autonomy 滑块。"
        )
    }

    private static func eventSummary(_ presentation: ProjectGovernancePresentation) -> String {
        guard presentation.eventDrivenReviewEnabled else {
            return "只保留 A 档强制检查点、手动请求和用户覆盖"
        }
        let labels = presentation.eventReviewTriggerLabels.filter { !$0.isEmpty }
        if labels.isEmpty {
            return "当前以 cadence 与 safe point guidance 为主"
        }
        return labels.prefix(3).joined(separator: " / ")
    }

    private static func calloutTone(for presentation: ProjectGovernancePresentation) -> ProjectGovernanceCalloutTone {
        if !presentation.invalidMessages.isEmpty {
            return .invalid
        }
        if presentation.hasHighRiskWarning {
            return .warning
        }
        if !presentation.warningMessages.isEmpty {
            return .warning
        }
        return .info
    }
}

struct ProjectGovernanceThreeAxisOverviewView: View {
    let presentation: ProjectGovernancePresentation
    var compact: Bool = false
    var onSelectDestination: ((XTProjectGovernanceDestination) -> Void)? = nil
    var onOpenProjectMemoryControls: (() -> Void)? = nil
    var onOpenSupervisorMemoryControls: (() -> Void)? = nil

    private var model: ProjectGovernanceThreeAxisOverviewPresentation {
        ProjectGovernanceThreeAxisOverviewPresentation(presentation: presentation)
    }

    private var reviewTint: Color {
        ProjectGovernanceComposerAccentTone.forReviewPolicy(presentation.reviewPolicyMode).color
    }

    private var bridgeTone: Color {
        if !presentation.invalidMessages.isEmpty {
            return .red
        }
        if presentation.hasHighRiskWarning {
            return .orange
        }
        if presentation.executionTier == .a4OpenClaw && presentation.supervisorInterventionTier == .s3StrategicCoach {
            return .red
        }
        return .red
    }

    private var bridgeTitleColor: Color {
        switch model.bridgeTitle {
        case "推荐主档":
            return .red
        case "高风险组合":
            return .orange
        default:
            return .secondary
        }
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                executionTint.opacity(compact ? 0.14 : 0.18),
                Color(nsColor: .controlBackgroundColor),
                supervisorTint.opacity(compact ? 0.14 : 0.18)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var executionTint: Color {
        ProjectGovernanceComposerAccentTone.forExecutionTier(
            presentation.effectiveExecutionTier ?? presentation.executionTier
        ).color
    }

    private var supervisorTint: Color {
        ProjectGovernanceComposerAccentTone.forSupervisorTier(
            presentation.effectiveSupervisorInterventionTier ?? presentation.supervisorInterventionTier
        ).color
    }

    var body: some View {
        Group {
            if compact {
                overviewCardContent
            } else {
                GroupBox("A-Tier / S-Tier / Heartbeat / Review") {
                    overviewCardContent
                        .padding(8)
                }
            }
        }
    }

    private var overviewCardContent: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            principleLineBlock

            dualDialDeck

            rhythmDeck

            memoryDeck

            governedRuntimeDeck

            guidanceFlowDeck

            hardBoundaryDeck

            VStack(alignment: .leading, spacing: 6) {
                Text(model.coordinationSummary)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.memorySummary)
                    .font(compact ? .caption2 : .caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(model.memoryRuleSummary)
                    .font(compact ? .caption2 : .caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let callout = model.callout {
                Text("当前提示：\(callout)")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(calloutColor(model.calloutTone))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: compact ? 16 : 18)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 16 : 18)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private var principleLineBlock: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            ForEach(Array(model.principleLines.enumerated()), id: \.offset) { index, line in
                principleLineRow(index: index, text: line)
            }
        }
    }

    private func principleLineRow(index: Int, text: String) -> some View {
        let tint: Color
        let iconName: String
        switch index {
        case 0:
            tint = executionTint
            iconName = "figure.run"
        case 1:
            tint = supervisorTint
            iconName = "eye"
        default:
            tint = reviewTint
            iconName = "waveform.path.ecg"
        }

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16, alignment: .center)

            Text(text)
                .font(compact ? .caption : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dualDialDeck: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: compact ? 10 : 14) {
                    dialCard(model.executionDial, tint: executionTint)
                    dialConnector
                    dialCard(model.supervisorDial, tint: supervisorTint)
                }

                VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                    dialCard(model.executionDial, tint: executionTint)
                    dialConnector
                    dialCard(model.supervisorDial, tint: supervisorTint)
                }
            }

            combinationSummaryCard
        }
    }

    private func dialCard(
        _ dial: ProjectGovernanceThreeAxisOverviewPresentation.Dial,
        tint: Color
    ) -> some View {
        let content = VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dial.title)
                        .font((compact ? Font.caption : .caption).weight(.semibold))
                        .foregroundStyle(tint)

                    Text(dial.titleDetail)
                        .font(compact ? .caption2 : .caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if onSelectDestination != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            ZStack {
                ProjectGovernanceTierDialTrack(
                    stepCount: dial.markerTokens.count,
                    selectedIndex: dial.selectedIndex,
                    tint: tint,
                    compact: compact
                )

                VStack(spacing: 2) {
                    Text(dial.token)
                        .font(.system(size: compact ? 24 : 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(dial.label)
                        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: compact ? 132 : 176, height: compact ? 132 : 176)
            .frame(maxWidth: .infinity)

            markerStrip(dial.markerTokens, selectedIndex: dial.selectedIndex, tint: tint)

            Text(dial.summary)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(dial.detail)
                .font(compact ? .caption2 : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )

        if let onSelectDestination {
            return AnyView(
                Button {
                    onSelectDestination(dial.destination)
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .help("打开\(dial.destination.localizedDisplayTitle)")
            )
        }

        return AnyView(content)
    }

    private var dialConnector: some View {
        VStack(spacing: compact ? 6 : 8) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [bridgeTone.opacity(0.95), bridgeTone.opacity(0.65)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: compact ? 44 : 58, height: compact ? 6 : 8)

            Text(model.bridgeLabel)
                .font(.system(compact ? .caption2 : .caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(bridgeTone)
        }
        .frame(width: compact ? 68 : 84)
    }

    private var combinationSummaryCard: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.bridgeTitle)
                    .font((compact ? Font.caption2 : .caption).weight(.semibold))
                    .foregroundStyle(bridgeTitleColor)

                Text(model.bridgeLabel)
                    .font(.system(compact ? .caption2 : .caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(model.bridgeDetail)
                .font(compact ? .caption2 : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bridgeTone.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(bridgeTone.opacity(0.14), lineWidth: 1)
        )
    }

    private func markerStrip(_ labels: [String], selectedIndex: Int, tint: Color) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(.system(compact ? .caption2 : .caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(index == selectedIndex ? tint : .secondary)
                    .padding(.horizontal, compact ? 6 : 7)
                    .padding(.vertical, compact ? 3 : 4)
                    .background(
                        Capsule()
                            .fill(index == selectedIndex ? tint.opacity(0.14) : Color.secondary.opacity(0.10))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rhythmDeck: some View {
        let card = VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heartbeat / Review")
                        .font((compact ? Font.caption : .caption).weight(.semibold))
                        .foregroundStyle(reviewTint)

                    Text("多久看一次、什么时候插手")
                        .font(compact ? .caption2 : .caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if onSelectDestination != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: compact ? 140 : 160), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(model.rhythmCards) { item in
                    rhythmCard(item)
                }
            }
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .fill(reviewTint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .stroke(reviewTint.opacity(0.22), lineWidth: 1)
        )

        if let onSelectDestination {
            return AnyView(
                Button {
                    onSelectDestination(.heartbeatReview)
                } label: {
                    card
                }
                .buttonStyle(.plain)
                .help("打开\(XTProjectGovernanceDestination.heartbeatReview.localizedDisplayTitle)")
            )
        }

        return AnyView(card)
    }

    private var memoryDeck: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Role-Aware Memory")
                        .font((compact ? Font.caption : .caption).weight(.semibold))
                        .foregroundStyle(.indigo)

                    Text("四根独立记忆拨盘，不和 A/S 直接绑死")
                        .font(compact ? .caption2 : .caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: compact ? 150 : 170), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(model.memoryLanes) { lane in
                    memoryLaneCard(lane)
                }
            }
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .fill(Color.indigo.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .stroke(Color.indigo.opacity(0.18), lineWidth: 1)
        )
    }

    private func memoryLaneCard(
        _ lane: ProjectGovernanceThreeAxisOverviewPresentation.MemoryLane
    ) -> some View {
        let tint: Color = switch lane.role {
        case .projectAI:
            executionTint
        case .supervisor:
            supervisorTint
        }

        let card = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lane.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 0)

                Text(lane.token)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(lane.summary)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("ceiling \(lane.ceiling)")
                .font(.caption2)
                .foregroundStyle(tint)

            Text(lane.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )

        if let action = memoryLaneAction(for: lane.role) {
            return AnyView(
                Button {
                    action()
                } label: {
                    card
                }
                .buttonStyle(.plain)
                .help(memoryLaneHelp(for: lane.role))
            )
        }

        return AnyView(card)
    }

    private func memoryLaneAction(
        for role: ProjectGovernanceThreeAxisOverviewPresentation.MemoryLane.Role
    ) -> (() -> Void)? {
        switch role {
        case .projectAI:
            return onOpenProjectMemoryControls
        case .supervisor:
            return onOpenSupervisorMemoryControls
        }
    }

    private func memoryLaneHelp(
        for role: ProjectGovernanceThreeAxisOverviewPresentation.MemoryLane.Role
    ) -> String {
        switch role {
        case .projectAI:
            return "打开 Project AI 的 Recent Project Dialogue / Project Context Depth 控制面"
        case .supervisor:
            return "打开 Supervisor 的 Review Memory Depth 控制面"
        }
    }

    private var governedRuntimeDeck: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Governed Agent Runtime")
                    .font((compact ? Font.caption : .caption).weight(.semibold))
                    .foregroundStyle(.teal)

                Text("A4 不是裸放权，而是双环治理 + Hub 主链")
                    .font(compact ? .caption2 : .caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: compact ? 150 : 170), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(model.runtimeLoops) { item in
                    runtimeLoopCard(item)
                }
            }

            Text(model.runtimeSummary)
                .font(compact ? .caption2 : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .fill(Color.teal.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .stroke(Color.teal.opacity(0.18), lineWidth: 1)
        )
    }

    private func runtimeLoopCard(
        _ item: ProjectGovernanceThreeAxisOverviewPresentation.RuntimeLoop
    ) -> some View {
        let tint = runtimeLoopTint(item.role)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 0)

                Text(item.token)
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(item.summary)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
    }

    private func runtimeLoopTint(
        _ role: ProjectGovernanceThreeAxisOverviewPresentation.RuntimeLoop.Role
    ) -> Color {
        switch role {
        case .projectCoder:
            return executionTint
        case .supervisor:
            return supervisorTint
        case .scheduler:
            return .teal
        }
    }

    private var guidanceFlowDeck: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Structured Guidance")
                    .font((compact ? Font.caption : .caption).weight(.semibold))
                    .foregroundStyle(.orange)

                Text("Review Note -> Guidance Injection -> Safe Point -> Ack")
                    .font(compact ? .caption2 : .caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: compact ? 140 : 160), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(model.guidanceSteps) { item in
                    guidanceStepCard(item)
                }
            }

            Text(model.guidanceFlowSummary)
                .font(compact ? .caption2 : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private func guidanceStepCard(
        _ item: ProjectGovernanceThreeAxisOverviewPresentation.GuidanceStep
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                Spacer(minLength: 0)

                Text(item.token)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
    }

    private var hardBoundaryDeck: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hard Boundaries")
                    .font((compact ? Font.caption : .caption).weight(.semibold))
                    .foregroundStyle(.red)

                Text("真正决定动作放行的是执行边界，不是单纯 A/S 组合")
                    .font(compact ? .caption2 : .caption2)
                    .foregroundStyle(.secondary)
            }

            flowTokenStrip(model.boundaryTokens, tint: .red)

            Text(model.boundarySummary)
                .font(compact ? .caption2 : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
    }

    private func flowTokenStrip(_ tokens: [String], tint: Color) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compact ? 84 : 96), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(tokens, id: \.self) { token in
                Text(token)
                    .font(.system(compact ? .caption2 : .caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, compact ? 7 : 8)
                    .padding(.vertical, compact ? 4 : 5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.10))
                    )
            }
        }
    }

    private func rhythmCard(_ item: ProjectGovernanceThreeAxisOverviewPresentation.RhythmCard) -> some View {
        let tint = rhythmTint(item.emphasis)
        return VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)

            Text(item.value)
                .font(compact ? .caption.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
    }

    private func rhythmTint(_ emphasis: ProjectGovernanceThreeAxisOverviewPresentation.RhythmCard.Emphasis) -> Color {
        switch emphasis {
        case .heartbeat:
            return .red
        case .review:
            return reviewTint
        case .guidance:
            return supervisorTint
        case .event:
            return executionTint
        }
    }

    private func calloutColor(_ tone: ProjectGovernanceCalloutTone) -> Color {
        switch tone {
        case .invalid:
            return .red
        case .warning:
            return .orange
        case .info:
            return .secondary
        case .neutral:
            return .secondary
        }
    }
}

private struct ProjectGovernanceTierDialTrack: View {
    let stepCount: Int
    let selectedIndex: Int
    let tint: Color
    let compact: Bool

    private let startAngle = 140.0
    private let endAngle = 400.0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let rect = CGRect(
                x: (proxy.size.width - size) / 2,
                y: (proxy.size.height - size) / 2,
                width: size,
                height: size
            )
            let trackLineWidth = compact ? 10.0 : 12.0
            let fillLineWidth = compact ? 12.0 : 14.0
            let selectedAngle = angle(for: selectedIndex)

            ZStack {
                ProjectGovernanceDialArcShape(
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                .stroke(
                    Color.secondary.opacity(0.14),
                    style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round)
                )

                ProjectGovernanceDialArcShape(
                    startAngle: startAngle,
                    endAngle: selectedAngle
                )
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: fillLineWidth, lineCap: .round)
                )

                ForEach(0..<stepCount, id: \.self) { index in
                    let point = markerPoint(in: rect, index: index)
                    Circle()
                        .fill(index == selectedIndex ? tint : Color.secondary.opacity(0.22))
                        .frame(
                            width: index == selectedIndex ? (compact ? 12 : 14) : (compact ? 6 : 7),
                            height: index == selectedIndex ? (compact ? 12 : 14) : (compact ? 6 : 7)
                        )
                        .position(point)
                }

                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: size * 0.48, height: size * 0.48)
                    .overlay(
                        Circle()
                            .stroke(tint.opacity(0.12), lineWidth: 1)
                    )
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func angle(for index: Int) -> Double {
        guard stepCount > 1 else { return endAngle }
        let clamped = min(max(index, 0), stepCount - 1)
        let progress = Double(clamped) / Double(stepCount - 1)
        return startAngle + ((endAngle - startAngle) * progress)
    }

    private func markerPoint(in rect: CGRect, index: Int) -> CGPoint {
        let radius = min(rect.width, rect.height) * 0.40
        let angle = angle(for: index) * .pi / 180
        return CGPoint(
            x: rect.midX + CGFloat(cos(angle)) * radius,
            y: rect.midY + CGFloat(sin(angle)) * radius
        )
    }
}

private struct ProjectGovernanceDialArcShape: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.40
        let segments = 100

        for step in 0...segments {
            let progress = Double(step) / Double(segments)
            let angle = startAngle + ((endAngle - startAngle) * progress)
            let radians = angle * .pi / 180
            let point = CGPoint(
                x: center.x + CGFloat(cos(radians)) * radius,
                y: center.y + CGFloat(sin(radians)) * radius
            )

            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}

private extension AXProjectExecutionTier {
    var dialIndex: Int {
        switch self {
        case .a0Observe:
            return 0
        case .a1Plan:
            return 1
        case .a2RepoAuto:
            return 2
        case .a3DeliverAuto:
            return 3
        case .a4OpenClaw:
            return 4
        }
    }
}

private extension AXProjectSupervisorInterventionTier {
    var dialIndex: Int {
        switch self {
        case .s0SilentAudit:
            return 0
        case .s1MilestoneReview:
            return 1
        case .s2PeriodicReview:
            return 2
        case .s3StrategicCoach:
            return 3
        case .s4TightSupervision:
            return 4
        }
    }
}
