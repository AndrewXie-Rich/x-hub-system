import Foundation
import Testing

struct XTCalendarBoundaryDocsTruthSyncTests {
    @Test
    func hubTemplateStaysCalendarFreeWhileXtTemplateOwnsCalendarAccess() throws {
        let root = repoRoot()
        let hubInfo = try plistDictionary(
            at: root.appendingPathComponent("x-hub/macos/app_template/Info.plist")
        )
        let hubEntitlements = try plistDictionary(
            at: root.appendingPathComponent("x-hub/macos/app_template/RELFlowHub.entitlements")
        )
        let xtInfo = try plistDictionary(
            at: root.appendingPathComponent("x-terminal/Info.plist")
        )
        let xtEntitlements = try plistDictionary(
            at: root.appendingPathComponent("x-terminal/X-Terminal.entitlements")
        )

        #expect(hubInfo["NSCalendarsUsageDescription"] == nil)
        #expect(hubInfo["NSCalendarsFullAccessUsageDescription"] == nil)
        #expect(boolValue(hubEntitlements["com.apple.security.personal-information.calendars"]) != true)

        let xtLegacyUsage = xtInfo["NSCalendarsUsageDescription"] as? String
        let xtFullAccessUsage = xtInfo["NSCalendarsFullAccessUsageDescription"] as? String
        #expect(xtLegacyUsage?.contains("X-Terminal") == true)
        #expect(xtFullAccessUsage?.contains("X-Terminal") == true)
        #expect(boolValue(xtEntitlements["com.apple.security.personal-information.calendars"]) == true)
    }

    @Test
    func hubAndXtSurfaceCopyReflectCalendarOwnershipBoundary() throws {
        let root = repoRoot()
        let hubStore = try read(
            root.appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift")
        )
        let hubUIStrings = try read(
            root.appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubUIStrings.swift")
        )
        let xtSettings = try read(
            root.appendingPathComponent("x-terminal/Sources/UI/SupervisorSettingsView.swift")
        )

        #expect(hubStore.contains("HubUIStrings.Menu.calendarMigrated"))
        #expect(hubUIStrings.contains("日历已迁移到 X-Terminal"))
        #expect(hubUIStrings.contains("日历提醒已经迁到 X-Terminal Supervisor，这样 Hub 启动时就不需要再申请日历权限。"))
        #expect(!hubStore.contains("CalendarPipeline"))
        #expect(!hubStore.contains("requestCalendarAccessAndStart"))
        #expect(!hubStore.contains("requestNotificationAuthorizationIfNeeded"))

        #expect(xtSettings.contains("授予日历权限"))
        #expect(xtSettings.contains("打开日历设置"))
        #expect(xtSettings.contains("试听提醒播报"))
        #expect(xtSettings.contains("测试通知回退"))
        #expect(xtSettings.contains("模拟真实投递"))
        #expect(xtSettings.contains("预览阶段"))
    }

    @Test
    func hubInstallAndDistributionCopyDoNotReintroduceCalendarPermissionGuidance() throws {
        let root = repoRoot()
        let installDoctor = try read(
            root.appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/AppInstallDoctor.swift")
        )
        let hubUIStrings = try read(
            root.appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubUIStrings.swift")
        )
        let dmgScript = try read(
            root.appendingPathComponent("x-hub/tools/build_hub_dmg.command")
        )
        let removedCalendarPipelinePath = root.appendingPathComponent(
            "x-hub/macos/RELFlowHub/Sources/RELFlowHub/CalendarPipeline.swift"
        )

        #expect(installDoctor.contains("HubUIStrings.InstallDoctor.currentLocation"))
        #expect(hubUIStrings.contains("为了让辅助功能权限和辅助进程启动路径保持稳定"))
        #expect(hubUIStrings.contains("请把 X-Hub.app 拖到 /Applications，然后从那里重新打开。"))
        #expect(!installDoctor.contains("Calendar/Accessibility permissions"))
        #expect(!installDoctor.contains("X-Hub Dock Agent.app / X-Hub Bridge.app"))

        #expect(dmgScript.contains("Calendar reminders moved to X-Terminal Supervisor so Hub launch stays permission-free."))
        #expect(!dmgScript.contains("Calendar: turn on Calendar integration"))
        #expect(FileManager.default.fileExists(atPath: removedCalendarPipelinePath.path) == false)
    }

    @Test
    func docsAndIndexesTrackXtCalendarBoundaryAndSmokeState() throws {
        let root = repoRoot()
        let workingIndex = try read(root.appendingPathComponent("docs/WORKING_INDEX.md"))
        let workOrderReadme = try read(root.appendingPathComponent("x-terminal/work-orders/README.md"))
        let xMemory = try read(root.appendingPathComponent("X_MEMORY.md"))
        let pack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md"
            )
        )

        #expect(workingIndex.contains("xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md"))
        #expect(workingIndex.contains("Hub-side calendar de-scope is landed"))
        #expect(workingIndex.contains("XT-side preview/live reminder entrypoints are landed"))
        #expect(workingIndex.contains("real-device smoke on `X-Terminal.app`"))

        #expect(workOrderReadme.contains("xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md"))
        #expect(workOrderReadme.contains("how XT should own personal calendar reminders so Hub launch stays permission-free"))

        #expect(xMemory.contains("XT device-local calendar reminders"))
        #expect(xMemory.contains("SupervisorCalendarVoiceBridge"))
        #expect(xMemory.contains("Preview Voice Reminder / Test Notification Fallback / Simulate Live Delivery / Preview Phase"))

        #expect(pack.contains("`Hub cut-off` 已完成"))
        #expect(pack.contains("XT 打包产物已恢复"))
        #expect(pack.contains("真机手工 smoke 还未补齐"))
        #expect(pack.contains("X-Terminal.app"))
        #expect(pack.contains("Preview Phase"))
    }

    private func repoRoot() -> URL {
        monorepoTestRepoRoot(filePath: #filePath)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func plistDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        return plist
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }
}
