import XCTest
@testable import RELFlowHub

    @MainActor
    final class HubRemoteAccessRouteProbeTests: XCTestCase {
        func testRefreshSkipsResolutionForRawIP() {
        let probe = HubRemoteAccessRouteProbe(resolver: { _ in
            return []
        })

        probe.refresh(host: "17.81.11.116")

        XCTAssertEqual(probe.snapshot.state, .skipped)
        XCTAssertEqual(probe.snapshot.statusText, HubUIStrings.Settings.GRPC.RemoteRoute.statusSkipped)
        XCTAssertTrue(probe.snapshot.detailText.contains("17.81.11.116"))
    }

    func testRefreshResolvesStableHostUsingInjectedResolver() async {
        let probe = HubRemoteAccessRouteProbe(resolver: { host in
            XCTAssertEqual(host, "hub.tailnet.example")
            return ["100.96.10.8", "2607:f8b0::1"]
        })

        probe.refresh(host: "hub.tailnet.example")
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(probe.snapshot.state, .resolved)
        XCTAssertEqual(probe.snapshot.statusText, HubUIStrings.Settings.GRPC.RemoteRoute.statusResolved)
        XCTAssertEqual(probe.snapshot.addresses, ["100.96.10.8", "2607:f8b0::1"])
    }

    func testRefreshSurfacesResolverFailure() async {
        let probe = HubRemoteAccessRouteProbe(resolver: { _ in
            throw HubRemoteAccessRouteProbeFailure(message: "dns_timeout")
        })

        probe.refresh(host: "hub.tailnet.example")
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(probe.snapshot.state, .failed)
        XCTAssertEqual(probe.snapshot.statusText, HubUIStrings.Settings.GRPC.RemoteRoute.statusFailed)
        XCTAssertTrue(probe.snapshot.detailText.contains("dns_timeout"))
    }
}
