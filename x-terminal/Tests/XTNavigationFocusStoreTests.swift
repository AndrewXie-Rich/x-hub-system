import Testing
@testable import XTerminal

struct XTNavigationFocusStoreTests {
    @Test
    @MainActor
    func appModelMirrorsSettingsFocusIntoFocusedStore() {
        let appModel = AppModel.makeForTesting()

        appModel.requestSettingsFocus(
            sectionId: "diagnostics",
            title: "Diagnostics",
            detail: "Open diagnostics"
        )

        let request = appModel.navigationFocusStore.snapshot.settingsFocusRequest
        #expect(request?.sectionId == "diagnostics")
        #expect(request?.context?.title == "Diagnostics")
    }

    @Test
    @MainActor
    func appModelMirrorsModelAndSupervisorFocusIntoFocusedStore() {
        let appModel = AppModel.makeForTesting()

        appModel.requestModelSettingsFocus(
            role: .coder,
            title: "Model",
            detail: "Route"
        )
        appModel.requestSupervisorBoardFocus(anchorID: "automation")

        let snapshot = appModel.navigationFocusStore.snapshot
        #expect(snapshot.modelSettingsFocusRequest?.role == .coder)
        #expect(snapshot.supervisorFocusRequest?.subject == .board(anchorID: "automation"))
    }

    @Test
    @MainActor
    func appModelMirrorsProjectSettingsFocusIntoFocusedStore() {
        let appModel = AppModel.makeForTesting()

        appModel.requestProjectSettingsFocus(
            projectId: "project-nav",
            destination: .executionTier,
            preserveCurrentPane: true
        )

        let request = appModel.navigationFocusStore.snapshot.projectSettingsFocusRequest
        #expect(request?.projectId == "project-nav")
        #expect(request?.destination == .executionTier)
    }

    @Test
    @MainActor
    func appModelMirrorsProjectDetailFocusIntoFocusedStoreAndClearsIt() throws {
        let appModel = AppModel.makeForTesting()

        appModel.requestProjectDetailFocus(
            projectId: "project-detail",
            section: .timeline,
            title: "Resume",
            detail: "Open latest work"
        )

        let request = try #require(appModel.navigationFocusStore.snapshot.projectDetailFocusRequest)
        #expect(request.projectId == "project-detail")
        #expect(request.section == .timeline)
        #expect(request.context?.title == "Resume")

        appModel.clearProjectDetailFocusRequest(request)

        #expect(appModel.navigationFocusStore.snapshot.projectDetailFocusRequest == nil)
    }

    @Test
    @MainActor
    func clearingFocusRequestUpdatesFocusedStore() throws {
        let appModel = AppModel.makeForTesting()
        appModel.requestSettingsFocus(sectionId: "hub")
        let request = try #require(appModel.navigationFocusStore.snapshot.settingsFocusRequest)

        appModel.clearSettingsFocusRequest(request)

        #expect(appModel.navigationFocusStore.snapshot.settingsFocusRequest == nil)
    }
}
