import Testing
@testable import XTerminal

struct HubPairingTransportTests {
    @Test
    func secureTransportAndProfilePolicy() throws {
        try HubPairingTransportRegression.policyChecks()
    }
}
