import Foundation

struct SupervisorPersonalAssistantCockpitPresentation: Equatable {
    struct Badge: Identifiable, Equatable {
        var id: String
        var text: String
        var tone: Tone
    }

    struct QuickAction: Identifiable, Equatable {
        var id: String
        var title: String
        var prompt: String
    }

    enum Tone: String, Equatable {
        case neutral
        case accent
        case warning
        case positive
    }

    var activePersonaName: String
    var statusLine: String
    var badges: [Badge]
    var highlights: [String]
    var quickActions: [QuickAction]
}

enum SupervisorPersonalAssistantCockpitPresentationBuilder {
    static func build(
        persona: SupervisorPersonaSlot,
        personalMemory: SupervisorPersonalMemorySnapshot,
        reviewSnapshot: SupervisorPersonalReviewNoteSnapshot,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> SupervisorPersonalAssistantCockpitPresentation {
        let memorySummary = SupervisorPersonalMemorySummaryBuilder.build(
            snapshot: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: locale
        )
        let followUpLedger = SupervisorFollowUpLedgerBuilder.build(
            from: personalMemory,
            now: now
        )
        let followUpSummary = SupervisorFollowUpLedgerBuilder.summary(
            from: followUpLedger,
            timeZone: timeZone,
            locale: locale
        )
        let reviewPreview = SupervisorPersonalReviewNoteBuilder.preview(
            snapshot: reviewSnapshot,
            policy: persona.personalPolicy,
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: locale,
            calendar: calendar
        )

        let statusParts = [
            reviewPreview.dueCount > 0 ? "\(reviewPreview.dueCount) 条复盘待处理" : nil,
            followUpSummary.overdueCount > 0 ? "\(followUpSummary.overdueCount) 条跟进已逾期" : nil,
            followUpSummary.peopleWaitingCount > 0 ? "\(followUpSummary.peopleWaitingCount) 位在等你" : nil,
            memorySummary.activeCommitmentCount > 0 ? "\(memorySummary.activeCommitmentCount) 项承诺未收口" : nil
        ].compactMap { $0 }

        let badges = buildBadges(
            persona: persona,
            memorySummary: memorySummary,
            followUpSummary: followUpSummary,
            reviewPreview: reviewPreview
        )

        let highlights = buildHighlights(
            followUpSummary: followUpSummary,
            reviewPreview: reviewPreview,
            memorySummary: memorySummary
        )

        return SupervisorPersonalAssistantCockpitPresentation(
            activePersonaName: persona.displayName,
            statusLine: statusParts.isEmpty
                ? "个人助理上下文已就绪，当前没有明显滑落的复盘或待跟进事项。"
                : statusParts.joined(separator: " · "),
            badges: badges,
            highlights: highlights,
            quickActions: buildQuickActions(reviewPreview: reviewPreview, followUpSummary: followUpSummary)
        )
    }

    private static func buildBadges(
        persona: SupervisorPersonaSlot,
        memorySummary: SupervisorPersonalMemorySummary,
        followUpSummary: SupervisorFollowUpLedgerSummary,
        reviewPreview: SupervisorPersonalReviewPreview
    ) -> [SupervisorPersonalAssistantCockpitPresentation.Badge] {
        var badges: [SupervisorPersonalAssistantCockpitPresentation.Badge] = [
            .init(id: "persona", text: persona.displayName, tone: .accent)
        ]
        if reviewPreview.dueCount > 0 {
            badges.append(
                .init(
                    id: "reviews_due",
                    text: reviewPreview.overdueCount > 0
                        ? "\(reviewPreview.dueCount) 条复盘待处理"
                        : "\(reviewPreview.dueCount) 条复盘可开始",
                    tone: reviewPreview.overdueCount > 0 ? .warning : .accent
                )
            )
        } else {
            badges.append(.init(id: "reviews_clear", text: "复盘清零", tone: .positive))
        }
        if followUpSummary.openCount > 0 {
            badges.append(
                .init(
                    id: "followups",
                    text: "\(followUpSummary.openCount) 条待跟进",
                    tone: followUpSummary.overdueCount > 0 ? .warning : .neutral
                )
            )
        }
        if followUpSummary.peopleWaitingCount > 0 {
            badges.append(
                .init(
                    id: "people_waiting",
                    text: "\(followUpSummary.peopleWaitingCount) 位在等你",
                    tone: .neutral
                )
            )
        }
        if memorySummary.activeCommitmentCount > 0 {
            badges.append(
                .init(
                    id: "commitments",
                    text: "\(memorySummary.activeCommitmentCount) 项承诺",
                    tone: .neutral
                )
            )
        }
        return badges
    }

    private static func buildHighlights(
        followUpSummary: SupervisorFollowUpLedgerSummary,
        reviewPreview: SupervisorPersonalReviewPreview,
        memorySummary: SupervisorPersonalMemorySummary
    ) -> [String] {
        var lines: [String] = []
        if let dueReview = reviewPreview.dueNotes.first {
            lines.append("\(dueReview.reviewType.displayName): \(dueReview.summary)")
        }
        if let firstFollowUp = followUpSummary.highlightedItems.first {
            lines.append(firstFollowUp)
        }
        if let firstMemoryLine = memorySummary.highlightedItems.first {
            lines.append(firstMemoryLine)
        }
        if lines.isEmpty {
            lines.append("当前没有逾期的个人复盘或待跟进事项。")
        }
        return Array(lines.prefix(3))
    }

    private static func buildQuickActions(
        reviewPreview: SupervisorPersonalReviewPreview,
        followUpSummary: SupervisorFollowUpLedgerSummary
    ) -> [SupervisorPersonalAssistantCockpitPresentation.QuickAction] {
        var actions: [SupervisorPersonalAssistantCockpitPresentation.QuickAction] = []
        if let dueReview = reviewPreview.dueNotes.first {
            actions.append(
                .init(
                    id: "due_review",
                    title: dueReview.reviewType.displayName,
                    prompt: "Use my current personal review context and give me a \(dueReview.reviewType.displayName.lowercased()) with the most important actions first."
                )
            )
        } else {
            actions.append(
                .init(
                    id: "today_brief",
                    title: "今日简报",
                    prompt: "结合我当前的个人记忆、待跟进队列和复盘上下文，给我一版今天的个人事务优先级摘要。"
                )
            )
        }

        if followUpSummary.peopleWaitingCount > 0 {
            actions.append(
                .init(
                    id: "people_waiting",
                    title: "谁在等你",
                    prompt: "现在有哪些人在等我，我最该先回复或收口哪一项？"
                )
            )
        }

        actions.append(
            .init(
                id: "personal_admin",
                title: "事务扫尾",
                prompt: "给我一版简洁的个人事务扫尾：哪些在滑落、哪些快到期、我下一步最该做哪一件。"
            )
        )

        return Array(actions.prefix(3))
    }
}
