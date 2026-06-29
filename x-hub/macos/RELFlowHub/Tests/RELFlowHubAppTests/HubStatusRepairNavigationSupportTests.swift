import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubStatusRepairNavigationSupportTests: XCTestCase {
    func testGRPCRootCauseTargetsGRPCServerSection() {
        let target = HubStatusRepairNavigationSupport.target(
            snapshot: launchSnapshot(
                state: .failed,
                rootCause: HubLaunchRootCause(component: .grpc, errorCode: "XHUB_GRPC_PORT_IN_USE")
            )
        )

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .access,
                anchorID: HubSettingsSectionAnchorID.grpcServerSection,
                expansion: nil
            )
        )
    }

    func testRuntimeRootCauseTargetsRuntimeMonitorSection() {
        let target = HubStatusRepairNavigationSupport.target(
            snapshot: launchSnapshot(
                state: .degradedServing,
                rootCause: HubLaunchRootCause(component: .runtime, errorCode: "XHUB_RT_IMPORT_ERROR")
            )
        )

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .runtime,
                anchorID: HubSettingsSectionAnchorID.runtimeMonitorSection,
                expansion: nil
            )
        )
    }

    func testBridgeRootCauseTargetsNetworkingSection() {
        let target = HubStatusRepairNavigationSupport.target(
            snapshot: launchSnapshot(
                state: .failed,
                rootCause: HubLaunchRootCause(component: .bridge, errorCode: "XHUB_BRIDGE_UNAVAILABLE")
            )
        )

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .diagnostics,
                anchorID: HubSettingsSectionAnchorID.networkingSection,
                expansion: .diagnosticsNetwork
            )
        )
    }

    func testEnvironmentRootCauseTargetsDoctorSection() {
        let target = HubStatusRepairNavigationSupport.target(
            snapshot: launchSnapshot(
                state: .failed,
                rootCause: HubLaunchRootCause(component: .env, errorCode: "XHUB_ENV_INVALID")
            )
        )

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .diagnostics,
                anchorID: HubSettingsSectionAnchorID.doctorSection,
                expansion: nil
            )
        )
    }

    func testLocalModelBlockedCapabilityTargetsRuntimeMonitorSection() {
        let target = HubStatusRepairNavigationSupport.target(
            snapshot: launchSnapshot(
                state: .serving,
                blockedCapabilities: ["ai.embed.local"]
            )
        )

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .runtime,
                anchorID: HubSettingsSectionAnchorID.runtimeMonitorSection,
                expansion: nil
            )
        )
    }

    func testPaidModelBlockedCapabilityTargetsProviderKeysSection() {
        let target = HubStatusRepairNavigationSupport.target(
            snapshot: launchSnapshot(
                state: .serving,
                blockedCapabilities: ["ai.generate.paid"]
            )
        )

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .models,
                anchorID: HubSettingsSectionAnchorID.providerKeysSection,
                expansion: .providerQuotaOperations
            )
        )
    }

    func testNetworkBlockedCapabilityTargetsNetworkPoliciesSection() {
        let target = HubStatusRepairNavigationSupport.target(
            snapshot: launchSnapshot(
                state: .serving,
                blockedCapabilities: ["web.fetch"]
            )
        )

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .diagnostics,
                anchorID: HubSettingsSectionAnchorID.networkPoliciesSection,
                expansion: .diagnosticsNetwork
            )
        )
    }

    func testMissingSnapshotTargetsRustKernelSection() {
        let target = HubStatusRepairNavigationSupport.target(snapshot: nil)

        XCTAssertEqual(
            target,
            .settingsPage(
                page: .runtime,
                anchorID: HubSettingsSectionAnchorID.rustHubKernelSection,
                expansion: nil
            )
        )
    }

    private func launchSnapshot(
        state: HubLaunchState,
        rootCause: HubLaunchRootCause? = nil,
        blockedCapabilities: [String] = []
    ) -> HubLaunchStatusSnapshot {
        HubLaunchStatusSnapshot(
            updatedAtMs: 1,
            state: state,
            steps: [],
            rootCause: rootCause,
            degraded: HubLaunchDegraded(
                isDegraded: !blockedCapabilities.isEmpty || rootCause != nil,
                blockedCapabilities: blockedCapabilities
            )
        )
    }
}
