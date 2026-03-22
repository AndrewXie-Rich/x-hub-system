import Foundation
import Testing
@testable import XTerminal

struct SupervisorBigTaskAssistTests {

    @Test
    func detectPrefersInputAndRespectsDismissal() {
        let candidate = SupervisorBigTaskAssist.detect(
            inputText: "请帮我做一个能自动拆工单并推进的 Agent 项目系统",
            latestUserMessage: "做个网页",
            dismissedFingerprint: nil
        )

        #expect(candidate?.goal == "请帮我做一个能自动拆工单并推进的 Agent 项目系统")
        #expect(candidate?.fingerprint.isEmpty == false)

        let dismissed = SupervisorBigTaskAssist.detect(
            inputText: "请帮我做一个能自动拆工单并推进的 Agent 项目系统",
            latestUserMessage: nil,
            dismissedFingerprint: candidate?.fingerprint
        )

        #expect(dismissed == nil)
    }

    @Test
    func candidateFiltersOutCommandsAndWeakSignals() {
        #expect(SupervisorBigTaskAssist.candidate(from: "/help") == nil)
        #expect(SupervisorBigTaskAssist.candidate(from: "总结一下") == nil)
        #expect(
            SupervisorBigTaskAssist.candidate(
                from: "请把这件事建成一个大任务，并先给出 job + initial plan"
            ) == nil
        )
    }

    @Test
    func promptWrapsGoalInBigTaskInstruction() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "帮我搭一个多项目 Agent 平台",
            fingerprint: "fp"
        )

        let prompt = SupervisorBigTaskAssist.prompt(for: candidate)

        #expect(prompt.contains("job + initial plan"))
        #expect(prompt.contains(candidate.goal))
        #expect(prompt.contains("只问我一个最关键的问题"))
    }
}
