import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubIPCClientLocalTaskTests {
    private static let gate = HubGlobalStateTestGate.shared

    @Test
    func executeLocalTaskViaLocalHubUsesFileIPCAndMapsAck() async throws {
        try await Self.gate.run {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_hub_local_task_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try writeTestHubStatus(base: base)

            HubPaths.setPinnedBaseDirOverride(base)
            defer {
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: base)
            }

            let capture = LocalTaskRequestCapture()
            let writerTask = Task {
                let eventsDir = base.appendingPathComponent("ipc_events", isDirectory: true)
                let responsesDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
                let deadline = Date().addingTimeInterval(2.0)

                while Date() < deadline {
                    let files = (try? FileManager.default.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: nil)) ?? []
                    if let requestURL = files.first(where: { $0.lastPathComponent.hasPrefix("xterminal_local_task_") }),
                       let data = try? Data(contentsOf: requestURL),
                       let request = try? JSONDecoder().decode(HubIPCClient.LocalTaskIPCRequest.self, from: data) {
                        capture.set(request)
                        let response = HubIPCClient.LocalTaskIPCResponse(
                            type: "local_task_execute_ack",
                            reqId: request.reqId,
                            ok: true,
                            id: request.localTask.modelId,
                            error: nil,
                            localTask: HubIPCClient.LocalTaskResult(
                                ok: true,
                                source: "hub_ipc",
                                runtimeSource: "local_runtime_command",
                                provider: "transformers",
                                modelId: request.localTask.modelId,
                                taskKind: request.localTask.taskKind,
                                reasonCode: "vision_completed",
                                runtimeReasonCode: nil,
                                error: nil,
                                detail: "generated",
                                payload: [
                                    "text": .string("A red cube sits on a table."),
                                    "route_trace": .array([.string("processor_loaded"), .string("model_ran")]),
                                ]
                            )
                        )
                        let responseData = try? JSONEncoder().encode(response)
                        if let responseData {
                            let responseURL = responsesDir.appendingPathComponent("resp_\(request.reqId).json")
                            try? responseData.write(to: responseURL, options: .atomic)
                        }
                        return true
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return false
            }

            let result = HubIPCClient.executeLocalTaskViaLocalHub(
                taskKind: "vision_understand",
                modelID: "qwen2-vl-ocr-only",
                parameters: [
                    "image_path": .string("/tmp/frame.png"),
                    "prompt": .string("describe the frame"),
                    "options": .object(["locale": .string("zh-CN")]),
                ],
                deviceID: "device-vision-lane",
                timeoutSec: 1.5
            )

            let writeFinished = await writerTask.value
            #expect(writeFinished)
            let request = try #require(capture.get())
            #expect(request.type == "local_task_execute")
            #expect(request.localTask.schemaVersion == "xhub.local_task_ipc.v1")
            #expect(request.localTask.taskKind == "vision_understand")
            #expect(request.localTask.modelId == "qwen2-vl-ocr-only")
            #expect(request.localTask.deviceId == "device-vision-lane")
            #expect(request.localTask.timeoutSec == 1.5)
            #expect(request.localTask.parameters["image_path"]?.stringValue == "/tmp/frame.png")
            #expect(request.localTask.parameters["prompt"]?.stringValue == "describe the frame")
            #expect(request.localTask.parameters["options"]?.objectValue?["locale"]?.stringValue == "zh-CN")

            #expect(result.ok)
            #expect(result.source == "file_ipc")
            #expect(result.runtimeSource == "local_runtime_command")
            #expect(result.provider == "transformers")
            #expect(result.modelId == "qwen2-vl-ocr-only")
            #expect(result.taskKind == "vision_understand")
            #expect(result.reasonCode == "vision_completed")
            #expect(result.payload["text"]?.stringValue == "A red cube sits on a table.")
            #expect(result.payload["route_trace"]?.arrayValue?.compactMap(\.stringValue) == ["processor_loaded", "model_ran"])
        }
    }

    private func writeTestHubStatus(base: URL) throws {
        let eventsDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let responsesDir = base.appendingPathComponent("ipc_responses", isDirectory: true)
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)

        let status = HubStatus(
            pid: nil,
            startedAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: eventsDir.path,
            baseDir: base.path,
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: base.appendingPathComponent("hub_status.json"), options: .atomic)
    }
}

private final class LocalTaskRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: HubIPCClient.LocalTaskIPCRequest?

    func set(_ value: HubIPCClient.LocalTaskIPCRequest) {
        lock.lock()
        request = value
        lock.unlock()
    }

    func get() -> HubIPCClient.LocalTaskIPCRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}
