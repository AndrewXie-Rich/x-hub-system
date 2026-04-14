import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class RemoteModelTrialRunnerTests: XCTestCase {
    func testDisabledLookupDoesNotFailoverAcrossSiblingKeys() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        RemoteModelTrialRunner.providerCallOverride = nil
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let primary = RemoteModelEntry(
            id: "paid-model-primary",
            name: "Primary",
            backend: "openai",
            enabled: false,
            baseURL: "https://api.openai.com/v1",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-primary"
        )
        let sibling = RemoteModelEntry(
            id: "paid-model-sibling",
            name: "Sibling",
            backend: "openai",
            enabled: false,
            baseURL: "https://api.openai.com/v1",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-sibling"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [primary, sibling], updatedAt: Date().timeIntervalSince1970)
        )

        var calledIDs: [String] = []
        RemoteModelTrialRunner.providerCallOverride = { remote, _, _, _, _, _ in
            calledIDs.append(remote.id)
            return .init(ok: false, status: 429, text: "", error: "quota exceeded", usage: [:])
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: primary.id,
            allowDisabledModelLookup: true,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(calledIDs, [primary.id])
    }

    func testEnabledLookupCanFailoverAcrossSiblingKeys() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        RemoteModelTrialRunner.providerCallOverride = nil
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let primary = RemoteModelEntry(
            id: "paid-model-primary",
            name: "Primary",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-primary"
        )
        let sibling = RemoteModelEntry(
            id: "paid-model-sibling",
            name: "Sibling",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-sibling"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [primary, sibling], updatedAt: Date().timeIntervalSince1970)
        )

        var calledIDs: [String] = []
        RemoteModelTrialRunner.providerCallOverride = { remote, _, _, _, _, _ in
            calledIDs.append(remote.id)
            if remote.id == primary.id {
                return .init(ok: false, status: 429, text: "", error: "quota exceeded", usage: [:])
            }
            return .init(ok: true, status: 200, text: "HUB_OK", error: "", usage: [:])
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: primary.id,
            allowDisabledModelLookup: false,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.text, "HUB_OK")
        XCTAssertEqual(calledIDs, [primary.id, sibling.id])
    }

    func testResponsesWireAPIUsesResponsesEndpointAndPayload() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-test"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        var capturedURL: URL?
        var capturedBody: [String: Any] = [:]
        RemoteModelTrialRunner.httpDataOverride = { request in
            capturedURL = request.url
            if let data = request.httpBody,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                capturedBody = body
            }
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "id": "resp_test",
                "output": [
                    [
                        "content": [
                            [
                                "type": "output_text",
                                "text": "HUB_OK",
                            ],
                        ],
                    ],
                ],
                "usage": [
                    "input_tokens": 5,
                    "output_tokens": 2,
                    "total_tokens": 7,
                ],
            ])
            return (payload, response)
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.text, "HUB_OK")
        XCTAssertEqual(capturedURL?.absoluteString, "https://wxs.lat/openai/v1/responses")
        XCTAssertEqual(capturedBody["model"] as? String, "gpt-5.4")
        XCTAssertEqual(capturedBody["input"] as? String, "Reply with HUB_OK.")
        XCTAssertEqual(capturedBody["max_output_tokens"] as? Int, 24)
        XCTAssertNil(capturedBody["messages"])
        XCTAssertEqual(result.usage["prompt_tokens"] as? Int, 5)
        XCTAssertEqual(result.usage["completion_tokens"] as? Int, 2)
    }

    func testResponsesWireAPIIsInferredFromActiveCodexProviderConfig() async throws {
        let home = try makeTempDir()
        let codexHome = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
            unsetenv("XHUB_CODEX_HOME_OVERRIDE")
        }

        try """
        model_provider = "crs"
        model = "gpt-5.4"

        [model_providers.crs]
        base_url = "https://wxs.lat/openai"
        wire_api = "responses"
        requires_openai_auth = true
        """.write(
            to: codexHome.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-test"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        var capturedURL: URL?
        RemoteModelTrialRunner.httpDataOverride = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "output": [
                    [
                        "content": [
                            [
                                "type": "output_text",
                                "text": "HUB_OK",
                            ],
                        ],
                    ],
                ],
            ])
            return (payload, response)
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(capturedURL?.absoluteString, "https://wxs.lat/openai/v1/responses")
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
