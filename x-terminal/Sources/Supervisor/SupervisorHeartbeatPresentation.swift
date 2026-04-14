import Foundation

enum SupervisorHeartbeatPriority: Int, Equatable {
    case immediate = 0
    case attention = 1
    case watch = 2
    case stable = 3

    var label: String {
        switch self {
        case .immediate:
            return "立即处理"
        case .attention:
            return "优先关注"
        case .watch:
            return "继续观察"
        case .stable:
            return "最近汇报"
        }
    }

    var tone: SupervisorHeaderControlTone {
        switch self {
        case .immediate:
            return .warning
        case .attention:
            return .accent
        case .watch:
            return .success
        case .stable:
            return .neutral
        }
    }

    var actionStyle: SupervisorHeartbeatActionStyle {
        switch self {
        case .immediate, .attention:
            return .prominent
        case .watch, .stable:
            return .standard
        }
    }

    var belongsToAttentionSection: Bool {
        switch self {
        case .immediate, .attention:
            return true
        case .watch, .stable:
            return false
        }
    }
}

enum SupervisorHeartbeatActionStyle: Equatable {
    case standard
    case prominent
}

enum SupervisorHeartbeatAction: Equatable {
    case openFocus(String)
}

struct SupervisorHeartbeatActionDescriptor: Equatable, Identifiable {
    var action: SupervisorHeartbeatAction
    var label: String
    var style: SupervisorHeartbeatActionStyle
    var tone: SupervisorHeaderControlTone
    var isEnabled: Bool

    var id: String {
        switch action {
        case .openFocus(let rawURL):
            return "openFocus|\(rawURL)|\(label)|\(style)|\(tone)|\(isEnabled)"
        }
    }
}

enum SupervisorHeartbeatDigestVisibility: Equatable {
    case userFacing
    case internalOnly
}

struct SupervisorHeartbeatDigest: Equatable {
    var whatChangedText: String
    var whyImportantText: String
    var systemNextStepText: String
    var visibility: SupervisorHeartbeatDigestVisibility
}

struct SupervisorHeartbeatEntryPresentation: Equatable, Identifiable {
    var id: String
    var timeText: String
    var changeText: String
    var changeTone: SupervisorHeaderControlTone
    var reasonText: String
    var priority: SupervisorHeartbeatPriority
    var priorityText: String
    var priorityTone: SupervisorHeaderControlTone
    var headlineText: String
    var headlineTone: SupervisorHeaderControlTone
    var detailLines: [String]
    var contentText: String
    var digest: SupervisorHeartbeatDigest
    var focusAction: SupervisorHeartbeatActionDescriptor?
}

struct SupervisorHeartbeatOverviewPresentation: Equatable {
    var priority: SupervisorHeartbeatPriority
    var priorityText: String
    var priorityTone: SupervisorHeaderControlTone
    var headlineText: String
    var detailText: String
    var metadataText: String
    var focusAction: SupervisorHeartbeatActionDescriptor?
}

struct SupervisorHeartbeatFeedPresentation: Equatable {
    var title: String
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var emptyStateText: String
    var digestModeNoteText: String
    var suppressedInternalCount: Int
    var overview: SupervisorHeartbeatOverviewPresentation?
    var entries: [SupervisorHeartbeatEntryPresentation]

    var isEmpty: Bool {
        entries.isEmpty
    }
}

enum SupervisorHeartbeatPresentation {
    private static let sectionTitles: Set<String> = [
        "主动推进",
        "重点看板",
        "排队态势",
        "权限申请",
        "Recovery 跟进",
        "治理审查",
        "治理修复",
        "项目创建",
        "配对续连",
        "语音就绪",
        "Hub 负载",
        "技能 Doctor Truth",
        "Project AI 记忆（advisory）",
        "Lane 健康巡检",
        "Coder 下一步建议"
    ]

    private enum FocusKind: Equatable {
        case governance
        case routeDiagnose
        case authorization
        case candidateReview
        case skillRecord
        case project
        case supervisor
        case settings
        case other
    }

    private struct FocusDescriptor: Equatable {
        var kind: FocusKind
        var actionLabel: String
    }

    private struct EntrySummary: Equatable {
        var priority: SupervisorHeartbeatPriority
        var headlineText: String
        var headlineTone: SupervisorHeaderControlTone
        var detailLines: [String]
    }

    static func map(
        entries: [SupervisorManager.HeartbeatFeedEntry],
        limit: Int = 4,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        historicalProjectBoundaryRepairStatusLine: String = "",
        doctorPresentation: SupervisorDoctorBoardPresentation? = nil,
        now: Date = Date()
    ) -> SupervisorHeartbeatFeedPresentation {
        let effectiveEntries = mergedEntries(
            entries: entries,
            historicalProjectBoundaryRepairStatusLine: historicalProjectBoundaryRepairStatusLine,
            doctorPresentation: doctorPresentation,
            now: now
        )
        let unsortedEntries = effectiveEntries.enumerated().map { index, entry in
            let focusDescriptor = focusDescriptor(for: entry.focusActionURL)
            let summary = summarize(entry: entry, focusDescriptor: focusDescriptor)
            let digest = heartbeatDigest(
                entry: entry,
                summary: summary,
                focusDescriptor: focusDescriptor
            )
            return (
                index: index,
                entry: SupervisorHeartbeatEntryPresentation(
                    id: entry.id,
                    timeText: timeText(
                        entry.createdAt,
                        timeZone: timeZone,
                        locale: locale
                    ),
                    changeText: entry.changed ? "有变化" : "无重大变化",
                    changeTone: entry.changed ? .success : .neutral,
                    reasonText: reasonText(for: entry.reason),
                    priority: summary.priority,
                    priorityText: summary.priority.label,
                    priorityTone: summary.priority.tone,
                    headlineText: summary.headlineText,
                    headlineTone: summary.headlineTone,
                    detailLines: summary.detailLines,
                    contentText: userFacingContentPreview(
                        entry.content,
                        fallbackHeadline: summary.headlineText
                    ),
                    digest: digest,
                    focusAction: nonEmpty(entry.focusActionURL).map {
                        SupervisorHeartbeatActionDescriptor(
                            action: .openFocus($0),
                            label: focusDescriptor.actionLabel,
                            style: summary.priority.actionStyle,
                            tone: summary.headlineTone,
                            isEnabled: true
                        )
                    }
                )
            )
        }

        let mappedEntries = unsortedEntries.sorted { lhs, rhs in
            if lhs.entry.priority.rawValue != rhs.entry.priority.rawValue {
                return lhs.entry.priority.rawValue < rhs.entry.priority.rawValue
            }
            return lhs.index < rhs.index
        }
        .map { $0.entry }

        let suppressedInternalCount = mappedEntries.reduce(into: 0) { count, entry in
            if entry.digest.visibility == .internalOnly {
                count += 1
            }
        }
        let visibleEntries = Array(
            mappedEntries
                .filter { $0.digest.visibility == .userFacing }
                .prefix(limit)
        )

        let overview = visibleEntries.first.map {
            overviewPresentation(
                topEntry: $0,
                totalCount: visibleEntries.count
            )
        }

        let digestModeNoteText = heartbeatDigestModeNoteText(
            suppressedInternalCount: suppressedInternalCount
        )
        let emptyStateText: String
        if visibleEntries.isEmpty, suppressedInternalCount > 0 {
            emptyStateText =
                "当前没有需要你看的 heartbeat digest；另有 \(suppressedInternalCount) 条内部调试 heartbeat 已隐藏，可在 Doctor / Runtime 查看。"
        } else {
            emptyStateText =
                "当前还没有 heartbeat。收到新的主动汇报后，心脏会跳两下，并在这里保留最近记录。"
        }

        return SupervisorHeartbeatFeedPresentation(
            title: "Supervisor 心跳",
            iconName: "heart.fill",
            iconTone: overview?.priorityTone ?? .danger,
            emptyStateText: emptyStateText,
            digestModeNoteText: digestModeNoteText,
            suppressedInternalCount: suppressedInternalCount,
            overview: overview,
            entries: visibleEntries
        )
    }

