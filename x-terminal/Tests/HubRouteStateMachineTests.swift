import Foundation
import Testing
@testable import XTerminal

struct HubRouteStateMachineTests {
    @Test
    func autoFallbackTreatsRawGRPCUnavailableAsRemoteOutage() {
        let raw = "14_UNAVAILABLE:_No_connection_established._Last_error:_null._Resolution_note:"
        #expect(HubRouteStateMachine.shouldFallbackToFile(afterRemoteReasonCode: raw))
    }

    @Test
    func autoFallbackTreatsFailedToConnectToAllAddressesAsRemoteOutage() {
        let raw = "14 UNAVAILABLE: failed to connect to all addresses; last error: UNKNOWN: ipv4:127.0.0.1:50051: Failed to connect to remote host: Connection refused"
        #expect(HubRouteStateMachine.shouldFallbackToFile(afterRemoteReasonCode: raw))
    }

    @Test
    func pendingGrantSnapshotAutoFallbackRequiresRouteUnavailableReason() {
        let autoWithRemote = HubRouteStateMachine.resolve(mode: .auto, hasRemoteProfile: true)
        #expect(
            HubRouteStateMachine.shouldFallbackToFileForPendingGrantSnapshot(
                routeDecision: autoWithRemote,
                remoteReasonCode: "hub_env_missing"
            )
        )
        #expect(
            !HubRouteStateMachine.shouldFallbackToFileForPendingGrantSnapshot(
                routeDecision: autoWithRemote,
                remoteReasonCode: "model_not_found"
            )
        )
    }

    @Test
    func pendingGrantSnapshotFallbackSourceDisclosesFallbackTruth() {
        let autoWithRemote = HubRouteStateMachine.resolve(mode: .auto, hasRemoteProfile: true)
        let source = HubRouteStateMachine.pendingGrantSnapshotFallbackSource(
            localSource: "hub_pending_grants_file",
            routeDecision: autoWithRemote,
            remoteReasonCode: "hub_env_missing"
        )
        #expect(source.contains("transport=auto"))
        #expect(source.contains("remote_snapshot_unavailable=1"))
        #expect(source.contains("fallback_used=1"))
        #expect(source.contains("fallback_reason=hub_env_missing"))
    }

    @Test
    func pendingGrantSnapshotFallbackSourceDoesNotAnnotateGrpc() {
        let grpcWithRemote = HubRouteStateMachine.resolve(mode: .grpc, hasRemoteProfile: true)
        let source = HubRouteStateMachine.pendingGrantSnapshotFallbackSource(
            localSource: "hub_pending_grants_file",
            routeDecision: grpcWithRemote,
            remoteReasonCode: "hub_env_missing"
        )
        #expect(source == "hub_pending_grants_file")
    }
}
