import Testing
@testable import XTerminal

struct SupervisorBlockerPresentationTests {
    @Test
    func displayTextReturnsNilForEmptyAndNone() {
        #expect(SupervisorBlockerPresentation.displayText(nil) == nil)
        #expect(SupervisorBlockerPresentation.displayText("") == nil)
        #expect(SupervisorBlockerPresentation.displayText("none") == nil)
    }

    @Test
    func displayTextHumanizesKnownGovernanceAndCompositeCodes() {
        #expect(
            SupervisorBlockerPresentation.displayText("grant_required")
                == "Hub 授权未完成（grant_required）"
        )
        #expect(
            SupervisorBlockerPresentation.displayText("grant_required | decision_requires_approval:security")
                == "Hub 授权未完成（grant_required） | decision_requires_approval:security"
        )
    }

    @Test
    func displayTextHumanizesAutomationAndOneShotFailureCodes() {
        #expect(
            SupervisorBlockerPresentation.displayText("legacy_supervisor_runtime_unavailable")
                == "Supervisor 执行运行时当前不可用（legacy_supervisor_runtime_unavailable）"
        )
        #expect(
            SupervisorBlockerPresentation.displayText("automation_active_run_present")
                == "项目已有进行中的 automation（automation_active_run_present）"
        )
        #expect(
            SupervisorBlockerPresentation.displayText("trusted_automation_project_not_bound")
                == "项目未绑定到当前设备（trusted_automation_project_not_bound）"
        )
    }
}
