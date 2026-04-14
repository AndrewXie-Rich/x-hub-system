import Testing
@testable import XTerminal

struct AppModelHubSetupProgressTests {
    @Test
    func bootstrapAwaitingApprovalMapsToDedicatedStepState() {
        let event = HubRemoteProgressEvent(
            phase: .bootstrap,
            state: .started,
            detail: "awaiting_hub_approval"
        )

        #expect(AppModel.hubSetupStepState(for: event) == .awaitingApproval)
    }

    @Test
    func bootstrapAwaitingApprovalUsesExplicitSummary() {
        let event = HubRemoteProgressEvent(
            phase: .bootstrap,
            state: .started,
            detail: "awaiting_hub_approval"
        )

        #expect(AppModel.hubSetupSummary(for: event) == "waiting for Hub local approval ...")
    }

    @Test
    func connectStartedUsesConnectingSummary() {
        let event = HubRemoteProgressEvent(
            phase: .connect,
            state: .started,
            detail: "lan"
        )

        #expect(AppModel.hubSetupStepState(for: event) == .running)
        #expect(AppModel.hubSetupSummary(for: event) == "connecting hub route ...")
    }

    @Test
    func bootstrapRefreshUsesRefreshSummaryInsteadOfApprovalWait() {
        let event = HubRemoteProgressEvent(
            phase: .bootstrap,
            state: .started,
            detail: "refresh"
        )

        #expect(AppModel.hubSetupStepState(for: event) == .running)
        #expect(AppModel.hubSetupSummary(for: event) == "refreshing pairing profile ...")
    }

    @Test
    func connectOnlyReconnectKeepsCompletedDiscoverStateVisible() {
        let event = HubRemoteProgressEvent(
            phase: .discover,
            state: .skipped,
            detail: "bootstrap_disabled"
        )

        #expect(
            AppModel.resolveHubSetupDisplayState(
                current: .success,
                for: event
            ) == .success
        )
    }

    @Test
    func connectOnlyReconnectKeepsCompletedBootstrapStateVisible() {
        let event = HubRemoteProgressEvent(
            phase: .bootstrap,
            state: .skipped,
            detail: "bootstrap_disabled"
        )

        #expect(
            AppModel.resolveHubSetupDisplayState(
                current: .success,
                for: event
            ) == .success
        )
    }

    @Test
    func connectOnlyReconnectStillShowsSkippedWithoutPriorCompletion() {
        let event = HubRemoteProgressEvent(
            phase: .bootstrap,
            state: .skipped,
            detail: "bootstrap_disabled"
        )

        #expect(
            AppModel.resolveHubSetupDisplayState(
                current: .idle,
                for: event
            ) == .skipped
        )
    }

    @Test
    func connectOnlyReconnectUsesExplicitVerificationSummary() {
        #expect(
            AppModel.defaultHubRemoteSetupSummary(allowBootstrap: false)
                == "verifying saved hub route ..."
        )
    }
}
