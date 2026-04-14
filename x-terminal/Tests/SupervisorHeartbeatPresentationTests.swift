import Foundation
import Testing
@testable import XTerminal

struct SupervisorHeartbeatPresentationTests {

    @Test
    func mapBuildsEmptyStatePresentation() {
        let presentation = SupervisorHeartbeatPresentation.map(entries: [])

        #expect(presentation.title == "Supervisor 心跳")
        #expect(presentation.iconName == "heart.fill")
        #expect(presentation.iconTone == .danger)
        #expect(presentation.overview == nil)
        #expect(presentation.isEmpty)
        #expect(!presentation.emptyStateText.isEmpty)
    }

    @Test
    func mapLimitsEntriesAndPreservesFocusAction() {
        let entries = [
            heartbeat(id: "hb-1", createdAt: 1_000, changed: true, focusActionURL: "x-terminal://focus/1"),
            heartbeat(id: "hb-2", createdAt: 2_000, changed: false, focusActionURL: "  "),
            heartbeat(id: "hb-3", createdAt: 3_000, changed: true, focusActionURL: nil)
        ]

        let presentation = SupervisorHeartbeatPresentation.map(
            entries: entries,
            limit: 2,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_GB_POSIX")
        )

        #expect(!presentation.isEmpty)
        #expect(presentation.entries.map(\.id) == ["hb-1", "hb-2"])
        #expect(presentation.entries[0].changeText == "有变化")
        #expect(presentation.entries[0].changeTone == .success)
        #expect(presentation.entries[0].reasonText == "定时巡检")
        #expect(presentation.entries[0].priority == .stable)
        #expect(presentation.entries[0].priorityText == "最近汇报")
        #expect(presentation.entries[0].headlineText == "状态稳定")
        #expect(presentation.entries[0].focusAction?.label == "打开相关视图")
        #expect(presentation.entries[0].focusAction?.style == .standard)
        #expect(presentation.entries[1].changeText == "无重大变化")
        #expect(presentation.entries[1].changeTone == .neutral)
        #expect(presentation.entries[1].focusAction == nil)
        #expect(presentation.overview?.headlineText == "状态稳定")
        #expect(presentation.overview?.detailText == "summary hb-1")
        #expect(presentation.overview?.metadataText == "定时巡检 · 00:16 · 另有 1 条更新")
        #expect(!presentation.entries[0].timeText.isEmpty)
    }

