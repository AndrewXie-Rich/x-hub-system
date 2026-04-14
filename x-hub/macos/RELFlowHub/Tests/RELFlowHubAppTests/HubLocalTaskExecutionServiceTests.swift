import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubLocalTaskExecutionServiceTests: XCTestCase {
    override func tearDown() {
        HubLocalTaskExecutionService.resetTestingOverrides()
        super.tearDown()
    }

    func testExecuteBuildsRuntimeRequestAndMapsGenericResponse() throws {
        let model = HubModel(
            id: "qwen2-vl-ocr-only",
            name: "Qwen2 VL OCR",
            backend: "transformers",
            quant: "bf16",
            contextLength: 32_768,
            paramsB: 7.0,
            state: .available,
            modelPath: "/tmp/qwen2-vl-ocr",
            taskKinds: ["vision_understand", "ocr"],
            inputModalities: ["image"],
            outputModalities: ["text", "spans"]
        )
        let expectedLaunchConfig = LocalRuntimeCommandLaunchConfig(
            executable: "/usr/bin/python3",
            argumentsPrefix: ["runtime.py"],
            environment: ["PYTHONPATH": "/tmp/python_service"],
            baseDirPath: "/tmp"
        )

        HubLocalTaskExecutionService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            launchConfigResolver: { providerID in
                XCTAssertEqual(providerID, "transformers")
                return expectedLaunchConfig
            },
            compatibilityMessageEvaluator: { _, _ in nil },
            runtimeCommandRunner: { command, requestData, launchConfig, timeoutSec in
                XCTAssertEqual(command, "run-local-task")
                XCTAssertEqual(launchConfig.executable, expectedLaunchConfig.executable)
                XCTAssertEqual(launchConfig.argumentsPrefix, expectedLaunchConfig.argumentsPrefix)
                XCTAssertEqual(launchConfig.environment, expectedLaunchConfig.environment)
                XCTAssertEqual(launchConfig.baseDirPath, expectedLaunchConfig.baseDirPath)
                XCTAssertEqual(timeoutSec, 37.5, accuracy: 0.001)

                let request = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: requestData, options: []) as? [String: Any]
                )
                XCTAssertEqual(request["provider"] as? String, "transformers")
                XCTAssertEqual(request["model_id"] as? String, model.id)
                XCTAssertEqual(request["task_kind"] as? String, "vision_understand")
                XCTAssertEqual(request["device_id"] as? String, "device-vision-lane")
                XCTAssertEqual(request["allow_daemon_proxy"] as? Bool, false)
                XCTAssertEqual(request["image_path"] as? String, "/tmp/frame.png")
                XCTAssertEqual(request["prompt"] as? String, "describe the frame")
                let options = try XCTUnwrap(request["options"] as? [String: Any])
                XCTAssertEqual(options["locale"] as? String, "zh-CN")

                let response: [String: Any] = [
                    "ok": true,
                    "provider": "transformers",
                    "model_id": model.id,
                    "task_kind": "vision_understand",
                    "text": "A red cube sits on a table.",
                    "reason_code": "vision_completed",
                    "route_trace": ["processor_loaded", "model_ran"],
                ]
                return try JSONSerialization.data(withJSONObject: response, options: [])
            }
        )

        let result = HubLocalTaskExecutionService.execute(
            IPCLocalTaskRequestPayload(
                taskKind: "vision_understand",
                modelID: model.id,
                deviceID: "device-vision-lane",
                timeoutSec: 37.5,
                parameters: [
                    "image_path": .string("/tmp/frame.png"),
                    "prompt": .string("describe the frame"),
                    "options": .object(["locale": .string("zh-CN")]),
                ]
            )
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.source, "hub_ipc")
        XCTAssertEqual(result.runtimeSource, "local_runtime_command")
        XCTAssertEqual(result.provider, "transformers")
        XCTAssertEqual(result.modelID, model.id)
        XCTAssertEqual(result.taskKind, "vision_understand")
        XCTAssertEqual(result.reasonCode, "vision_completed")
        XCTAssertNil(result.runtimeReasonCode)
        XCTAssertEqual(result.payload["text"]?.stringValue, "A red cube sits on a table.")
        XCTAssertEqual(
            result.payload["route_trace"]?.arrayValue?.compactMap(\.stringValue),
            ["processor_loaded", "model_ran"]
        )
    }

    func testExecuteFailsClosedWhenCompatibilityBlocksRuntime() {
        let model = HubModel(
            id: "qwen2-vl-ocr-only",
            name: "Qwen2 VL OCR",
            backend: "transformers",
            quant: "bf16",
            contextLength: 32_768,
            paramsB: 7.0,
            state: .available,
            modelPath: "/tmp/qwen2-vl-ocr",
            taskKinds: ["vision_understand", "ocr"],
            inputModalities: ["image"],
            outputModalities: ["text", "spans"]
        )

        var runtimeCallCount = 0
        HubLocalTaskExecutionService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            launchConfigResolver: { _ in
                LocalRuntimeCommandLaunchConfig(
                    executable: "/usr/bin/python3",
                    argumentsPrefix: ["runtime.py"],
                    environment: [:],
                    baseDirPath: "/tmp"
                )
            },
            compatibilityMessageEvaluator: { _, _ in
                "Hub 只有在 torch 可用后才能加载这个 Transformers 模型。"
            },
            runtimeCommandRunner: { _, _, _, _ in
                runtimeCallCount += 1
                return Data()
            }
        )

        let result = HubLocalTaskExecutionService.execute(
            IPCLocalTaskRequestPayload(
                taskKind: "vision_understand",
                modelID: model.id,
                parameters: ["image_path": .string("/tmp/frame.png")]
            )
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.source, "hub_ipc")
        XCTAssertEqual(result.reasonCode, "local_task_runtime_incompatible")
        XCTAssertEqual(result.detail, "Hub 只有在 torch 可用后才能加载这个 Transformers 模型。")
        XCTAssertEqual(runtimeCallCount, 0)
    }

    func testExecuteRejectsRemoteModelBeforeRuntime() {
        let model = HubModel(
            id: "openai/gpt-5.4",
            name: "GPT 5.4",
            backend: "openai",
            quant: "n/a",
            contextLength: 200_000,
            paramsB: 0,
            state: .loaded,
            modelPath: nil,
            taskKinds: ["text_generate"],
            inputModalities: ["text"],
            outputModalities: ["text"]
        )

        var runtimeCallCount = 0
        HubLocalTaskExecutionService.installTestingOverrides(
            modelResolver: { id in
                id == model.id ? model : nil
            },
            runtimeCommandRunner: { _, _, _, _ in
                runtimeCallCount += 1
                return Data()
            }
        )

        let result = HubLocalTaskExecutionService.execute(
            IPCLocalTaskRequestPayload(
                taskKind: "text_generate",
                modelID: model.id,
                parameters: ["prompt": .string("hello")]
            )
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.reasonCode, "local_task_model_ineligible")
        XCTAssertEqual(runtimeCallCount, 0)
    }
}
