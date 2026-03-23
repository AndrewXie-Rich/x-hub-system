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
}