    @Test
    func mapHighlightsGovernanceRepairHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governance",
                pane: .chat,
                governanceDestination: .executionTier
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-governance",
            createdAt: 1_000,
            changed: true,
            content: governanceHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .warning)
        #expect(mapped.headlineText == "治理修复")
        #expect(mapped.headlineTone == .warning)
        #expect(mapped.priority == .immediate)
        #expect(mapped.priorityText == "立即处理")
        #expect(mapped.detailLines.first?.contains("A-Tier") == true)
        #expect(mapped.focusAction?.label == "打开治理设置")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.priority == .immediate)
        #expect(overview.headlineText == "治理修复")
        #expect(overview.detailText.contains("A-Tier"))
        #expect(overview.focusAction?.label == "打开治理设置")
    }

    @Test
    func mapHighlightsQueuedGovernedReviewHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governed-review",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-governed-review",
            createdAt: 1_000,
            changed: true,
            content: governedReviewHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .accent)
        #expect(mapped.headlineText == "治理审查已排队")
        #expect(mapped.headlineTone == .accent)
        #expect(mapped.priority == .attention)
        #expect(mapped.priorityText == "优先关注")
        #expect(mapped.detailLines.first?.contains("战略审查") == true)
        #expect(mapped.detailLines.first?.contains("无进展复盘") == true)
        #expect(mapped.detailLines.contains(where: {
            $0.contains("记忆供给") &&
            $0.contains("latest coder usage") &&
            $0.contains("heartbeat digest 已在 Project AI working set 中")
        }))
        #expect(mapped.digest.whyImportantText.contains("latest coder usage"))
        #expect(mapped.digest.systemNextStepText.contains("safe point"))
        #expect(mapped.digest.systemNextStepText.contains("不再额外重复灌入同一份 heartbeat digest"))
        #expect(mapped.focusAction?.label == "打开项目")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.priority == .attention)
        #expect(overview.headlineText == "治理审查已排队")
        #expect(overview.detailText.contains("长时间无进展"))
    }

    @Test
    func mapHighlightsProjectCreationHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.supervisorURL(
                focusTarget: .projectCreationBoard
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-project-creation",
            createdAt: 1_000,
            changed: true,
            content: projectCreationHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .accent)
        #expect(mapped.headlineText == "项目创建差一句触发")
        #expect(mapped.headlineTone == .accent)
        #expect(mapped.priority == .attention)
        #expect(mapped.priorityText == "优先关注")
        #expect(mapped.detailLines.first == "项目创建还差一句触发。")
        #expect(mapped.contentText == "项目创建还差一句触发。")
        #expect(mapped.focusAction?.label == "打开项目创建板")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.headlineText == "项目创建差一句触发")
        #expect(overview.detailText == "项目创建还差一句触发。")
    }

    @Test
    func mapHighlightsProjectMemoryAdvisoryHeartbeatAsWatch() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-memory",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-project-memory",
            createdAt: 1_000,
            changed: true,
            content: projectMemoryAdvisoryHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .success)
        #expect(mapped.headlineText == "Project AI 记忆需补强")
        #expect(mapped.headlineTone == .accent)
        #expect(mapped.priority == .watch)
        #expect(mapped.priorityText == "继续观察")
        #expect(mapped.detailLines.count == 3)
        #expect(mapped.detailLines[0].contains("Project AI 记忆装配还需要补强"))
        #expect(mapped.detailLines[1].contains("recent coder usage"))
        #expect(mapped.detailLines[2].contains("machine-readable memory assembly truth"))
        #expect(mapped.digest.visibility == .userFacing)
        #expect(mapped.digest.whatChangedText.contains("Project AI 记忆装配还需要补强"))
        #expect(mapped.digest.whyImportantText.contains("recent coder usage"))
        #expect(mapped.digest.systemNextStepText.contains("heartbeat 节奏"))
        #expect(overview.headlineText == "Project AI 记忆需补强")
        #expect(overview.detailText.contains("Project AI 记忆装配还需要补强"))
        #expect(mapped.focusAction?.label == "打开项目")
        #expect(mapped.focusAction?.style == .standard)
    }

    @Test
    func mapHumanizesEnglishGovernedReviewDigest() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governed-review-en",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-governed-review-en",
            createdAt: 1_000,
            changed: true,
            content: governedReviewHeartbeatContentRawEnglish(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "治理审查已排队")
        #expect(mapped.detailLines.first?.contains("战略审查") == true)
        #expect(mapped.detailLines.first?.contains("无进展复盘") == true)
        #expect(mapped.detailLines.first?.contains("长时间无进展") == true)
        #expect(!mapped.detailLines.joined(separator: "\n").contains("queued strategic governance review"))
        #expect(mapped.contentText.contains("已排队战略审查"))
        #expect(mapped.contentText.contains("无进展复盘"))
        #expect(!mapped.contentText.contains("Open the project"))
        #expect(overview.detailText.contains("长时间无进展"))
    }

    @Test
    func mapEscalatesQueuedRescueReviewHeartbeatToImmediate() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-rescue-review",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-rescue-review",
            createdAt: 1_000,
            changed: true,
            content: rescueGovernedReviewHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .warning)
        #expect(mapped.headlineText == "救援审查已排队")
        #expect(mapped.headlineTone == .warning)
        #expect(mapped.priority == .immediate)
        #expect(mapped.priorityText == "立即处理")
        #expect(mapped.detailLines.first?.contains("救援审查") == true)
        #expect(mapped.detailLines.first?.contains("完成声明证据偏弱") == true)
        #expect(mapped.focusAction?.label == "打开项目")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.priority == .immediate)
        #expect(overview.headlineText == "救援审查已排队")
        #expect(overview.detailText.contains("完成声明证据偏弱"))
    }

    @Test
    func mapHighlightsRouteDiagnoseHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-route",
                pane: .chat,
                focusTarget: .routeDiagnose
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-route",
            createdAt: 1_000,
            changed: true,
            content: routeHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(presentation.iconTone == .accent)
        #expect(mapped.headlineText == "模型路由诊断")
        #expect(mapped.headlineTone == .accent)
        #expect(mapped.priority == .attention)
        #expect(mapped.priorityText == "优先关注")
        #expect(mapped.detailLines.first?.contains("模型路由") == true)
        #expect(mapped.focusAction?.label == "打开路由诊断")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.priority == .attention)
        #expect(overview.detailText.contains("模型路由"))
    }

    @Test
    func mapSortsActionableHeartbeatAheadOfStableUpdates() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governance",
                pane: .chat,
                governanceDestination: .executionTier
            )?.absoluteString
        )
        let entries = [
            heartbeat(
                id: "hb-stable",
                createdAt: 2_000,
                changed: false,
                content: "summary hb-stable",
                focusActionURL: nil
            ),
            heartbeat(
                id: "hb-governance",
                createdAt: 1_000,
                changed: true,
                content: governanceHeartbeatContent(),
                focusActionURL: focusActionURL
            )
        ]

        let presentation = SupervisorHeartbeatPresentation.map(entries: entries)

        #expect(presentation.entries.map(\.id) == ["hb-governance", "hb-stable"])
        #expect(presentation.entries.first?.priority == .immediate)
        #expect(presentation.entries.last?.priority == .stable)
        #expect(presentation.overview?.headlineText == "治理修复")
        #expect(presentation.overview?.metadataText.contains("另有 1 条更新") == true)
    }

    @Test
    func highestPriorityPrefersMostActionableHeartbeat() throws {
        let governanceActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governance",
                pane: .chat,
                governanceDestination: .executionTier
            )?.absoluteString
        )
        let routeActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-route",
                pane: .chat,
                focusTarget: .routeDiagnose
            )?.absoluteString
        )

        let entries = [
            heartbeat(
                id: "hb-stable",
                createdAt: 3_000,
                changed: false,
                content: "summary hb-stable",
                focusActionURL: nil
            ),
            heartbeat(
                id: "hb-route",
                createdAt: 2_000,
                changed: true,
                content: routeHeartbeatContent(),
                focusActionURL: routeActionURL
            ),
            heartbeat(
                id: "hb-governance",
                createdAt: 1_000,
                changed: true,
                content: governanceHeartbeatContent(),
                focusActionURL: governanceActionURL
            )
        ]

        #expect(
            SupervisorHeartbeatPresentation.highestPriority(entries: entries) == .immediate
        )
    }

    @Test
    func mapHighlightsVoiceReadinessRepairHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "troubleshoot",
                title: "Voice readiness",
                detail: "Repair bridge before verify"
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-voice",
            createdAt: 1_000,
            changed: true,
            content: voiceHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "语音链路待修复")
        #expect(mapped.priority == .attention)
        #expect(mapped.detailLines.first?.contains("fail-closed on bridge / tool readiness") == true)
        #expect(mapped.focusAction?.label == "打开 Hub Recovery")
        #expect(overview.headlineText == "语音链路待修复")
        #expect(overview.detailText.contains("bridge / tool readiness"))
    }

    @Test
    func mapHighlightsPairingContinuityHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "pair_progress",
                title: "Pairing continuity",
                detail: "Verify formal remote route"
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-pairing",
            createdAt: 1_000,
            changed: true,
            content: pairingHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "配对续连仍需确认")
        #expect(mapped.priority == .watch)
        #expect(mapped.detailLines.first?.contains("正式异网入口") == true)
        #expect(mapped.focusAction?.label == "打开 Hub 配对")
        #expect(overview.headlineText == "配对续连仍需确认")
        #expect(overview.detailText.contains("正式异网入口"))
    }

    @Test
    func mapHighlightsHubLoadHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "troubleshoot",
                title: "Hub 负载偏高",
                detail: "Inspect queue and thermal state"
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-hub-load",
            createdAt: 1_000,
            changed: true,
            content: hubLoadHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "Hub 负载偏高")
        #expect(mapped.priority == .attention)
        #expect(mapped.detailLines.first?.contains("Hub 主机负载偏高") == true)
        #expect(mapped.focusAction?.label == "打开 Hub 诊断")
        #expect(overview.headlineText == "Hub 负载偏高")
        #expect(overview.detailText.contains("Hub 主机负载偏高"))
    }

    @Test
    func mapUsesHubRecoveryActionLabelForRouteRepairFollowUp() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "troubleshoot",
                title: "Route repair",
                detail: "Check Hub Recovery"
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-route-hub-recovery",
            createdAt: 1_000,
            changed: true,
            content: routeHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)

        #expect(mapped.headlineText == "模型路由诊断")
        #expect(mapped.focusAction?.label == "打开 Hub Recovery")
        #expect(mapped.focusAction?.style == .prominent)
    }

    @Test
    func mapLocalizesGuidanceFollowUpReason() {
        let entry = heartbeat(
            id: "hb-guidance",
            createdAt: 1_000,
            changed: true,
            content: "summary hb-guidance",
            focusActionURL: nil,
            reason: "guidance_ack_follow_up"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])

        #expect(presentation.entries.first?.reasonText == "指导跟进")
        #expect(presentation.overview?.metadataText.contains("指导跟进") == true)
    }

    @Test
    func mapHumanizesRouteReasonInMetadata() {
        let entry = heartbeat(
            id: "hb-route-reason",
            createdAt: 1_000,
            changed: true,
            content: "summary hb-route-reason",
            focusActionURL: nil,
            reason: "deny_code=policy_remote_denied"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])

        #expect(
            presentation.entries.first?.reasonText == "当前策略不允许远端执行（policy_remote_denied）"
        )
        #expect(
            presentation.overview?.metadataText.contains("当前策略不允许远端执行（policy_remote_denied）") == true
        )
    }

    @Test
    func mapHumanizesVoiceReasonInMetadata() {
        let entry = heartbeat(
            id: "hb-voice-reason",
            createdAt: 1_000,
            changed: true,
            content: "summary hb-voice-reason",
            focusActionURL: nil,
            reason: "system_speech_authorization_denied"
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])

        #expect(
            presentation.entries.first?.reasonText == "系统语音识别权限已被拒绝（system_speech_authorization_denied）"
        )
        #expect(
            presentation.overview?.metadataText.contains("系统语音识别权限已被拒绝（system_speech_authorization_denied）") == true
        )
    }

    @Test
    func mapSuppressesInternalNoiseAndKeepsUserFacingAuthorizationDigest() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-auth-digest",
                pane: .chat,
                focusTarget: .grant
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-auth-digest",
            createdAt: 1_000,
            changed: true,
            content: authorizationNoiseHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "授权待处理")
        #expect(mapped.contentText == "需要你批准 repo 写权限后，系统才会继续推进。")
        #expect(!mapped.contentText.contains("grant_pending"))
        #expect(!mapped.contentText.contains("lane="))
        #expect(!mapped.contentText.contains("event_loop_tick"))
        #expect(overview.detailText == "需要你批准 repo 写权限后，系统才会继续推进。")
    }

    @Test
    func mapHighlightsGrantRecoveryFollowUpHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-recovery-grant",
                pane: .chat,
                focusTarget: .grant
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-recovery-grant",
            createdAt: 1_000,
            changed: true,
            content: grantRecoveryHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "Recovery 跟进")
        #expect(mapped.priority == .immediate)
        #expect(mapped.headlineTone == .warning)
        #expect(mapped.detailLines.first?.contains("grant / 授权跟进") == true)
        #expect(mapped.detailLines.contains(where: { $0.contains("为什么先跟进") }))
        #expect(mapped.focusAction?.label == "打开授权处理")
        #expect(mapped.digest.whatChangedText.contains("grant / 授权跟进"))
        #expect(mapped.digest.whyImportantText.contains("grant / 授权跟进"))
        #expect(mapped.digest.systemNextStepText.contains("grant 跟进"))
        #expect(overview.headlineText == "Recovery 跟进")
        #expect(overview.detailText.contains("grant / 授权跟进"))
        #expect(!overview.detailText.contains("为什么先跟进"))
    }

    @Test
    func mapHighlightsReplayRecoveryFollowUpHeartbeat() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-recovery-replay",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-recovery-replay",
            createdAt: 1_000,
            changed: true,
            content: replayRecoveryHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "Recovery 跟进")
        #expect(mapped.priority == .attention)
        #expect(mapped.headlineTone == .accent)
        #expect(mapped.detailLines.first?.contains("重放 follow-up / 续跑链") == true)
        #expect(mapped.detailLines.contains(where: { $0.contains("为什么先跟进") }))
        #expect(mapped.focusAction?.label == "打开项目")
        #expect(mapped.digest.whatChangedText.contains("重放 follow-up / 续跑链"))
        #expect(mapped.digest.whyImportantText.contains("续跑链"))
        #expect(mapped.digest.systemNextStepText.contains("重放挂起的 follow-up"))
        #expect(overview.headlineText == "Recovery 跟进")
        #expect(overview.detailText.contains("重放 follow-up / 续跑链"))
        #expect(!overview.detailText.contains("为什么先跟进"))
    }

    @Test
    func mapFallsBackToHeadlineWhenFreeformHeartbeatContainsOnlyInternalNoise() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-auth-noise-only",
                pane: .chat,
                focusTarget: .grant
            )?.absoluteString
        )
        let entry = heartbeat(
            id: "hb-auth-noise-only",
            createdAt: 1_000,
            changed: true,
            content: authorizationNoiseOnlyHeartbeatContent(),
            focusActionURL: focusActionURL
        )

        let presentation = SupervisorHeartbeatPresentation.map(entries: [entry])
        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.headlineText == "授权待处理")
        #expect(mapped.contentText == "授权待处理")
        #expect(!mapped.contentText.contains("grant_pending"))
        #expect(!mapped.contentText.contains("lane="))
        #expect(overview.detailText == "授权待处理")
    }

    @Test
    func mapInjectsHistoricalProjectBoundaryRepairHeartbeatWhenRepairNeedsAttention() throws {
        let presentation = SupervisorHeartbeatPresentation.map(
            entries: [],
            historicalProjectBoundaryRepairStatusLine: "historical_project_boundary_repair=partial reason=load_registry scanned=4 repaired_config=1 repaired_memory=2 failed=1",
            now: Date(timeIntervalSince1970: 1_000)
        )

        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(!presentation.isEmpty)
        #expect(mapped.id == "historical_project_boundary_repair_partial")
        #expect(mapped.reasonText == "历史项目修复")
        #expect(mapped.priority == .immediate)
        #expect(mapped.headlineText == "治理修复")
        #expect(mapped.detailLines.first?.contains("启动时加载项目注册表") == true)
        #expect(mapped.detailLines.first?.contains("仍有 1 个项目") == true)
        #expect(mapped.focusAction?.label == "打开 XT Diagnostics")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(overview.priority == .immediate)
        #expect(overview.detailText.contains("启动时加载项目注册表"))
    }

    @Test
    func highestPriorityIncludesHistoricalProjectBoundaryRepairSignal() {
        let entries = [
            heartbeat(
                id: "hb-stable",
                createdAt: 3_000,
                changed: false,
                content: "summary hb-stable",
                focusActionURL: nil
            )
        ]

        #expect(
            SupervisorHeartbeatPresentation.highestPriority(
                entries: entries,
                historicalProjectBoundaryRepairStatusLine: "historical_project_boundary_repair=failed reason=load_registry scanned=2 repaired_config=0 repaired_memory=0 failed=2",
                now: Date(timeIntervalSince1970: 2_000)
            ) == .immediate
        )
    }

    @Test
    func mapInjectsBlockedSkillDoctorTruthHeartbeat() throws {
        let presentation = SupervisorHeartbeatPresentation.map(
            entries: [],
            doctorPresentation: doctorPresentation(
                skillDoctorTruthStatusLine: "技能 doctor truth：2 个技能当前不可运行。",
                skillDoctorTruthTone: .danger,
                skillDoctorTruthDetailLine: "当前可直接运行：1 个；当前阻塞：2 个（shell.exec, browser.open）；技能计数：3 个。"
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.id == "skill_doctor_truth_blocked")
        #expect(mapped.reasonText == "技能 Doctor Truth")
        #expect(mapped.priority == .attention)
        #expect(mapped.headlineText == "技能能力阻塞")
        #expect(mapped.headlineTone == .danger)
        #expect(mapped.detailLines.first == "技能 doctor truth：2 个技能当前不可运行。")
        #expect(mapped.detailLines.contains(where: { $0.contains("当前阻塞：2 个") }))
        #expect(mapped.focusAction?.label == "打开 Supervisor")
        #expect(mapped.focusAction?.style == .prominent)
        #expect(mapped.digest.whatChangedText == "技能 doctor truth：2 个技能当前不可运行。")
        #expect(mapped.digest.whyImportantText.contains("typed capability / readiness"))
        #expect(mapped.digest.systemNextStepText.contains("处理技能 doctor truth 里的阻塞项"))
        #expect(overview.headlineText == "技能能力阻塞")
        #expect(overview.detailText == "技能 doctor truth：2 个技能当前不可运行。")
    }

    @Test
    func mapInjectsPendingSkillDoctorTruthHeartbeat() throws {
        let presentation = SupervisorHeartbeatPresentation.map(
            entries: [],
            doctorPresentation: doctorPresentation(
                skillDoctorTruthStatusLine: "技能 doctor truth：1 个待 Hub grant，2 个待本地确认。",
                skillDoctorTruthTone: .warning,
                skillDoctorTruthDetailLine: "当前可直接运行：4 个；待 Hub grant：1 个；待本地确认：2 个；技能计数：7 个。"
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        let mapped = try #require(presentation.entries.first)
        let overview = try #require(presentation.overview)

        #expect(mapped.id == "skill_doctor_truth_pending")
        #expect(mapped.reasonText == "技能 Doctor Truth")
        #expect(mapped.priority == .attention)
        #expect(mapped.headlineText == "技能授权待补齐")
        #expect(mapped.headlineTone == .warning)
        #expect(mapped.detailLines.first == "技能 doctor truth：1 个待 Hub grant，2 个待本地确认。")
        #expect(mapped.detailLines.contains(where: { $0.contains("待 Hub grant：1 个") }))
        #expect(mapped.focusAction?.label == "打开 Supervisor")
        #expect(mapped.digest.whatChangedText == "技能 doctor truth：1 个待 Hub grant，2 个待本地确认。")
        #expect(mapped.digest.whyImportantText.contains("Hub grant"))
        #expect(mapped.digest.systemNextStepText.contains("Hub grant / 本地确认项"))
        #expect(overview.headlineText == "技能授权待补齐")
        #expect(overview.detailText == "技能 doctor truth：1 个待 Hub grant，2 个待本地确认。")
    }

    @Test
    func mapSortsSkillDoctorTruthAheadOfOtherAttentionSignalsWhenNoHigherPriorityExists() throws {
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-route-doctor-truth",
                pane: .chat,
                focusTarget: .routeDiagnose
            )?.absoluteString
        )
        let entries = [
            heartbeat(
                id: "hb-route",
                createdAt: 1_000,
                changed: true,
                content: routeHeartbeatContent(),
                focusActionURL: focusActionURL
            )
        ]

        let presentation = SupervisorHeartbeatPresentation.map(
            entries: entries,
            doctorPresentation: doctorPresentation(
                skillDoctorTruthStatusLine: "技能 doctor truth：1 个技能当前不可运行。",
                skillDoctorTruthTone: .danger,
                skillDoctorTruthDetailLine: "当前可直接运行：2 个；当前阻塞：1 个（hub.remote.exec）；技能计数：3 个。"
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(presentation.entries.map(\.id) == ["skill_doctor_truth_blocked", "hb-route"])
        #expect(presentation.entries.first?.headlineText == "技能能力阻塞")
        #expect(presentation.entries.last?.headlineText == "模型路由诊断")
    }

    private func heartbeat(
        id: String,
        createdAt: Double,
        changed: Bool,
        content: String = "",
        focusActionURL: String?,
        reason: String = "periodic_check"
    ) -> SupervisorManager.HeartbeatFeedEntry {
        SupervisorManager.HeartbeatFeedEntry(
            id: id,
            createdAt: createdAt,
            reason: reason,
            projectCount: 3,
            changed: changed,
            content: content.isEmpty ? "summary \(id)" : content,
            focusActionURL: focusActionURL
        )
    }

    private func doctorPresentation(
        skillDoctorTruthStatusLine: String?,
        skillDoctorTruthTone: SupervisorHeaderControlTone,
        skillDoctorTruthDetailLine: String?
    ) -> SupervisorDoctorBoardPresentation {
        SupervisorDoctorBoardPresentation(
            iconName: "checkmark.shield.fill",
            iconTone: .success,
            title: "Supervisor 体检",
            statusLine: "体检检查通过",
            releaseBlockLine: "发布级体检门已满足。",
            skillDoctorTruthStatusLine: skillDoctorTruthStatusLine,
            skillDoctorTruthTone: skillDoctorTruthTone,
            skillDoctorTruthDetailLine: skillDoctorTruthDetailLine,
            memoryReadinessLine: "战略记忆已就绪。",
            memoryReadinessTone: .success,
            memoryIssueSummaryLine: nil,
            memoryIssueDetailLine: nil,
            projectMemoryAdvisoryLine: nil,
            projectMemoryAdvisoryTone: .neutral,
            projectMemoryAdvisoryDetailLine: nil,
            memoryContinuitySummaryLine: nil,
            memoryContinuityDetailLine: nil,
            canonicalRetryStatusLine: nil,
            canonicalRetryTone: .neutral,
            canonicalRetryMetaLine: nil,
            canonicalRetryDetailLine: nil,
            emptyStateText: nil,
            reportLine: nil
        )
    }

    private func governanceHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：1
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Governance Runtime：⏸️ 暂停中

排队态势：
（无）

权限申请：
（无）

治理修复：
• Governance Runtime：A-Tier 需要调整；Open Project Settings -> A-Tier and raise it to A2 Repo Auto or above before starting, inspecting, or stopping managed processes.

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. 治理修复：Governance Runtime — 建议先打开 Project Governance -> A-Tier。
"""
    }

    private func routeHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Route Runtime：✅ 继续当前任务

排队态势：
（无）

权限申请：
（无）

治理修复：
（无）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. 模型路由：Route Runtime 最近最常见是 目标模型未加载（model_not_found）（2 次）；最近一次失败停在 重连并重诊断。建议先看 /route diagnose。
"""
    }

    private func projectMemoryAdvisoryHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理审查项目：0
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Memory Runtime：✅ 继续当前任务

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

Project AI 记忆（advisory）：
Beta 的 Project AI 记忆装配还需要补强（advisory，尚未捕获 Project AI 的最近一次 memory 装配真相）。
目前还缺 recent coder usage 这层 machine-readable truth，Doctor 还不能确认最近一轮 coder 真正吃到了哪些 project memory。
系统会继续维持当前 heartbeat 节奏，并等待下一轮 recent coder usage 补齐 machine-readable memory assembly truth。

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
（暂无）
"""
    }

    private func governedReviewHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理审查项目：1
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Review Runtime：✅ 继续当前任务

排队态势：
（无）

权限申请：
（无）

治理审查：
• Review Runtime：已排队战略审查（无进展复盘 · 长时间无进展）
• 依据：当前项目治理要求在长时间无进展时进入 brainstorm review，heartbeat 已自动排队。
• 记忆供给：Project AI 最近一轮 memory truth 来自 latest coder usage，effective depth=deep；heartbeat digest 已在 Project AI working set 中。

治理修复：
（无）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. Review Runtime：等待 Supervisor 执行已排队的 review，并在 safe point 接收 guidance。
"""
    }

    private func projectCreationHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：0
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理审查项目：0
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
（无）

排队态势：
（无）

权限申请：
（无）

治理审查：
（无）

治理修复：
（无）

项目创建：
项目创建还差一句触发。
已锁定《贪食蛇游戏》，再说“立项”“创建一个project”或“按默认方案建项目”就会真正创建。
目标：我要做个贪食蛇游戏
可直接说：“立项” / “创建一个project” / “按默认方案建项目”

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
直接说立项，或说创建一个project。
"""
    }

    private func governedReviewHeartbeatContentRawEnglish() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理审查项目：1
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Review Runtime：✅ 继续当前任务

排队态势：
（无）

权限申请：
（无）

治理审查：
• Project Review Runtime has queued strategic governance review. Supervisor heartbeat queued it via no-progress brainstorm cadence because of long no progress.
• Current project governance requires a brainstorm review after long no progress; heartbeat automatically queued it.

治理修复：
（无）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. Open the project and inspect why the queued governance review was scheduled.
"""
    }

    private func rescueGovernedReviewHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理审查项目：1
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Rescue Runtime：⚠️ 需要立即复核完成声明

