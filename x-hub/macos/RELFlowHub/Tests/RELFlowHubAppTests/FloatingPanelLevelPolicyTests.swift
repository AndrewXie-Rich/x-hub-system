import AppKit
import XCTest
@testable import RELFlowHub

final class FloatingPanelLevelPolicyTests: XCTestCase {
    func testOrbUsesFloatingLevelSoItRemainsVisibleAfterMainPanelCloses() {
        XCTAssertEqual(FloatingPanelLevelPolicy.level(for: .orb), .floating)
    }

    func testCardKeepsNormalLevel() {
        XCTAssertEqual(FloatingPanelLevelPolicy.level(for: .card), .normal)
    }
}
