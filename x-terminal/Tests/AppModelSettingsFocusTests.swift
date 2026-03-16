import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelSettingsFocusTests {
    @Test
    func ignoresEmptySettingsFocusRequests() {
        let appModel = AppModel()

        appModel.requestSettingsFocus(sectionId: "   ")

        #expect(appModel.settingsFocusRequest == nil)
    }

    @Test
    func settingsFocusRequestUsesFreshNonceAndClearsCurrentOnly() throws {
        let appModel = AppModel()

        appModel.requestSettingsFocus(
            sectionId: " diagnostics ",
            title: " 路由诊断 ",
            detail: " requested=openai/gpt-5.4 "
        )
        let first = try #require(appModel.settingsFocusRequest)
        #expect(first.sectionId == "diagnostics")
        #expect(first.context?.title == "路由诊断")
        #expect(first.context?.detail == "requested=openai/gpt-5.4")

        appModel.requestSettingsFocus(sectionId: "diagnostics")
        let second = try #require(appModel.settingsFocusRequest)
        #expect(second.sectionId == "diagnostics")
        #expect(second.nonce == first.nonce + 1)

        appModel.clearSettingsFocusRequest(first)
        #expect(appModel.settingsFocusRequest?.nonce == second.nonce)

        appModel.clearSettingsFocusRequest(second)
        #expect(appModel.settingsFocusRequest == nil)
    }
}