    static func highestPriority(
        entries: [SupervisorManager.HeartbeatFeedEntry],
        historicalProjectBoundaryRepairStatusLine: String = "",
        doctorPresentation: SupervisorDoctorBoardPresentation? = nil,
        now: Date = Date()
    ) -> SupervisorHeartbeatPriority? {
        mergedEntries(
            entries: entries,
            historicalProjectBoundaryRepairStatusLine: historicalProjectBoundaryRepairStatusLine,
            doctorPresentation: doctorPresentation,
            now: now
        )
        .reduce(nil) { current, entry in
            let focusDescriptor = focusDescriptor(for: entry.focusActionURL)
            let priority = summarize(entry: entry, focusDescriptor: focusDescriptor).priority
            guard let current else { return priority }
            return priority.rawValue < current.rawValue ? priority : current
        }
    }

    static func userFacingReasonText(for rawReason: String) -> String {
        reasonText(for: rawReason)
    }

    static func userFacingSanitizedLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .compactMap(userFacingSanitizedLine)
            .uniqued()
    }

    static func userFacingSanitizedBlock(
        from text: String,
        emptyPlaceholder: String
    ) -> String {
        let lines = userFacingSanitizedLines(from: text)
        return lines.isEmpty ? emptyPlaceholder : lines.joined(separator: "\n")
    }

    private static func summarize(
        entry: SupervisorManager.HeartbeatFeedEntry,
        focusDescriptor: FocusDescriptor
    ) -> EntrySummary {
        let sections = sectionLines(from: entry.content)
        let governanceLines = sections["治理修复"] ?? []
        let governedReviewLines = sections["治理审查"] ?? []
        let projectCreationLines = sections["项目创建"] ?? []
        let pairingContinuityLines = sections["配对续连"] ?? []
        let voiceReadinessLines = sections["语音就绪"] ?? []
        let hubLoadLines = sections["Hub 负载"] ?? []
        let skillDoctorTruthLines = sections["技能 Doctor Truth"] ?? []
        let projectMemoryLines = sections["Project AI 记忆（advisory）"] ?? []
        let permissionLines = sections["权限申请"] ?? []
        let nextStepLines = sections["Coder 下一步建议"] ?? []
        let recoveryLines = sections["Recovery 跟进"] ?? nextStepLines.filter {
            $0.contains("Recovery 跟进")
        }
        let queueLines = sections["排队态势"] ?? []
        let progressLines = sections["主动推进"] ?? []
        let topBoardLines = sections["重点看板"] ?? []

        let routeLines = nextStepLines.filter {
            $0.contains("模型路由") || $0.contains("/route diagnose")
        }
        let blockerLines = topBoardLines.filter {
            $0.contains("🚧") || $0.contains("阻塞")
        }

        if focusDescriptor.kind == .governance || !governanceLines.isEmpty {
            return EntrySummary(
                priority: .immediate,
                headlineText: "治理修复",
                headlineTone: .warning,
                detailLines: prioritizedLines(governanceLines, fallback: nextStepLines)
            )
        }

        if !recoveryLines.isEmpty {
            let recoveryNeedsAuthorization = recoveryLines.contains { line in
                line.localizedCaseInsensitiveContains("grant")
                    || line.contains("授权")
                    || line.contains("权限")
            } || focusDescriptor.kind == .authorization
            return EntrySummary(
                priority: recoveryNeedsAuthorization ? .immediate : .attention,
                headlineText: "Recovery 跟进",
                headlineTone: recoveryNeedsAuthorization ? .warning : .accent,
                detailLines: prioritizedLines(recoveryLines, fallback: nextStepLines, limit: 3)
            )
        }

        if focusDescriptor.kind == .authorization || !permissionLines.isEmpty {
            return EntrySummary(
                priority: .immediate,
                headlineText: "授权待处理",
                headlineTone: .warning,
                detailLines: prioritizedLines(permissionLines, fallback: nextStepLines)
            )
        }

        if !governedReviewLines.isEmpty {
            let hasRescueReview = governedReviewLines.contains { line in
                line.contains("救援审查") || line.contains("高风险")
            }
            let hasPulseOnly = !hasRescueReview && governedReviewLines.contains { line in
                line.contains("脉冲审查")
            } && !governedReviewLines.contains { line in
                line.contains("战略审查")
            }
            let governedReviewDetailLimit = governedReviewLines.contains { line in
                line.contains("记忆供给")
            } ? 3 : 2
            return EntrySummary(
                priority: hasRescueReview ? .immediate : .attention,
                headlineText: hasRescueReview ? "救援审查已排队" : (hasPulseOnly ? "治理脉冲已排队" : "治理审查已排队"),
                headlineTone: hasRescueReview ? .warning : .accent,
                detailLines: prioritizedLines(
                    governedReviewLines,
                    fallback: nextStepLines,
                    limit: governedReviewDetailLimit
                )
            )
        }

        if !projectCreationLines.isEmpty {
            return Self.projectCreationEntrySummary(projectCreationLines)
        }

        if focusDescriptor.kind == .candidateReview {
            return EntrySummary(
                priority: .attention,
                headlineText: "候选审查待处理",
                headlineTone: .accent,
                detailLines: prioritizedLines(topBoardLines, fallback: nextStepLines)
            )
        }

        if !pairingContinuityLines.isEmpty {
            let advisoryOnly = heartbeatReadinessIsAdvisory(pairingContinuityLines)
            return EntrySummary(
                priority: advisoryOnly ? .watch : .attention,
                headlineText: advisoryOnly ? "配对续连仍需确认" : "配对续连待修复",
                headlineTone: advisoryOnly ? .accent : .warning,
                detailLines: prioritizedLines(pairingContinuityLines, fallback: nextStepLines)
            )
        }

        if !voiceReadinessLines.isEmpty {
            let advisoryOnly = heartbeatReadinessIsAdvisory(voiceReadinessLines)
            return EntrySummary(
                priority: advisoryOnly ? .watch : .attention,
                headlineText: advisoryOnly ? "语音仍有待修复项" : "语音链路待修复",
                headlineTone: advisoryOnly ? .accent : .warning,
                detailLines: prioritizedLines(voiceReadinessLines, fallback: nextStepLines)
            )
        }

        if !hubLoadLines.isEmpty {
            let critical = hubLoadLines.contains {
                $0.contains("负载过高")
                    || $0.contains("thermal_state=critical")
                    || $0.contains("热状态 critical")
                    || $0.contains("host_load_severity=critical")
            }
            let elevatedOnly = !critical && hubLoadLines.contains {
                $0.contains("需要关注")
                    || $0.contains("host_load_severity=elevated")
            }
            return EntrySummary(
                priority: critical ? .immediate : (elevatedOnly ? .watch : .attention),
                headlineText: critical ? "Hub 负载过高" : (elevatedOnly ? "Hub 负载关注" : "Hub 负载偏高"),
                headlineTone: critical ? .warning : .accent,
                detailLines: prioritizedLines(hubLoadLines, fallback: nextStepLines)
            )
        }

        if !skillDoctorTruthLines.isEmpty {
            let blocked = skillDoctorTruthLines.contains { line in
                line.contains("当前不可运行") || line.contains("当前阻塞")
            }
            return EntrySummary(
                priority: .attention,
                headlineText: blocked ? "技能能力阻塞" : "技能授权待补齐",
                headlineTone: blocked ? .danger : .warning,
                detailLines: prioritizedLines(
                    skillDoctorTruthLines,
                    fallback: nextStepLines,
                    limit: 3
                )
            )
        }

        if focusDescriptor.kind == .routeDiagnose || !routeLines.isEmpty {
            return EntrySummary(
                priority: .attention,
                headlineText: "模型路由诊断",
                headlineTone: .accent,
                detailLines: prioritizedLines(routeLines, fallback: topBoardLines)
            )
        }

        if !blockerLines.isEmpty {
            return EntrySummary(
                priority: .attention,
                headlineText: "项目阻塞",
                headlineTone: .danger,
                detailLines: prioritizedLines(blockerLines, fallback: nextStepLines)
            )
        }

        if !projectMemoryLines.isEmpty {
            return EntrySummary(
                priority: .watch,
                headlineText: "Project AI 记忆需补强",
                headlineTone: .accent,
                detailLines: prioritizedLines(projectMemoryLines, fallback: nextStepLines, limit: 3)
            )
        }

        if let firstProgress = firstMeaningfulLine(progressLines) {
            return EntrySummary(
                priority: .watch,
                headlineText: "已主动推进",
                headlineTone: .success,
                detailLines: prioritizedLines([firstProgress], fallback: nextStepLines)
            )
        }

        if !queueLines.isEmpty {
            return EntrySummary(
                priority: .watch,
                headlineText: "排队关注",
                headlineTone: .accent,
                detailLines: prioritizedLines(queueLines, fallback: nextStepLines)
            )
        }

        return EntrySummary(
            priority: .stable,
            headlineText: "状态稳定",
            headlineTone: entry.changed ? .success : .neutral,
            detailLines: prioritizedLines(topBoardLines, fallback: nextStepLines)
        )
    }

    private static func heartbeatDigest(
        entry: SupervisorManager.HeartbeatFeedEntry,
        summary: EntrySummary,
        focusDescriptor: FocusDescriptor
    ) -> SupervisorHeartbeatDigest {
        let sections = sectionLines(from: entry.content)
        let nextStepLines = sections["Coder 下一步建议"] ?? []
        let governedReviewMemoryLine = governedReviewProjectMemoryLine(from: sections)
        let governedReviewHeadline = isGovernedReviewHeadline(summary.headlineText)
        let contentPreview = userFacingContentPreview(
            entry.content,
            fallbackHeadline: summary.headlineText
        )
        let visibility = heartbeatDigestVisibility(
            entry: entry,
            summary: summary,
            focusDescriptor: focusDescriptor
        )
        let prefersExplicitImportanceFallback = focusDescriptor.kind == .authorization
            || focusDescriptor.kind == .governance
            || summary.headlineText == "Recovery 跟进"
            || summary.headlineText == "技能能力阻塞"
            || summary.headlineText == "技能授权待补齐"
            || governedReviewHeadline
            || summary.headlineText.hasPrefix("项目创建")
        let whyImportantText: String
        if governedReviewHeadline {
            whyImportantText = governedReviewDigestImportanceText(
                memoryLine: governedReviewMemoryLine,
                fallback: heartbeatDigestImportanceFallback(
                    summary: summary,
                    focusDescriptor: focusDescriptor
                )
            )
        } else if prefersExplicitImportanceFallback {
            whyImportantText = heartbeatDigestImportanceFallback(
                summary: summary,
                focusDescriptor: focusDescriptor
            )
        } else {
            whyImportantText =
                firstDistinctMeaningfulLine(
                    summary.detailLines,
                    excluding: [contentPreview]
                ) ?? heartbeatDigestImportanceFallback(
                    summary: summary,
                    focusDescriptor: focusDescriptor
                )
        }
        let preferredNextStepLines = summary.headlineText == "Recovery 跟进"
            ? summary.detailLines
            : nextStepLines
        let fallbackNextStepLines = summary.headlineText == "Recovery 跟进"
            ? nextStepLines
            : summary.detailLines
        let baseNextStepText =
            firstDistinctMeaningfulLine(
                preferredNextStepLines,
                excluding: [contentPreview, whyImportantText]
            ) ??
            firstDistinctMeaningfulLine(
                fallbackNextStepLines,
                excluding: [contentPreview, whyImportantText]
            ) ??
            heartbeatDigestNextStepFallback(
                summary: summary,
                focusDescriptor: focusDescriptor
            )
        let systemNextStepText = governedReviewHeadline
            ? governedReviewDigestNextStepText(
                base: baseNextStepText,
                memoryLine: governedReviewMemoryLine
            )
            : baseNextStepText

        return SupervisorHeartbeatDigest(
            whatChangedText: contentPreview,
            whyImportantText: whyImportantText,
            systemNextStepText: systemNextStepText,
            visibility: visibility
        )
    }

    private static func heartbeatDigestVisibility(
        entry: SupervisorManager.HeartbeatFeedEntry,
        summary: EntrySummary,
        focusDescriptor: FocusDescriptor
    ) -> SupervisorHeartbeatDigestVisibility {
        if summary.priority != .stable {
            return .userFacing
        }
        if focusDescriptor.kind != .other {
            return .userFacing
        }
        return hasExplicitUserFacingSignal(in: entry.content) ? .userFacing : .internalOnly
    }

    private static func hasExplicitUserFacingSignal(in content: String) -> Bool {
        if !sectionLines(from: content).isEmpty {
            return true
        }
        return content
            .components(separatedBy: .newlines)
            .compactMap(userFacingFreeformLine)
            .isEmpty == false
    }

    private static func heartbeatDigestImportanceFallback(
        summary: EntrySummary,
        focusDescriptor: FocusDescriptor
    ) -> String {
        if summary.headlineText == "Recovery 跟进" {
            let detailText = summary.detailLines.joined(separator: "\n")
            if detailText.localizedCaseInsensitiveContains("grant")
                || detailText.contains("授权")
                || detailText.contains("权限") {
                return "系统已判断当前需要先补齐 grant / 授权跟进，不能把状态当成正常推进。"
            }
            if detailText.localizedCaseInsensitiveContains("follow-up")
                || detailText.contains("续跑链")
                || detailText.contains("drain") {
                return "系统已判断当前要先修复挂起的 follow-up / 续跑链，不能把状态当成正常推进。"
            }
            return "系统已判断需要恢复或补救动作，不能把当前状态当成正常推进。"
        }

        switch focusDescriptor.kind {
        case .governance:
            return "当前治理边界已经影响执行，必须先修好再继续推进。"
        case .authorization:
            return "当前推进被授权或审批挡住，在你处理前系统不会越权继续执行。"
        case .candidateReview:
            return "当前有待处理的候选审查，先确认它能减少后续误判。"
        case .routeDiagnose:
            return "这说明当前路由与真实可用执行面可能不一致，继续推进前最好先确认。"
        case .settings:
            if summary.headlineText.contains("Hub 负载") {
                return "Hub 侧资源已经吃紧，可能影响队列、模型加载和运行稳定性。"
            }
            if summary.headlineText.contains("配对") || summary.headlineText.contains("续连") {
                return "正式异网入口还没完全确认，切网或换环境后仍可能断开。"
            }
            if summary.headlineText.contains("语音") {
                return "语音链路还不稳定，相关任务可能 fail-closed 或退化。"
            }
            return "当前信号已经落到一个具体的修复或诊断面板，不需要你再翻工程噪音。"
        case .project, .supervisor, .skillRecord, .other:
            break
        }

        switch summary.headlineText {
        case "治理审查已排队", "治理脉冲已排队", "救援审查已排队":
            return "这说明系统判断需要额外复盘，避免在无进展或高风险时继续盲跑。"
        case "项目创建差一句触发", "项目创建待确认":
            return "当前不会误把“已理解需求”当成“已真正创建项目”。"
        case "项目已创建待补目标":
            return "项目已经先建好，但当前还不能把一个没有明确交付目标的项目当成可继续自动推进。"
        case "项目创建缺目标":
            return "当前不会把一句泛化的“建项目/立项”误判成真正可推进的项目创建，避免在项目名和目标都不清楚时误建空壳。"
        case "项目创建处理中":
            return "上一轮创建已经在处理中，重复触发只会制造重复执行或重复提醒。"
        case "配对续连待修复", "配对续连仍需确认":
            return "这说明正式异网入口还没完全确认，切网或换环境后仍可能断开。"
        case "语音链路待修复", "语音仍有待修复项":
            return "语音链路还不稳定，相关任务可能 fail-closed 或退化。"
        case "Hub 负载过高", "Hub 负载偏高", "Hub 负载关注":
            return "Hub 侧资源已经吃紧，可能影响队列、模型加载和运行稳定性。"
        case "技能能力阻塞":
            return "这说明 typed capability / readiness 与真实可运行事实还没对齐，继续派活会命中 fail-closed 或空转。"
        case "技能授权待补齐":
            return "这说明部分技能虽然已被纳入治理，但还没完成 Hub grant 或本地确认，系统不会把它们当成可直接执行。"
        case "模型路由诊断":
            return "这说明当前路由与真实可用执行面可能不一致，继续推进前最好先确认。"
        case "Project AI 记忆需补强":
            return "这不会改变 Hub 的治理边界，但说明 coder 最近拿到的项目上下文装配还不够稳。"
        case "项目阻塞":
            return "项目推进已经受阻，如果继续等待只会让 blocker 累积。"
        case "已主动推进":
            return "项目还在持续推进，目前更多是观察而不是立即接管。"
        case "排队关注":
            return "任务仍在排队或等待恢复，不一定是故障，但值得继续留意。"
        case "授权待处理":
            return "当前推进被授权或审批挡住，在你处理前系统不会越权继续执行。"
        case "状态稳定":
            return "当前没有新的高风险或高优先级治理信号，系统保持持续观察。"
        default:
            switch summary.priority {
            case .immediate:
                return "这条 heartbeat 已经进入需要立即处理的范围，不适合继续静默观察。"
            case .attention:
                return "这条 heartbeat 已经值得优先关注，继续拖着只会让偏差继续积累。"
            case .watch:
                return "这条 heartbeat 目前以观察为主，但还需要继续留意后续变化。"
            case .stable:
                return "当前没有新的高风险或高优先级治理信号，系统保持持续观察。"
            }
        }
    }

    private static func heartbeatDigestNextStepFallback(
        summary: EntrySummary,
        focusDescriptor: FocusDescriptor
    ) -> String {
        if summary.headlineText == "Recovery 跟进" {
            let detailText = summary.detailLines.joined(separator: "\n")
            if detailText.localizedCaseInsensitiveContains("grant")
                || detailText.contains("授权")
                || detailText.contains("权限") {
                return "系统会先发起所需 grant / 授权跟进，待放行后再继续恢复执行。"
            }
            if detailText.localizedCaseInsensitiveContains("follow-up")
                || detailText.contains("续跑链")
                || detailText.contains("drain") {
                return "系统会先重放挂起的 follow-up / 续跑链，再确认执行是否恢复。"
            }
            return "系统会先执行必要的恢复或补救动作，再决定是否继续自动推进。"
        }

        switch focusDescriptor.kind {
        case .governance:
            return "系统会把你带到治理设置，修好执行边界后再继续推进。"
        case .authorization:
            return "系统会等待你处理授权或审批后，再继续推进当前项目。"
        case .candidateReview:
            return "系统会等待你先处理候选审查，再继续后续推进。"
        case .routeDiagnose:
            return "系统会先打开诊断目标，核对真实模型路由和恢复建议。"
        case .settings:
            if summary.headlineText.contains("Hub 负载") {
                return "系统会优先检查 Hub 诊断，再决定是否降载或继续排队。"
            }
            if summary.headlineText.contains("配对") || summary.headlineText.contains("续连") {
                return "系统会引导你进入配对页，继续核对正式异网入口和续连状态。"
            }
            if summary.headlineText.contains("语音") {
                return "系统会引导你进入语音修复面板，继续排查 bridge 和工具链路。"
            }
            return "系统会把你带到对应设置页，再根据结果决定是否继续。"
        case .project, .supervisor, .skillRecord, .other:
            break
        }

        switch summary.headlineText {
        case "治理审查已排队", "治理脉冲已排队", "救援审查已排队":
            return "Supervisor 会在下一个 safe point 执行 review，并把 guidance 注入给项目执行环。"
        case "项目创建差一句触发":
            return "直接说立项，或说创建一个project。"
        case "项目创建待确认":
            return "直接说立项，或说就按这个建。"
        case "项目已创建待补目标":
            return "直接说“我要用默认的MVP”，或说“第一版先做成最小可运行版本”。"
        case "项目创建缺目标":
            return "直接给项目名，或先补一句要做什么。"
        case "项目创建处理中":
            return "等这轮创建完成。"
        case "配对续连待修复", "配对续连仍需确认":
            return "系统会继续引导你核对正式异网入口，并在切网续连验证完成前保持关注。"
        case "技能能力阻塞":
            return "系统会引导你打开 Supervisor 体检，先处理技能 doctor truth 里的阻塞项，再继续派活。"
        case "技能授权待补齐":
            return "系统会引导你打开 Supervisor 体检，先补齐技能 doctor truth 里的 Hub grant / 本地确认项。"
        case "Project AI 记忆需补强":
            return "系统会继续维持当前 heartbeat 节奏，并等待下一轮 coder usage / memory resolution truth 补齐。"
        case "项目阻塞":
            return "系统会继续观察 blocker，并在需要时升级到更强的 review 或提醒。"
        case "已主动推进":
            return "系统会继续推进当前任务，并在下一次 heartbeat 再汇报关键变化。"
        case "排队关注":
            return "系统会继续等待排队状态变化，并在值得介入时再提醒。"
        case "状态稳定":
            return "系统会继续观察当前项目，有实质变化再提醒你。"
        default:
            switch summary.priority {
            case .immediate:
                return "系统会保持当前高优先级提醒，直到关键阻塞被处理。"
            case .attention:
                return "系统会继续观察这条信号，并在下一个安全时机推动你处理。"
            case .watch:
                return "系统会继续观察后续变化，暂不需要额外打断。"
            case .stable:
                return "系统会继续观察当前项目，有实质变化再提醒你。"
            }
        }
    }

    private static func firstDistinctMeaningfulLine(
        _ lines: [String],
        excluding excludedValues: [String]
    ) -> String? {
        let excluded = Set(
            excludedValues.map { normalizedScalar($0) }
                .filter { !$0.isEmpty }
        )
        return lines.compactMap(userFacingSanitizedLine).first { line in
            !excluded.contains(normalizedScalar(line))
        }
    }

    private static func isGovernedReviewHeadline(_ headline: String) -> Bool {
        switch headline {
        case "治理审查已排队", "治理脉冲已排队", "救援审查已排队":
            return true
        default:
            return false
        }
    }

    private static func governedReviewProjectMemoryLine(
        from sections: [String: [String]]
    ) -> String? {
        let governedReviewLines = sections["治理审查"] ?? []
        return governedReviewLines
            .compactMap(userFacingSanitizedLine)
            .first(where: { $0.contains("记忆供给") })
    }

    private static func governedReviewDigestImportanceText(
        memoryLine: String?,
        fallback: String
    ) -> String {
        let normalized = normalizedScalar(memoryLine ?? "")
        guard !normalized.isEmpty else { return fallback }
        if normalized.contains("latest coder usage") {
            return "这次治理判断已对齐到 Project AI 最近一轮 latest coder usage memory truth，避免 Supervisor 和 coder 各看各的。"
        }
        if normalized.contains("config-only baseline") || normalized.contains("config baseline") {
            return "当前治理判断还只有 config-only baseline，后续仍要等 recent coder usage 回写，避免把配置基线误当成最新执行真相。"
        }
        return "这次治理判断已附带 Project AI 的记忆供给真相，不是只按静态配置盲审。"
    }

    private static func governedReviewDigestNextStepText(
        base: String,
        memoryLine: String?
    ) -> String {
        let normalized = normalizedScalar(memoryLine ?? "")
        guard !normalized.isEmpty else { return base }
        if normalized.contains("heartbeat digest 已在 Project AI working set 中") {
            return "\(base) 系统会沿这份 memory truth 在 safe point 注入 guidance，不再额外重复灌入同一份 heartbeat digest。"
        }
        return "\(base) 系统会继续沿当前治理链把 heartbeat digest 补进 Project AI working set，而不是绕过既有 review / gate 边界。"
    }

    private static func heartbeatReadinessIsAdvisory(_ lines: [String]) -> Bool {
        lines.contains { line in
            line.contains("首个任务已可启动")
                || line.localizedCaseInsensitiveContains("first task ready")
        }
    }

    private static func projectCreationEntrySummary(_ lines: [String]) -> EntrySummary {
        let normalized = lines.map(normalizedScalar)
        let headlineText: String
        let priority: SupervisorHeartbeatPriority
        let headlineTone: SupervisorHeaderControlTone

        if normalized.contains(where: {
            $0.contains("上一轮项目创建流程仍在处理中")
                || $0.contains("创建完成后会继续")
                || $0.contains("不用重复再发一次")
        }) {
            headlineText = "项目创建处理中"
            priority = .watch
            headlineTone = .accent
        } else if normalized.contains(where: {
            $0.contains("项目已创建待补目标")
                || $0.contains("已经创建完成")
                || $0.contains("已先创建项目")
                || $0.contains("我要用默认的mvp")
                || $0.contains("最小可运行版本")
        }) {
            headlineText = "项目已创建待补目标"
            priority = .attention
            headlineTone = .accent
        } else if normalized.contains(where: {
            $0.contains("缺明确交付目标")
                || $0.contains("缺项目名")
                || $0.contains("先说目标")
                || $0.contains("补一句要做什么")
                || $0.contains("直接给项目名")
        }) {
            headlineText = "项目创建缺目标"
            priority = .attention
            headlineTone = .warning
        } else if normalized.contains(where: {
            $0.contains("就按这个建")
                || $0.contains("恢复《")
                || $0.contains("恢复最近 proposal")
                || $0.contains("待确认")
        }) {
            headlineText = "项目创建待确认"
            priority = .attention
            headlineTone = .accent
        } else {
            headlineText = "项目创建差一句触发"
            priority = .attention
            headlineTone = .accent
        }

        let statusLine = projectCreationStatusLine(for: headlineText)
        let actionLine = projectCreationActionLine(for: headlineText)
        let supportingLine = normalized.first(where: { line in
            let candidate = normalizedScalar(line)
            return !candidate.isEmpty
                && candidate != statusLine
                && candidate != actionLine
                && !candidate.hasPrefix("可直接说：")
        })

        return EntrySummary(
            priority: priority,
            headlineText: headlineText,
            headlineTone: headlineTone,
            detailLines: [statusLine, actionLine, supportingLine]
                .compactMap { raw in
                    let trimmed = normalizedScalar(raw ?? "")
                    return trimmed.isEmpty ? nil : trimmed
                }
                .uniqued()
        )
    }

    private static func projectCreationStatusLine(for headlineText: String) -> String {
        switch headlineText {
        case "项目创建处理中":
            return "上一轮项目创建流程仍在处理中。"
        case "项目已创建待补目标":
            return "项目已创建，待补交付目标。"
        case "项目创建缺目标":
            return "项目创建还缺项目名或明确交付目标。"
        case "项目创建待确认":
            return "项目创建待确认，系统已恢复最近 proposal。"
        default:
            return "项目创建还差一句触发。"
        }
    }

    private static func projectCreationActionLine(for headlineText: String) -> String {
        switch headlineText {
        case "项目创建处理中":
            return "等这轮创建完成。"
        case "项目已创建待补目标":
            return "直接说“我要用默认的MVP”，或说“第一版先做成最小可运行版本”。"
        case "项目创建缺目标":
            return "直接给项目名，或先补一句要做什么。"
        case "项目创建待确认":
            return "直接说立项，或说就按这个建。"
        default:
            return "直接说立项，或说创建一个project。"
        }
    }

    private static func heartbeatDigestModeNoteText(
        suppressedInternalCount: Int
    ) -> String {
        if suppressedInternalCount > 0 {
            return "这里只展示用户 digest；另有 \(suppressedInternalCount) 条内部调试 heartbeat 已隐藏，可在 Doctor / Runtime 查看。"
        }
        return "这里只展示用户 digest，运行时噪音留在 Doctor / Runtime。"
    }

    private static func overviewPresentation(
        topEntry: SupervisorHeartbeatEntryPresentation,
        totalCount: Int
    ) -> SupervisorHeartbeatOverviewPresentation {
        let detailText = firstMeaningfulLine(topEntry.detailLines)
            ?? firstMeaningfulLine(topEntry.contentText)
            ?? topEntry.headlineText
        let remainingCount = max(0, totalCount - 1)
        var metadataParts = [topEntry.reasonText, topEntry.timeText]
        if remainingCount > 0 {
            metadataParts.append("另有 \(remainingCount) 条更新")
        }

        return SupervisorHeartbeatOverviewPresentation(
            priority: topEntry.priority,
            priorityText: topEntry.priorityText,
            priorityTone: topEntry.priorityTone,
            headlineText: topEntry.headlineText,
            detailText: detailText,
            metadataText: metadataParts.joined(separator: " · "),
            focusAction: topEntry.focusAction
        )
    }

    private static func focusDescriptor(for rawURL: String?) -> FocusDescriptor {
        let trimmed = nonEmpty(rawURL) ?? ""
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let route = XTDeepLinkParser.parse(url) else {
            return FocusDescriptor(kind: .other, actionLabel: "打开相关视图")
        }

        switch route {
        case .supervisor(let supervisorRoute):
            switch supervisorRoute.focusTarget {
            case .projectCreationBoard:
                return FocusDescriptor(kind: .supervisor, actionLabel: "打开项目创建板")
            case .grant, .approval, .candidateReview, .skillRecord, .toolApproval, .routeDiagnose, nil:
                return FocusDescriptor(kind: .supervisor, actionLabel: "打开 Supervisor")
            }
        case .hubSetup(let hubRoute):
            let sectionID = normalizedScalar(hubRoute.sectionId ?? "").lowercased()
            let title = normalizedScalar(hubRoute.title ?? "")
            if sectionID == "connection_log" {
                return FocusDescriptor(kind: .settings, actionLabel: "打开 Hub 日志")
            }
            if sectionID == "choose_model" {
                return FocusDescriptor(kind: .settings, actionLabel: "打开 Hub 模型")
            }
            if sectionID == "pair_progress" || sectionID == "pair_hub" {
                return FocusDescriptor(kind: .settings, actionLabel: "打开 Hub 配对")
            }
            if sectionID == "troubleshoot" {
                if title.contains("Hub 负载") {
                    return FocusDescriptor(kind: .settings, actionLabel: "打开 Hub 诊断")
                }
                return FocusDescriptor(kind: .settings, actionLabel: "打开 Hub Recovery")
            }
            return FocusDescriptor(kind: .settings, actionLabel: "打开 Hub 设置")
        case .settings(let settingsRoute):
            if settingsRoute.refreshAction == .repairHistoricalProjectBoundaries
                || settingsRoute.sectionId == "diagnostics" {
                return FocusDescriptor(kind: .settings, actionLabel: "打开 XT Diagnostics")
            }
            return FocusDescriptor(kind: .settings, actionLabel: "打开设置")
        case .supervisorSettings:
            return FocusDescriptor(kind: .settings, actionLabel: "打开 Supervisor Control Center")
        case .supervisorModelSettings:
            return FocusDescriptor(
                kind: .settings,
                actionLabel: "打开 Supervisor Control Center · AI 模型"
            )
        case .resume:
            return FocusDescriptor(kind: .project, actionLabel: "打开项目")
        case .project(let projectRoute):
            if projectRoute.governanceDestination != nil {
                return FocusDescriptor(kind: .governance, actionLabel: "打开治理设置")
            }
            switch projectRoute.focusTarget {
            case .routeDiagnose:
                return FocusDescriptor(kind: .routeDiagnose, actionLabel: "打开路由诊断")
            case .grant, .approval, .toolApproval:
                return FocusDescriptor(kind: .authorization, actionLabel: "打开授权处理")
            case .candidateReview:
                return FocusDescriptor(kind: .candidateReview, actionLabel: "打开候选审查")
            case .skillRecord:
                return FocusDescriptor(kind: .skillRecord, actionLabel: "打开技能记录")
            case .projectCreationBoard, nil:
                break
            }
            if projectRoute.openTarget == .supervisor {
                return FocusDescriptor(kind: .supervisor, actionLabel: "打开 Supervisor")
            }
            return FocusDescriptor(kind: .project, actionLabel: "打开项目")
        }
    }

    private static func sectionLines(from content: String) -> [String: [String]] {
        var sections: [String: [String]] = [:]
        var currentSection: String?

        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if sectionTitles.contains(trimmed.replacingOccurrences(of: "：", with: "")) {
                currentSection = trimmed.replacingOccurrences(of: "：", with: "")
                continue
            }

            guard let currentSection else { continue }
            guard let sanitized = userFacingSanitizedLine(trimmed),
                  sanitized != "（无）",
                  sanitized != "（本轮无需介入）",
                  sanitized != "（暂无）",
                  sanitized != "（无异常 lane）",
                  sanitized != "（无异常泳道）" else {
                continue
            }
            sections[currentSection, default: []].append(sanitized)
        }

        return sections
    }

    private static func userFacingContentPreview(
        _ content: String,
        fallbackHeadline: String
    ) -> String {
        let sections = sectionLines(from: content)
        let preferredSectionOrder = [
            "治理修复",
            "Recovery 跟进",
            "权限申请",
            "治理审查",
            "项目创建",
            "配对续连",
            "语音就绪",
            "Hub 负载",
            "技能 Doctor Truth",
            "Project AI 记忆（advisory）",
            "重点看板",
            "主动推进",
            "排队态势",
            "Coder 下一步建议"
        ]

        for section in preferredSectionOrder {
            if let lines = sections[section],
               let preview = previewLine(for: section, lines: lines) {
                return preview
            }
        }

        let preview = content
            .components(separatedBy: .newlines)
            .compactMap(userFacingFreeformLine)
            .first
        return preview ?? fallbackHeadline
    }

    private static func previewLine(for section: String, lines: [String]) -> String? {
        if section == "项目创建" {
            return projectCreationPreviewLine(lines)
        }
        return firstMeaningfulLine(lines)
    }

    private static func projectCreationPreviewLine(_ lines: [String]) -> String? {
        guard !lines.isEmpty else { return nil }
        return firstMeaningfulLine(Self.projectCreationEntrySummary(lines).detailLines)
    }

    private static func prioritizedLines(
        _ primary: [String],
        fallback: [String],
        limit: Int = 2
    ) -> [String] {
        let primaryLines = primary.compactMap(userFacingSanitizedLine).uniqued()
        let fallbackLines = fallback.compactMap(userFacingSanitizedLine).uniqued()
        let combined = (primaryLines + fallbackLines).uniqued()
        return Array(combined.prefix(max(1, limit)))
    }

    private static func firstMeaningfulLine(_ raw: String) -> String? {
        let normalized = normalizedLine(raw)
        return normalized.isEmpty ? nil : normalized
    }

    private static func firstMeaningfulLine(_ lines: [String]) -> String? {
        lines.compactMap(firstMeaningfulLine).first
    }

    private static func userFacingSanitizedLine(_ raw: String) -> String? {
        let normalized = normalizedLine(raw)
        guard !normalized.isEmpty else { return nil }
        let humanized = humanizedGovernedReviewLine(normalized) ?? normalized
        guard !isInternalNoiseLine(humanized) else { return nil }
        return humanized
    }

    private static func userFacingFreeformLine(_ raw: String) -> String? {
        guard let normalized = userFacingSanitizedLine(raw) else { return nil }
        if isHeartbeatEnvelopeLine(normalized) {
            return nil
        }
        return normalized
    }

    private static func normalizedLine(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[•\-]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"（打开：.*?）$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func humanizedGovernedReviewLine(_ normalized: String) -> String? {
        let lowercased = normalizedScalar(normalized).lowercased()
        guard lowercased.contains("governance review")
            || lowercased.contains("governed review")
            || lowercased.contains("queued review")
            || lowercased.contains("queued rescue review")
            || lowercased.contains("safe point")
            || lowercased.contains("brainstorm review")
            || lowercased.contains("brainstorm cadence")
            || lowercased.contains("heartbeat automatically queued")
            || lowercased.contains("supervisor heartbeat queued") else {
            return nil
        }

        let labels = governedReviewLabels(for: lowercased)
        let metadata = governedReviewMetadata(for: lowercased)

        if lowercased.hasPrefix("open the project") {
            switch labels.action {
            case "救援审查":
                return "打开项目并优先处理这次救援审查。"
            case "脉冲审查":
                return "打开项目并查看这次脉冲审查为何被排队。"
            default:
                return "打开项目并查看这次治理审查为何被排队。"
            }
        }

        if lowercased.contains("safe point") && lowercased.contains("guidance") {
            return "等待 Supervisor 执行已排队的 review，并在 safe point 接收 guidance。"
        }

        if lowercased.hasPrefix("governance review:")
            || lowercased.hasPrefix("governed review:") {
            let headline = labels.headline == "治理脉冲" ? "治理脉冲" : labels.action
            return "已排队\(headline)"
        }

        if lowercased.contains("has queued")
            && (lowercased.contains("governance review") || lowercased.contains("governed review")) {
            let subjectPrefix = governedReviewSubjectPrefix(from: normalized)
            return "\(subjectPrefix)已排队\(labels.summary)\(governedReviewMetadataSuffix(metadata))"
        }

        if lowercased.contains("current project governance requires")
            || lowercased.contains("supervisor heartbeat queued")
            || lowercased.contains("heartbeat automatically queued")
            || (lowercased.contains("queued") && (metadata.runKind != nil || metadata.cause != nil)) {
            let metadataText = governedReviewMetadataText(metadata)
            if metadataText.isEmpty {
                return "依据：heartbeat 已自动排队\(labels.action)。"
            }
            return "依据：heartbeat 已按\(metadataText)自动排队\(labels.action)。"
        }

        return nil
    }

    private static func governedReviewLabels(
        for lowercased: String
    ) -> (summary: String, action: String, headline: String) {
        if lowercased.contains("rescue") {
            return ("救援审查", "救援审查", "救援审查")
        }
        if lowercased.contains("pulse") {
            return ("脉冲审查", "脉冲审查", "治理脉冲")
        }
        if lowercased.contains("strategic") || lowercased.contains("brainstorm") {
            return ("战略审查", "治理审查", "治理审查")
        }
        return ("治理审查", "治理审查", "治理审查")
    }

    private static func governedReviewMetadata(
        for lowercased: String
    ) -> (runKind: String?, cause: String?) {
        let runKind: String?
        if lowercased.contains("brainstorm") || lowercased.contains("no-progress") || lowercased.contains("no progress") {
            runKind = "无进展复盘"
        } else if lowercased.contains("event-driven") || lowercased.contains("event driven") {
            runKind = "事件触发"
        } else if lowercased.contains("pulse cadence") || lowercased.contains("periodic pulse") {
            runKind = "周期脉冲"
        } else if lowercased.contains("manual request") {
            runKind = "手动请求"
        } else {
            runKind = nil
        }

        let cause: String?
        if lowercased.contains("weak completion evidence") {
            cause = "完成声明证据偏弱"
        } else if lowercased.contains("weak blocker evidence") {
            cause = "blocker 解释偏弱"
        } else if lowercased.contains("long no progress") || lowercased.contains("no progress") {
            cause = "长时间无进展"
        } else if lowercased.contains("blocker detected") {
            cause = "检测到 blocker"
        } else if lowercased.contains("suspected drift") || lowercased.contains("drift") {
            cause = "疑似偏航"
        } else if lowercased.contains("degraded heartbeat quality") {
            cause = "heartbeat 质量下降"
        } else if lowercased.contains("pre-done") || lowercased.contains("done verification") {
            cause = "完成前复核"
        } else if lowercased.contains("pre-high-risk") || lowercased.contains("high risk") {
            cause = "高风险动作前复核"
        } else {
            cause = nil
        }

        return (runKind, cause)
    }

    private static func governedReviewMetadataText(
        _ metadata: (runKind: String?, cause: String?)
    ) -> String {
        [metadata.runKind, metadata.cause]
            .compactMap { value in
                let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }

    private static func governedReviewMetadataSuffix(
        _ metadata: (runKind: String?, cause: String?)
    ) -> String {
        let text = governedReviewMetadataText(metadata)
        return text.isEmpty ? "" : "（\(text)）"
    }

    private static func governedReviewSubjectPrefix(from normalized: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)^(?:project\s+)?(.+?)\s+has queued\s+(?:(?:strategic|rescue|pulse)\s+)?(?:governance|governed)\s+review\b"#
        ) else {
            return ""
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              match.numberOfRanges >= 2,
              let subjectRange = Range(match.range(at: 1), in: normalized) else {
            return ""
        }
        let subject = normalized[subjectRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "" : "\(subject)："
    }

    private static func isHeartbeatEnvelopeLine(_ normalized: String) -> Bool {
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let normalizedTitle = trimmed.replacingOccurrences(of: "：", with: "")
        if sectionTitles.contains(normalizedTitle) {
            return true
        }
        if trimmed.hasPrefix("🫀") {
            return true
        }

        let envelopePrefixes = [
            "原因：",
            "项目总数：",
            "变化：",
            "排队项目：",
            "待授权项目：",
            "待治理审查项目：",
            "待治理修复项目：",
            "配对续连项：",
            "语音修复项：",
            "lane 状态：",
            "泳道健康："
        ]
        return envelopePrefixes.contains { trimmed.hasPrefix($0) }
    }

    private static func isInternalNoiseLine(_ normalized: String) -> Bool {
        let lowercased = normalized.lowercased()
        let knownNoiseTokens = [
            "grant_pending",
            "lane=",
            "event_loop_tick",
            "dedupe",
            "callback=",
            "heartbeat_seq=",
            "route=",
            "router=",
            "status=",
            "reason="
        ]
        if knownNoiseTokens.contains(where: { lowercased.contains($0) }) {
            return true
        }

        return machineKeyValueMatchCount(in: normalized) >= 2
    }

    private static func machineKeyValueMatchCount(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b[a-z0-9_]+=[^\s]+\b"#
        ) else {
            return 0
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(
            in: text,
            options: [],
            range: range
        )
    }

    static func timeText(
        _ timestamp: Double,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private static func reasonText(for rawReason: String) -> String {
        if let routeText = XTRouteTruthPresentation.userVisibleReasonText(rawReason) {
            return routeText
        }
        if let voiceText = SupervisorVoiceReasonPresentation.displayText(rawReason) {
            return voiceText
        }

        switch normalizedReasonCode(rawReason) {
        case "timer", "periodic_check":
            return "定时巡检"
        case "historical_project_boundary_repair":
            return "历史项目修复"
        case "project_created":
            return "新项目"
        case "project_updated":
            return "项目更新"
        case "project_removed":
            return "项目移除"
        case "incident_handled":
            return "事件处理"
        case "skill_doctor_truth":
            return "技能 Doctor Truth"
        case "lane_health_changed":
            return "泳道健康变化"
        case "guidance_ack_follow_up":
            return "指导跟进"
        case "event":
            return "事件触发"
        default:
            return normalizedReasonCode(rawReason)
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func normalizedReasonCode(_ rawReason: String) -> String {
        rawReason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func mergedEntries(
        entries: [SupervisorManager.HeartbeatFeedEntry],
        historicalProjectBoundaryRepairStatusLine: String,
        doctorPresentation: SupervisorDoctorBoardPresentation?,
        now: Date
    ) -> [SupervisorManager.HeartbeatFeedEntry] {
        let repairEntry = historicalProjectBoundaryRepairHeartbeatEntry(
            statusLine: historicalProjectBoundaryRepairStatusLine,
            now: now
        )
        let skillDoctorTruthEntry = skillDoctorTruthHeartbeatEntry(
            doctorPresentation: doctorPresentation,
            now: now
        )
        let syntheticEntries = [repairEntry, skillDoctorTruthEntry].compactMap { $0 }

        guard !syntheticEntries.isEmpty else {
            return entries
        }

        let syntheticIDs = Set(syntheticEntries.map(\.id))
        return syntheticEntries + entries.filter { !syntheticIDs.contains($0.id) }
    }

    private static func skillDoctorTruthHeartbeatEntry(
        doctorPresentation: SupervisorDoctorBoardPresentation?,
        now: Date
    ) -> SupervisorManager.HeartbeatFeedEntry? {
        guard let doctorPresentation,
              let statusLine = nonEmpty(doctorPresentation.skillDoctorTruthStatusLine) else {
            return nil
        }

        let tone = doctorPresentation.skillDoctorTruthTone
        guard tone == .danger || tone == .warning else {
            return nil
        }

        let blocked = tone == .danger
        let detailLine = nonEmpty(doctorPresentation.skillDoctorTruthDetailLine)
        let nextStep = blocked
            ? "打开 Supervisor 体检，优先处理技能 doctor truth 里的阻塞项，再继续派活。"
            : "打开 Supervisor 体检，优先补齐技能 doctor truth 里的 Hub grant / 本地确认项。"
        let actionURL = XTDeepLinkURLBuilder.supervisorURL()?.absoluteString

        return SupervisorManager.HeartbeatFeedEntry(
            id: blocked ? "skill_doctor_truth_blocked" : "skill_doctor_truth_pending",
            createdAt: now.timeIntervalSince1970,
            reason: "skill_doctor_truth",
            projectCount: 0,
            changed: true,
            content: skillDoctorTruthHeartbeatContent(
                createdAt: now.timeIntervalSince1970,
                statusLine: statusLine,
                detailLine: detailLine,
                nextStep: nextStep,
                actionURL: actionURL,
                blocked: blocked
            ),
            focusActionURL: actionURL
        )
    }

    private static func skillDoctorTruthHeartbeatContent(
        createdAt: Double,
        statusLine: String,
        detailLine: String?,
        nextStep: String,
        actionURL: String?,
        blocked: Bool
    ) -> String {
        let actionSuffix = actionURL.map { "（打开：\($0)）" } ?? ""
        let boardLine = blocked
            ? "技能 Doctor Truth：⛔️ \(statusLine)"
            : "技能 Doctor Truth：⚠️ \(statusLine)"
        let detailSectionLines = [
            "• \(statusLine)\(actionSuffix)",
            detailLine.map { "• \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let timeText = timeText(
            createdAt,
            timeZone: .current,
            locale: .current
        )

        return """
🫀 Supervisor Heartbeat (\(timeText))
原因：skill_doctor_truth
项目总数：0
变化：检测到技能 doctor truth 仍有待处理项
排队项目：0
待授权项目：0
待治理审查项目：0
待治理修复项目：0

主动推进：
（本轮无需介入）

重点看板：
• \(boardLine)

排队态势：
（无）

权限申请：
（无）

Recovery 跟进：
（无）

治理审查：
（无）

治理修复：
（无）

项目创建：
（无）

语音就绪：
（无）

Hub 负载：
（无）

技能 Doctor Truth：
\(detailSectionLines)

Coder 下一步建议：
1. \(nextStep)\(actionSuffix)
"""
    }

    private static func historicalProjectBoundaryRepairHeartbeatEntry(
        statusLine: String,
        now: Date
    ) -> SupervisorManager.HeartbeatFeedEntry? {
        let fields = scalarFields(statusLine)
        let outcome = normalizedScalar(
            fields["historical_project_boundary_repair"] ?? fields["status"] ?? ""
        ).lowercased()
        guard outcome == "partial" || outcome == "failed" else {
            return nil
        }

        let reason = normalizedScalar(fields["reason"] ?? "")
        let scannedCount = Int(normalizedScalar(fields["scanned"] ?? "")) ?? 0
        let repairedConfigCount = Int(normalizedScalar(fields["repaired_config"] ?? "")) ?? 0
        let repairedMemoryCount = Int(normalizedScalar(fields["repaired_memory"] ?? "")) ?? 0
        let failedCount = Int(normalizedScalar(fields["failed"] ?? "")) ?? 0
        let repairedCount = repairedConfigCount + repairedMemoryCount
        let reasonLabel = historicalProjectBoundaryRepairReasonLabel(reason)

        let boardLine: String
        let governanceLine: String
        if failedCount > 0 {
            let lead = reasonLabel.isEmpty
                ? "历史项目边界修复仍未完成"
                : "\(reasonLabel)时发现历史项目边界仍未补齐"
            boardLine = "\(lead)；仍有 \(failedCount) 个项目缺失 config.json 或 project memory。"
            governanceLine = boardLine
        } else if repairedCount > 0 {
            let lead = reasonLabel.isEmpty
                ? "历史项目边界已补齐一部分"
                : "\(reasonLabel)时补齐了一部分历史项目边界"
            boardLine = "\(lead)；已补齐 \(repairedCount) 处边界，但仍建议立刻复核。"
            governanceLine = boardLine
        } else if scannedCount > 0 {
            boardLine = "已扫描 \(scannedCount) 个历史项目，但边界修复结果仍不完整。"
            governanceLine = boardLine
        } else {
            boardLine = "历史项目边界修复状态异常，建议立刻重跑。"
            governanceLine = boardLine
        }

        let detail = [
            reasonLabel.isEmpty ? "" : "原因=\(reasonLabel)",
            scannedCount > 0 ? "扫描=\(scannedCount)" : "",
            repairedConfigCount > 0 ? "补齐 config=\(repairedConfigCount)" : "",
            repairedMemoryCount > 0 ? "补齐 memory=\(repairedMemoryCount)" : "",
            failedCount > 0 ? "失败=\(failedCount)" : ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        let actionURL = XTDeepLinkURLBuilder.settingsURL(
            sectionId: "diagnostics",
            title: "历史项目修复",
            detail: detail.isEmpty
                ? "打开诊断并重跑历史项目边界修复。"
                : detail,
            refreshAction: .repairHistoricalProjectBoundaries,
            refreshReason: "supervisor_heartbeat_historical_project_boundary_repair"
        )?.absoluteString
        let nextStep = "打开 XT Diagnostics 并重跑历史项目修复，确认目标项目重新生成 config.json 与 project memory。"

        return SupervisorManager.HeartbeatFeedEntry(
            id: "historical_project_boundary_repair_\(outcome)",
            createdAt: now.timeIntervalSince1970,
            reason: "historical_project_boundary_repair",
            projectCount: max(scannedCount, failedCount),
            changed: true,
            content: historicalProjectBoundaryRepairHeartbeatContent(
                createdAt: now.timeIntervalSince1970,
                headlineLine: boardLine,
                governanceLine: governanceLine,
                nextStep: nextStep,
                actionURL: actionURL,
                failedCount: failedCount
            ),
            focusActionURL: actionURL
        )
    }

    private static func historicalProjectBoundaryRepairHeartbeatContent(
        createdAt: Double,
        headlineLine: String,
        governanceLine: String,
        nextStep: String,
        actionURL: String?,
        failedCount: Int
    ) -> String {
        let actionSuffix = actionURL.map { "（打开：\($0)）" } ?? ""
        let governanceCount = max(1, failedCount)
        let timeText = timeText(
            createdAt,
            timeZone: .current,
            locale: .current
        )

        return """
🫀 Supervisor Heartbeat (\(timeText))
原因：historical_project_boundary_repair
项目总数：0
变化：检测到历史项目边界修复仍未完成
排队项目：0
待授权项目：0
待治理修复项目：\(governanceCount)

主动推进：
（本轮无需介入）

重点看板：
• 历史项目边界：⚠️ \(headlineLine)

排队态势：
（无）

权限申请：
（无）

治理修复：
• \(governanceLine)\(actionSuffix)

Coder 下一步建议：
1. \(nextStep)\(actionSuffix)
"""
    }

    private static func historicalProjectBoundaryRepairReasonLabel(_ raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "load_registry":
            return "启动时加载项目注册表"
        case "settings_diagnostics_manual":
            return "诊断页手动重跑"
        case "supervisor_historical_project_boundary_repair":
            return "Supervisor 触发重跑"
        case "supervisor_doctor_historical_project_boundary_repair":
            return "Supervisor Doctor 建议重跑"
        case "supervisor_heartbeat_historical_project_boundary_repair":
            return "Supervisor Heartbeat 建议重跑"
        case "test_manual":
            return "测试手动触发"
        default:
            return normalizedScalar(raw)
        }
    }

    private static func scalarFields(_ raw: String) -> [String: String] {
        normalizedScalar(raw)
            .split(separator: " ")
            .reduce(into: [String: String]()) { result, token in
                let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return }
                result[key] = value
            }
    }

    private static func normalizedScalar(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
