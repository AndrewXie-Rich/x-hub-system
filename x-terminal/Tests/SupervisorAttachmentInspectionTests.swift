import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorAttachmentInspectionTests {
    @Test
    func appAttachmentInspectionUsesLastAttachmentInsteadOfProjectRoot() async throws {
        let manager = SupervisorManager.makeForTesting()
        let projectRoot = try makeDirectory("xt-attachment-project")
        let externalRoot = try makeDirectory("xt-attachment-external")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: externalRoot)
        }

        try "# Tank Battle\n".write(
            to: projectRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let appBundle = try makeFixtureAppBundle(in: externalRoot)
        let attachment = AXChatAttachment(
            displayName: appBundle.lastPathComponent,
            path: appBundle.path,
            kind: .directory,
            scope: .attachmentReadOnly
        )
        manager.messages = [
            SupervisorMessage(
                id: "attached-app",
                role: .user,
                content: "我拖了这个文件给 supervisor",
                isVoice: false,
                timestamp: 1,
                attachments: [attachment]
            )
        ]

        let project = makeProjectEntry(root: projectRoot, displayName: "坦克大战")
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        let userMessage = "看我刚发的附件的逆向梳理界面和能力：根据资源文件、配置、字符串，尽量列出它有哪些菜单/按钮/功能"
        let attachmentReply = try #require(
            manager.directSupervisorAttachmentInspectionReplyForTesting(userMessage)
        )
        let repoReply = await manager.directSupervisorRepoInspectionReplyForTesting(userMessage)

        #expect(attachmentReply.contains("只读方式静态检查"))
        #expect(attachmentReply.contains("Tk_Acoustic_Plot 2.app"))
        #expect(attachmentReply.contains("Contents/MacOS/Tk_Acoustic_Plot"))
        #expect(attachmentReply.contains("Info.plist"))
        #expect(attachmentReply.contains("Open CSV"))
        #expect(attachmentReply.contains("声学") || attachmentReply.lowercased().contains("acoustic"))
        #expect(repoReply == nil)
    }

    @Test
    func currentTurnAppAttachmentInspectionDoesNotNeedAttachmentWord() throws {
        let manager = SupervisorManager.makeForTesting()
        let externalRoot = try makeDirectory("xt-current-app-attachment")
        defer { try? FileManager.default.removeItem(at: externalRoot) }

        let appBundle = try makeFixtureAppBundle(in: externalRoot)
        let attachment = AXChatAttachment(
            displayName: appBundle.lastPathComponent,
            path: appBundle.path,
            kind: .directory,
            scope: .attachmentReadOnly
        )

        let reply = try #require(
            manager.directSupervisorAttachmentInspectionReplyForTesting(
                "这个app 有哪些功能？",
                currentTurnAttachments: [attachment]
            )
        )

        #expect(reply.contains("基于这些线索可谨慎判断"))
        #expect(reply.contains("曲线") || reply.lowercased().contains("plot"))
    }

    private func makeFixtureAppBundle(in root: URL) throws -> URL {
        let app = root.appendingPathComponent("Tk_Acoustic_Plot 2.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleName": "Tk_Acoustic_Plot",
            "CFBundleIdentifier": "com.example.tk-acoustic-plot",
            "CFBundleExecutable": "Tk_Acoustic_Plot",
            "CFBundlePackageType": "APPL",
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeName": "Acoustic CSV Data",
                    "CFBundleTypeExtensions": ["csv", "txt", "wav"]
                ]
            ]
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        try """
        Tkinter Acoustic Plot
        Open CSV
        Load WAV
        Plot Frequency Spectrum
        Export PNG
        """.write(
            to: resources.appendingPathComponent("ui.strings"),
            atomically: true,
            encoding: .utf8
        )
        try "Tkinter Load CSV Plot Acoustic Frequency Export".write(
            to: macOS.appendingPathComponent("Tk_Acoustic_Plot"),
            atomically: true,
            encoding: .utf8
        )
        return app
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    private func makeProjectEntry(root: URL, displayName: String) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makeDirectory(_ prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
