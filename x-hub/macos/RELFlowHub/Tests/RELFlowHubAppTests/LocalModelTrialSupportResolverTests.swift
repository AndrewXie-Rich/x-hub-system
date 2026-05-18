import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalModelTrialSupportResolverTests: XCTestCase {
    func testResolveDefaultBenchSelectionForTransformersVisionModelUsesVisionFixture() throws {
        let model = makeVisionModel(modelPath: try makeModelDir().path)
        let runtimeStatus = makeReadyRuntimeStatus()
        let fakePython = try makeFakePython(
            """
            code=ok
            summary=ok
            blocking=0
            """
        )

        let result = LocalModelTrialSupportResolver.resolveDefaultBenchSelection(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: nil,
            pythonPath: fakePython.path
        )

        XCTAssertEqual(
            try result.get(),
            LocalModelDefaultBenchSelection(
                taskKind: "vision_understand",
                fixtureProfile: "vision_single_image"
            )
        )
    }

    func testResolveDefaultBenchSelectionReturnsCompatibilityFailureInsteadOfGenericBenchMessage() throws {
        let model = HubModel(
            id: "whisper-local",
            name: "Whisper Local",
            backend: "transformers",
            quant: "fp16",
            contextLength: 4096,
            paramsB: 1.0,
            state: .available,
            modelPath: try makeModelDir(modelType: "whisper").path,
            taskKinds: ["speech_to_text"]
        )
        let runtimeStatus = makeReadyRuntimeStatus(availableTaskKinds: ["speech_to_text"])
        let fakePython = try makeFakePython(
            """
            code=missing_module:torch
            summary=当前 Python 运行时缺少 torch。
            detail=Hub 只有在 torch 可用后才能加载这个 Transformers 模型。
            blocking=1
            """
        )

        let result = LocalModelTrialSupportResolver.resolveDefaultBenchSelection(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: nil,
            pythonPath: fakePython.path
        )

        switch result {
        case .success:
            XCTFail("expected failure")
        case .failure(let error):
            XCTAssertEqual(
                error.message,
                "无法加载。当前 Python 运行时缺少 torch。Hub 只有在 torch 可用后才能加载这个 Transformers 模型。"
            )
        }
    }

    func testResolveTrialRoutePrefersTextGenerateForTextModel() throws {
        let modelDir = try makeModelDir()
        let model = HubModel(
            id: "qwen3-text",
            name: "Qwen3 Text",
            backend: "mlx",
            quant: "4bit",
            contextLength: 8192,
            paramsB: 4.0,
            state: .available,
            modelPath: modelDir.path,
            taskKinds: ["text_generate"]
        )
        let runtimeStatus = AIRuntimeStatus(
            pid: 2002,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: true,
                    reasonCode: "ready",
                    availableTaskKinds: ["text_generate"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ]
        )

        let result = LocalModelTrialSupportResolver.resolveTrialRoute(
            for: model,
            runtimeStatus: runtimeStatus,
            probeLaunchConfig: nil,
            pythonPath: nil
        )

        XCTAssertEqual(try result.get(), .textGenerate)
    }

    private func makeVisionModel(modelPath: String) -> HubModel {
        HubModel(
            id: "tiny-qwen2-5-vl",
            name: "Tiny Qwen2.5 VL",
            backend: "transformers",
            quant: "bf16",
            contextLength: 32768,
            paramsB: 0.5,
            state: .available,
            modelPath: modelPath,
            taskKinds: ["vision_understand", "ocr"]
        )
    }

    private func makeReadyRuntimeStatus(
        availableTaskKinds: [String] = ["vision_understand", "ocr"]
    ) -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 2001,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "ready",
                    availableTaskKinds: ["vision_understand", "ocr"],
                    loadedModels: [],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970
                ),
            ]
        )
    }

    private func makeFakePython(_ output: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let scriptURL = root.appendingPathComponent("python3")
        let script = """
        #!/bin/sh
        cat <<'EOF'
        \(output.trimmingCharacters(in: .whitespacesAndNewlines))
        EOF
        exit 0
        """
        let data = try XCTUnwrap(script.data(using: .utf8))
        try data.write(to: scriptURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func makeModelDir(modelType: String = "qwen2_5_vl") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "model_type": modelType,
            ],
            options: [.sortedKeys]
        ).write(to: root.appendingPathComponent("config.json"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}
