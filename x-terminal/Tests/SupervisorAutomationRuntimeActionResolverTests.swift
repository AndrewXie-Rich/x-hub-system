import Foundation
import Testing
@testable import XTerminal

struct SupervisorAutomationRuntimeActionResolverTests {

    @Test
    func actionsStayDisabledWithoutProjectSelection() {
        let context = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: false,
            hasRecipe: false,
            hasLastLaunchRef: false
        )

        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .status, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .start, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .recover, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .cancel, context: context)
                .isEnabled == false
        )
    }

    @Test
    func startRequiresActiveRecipeAndRecoverFlowRequiresLaunchRef() {
        let context = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: true,
            hasRecipe: true,
            hasLastLaunchRef: false
        )

        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .start, context: context)
                .isEnabled
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .recover, context: context)
                .isEnabled == false
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.advanceDescriptors(context: context)
                .allSatisfy { $0.isEnabled == false }
        )
    }

    @Test
    func launchRefEnablesRecoverCancelAndAdvanceControls() {
        let context = SupervisorAutomationRuntimeActionResolver.Context(
            hasSelectedProject: true,
            hasRecipe: false,
            hasLastLaunchRef: true
        )

        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .recover, context: context)
                .isEnabled
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.descriptor(for: .cancel, context: context)
                .isEnabled
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.advanceDescriptors(context: context)
                .allSatisfy { $0.isEnabled }
        )
    }

    @Test
    func commandsMapToStableAutomationCliSurface() {
        #expect(
            SupervisorAutomationRuntimeActionResolver.command(for: .status)
                == "/automation status"
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.command(for: .start)
                == "/automation start"
        )
        #expect(
            SupervisorAutomationRuntimeActionResolver.command(for: .advance(.delivered))
                == "/automation advance delivered"
        )
    }
}
