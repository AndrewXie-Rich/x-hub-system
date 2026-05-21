import Testing
@testable import XTerminal

struct HubRemoteHostPolicyTests {
    @Test
    func tailscaleIPv4IsFormalRemoteNotLanOrPublicRaw() {
        let host = "100.122.237.57"
        let classification = XTHubRemoteAccessHostClassification.classify(host)

        #expect(HubRemoteHostPolicy.isTailscaleIPv4Host(host))
        #expect(HubRemoteHostPolicy.isFormalRemoteHost(host))
        #expect(HubRemoteHostPolicy.isDirectInternetRemoteHost(host))
        #expect(HubRemoteHostPolicy.isPublicIPv4Host(host) == false)
        #expect(HubRemoteHostPolicy.isDirectLocalFallbackHost(host) == false)
        #expect(classification.isFormalRemoteEntry)
        #expect(classification.ipScope == .tailscale)
        #expect(classification.ipScope?.doctorLabel == "Tailscale IP")
    }

    @Test
    func publicIPv4IsDirectInternetButNotFormalRemote() {
        let host = "17.81.11.116"
        let classification = XTHubRemoteAccessHostClassification.classify(host)

        #expect(HubRemoteHostPolicy.isPublicIPv4Host(host))
        #expect(HubRemoteHostPolicy.isDirectInternetRemoteHost(host))
        #expect(HubRemoteHostPolicy.isFormalRemoteHost(host) == false)
        #expect(classification.isFormalRemoteEntry == false)
        #expect(classification.ipScope == .publicInternet)
    }
}
