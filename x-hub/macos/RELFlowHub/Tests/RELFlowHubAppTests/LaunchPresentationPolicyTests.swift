import XCTest
@testable import RELFlowHub

final class LaunchPresentationPolicyTests: XCTestCase {
    func testDefaultsToForeground() {
        XCTAssertEqual(
            LaunchPresentationPolicy.from(arguments: ["X-Hub"], environment: [:]),
            .foreground
        )
    }

    func testBackgroundArgumentEnablesBackgroundLaunch() {
        XCTAssertEqual(
            LaunchPresentationPolicy.from(arguments: ["X-Hub", "--background"], environment: [:]),
            .background
        )
    }

    func testBackgroundEnvironmentEnablesBackgroundLaunch() {
        XCTAssertEqual(
            LaunchPresentationPolicy.from(
                arguments: ["X-Hub"],
                environment: ["RELFLOWHUB_LAUNCH_BACKGROUND": "1"]
            ),
            .background
        )
    }
}
