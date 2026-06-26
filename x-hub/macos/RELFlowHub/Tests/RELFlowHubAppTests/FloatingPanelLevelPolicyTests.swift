import AppKit
import XCTest
@testable import RELFlowHub

final class FloatingPanelLevelPolicyTests: XCTestCase {
    func testHiddenKeepsNormalLevel() {
        XCTAssertEqual(FloatingPanelLevelPolicy.level(for: .hidden), .normal)
    }

    func testOrbUsesFloatingLevelSoItRemainsVisibleAfterMainPanelCloses() {
        XCTAssertEqual(FloatingPanelLevelPolicy.level(for: .orb), .floating)
    }

    func testCardKeepsNormalLevel() {
        XCTAssertEqual(FloatingPanelLevelPolicy.level(for: .card), .normal)
    }
}
