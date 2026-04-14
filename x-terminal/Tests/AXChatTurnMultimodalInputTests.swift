import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AXChatTurnMultimodalInputTests {
    init() {
        AXChatTurnMultimodalInput.resetTestingOverrides()
        ChatSessionModel.resetLLMGenerateOverrideForTesting()
    }

    @Test
    func summaryRoutesOCRStylePromptAcrossMultipleImages() async throws {
        let imageA = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-turn-ocr-\(UUID().uuidString)-A.png")
        let imageB = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-turn-ocr-\(UUID().uuidString)-B.png")
        defer {
            try? FileManager.default.removeItem(at: imageA)
            try? FileManager.default.removeItem(at: imageB)
        }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageA, options: .atomic)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageB, options: .atomic)

        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "vision-local",
                    name: "Vision Local",
                    backend: "transformers",
                    quant: "bf16",
                    contextLength: 32_768,
                    paramsB: 7.0,
                    state: .loaded,
                    modelPath: "/tmp/vision-local",
                    taskKinds: ["vision_understand", "ocr"],
                    inputModalities: ["image"],
                    outputModalities: ["text", "spans"]
                )
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        AXChatTurnMultimodalInput.installTestingOverrides(
            snapshotLoader: { snapshot },
            localTaskExecutor: { taskKind, modelID, parameters, _ in
                #expect(taskKind == "ocr")
                #expect(modelID == "vision-local")
                #expect(parameters["image_paths"]?.stringArrayValue == [imageA.path, imageB.path])
                let messages = parameters["multimodal_messages"]?.arrayValue
                #expect(messages != nil)
                let firstMessage = messages?.first?.objectValue
                #expect(firstMessage?["role"]?.stringValue == "user")
                let content = firstMessage?["content"]?.arrayValue
                #expect(content?.count == 3)
                return HubIPCClient.LocalTaskResult(
                    ok: true,
                    source: "file_ipc",
                    runtimeSource: "local_runtime_command",
                    provider: "transformers",
                    modelId: modelID,
                    taskKind: taskKind,
                    reasonCode: "ocr_completed",
                    payload: [
                        "text": .string("[page 1] 牛奶 3.50\n\n[page 2] 面包 5.20"),
                        "spans": .array([
                            .object([
                                "fileName": .string(imageA.lastPathComponent),
                                "pageIndex": .number(0),
                                "pageCount": .number(2),
                                "text": .string("牛奶 3.50")
                            ]),
                            .object([
                                "fileName": .string(imageB.lastPathComponent),
                                "pageIndex": .number(1),
                                "pageCount": .number(2),
                                "text": .string("面包 5.20")
                            ])
                        ]),
                        "routeTrace": .object([
                            "selectionReason": .string("ocr_prompt_heuristic")
                        ])
                    ]
                )
            }
        )

        let summary = try #require(
            await AXChatTurnMultimodalInput.summary(
                userText: "请提取这两张图里的所有文字",
                attachments: [
                    AXChatAttachment(
                        displayName: imageA.lastPathComponent,
                        path: imageA.path,
                        kind: .file,
                        scope: .attachmentReadOnly
                    ),
                    AXChatAttachment(
                        displayName: imageB.lastPathComponent,
                        path: imageB.path,
                        kind: .file,
                        scope: .attachmentReadOnly
                    )
                ]
            )
        )

        #expect(summary.contains("task_kind=ocr") == true)
        #expect(summary.contains("selection_reason=ocr_prompt_heuristic") == true)
        #expect(summary.contains("page_spans:") == true)
        #expect(summary.contains("牛奶 3.50") == true)
        #expect(summary.contains("面包 5.20") == true)
    }

    @Test
    func chatPromptIncludesCurrentTurnMultimodalInputBlock() async throws {
        let root = try makeProjectRoot(named: "multimodal-turn-prompt")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-turn-vision-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL, options: .atomic)

        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "vision-local",
                    name: "Vision Local",
                    backend: "transformers",
                    quant: "bf16",
                    contextLength: 32_768,
                    paramsB: 7.0,
                    state: .loaded,
                    modelPath: "/tmp/vision-local",
                    taskKinds: ["vision_understand"],
                    inputModalities: ["image"],
                    outputModalities: ["text"]
                )
            ],
            updatedAt: Date().timeIntervalSince1970
        )

        AXChatTurnMultimodalInput.installTestingOverrides(
            snapshotLoader: { snapshot },
            localTaskExecutor: { taskKind, modelID, _, _ in
                #expect(taskKind == "vision_understand")
                #expect(modelID == "vision-local")
                return HubIPCClient.LocalTaskResult(
                    ok: true,
                    source: "file_ipc",
                    runtimeSource: "local_runtime_command",
                    provider: "transformers",
                    modelId: modelID,
                    taskKind: taskKind,
                    reasonCode: "vision_completed",
                    payload: [
                        "text": .string("The image shows a login form with email and password fields."),
                        "routeTrace": .object([
                            "selectionReason": .string("model_only_vision_understand")
                        ])
                    ]
                )
            }
        )

        ChatSessionModel.installLLMGenerateOverrideForTesting { _, prompt, _ in
            #expect(prompt.contains("Current-turn multimodal inputs:") == true)
            #expect(prompt.contains("task_kind=vision_understand") == true)
            #expect(prompt.contains("The image shows a login form") == true)
            return "{\"final\":\"已看到多模态块。\"}"
        }

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: ctx)
        session.handleDroppedFiles([imageURL], ctx: ctx)
        session.draft = "请根据这张图说明界面结构。"

        session.send(
            ctx: ctx,
            memory: nil,
            config: AXProjectConfig.default(forProjectRoot: root),
            router: LLMRouter(settingsStore: SettingsStore())
        )

        try await waitUntil(timeoutMs: 3_000) {
            session.isSending == false && session.messages.last?.role == .assistant
        }

        #expect(session.messages.last?.content.contains("已看到多模态块") == true)
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_turn_multimodal_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitUntil(timeoutMs: UInt64, condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(
            domain: "xterminal.tests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "condition_not_met_before_timeout"]
        )
    }
}
