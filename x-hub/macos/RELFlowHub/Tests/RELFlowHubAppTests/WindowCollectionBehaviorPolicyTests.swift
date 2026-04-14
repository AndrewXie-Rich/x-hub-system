import AppKit
import XCTest
@testable import RELFlowHub

final class WindowCollectionBehaviorPolicyTests: XCTestCase {
    func testMainPanelBehaviorAvoidsInvalidFlagCombination() {
        let behavior = WindowCollectionBehaviorPolicy.mainPanel()

        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(WindowCollectionBehaviorPolicy.isValid(behavior))
    }

    func testFloatingPanelBehaviorAvoidsInvalidFlagCombination() {
        let behavior = WindowCollectionBehaviorPolicy.floatingPanel()

        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertTrue(WindowCollectionBehaviorPolicy.isValid(behavior))
    }
}
