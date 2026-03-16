import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelModelSettingsFocusTests {
    @Test
    func ignoresEmptyModelSettingsFocusRequests() {
        let appModel = AppModel()

        appModel.requestModelSettingsFocus(
            role: nil,
            title: "   ",
            detail: "   "
        )

        #expect(appModel.modelSettingsFocusRequest == nil)
    }

    @Test
    func modelSettingsFocusRequestUsesFreshNonceAndClearsCurrentOnly() throws {
        let appModel = AppModel()

        appModel.requestModelSettingsFocus(
            role: .coder,
            title: " 路由诊断 ",
            detail: " reason=model_not_found "
        )
        let first = try #require(appModel.modelSettingsFocusRequest)
        #expect(first.role == .coder)
        #expect(first.context?.title == "路由诊断")
        #expect(first.context?.detail == "reason=model_not_found")

        appModel.requestModelSettingsFocus(role: .supervisor)
        let second = try #require(appModel.modelSettingsFocusRequest)
        #expect(second.role == .supervisor)
        #expect(second.context == nil)
        #expect(second.nonce == first.nonce + 1)

        appModel.clearModelSettingsFocusRequest(first)
        #expect(appModel.modelSettingsFocusRequest?.nonce == second.nonce)

        appModel.clearModelSettingsFocusRequest(second)
        #expect(appModel.modelSettingsFocusRequest == nil)
    }
}
