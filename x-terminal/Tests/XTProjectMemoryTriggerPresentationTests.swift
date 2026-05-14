import Testing
@testable import XTerminal

struct XTProjectMemoryTriggerPresentationTests {
    @Test
    func annotatedHumanizesKnownProjectTrigger() {
        #expect(
            XTProjectMemoryTriggerPresentation.annotated("review_guidance_follow_up")
                == "带着 review guidance 跟进执行（review_guidance_follow_up）"
        )
    }

    @Test
    func labelHumanizesHeartbeatReviewTrigger() {
        #expect(
            XTProjectMemoryTriggerPresentation.label("heartbeat_periodic_pulse_review")
                == "heartbeat 触发周期 pulse review"
        )
    }

    @Test
    func detailLineKeepsReadableLabelAndRawCode() {
        #expect(
            XTProjectMemoryTriggerPresentation.detailLine(
                prefix: "heartbeat_project_memory_actual_trigger_label",
                raw: "restart_recovery"
            ) == "heartbeat_project_memory_actual_trigger_label=恢复链需要重新接续当前 run（restart_recovery）"
        )
    }
}