排队态势：
（无）

权限申请：
（无）

治理审查：
• Rescue Runtime：已排队救援审查（事件触发 · 完成声明证据偏弱）
• 依据：当前项目治理要求在完成前补做 review，heartbeat 已自动排队。

治理修复：
（无）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. Rescue Runtime：等待 Supervisor 先完成 pre-done review，再继续收口。
"""
    }

    private func voiceHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：0
语音修复项：1（语音链路失败闭锁）
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Supervisor Voice：⚠️ fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable

排队态势：
（无）

权限申请：
（无）

治理修复：
（无）

语音就绪：
• fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable（打开：xterminal://supervisor-settings）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. 语音 fail-closed：fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable；建议先查看 Hub Recovery（打开：xterminal://hub-setup/troubleshoot）
"""
    }

    private func pairingHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：0
配对续连项：1（同网首配已完成，正在验证正式异网入口）
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Hub Pairing：🔗 首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口

排队态势：
（无）

权限申请：
（无）

治理修复：
（无）

配对续连：
• 首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口（打开：xterminal://hub-setup/pair_progress）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. 配对续连：首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口；建议先查看 Hub 配对（打开：xterminal://hub-setup/pair_progress）
"""
    }

    private func hubLoadHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：0
待治理修复项目：0
lane 状态：total=0, running=0, blocked=0, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Hub Runtime：🌡️ Hub 主机负载偏高 · CPU 92% · load 7.20 / 6.30 / 5.90 · 内存 high · 热状态 serious

排队态势：
（无）

权限申请：
（无）

治理修复：
（无）

语音就绪：
（无）

Hub 负载：
• Hub 主机负载偏高 · CPU 92% · load 7.20 / 6.30 / 5.90 · 内存 high · 热状态 serious（打开：xterminal://hub-setup/troubleshoot）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. Hub 负载：Hub 主机负载偏高 · CPU 92% · load 7.20 / 6.30 / 5.90 · 内存 high · 热状态 serious；建议先查看 Hub 诊断（打开：xterminal://hub-setup/troubleshoot）
"""
    }

    private func authorizationNoiseHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
