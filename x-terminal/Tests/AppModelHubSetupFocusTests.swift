import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelHubSetupFocusTests {
    @Test
    func ignoresEmptyHubSetupFocusRequests() {
        let appModel = AppModel()

        appModel.requestHubSetupFocus(sectionId: "   ")

        #expect(appModel.hubSetupFocusRequest == nil)
    }

    @Test
    func hubSetupFocusRequestUsesFreshNonceAndClearsCurrentOnly() throws {
        let appModel = AppModel()

        appModel.requestHubSetupFocus(
            sectionId: " troubleshoot ",
            title: " 检查 Hub Recovery ",
            detail: " reason=remote_export_blocked ",
            refreshAction: .recheckOfficialSkills,
            refreshReason: "official_skill_blocker"
        )
        let first = try #require(appModel.hubSetupFocusRequest)
        #expect(first.sectionId == "troubleshoot")
        #expect(first.context?.title == "检查 Hub Recovery")
        #expect(first.context?.detail == "reason=remote_export_blocked")
        #expect(first.context?.refreshAction == .recheckOfficialSkills)
        #expect(first.context?.refreshReason == "official_skill_blocker")

        appModel.requestHubSetupFocus(sectionId: "connection_log")
        let second = try #require(appModel.hubSetupFocusRequest)
        #expect(second.sectionId == "connection_log")
        #expect(second.nonce == first.nonce + 1)

        appModel.clearHubSetupFocusRequest(first)
        #expect(appModel.hubSetupFocusRequest?.nonce == second.nonce)

        appModel.clearHubSetupFocusRequest(second)
        #expect(appModel.hubSetupFocusRequest == nil)
    }
}
