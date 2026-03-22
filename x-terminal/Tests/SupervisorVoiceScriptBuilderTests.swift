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
            projectName: "Device Runtime",
            skillSummary: "browser.open -> guarded-automation",
            routingSummary: "浏览器入口会先收敛到受治理内建 guarded-automation 再执行",
            toolSummary: "打开 https://example.com/login",
            reasonSummary: "需要确认后再执行设备级浏览器操作"
        )

        #expect(script.joined(separator: " ").contains("受治理内建 guarded-automation"))
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
}
