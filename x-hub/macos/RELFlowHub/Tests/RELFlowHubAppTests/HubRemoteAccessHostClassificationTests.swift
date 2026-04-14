import XCTest
@testable import RELFlowHub

final class HubRemoteAccessHostClassificationTests: XCTestCase {
    func testClassifyReturnsMissingForEmptyHost() {
        let classification = HubRemoteAccessHostClassification.classify("   ")

        XCTAssertEqual(classification.kind, .missing)
        XCTAssertNil(classification.displayHost)
    }

    func testClassifyReturnsLanOnlyForBonjourStyleHost() {
        let classification = HubRemoteAccessHostClassification.classify("hub.local")

        XCTAssertEqual(classification.kind, .lanOnly)
        XCTAssertEqual(classification.displayHost, "hub.local")
    }

    func testClassifyReturnsRawIPWithPublicScope() {
        let classification = HubRemoteAccessHostClassification.classify("17.81.11.116")

        XCTAssertEqual(classification.kind, .rawIP(scope: .publicInternet))
        XCTAssertEqual(classification.displayHost, "17.81.11.116")
    }

    func testClassifyReturnsStableNamedHostForTailnetStyleName() {
        let classification = HubRemoteAccessHostClassification.classify("hub.tailnet.example")

        XCTAssertEqual(classification.kind, .stableNamed)
        XCTAssertEqual(classification.displayHost, "hub.tailnet.example")
    }

    func testClassifyIPAddressScopeRecognizesPrivateAndIPv6LinkLocal() {
        XCTAssertEqual(
            HubRemoteAccessHostClassification.classifyIPAddressScope("100.96.10.8"),
            .carrierGradeNat
        )
        XCTAssertEqual(
            HubRemoteAccessHostClassification.classifyIPAddressScope("fe80::1"),
            .linkLocal
        )
    }
}
