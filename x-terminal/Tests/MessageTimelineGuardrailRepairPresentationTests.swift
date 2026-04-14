import Testing
@testable import XTerminal

struct MessageTimelineGuardrailRepairPresentationTests {

    @Test
    func secondaryHintPrefersVisibleRepairHelpText() {
        let hint = XTGuardrailRepairHint(
            destination: .executionTier,
            buttonTitle: "打开 A-Tier",
            helpText: "在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。"
        )

        let text = MessageTimelineGuardrailRepairPresentation.secondaryHintText(
            repairHint: hint,
            repairActionSummary: "打开 A-Tier：旧的摘要"
        )

        #expect(text == "在项目设置里切到 A2 Repo Auto 或更高，再重试这次浏览器自动化。")
    }

    @Test
    func secondaryHintFallsBackToRepairActionSummaryWhenHelpTextMissing() {
        let hint = XTGuardrailRepairHint(
            destination: .overview,
            buttonTitle: "打开治理设置",
            helpText: "   "
        )

        let text = MessageTimelineGuardrailRepairPresentation.secondaryHintText(
            repairHint: hint,
            repairActionSummary: "打开治理设置：先解除当前运行面 clamp。"
        )

        #expect(text == "打开治理设置：先解除当前运行面 clamp。")
    }

    @Test
    func secondaryHintHidesBlankRepairMetadata() {
        #expect(
            MessageTimelineGuardrailRepairPresentation.secondaryHintText(
                repairHint: XTGuardrailRepairHint(
                    destination: .overview,
                    buttonTitle: "打开治理设置",
                    helpText: "\n"
                ),
                repairActionSummary: "   "
            ) == nil
        )
    }
}
