import Foundation
import Testing
@testable import XTerminal

struct SupervisorVoiceScriptBuilderTests {
    @Test
    func chinesePreviewScriptUsesProjectProgressToneAndLocalizedLabels() {
        let script = SupervisorVoiceScriptBuilder.previewScript(
            locale: .chineseMainland,
            timbre: .warm,
            speedLabel: "1.15x",
            resolvedOutput: .hubVoicePack,
            selectedVoicePackTitle: "Kokoro CN"
        )

        #expect(script.count == 2)
        #expect(script[0].contains("当前构建已通过"))
        #expect(script[1].contains("Hub 音包 Kokoro CN"))
        #expect(script[1].contains("温暖"))
        #expect(script[1].contains("1.15x"))
    }

    @Test
    func englishPreviewScriptFallsBackToSystemSpeechDescription() {
        let script = SupervisorVoiceScriptBuilder.previewScript(
            locale: .englishUS,
            timbre: .clear,
            speedLabel: "0.90x",
            resolvedOutput: .systemSpeech,
            selectedVoicePackTitle: nil
        )

        #expect(script.count == 2)
        #expect(script[0].contains("build is green"))
        #expect(script[1].contains("system speech"))
        #expect(script[1].contains("clear"))
        #expect(script[1].contains("0.90x"))
    }

    @Test
    func pendingSkillApprovalAnnouncementKeepsCanonicalSkillIdInRoutingSummary() {
        let script = SupervisorVoiceScriptBuilder.pendingSkillApprovalAnnouncementScript(
            pendingCount: 1,
            authorizationMode: .localApproval,
            projectName: "Device Runtime",
            skillSummary: "browser.open -> guarded-automation",
            routingSummary: "浏览器入口会先收敛到受治理内建 guarded-automation 再执行",
            toolSummary: "打开 https://example.com/login",
            reasonSummary: "需要确认后再执行设备级浏览器操作"
        )

        #expect(script.joined(separator: " ").contains("受治理内建 guarded-automation"))
    }

    @Test
    func pendingSkillApprovalAnnouncementUsesHubGrantWordingWhenGrantRequired() {
        let script = SupervisorVoiceScriptBuilder.pendingSkillApprovalAnnouncementScript(
            pendingCount: 1,
            authorizationMode: .hubGrant,
            projectName: "Device Runtime",
            skillSummary: "browser.open -> guarded-automation · 等待 Hub grant",
            routingSummary: "浏览器入口会先收敛到受治理内建 guarded-automation 再执行",
            toolSummary: "打开 https://example.com/login",
            reasonSummary: "需要确认后再执行设备级浏览器操作"
        )

        let spoken = script.joined(separator: " ")
        #expect(spoken.contains("技能授权待处理"))
        #expect(spoken.contains("需要你处理授权"))
        #expect(spoken.contains("Hub 授权面板"))
        #expect(spoken.contains("受治理内建 guarded-automation"))
    }

    @Test
    func governanceSignalHeartbeatKeepsCanonicalSkillIdInMetadata() {
        let script = SupervisorVoiceScriptBuilder.governanceSignalHeartbeatScript(
            signal: SupervisorGovernanceSignalVoicePresentation(
                trigger: .authorization,
                headlineText: "待审批技能",
                detailText: "先在 X-Terminal 里批准，让受治理工具继续执行。",
                metadataText: "1 项待处理 · 本地审批 · 路由说明： 浏览器入口会先收敛到受治理内建 guarded-automation 再执行",
                actionText: "查看技能审批",
                fingerprint: "fp"
            ),
            progressLine: nil,
            nextStepLine: nil
        )

        #expect(script.joined(separator: " ").contains("受治理内建 guarded-automation"))
    }

    @Test
    func governanceSignalHeartbeatUsesDirectProjectCreationActionPhrase() {
        let script = SupervisorVoiceScriptBuilder.governanceSignalHeartbeatScript(
            signal: SupervisorGovernanceSignalVoicePresentation(
                trigger: .blocked,
                headlineText: "项目创建差一句触发",
                detailText: "已锁定《俄罗斯方块》，再说“立项”就会真正创建。",
                metadataText: "目标：俄罗斯方块网页游戏 · 形态：网页版",
                actionText: "直接说立项，或说创建一个project",
                fingerprint: "project-creation"
            ),
            progressLine: nil,
            nextStepLine: nil
        )

        let spoken = script.joined(separator: " ")
        #expect(spoken.contains("项目创建差一句触发"))
        #expect(spoken.contains("你现在只需要"))
        #expect(spoken.contains("直接说立项"))
    }

    @Test
    func routeDiagnoseHeartbeatScriptCanCallOutHubSideHint() {
        let script = SupervisorVoiceScriptBuilder.routeDiagnoseHeartbeatScript(
            projectName: "Route Runtime",
            routeReason: "远端导出被拦截",
            failureAction: "打开 Hub Recovery",
            routeHint: "更像 Hub export gate / 策略挡住远端，先查 Hub，不要先急着改 XT 模型。",
            followUpLine: nil,
            progressLine: nil,
            nextStepLine: "模型路由：Route Runtime 最近最常见是 远端导出被拦截。建议先看 /route diagnose。"
        )

        let spoken = script.joined(separator: " ")
        #expect(spoken.contains("方向上更像"))
        #expect(spoken.contains("先查 Hub"))
        #expect(spoken.contains("route diagnose"))
    }

    @Test
    func routeDiagnoseHeartbeatScriptCanMentionStatusBarFollowUp() {
        let script = SupervisorVoiceScriptBuilder.routeDiagnoseHeartbeatScript(
            projectName: "Route Runtime",
            routeReason: "目标模型未加载",
            failureAction: "重连并重诊断",
            routeHint: nil,
            followUpLine: "我刚从顶部状态栏打开了 AI 模型",
            progressLine: nil,
            nextStepLine: "查看 AI 模型"
        )

        let spoken = script.joined(separator: " ")
        #expect(spoken.contains("顶部状态栏"))
        #expect(spoken.contains("AI 模型"))
        #expect(spoken.contains("查看 AI 模型"))
    }
}