grant_pending
lane=lane-auth status=blocked reason=grant_pending
需要你批准 repo 写权限后，系统才会继续推进。
event_loop_tick=42 dedupe_key=heartbeat:grant_pending
"""
    }

    private func authorizationNoiseOnlyHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
grant_pending
lane=lane-auth status=blocked reason=grant_pending
event_loop_tick=42 dedupe_key=heartbeat:grant_pending
"""
    }

    private func grantRecoveryHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：0
待授权项目：1
待治理修复项目：0
lane 状态：total=0, running=0, blocked=1, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Grant Recovery Runtime：⏸️ 等待授权恢复

排队态势：
（无）

权限申请：
• Grant Recovery Runtime：需要你批准 repo 写权限后，系统才会继续推进。（打开：xterminal://project?project_id=project-recovery-grant)

Recovery 跟进：
• Grant Recovery Runtime 需要 grant / 授权跟进
• 系统会先发起所需 grant 跟进，待放行后再继续恢复执行。
• 为什么先跟进：待授权会直接卡住推进（优先级：紧急 · score=8）

治理修复：
（无）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. Recovery 跟进：Grant Recovery Runtime — 建议先批准 repo 写权限，再继续恢复执行。
"""
    }

    private func replayRecoveryHeartbeatContent() -> String {
        """
🫀 Supervisor Heartbeat (10:00)
原因：timer
项目总数：1
变化：检测到项目状态更新
排队项目：1
待授权项目：0
待治理修复项目：0
lane 状态：total=0, running=0, blocked=1, stalled=0, failed=0

主动推进：
（本轮无需介入）

重点看板：
• Replay Recovery Runtime：⏸️ drain 收口后继续续跑

排队态势：
• Replay Recovery Runtime：1 个排队中（最长约 4 分钟）

权限申请：
（无）

Recovery 跟进：
• Replay Recovery Runtime 需要重放 follow-up / 续跑链
• 系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。
• 为什么先跟进：存在明确 blocker，需要优先解阻（优先级：高 · score=6）

治理修复：
（无）

Lane 健康巡检：
（无异常 lane）

Coder 下一步建议：
1. Recovery 跟进：Replay Recovery Runtime — 建议先打开项目查看 resume / replan。
"""
    }
}
