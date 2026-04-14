import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct AXChatAttachmentSupportTests {
    init() {
        AXChatAttachmentLocalModelPreview.resetTestingOverrides()
    }

    @Test
    func resolveDroppedURLsMarksProjectAndExternalScopes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-attachment-project-\(UUID().uuidString)", isDirectory: true)
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-attachment-external-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)

        let projectFile = root.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(
            at: projectFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("print(\"hi\")".utf8).write(to: projectFile, options: .atomic)

        let externalFile = externalDir.appendingPathComponent("Notes.txt")
        try Data("todo".utf8).write(to: externalFile, options: .atomic)

        let attachments = AXChatAttachmentSupport.resolveDroppedURLs(
            [projectFile, externalFile],
            projectRoot: root
        )

        #expect(attachments.count == 2)
        #expect(attachments.first(where: { $0.path == projectFile.path })?.scope == .projectWorkspace)
        #expect(attachments.first(where: { $0.path == projectFile.path })?.relativePath == "Sources/App.swift")
        #expect(attachments.first(where: { $0.path == externalFile.path })?.scope == .attachmentReadOnly)
        #expect(attachments.first(where: { $0.path == externalFile.path })?.relativePath == nil)
    }

    @Test
    func importAttachmentCopiesIntoImportedAttachmentsDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-attachment-import-project-\(UUID().uuidString)", isDirectory: true)
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-attachment-import-external-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: externalDir)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)

        let externalFile = externalDir.appendingPathComponent("Draft.md")
        try Data("# hello".utf8).write(to: externalFile, options: .atomic)

        let attachment = try #require(
            AXChatAttachmentSupport.resolveAttachment(
                url: externalFile,
                projectRoot: root
            )
        )

        let result = try AXChatAttachmentSupport.importAttachment(attachment, into: root)

        #expect(result.importedAttachment.scope == .projectWorkspace)
        #expect(result.importedAttachment.relativePath?.hasPrefix("Imported Attachments/") == true)
        #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
        #expect(result.destinationURL.path != externalFile.path)
    }

    @Test
    func importContinuationSuggestionForCodeFileUsesCodeSpecificLanguage() {
        let imported = AXChatAttachment(
            displayName: "Worker.swift",
            path: "/tmp/project/Imported Attachments/Worker.swift",
            relativePath: "Imported Attachments/Worker.swift",
            kind: .file,
            scope: .projectWorkspace
        )
        let result = AXChatAttachmentImportResult(
            sourceAttachment: AXChatAttachment(
                displayName: "Worker.swift",
                path: "/tmp/external/Worker.swift",
                kind: .file,
                scope: .attachmentReadOnly
            ),
            importedAttachment: imported,
            destinationURL: URL(fileURLWithPath: imported.path)
        )

        let suggestion = AXChatAttachmentSupport.importContinuationSuggestion(results: [result])

        #expect(suggestion?.headline == "代码文件已进入项目")
        #expect(suggestion?.detail.contains("项目内副本") == true)
        #expect(suggestion?.placementHint.contains("Sources/") == true)
        #expect(suggestion?.linkedFilesHint.contains("同名测试") == true)
        #expect(suggestion?.suggestedPrompt.contains("角色和影响范围") == true)
        #expect(suggestion?.suggestedPrompt.contains("Imported Attachments/Worker.swift") == true)
    }

    @Test
    func normalizedUserPromptFallsBackToAttachmentPromptWhenDraftIsEmpty() {
        let attachment = AXChatAttachment(
            displayName: "Notes.txt",
            path: "/tmp/Notes.txt",
            kind: .file,
            scope: .attachmentReadOnly
        )

        #expect(
            AXChatAttachmentSupport.normalizedUserPrompt(
                draft: "   \n",
                attachments: [attachment]
            ) == "请先阅读并理解我附带的文件。"
        )
        #expect(
            AXChatAttachmentSupport.hasSubmittableContent(
                draft: "",
                attachments: [attachment]
            )
        )
    }

    @Test
    func importSuccessNoticeAndContinuationForMixedFilesSummarizeBatch() {
        let importedDoc = AXChatAttachment(
            displayName: "Spec.md",
            path: "/tmp/project/Imported Attachments/Spec.md",
            relativePath: "Imported Attachments/Spec.md",
            kind: .file,
            scope: .projectWorkspace
        )
        let importedAsset = AXChatAttachment(
            displayName: "Mockup.png",
            path: "/tmp/project/Imported Attachments/Mockup.png",
            relativePath: "Imported Attachments/Mockup.png",
            kind: .file,
            scope: .projectWorkspace
        )
        let results = [
            AXChatAttachmentImportResult(
                sourceAttachment: AXChatAttachment(
                    displayName: "Spec.md",
                    path: "/tmp/external/Spec.md",
                    kind: .file,
                    scope: .attachmentReadOnly
                ),
                importedAttachment: importedDoc,
                destinationURL: URL(fileURLWithPath: importedDoc.path)
            ),
            AXChatAttachmentImportResult(
                sourceAttachment: AXChatAttachment(
                    displayName: "Mockup.png",
                    path: "/tmp/external/Mockup.png",
                    kind: .file,
                    scope: .attachmentReadOnly
                ),
                importedAttachment: importedAsset,
                destinationURL: URL(fileURLWithPath: importedAsset.path)
            )
        ]

        let notice = AXChatAttachmentSupport.importSuccessNotice(results: results)
        let suggestion = AXChatAttachmentSupport.importContinuationSuggestion(results: results)

        #expect(notice?.contains("Import & Continue") == true)
        #expect(notice?.contains("2 个附件") == true)
        #expect(suggestion?.headline == "2 个文件已进入项目")
        #expect(suggestion?.placementHint.contains("Imported Attachments/") == true)
        #expect(suggestion?.linkedFilesHint.contains("README") == true)
        #expect(suggestion?.suggestedPrompt.contains("按代码、配置、文档或资源分类") == true)
    }

    @Test
    func importContinuationSuggestionUsesWorkspaceAwareHintsWhenProjectLayoutExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-attachment-hints-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Tests", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("docs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("// package".utf8).write(
            to: root.appendingPathComponent("Package.swift"),
            options: .atomic
        )
        try Data("# readme".utf8).write(
            to: root.appendingPathComponent("README.md"),
            options: .atomic
        )

        let imported = AXChatAttachment(
            displayName: "Worker.swift",
            path: root.appendingPathComponent("Imported Attachments/Worker.swift").path,
            relativePath: "Imported Attachments/Worker.swift",
            kind: .file,
            scope: .projectWorkspace
        )
        let result = AXChatAttachmentImportResult(
            sourceAttachment: AXChatAttachment(
                displayName: "Worker.swift",
                path: "/tmp/external/Worker.swift",
                kind: .file,
                scope: .attachmentReadOnly
            ),
            importedAttachment: imported,
            destinationURL: URL(fileURLWithPath: imported.path)
        )

        let suggestion = AXChatAttachmentSupport.importContinuationSuggestion(
            results: [result],
            projectRoot: root
        )

        #expect(suggestion?.placementHint.contains("`Sources/`") == true)
        #expect(suggestion?.linkedFilesHint.contains("`Tests/`") == true)
        #expect(suggestion?.linkedFilesHint.contains("`README.md`") == true)
        #expect(suggestion?.linkedFilesHint.contains("`Package.swift`") == true)
    }

    @Test
    func promptSummaryUsesLocalHubVisionPreviewForCurrentImageAttachment() async throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-preview-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL, options: .atomic)

        let attachment = AXChatAttachment(
            displayName: "Screenshot.png",
            path: imageURL.path,
            kind: .file,
            scope: .attachmentReadOnly
        )
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "qwen2-vl",
                    name: "Qwen2 VL",
                    backend: "transformers",
                    quant: "bf16",
                    contextLength: 32_768,
                    paramsB: 7.0,
                    state: .loaded,
                    modelPath: "/tmp/qwen2-vl",
                    taskKinds: ["vision_understand"],
                    inputModalities: ["image"],
                    outputModalities: ["text"]
                )
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        AXChatAttachmentLocalModelPreview.installTestingOverrides(
            snapshotLoader: { snapshot },
            localTaskExecutor: { taskKind, modelID, parameters, _ in
                #expect(taskKind == "vision_understand")
                #expect(modelID == "qwen2-vl")
                #expect(parameters["image_path"]?.stringValue == imageURL.path)
                return HubIPCClient.LocalTaskResult(
                    ok: true,
                    source: "file_ipc",
                    runtimeSource: "local_runtime_command",
                    provider: "transformers",
                    modelId: modelID,
                    taskKind: taskKind,
                    reasonCode: "vision_completed",
                    payload: [
                        "text": .string("A login screen with two fields and a submit button.")
                    ]
                )
            }
        )

        let overrides = await AXChatAttachmentLocalModelPreview.previewOverrides(for: [attachment])
        let summary = AXChatAttachmentSupport.promptSummary(
            currentTurnAttachments: [attachment],
            activeAttachments: [attachment],
            projectRoot: nil,
            previewOverrides: overrides
        )

        #expect(summary.contains("image summary: A login screen with two fields and a submit button.") == true)
        #expect(summary.contains("(binary file preview unavailable") == false)
    }

    @Test
    func promptSummaryFallsBackToOCRWhenOnlyOCRModelIsAvailable() async throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL, options: .atomic)

        let attachment = AXChatAttachment(
            displayName: "Receipt.png",
            path: imageURL.path,
            kind: .file,
            scope: .attachmentReadOnly
        )
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "ocr-only",
                    name: "OCR Only",
                    backend: "transformers",
                    quant: "bf16",
                    contextLength: 8_192,
                    paramsB: 3.0,
                    state: .loaded,
                    modelPath: "/tmp/ocr-only",
                    taskKinds: ["ocr"],
                    inputModalities: ["image"],
                    outputModalities: ["text", "spans"]
                )
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        AXChatAttachmentLocalModelPreview.installTestingOverrides(
            snapshotLoader: { snapshot },
            localTaskExecutor: { taskKind, modelID, _, _ in
                #expect(taskKind == "ocr")
                #expect(modelID == "ocr-only")
                return HubIPCClient.LocalTaskResult(
                    ok: true,
                    source: "file_ipc",
                    runtimeSource: "local_runtime_command",
                    provider: "transformers",
                    modelId: modelID,
                    taskKind: taskKind,
                    reasonCode: "ocr_completed",
                    payload: [
                        "text": .string("Total 18.50"),
                        "language": .string("en")
                    ]
                )
            }
        )

        let overrides = await AXChatAttachmentLocalModelPreview.previewOverrides(for: [attachment])
        let summary = AXChatAttachmentSupport.promptSummary(
            currentTurnAttachments: [attachment],
            activeAttachments: [attachment],
            projectRoot: nil,
            previewOverrides: overrides
        )

        #expect(summary.contains("ocr text (en): Total 18.50") == true)
        #expect(summary.contains("(binary file preview unavailable") == false)
    }
}
