import XCTest
@testable import RELFlowHub

final class RemoteProviderClientTests: XCTestCase {
    override func tearDown() {
        unsetenv("XHUB_CODEX_HOME_OVERRIDE")
        super.tearDown()
    }

    func testModelIdsSupportsTopLevelModelsArray() {
        let payload: [String: Any] = [
            "models": [
                ["id": "gpt-5.2"],
                ["id": "gpt-5.3-codex"],
            ]
        ]

        let ids = RemoteProviderClient.modelIds(from: payload, backend: "openai")

        XCTAssertEqual(ids, ["gpt-5.2", "gpt-5.3-codex"])
    }

    func testModelIdsSupportsTopLevelArrayPayload() {
        let payload: [Any] = [
            ["model_id": "openai/gpt-5.2"],
            ["model_id": "openai/gpt-5.3-codex"],
        ]

        let ids = RemoteProviderClient.modelIds(from: payload, backend: "openai_compatible")

        XCTAssertEqual(ids, ["openai/gpt-5.2", "openai/gpt-5.3-codex"])
    }

    func testProviderAuthImportReadsOpenAIKeyFromAuthJSON() throws {
        let data = Data(#"{"OPENAI_API_KEY":"sk-test-123456789012345678901234","OPENAI_BASE_URL":"https://api.openai.com/v1"}"#.utf8)

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.backend, "openai")
        XCTAssertEqual(imported.apiKey, "sk-test-123456789012345678901234")
        XCTAssertEqual(imported.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(imported.apiKeyRef, "openai:api.openai.com")
        XCTAssertEqual(imported.wireAPI, "")
        XCTAssertEqual(imported.kind, .apiKey)
    }

    func testProviderAuthImportReadsChatGPTTokenBundleAsOpenAIResponsesCredentials() throws {
        let data = Data(#"""
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": {
            "access_token": "ey-test-access-token"
          }
        }
        """#.utf8)

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.backend, "openai")
        XCTAssertEqual(imported.apiKey, "ey-test-access-token")
        XCTAssertEqual(imported.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(imported.apiKeyRef, "openai:api.openai.com")
        XCTAssertEqual(imported.wireAPI, "responses")
        XCTAssertEqual(imported.kind, .chatGPTTokenBundle)
    }

    func testProviderConfigImportPrefersConfiguredModelProvider() throws {
        let text = """
        model_provider = "packycode"

        [model_providers.codex]
        base_url = "https://code.ppchat.vip/v1"
        requires_openai_auth = true

        [model_providers.packycode]
        base_url = "https://codex-api.packycode.com/v1"
        requires_openai_auth = true
        """

        let imported = try ProviderConfigImport.parse(text: text)

        XCTAssertEqual(imported.providerName, "packycode")
        XCTAssertEqual(imported.backend, "openai_compatible")
        XCTAssertEqual(imported.baseURL, "https://codex-api.packycode.com/v1")
        XCTAssertEqual(imported.apiKeyRef, "openai_compatible:codex-api.packycode.com")
        XCTAssertEqual(imported.preferredModelID, "")
        XCTAssertEqual(imported.wireAPI, "")
        XCTAssertEqual(imported.source, .explicitProvider)
    }

    func testProviderConfigImportReadsPreferredModel() throws {
        let text = """
        model_provider = "packycode"
        model = "gpt-5.4"

        [model_providers.packycode]
        base_url = "https://codex-api.packycode.com/v1"
        requires_openai_auth = true
        """

        let imported = try ProviderConfigImport.parse(text: text)

        XCTAssertEqual(imported.preferredModelID, "gpt-5.4")
    }

    func testProviderConfigImportReadsResponsesWireAPI() throws {
        let text = """
        model_provider = "crs"
        model = "gpt-5.4"

        [model_providers.crs]
        base_url = "https://wxs.lat/openai"
        wire_api = "responses"
        requires_openai_auth = true
        """

        let imported = try ProviderConfigImport.parse(text: text)

        XCTAssertEqual(imported.providerName, "crs")
        XCTAssertEqual(imported.baseURL, "https://wxs.lat/openai")
        XCTAssertEqual(imported.preferredModelID, "gpt-5.4")
        XCTAssertEqual(imported.wireAPI, "responses")
        XCTAssertEqual(imported.source, .explicitProvider)
    }

    func testProviderConfigImportRecognizesMinimalCodexConfigAsOpenAIResponses() throws {
        let text = """
        model = "gpt-5.4"
        model_reasoning_effort = "xhigh"

        [projects."/Users/andrew.xie/Documents/AX"]
        trust_level = "trusted"
        """

        let imported = try ProviderConfigImport.parse(text: text)

        XCTAssertEqual(imported.providerName, "openai")
        XCTAssertEqual(imported.backend, "openai")
        XCTAssertEqual(imported.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(imported.apiKeyRef, "openai:api.openai.com")
        XCTAssertEqual(imported.preferredModelID, "gpt-5.4")
        XCTAssertEqual(imported.wireAPI, "responses")
        XCTAssertEqual(imported.source, .fallbackOpenAI)
    }

    func testCodexProviderImportResolverUsesActiveCodexProviderForChatGPTTokenBundle() throws {
        let codexHome = try makeTempCodexHome()
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
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)

        let importRoot = try makeTempImportDir()
        try """
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": {
            "access_token": "ey-test-access-token"
          }
        }
        """.write(
            to: importRoot.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        model = "gpt-5.4"
        model_reasoning_effort = "xhigh"
        """.write(
            to: importRoot.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let resolved = try CodexProviderImportResolver.resolveAuthImport(
            from: importRoot.appendingPathComponent("auth.json")
        )

        let credentials = try XCTUnwrap(resolved.credentials)
        let providerConfig = try XCTUnwrap(resolved.providerConfig)
        XCTAssertEqual(credentials.kind, .chatGPTTokenBundle)
        XCTAssertEqual(credentials.backend, "openai_compatible")
        XCTAssertEqual(credentials.baseURL, "https://wxs.lat/openai")
        XCTAssertEqual(credentials.apiKeyRef, "openai_compatible:wxs.lat")
        XCTAssertEqual(credentials.wireAPI, "responses")
        XCTAssertEqual(providerConfig.baseURL, "https://wxs.lat/openai")
        XCTAssertEqual(providerConfig.source, .explicitProvider)
    }

    func testCodexProviderImportResolverLoadsSiblingAuthDuringConfigImport() throws {
        let importRoot = try makeTempImportDir()
        try """
        {
          "OPENAI_API_KEY": "sk-import-123",
          "OPENAI_BASE_URL": "https://ignored.example/v1"
        }
        """.write(
            to: importRoot.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        model_provider = "crs"
        model = "gpt-5.4"

        [model_providers.crs]
        base_url = "https://wxs.lat/openai"
        wire_api = "responses"
        requires_openai_auth = true
        """.write(
            to: importRoot.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let resolved = try CodexProviderImportResolver.resolveConfigImport(
            from: importRoot.appendingPathComponent("config.toml")
        )

        let credentials = try XCTUnwrap(resolved.credentials)
        let providerConfig = try XCTUnwrap(resolved.providerConfig)
        XCTAssertEqual(credentials.kind, .apiKey)
        XCTAssertEqual(credentials.apiKey, "sk-import-123")
        XCTAssertEqual(credentials.backend, "openai_compatible")
        XCTAssertEqual(credentials.baseURL, "https://wxs.lat/openai")
        XCTAssertEqual(credentials.apiKeyRef, "openai_compatible:wxs.lat")
        XCTAssertEqual(credentials.wireAPI, "responses")
        XCTAssertEqual(providerConfig.preferredModelID, "gpt-5.4")
    }

    func testRemoteProviderClientFallsBackToCodexCatalogWhenModelReadScopeMissing() throws {
        let codexHome = try makeTempCodexHome()
        let config = """
        model_provider = "crs"
        model = "gpt-5.4"

        [model_providers.crs]
        base_url = "https://aispeed.store/openai"
        requires_openai_auth = true
        """
        let modelsCache = """
        {
          "models": [
            {"slug": "gpt-5.4", "supported_in_api": true},
            {"slug": "gpt-5.3-codex", "supported_in_api": true}
          ]
        }
        """
        try config.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try modelsCache.write(to: codexHome.appendingPathComponent("models_cache.json"), atomically: true, encoding: .utf8)
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)

        let ids = RemoteProviderClient.fallbackModelIdsIfApplicable(
            backend: "openai_compatible",
            baseURL: "https://aispeed.store/openai",
            error: RemoteProviderClient.ProviderError.httpError(
                status: 403,
                body: #"{"error":"Missing scopes: api.model.read"}"#
            )
        )

        XCTAssertEqual(ids, ["gpt-5.4", "gpt-5.3-codex"])
    }

    func testCodexModelCatalogFallbackPrefersConfiguredModelBeforeCachedModels() throws {
        let codexHome = try makeTempCodexHome()
        let config = """
        model_provider = "crs"
        model = "gpt-5.4"

        [model_providers.crs]
        base_url = "https://aispeed.store/openai"
        requires_openai_auth = true

        [notice.model_migrations]
        gpt-5-codex = "gpt-5.3-codex"
        """
        let modelsCache = """
        {
          "models": [
            {"slug": "gpt-5.3-codex", "supported_in_api": true},
            {"slug": "gpt-5.2", "supported_in_api": true},
            {"slug": "gpt-5.1", "supported_in_api": true}
          ]
        }
        """
        try config.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try modelsCache.write(to: codexHome.appendingPathComponent("models_cache.json"), atomically: true, encoding: .utf8)
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)

        let ids = CodexModelCatalogFallback.modelIDs(
            backend: "openai_compatible",
            baseURL: "https://aispeed.store/openai"
        )

        XCTAssertEqual(ids, ["gpt-5.4", "gpt-5.3-codex", "gpt-5.2", "gpt-5.1"])
    }

    func testRemoteProviderClientFallsBackToCodexCatalogWhenModelsEndpointUnsupported() throws {
        let codexHome = try makeTempCodexHome()
        let config = """
        model_provider = "crs"
        model = "gpt-5.4"

        [model_providers.crs]
        base_url = "https://aispeed.store/openai"
        requires_openai_auth = true
        """
        let modelsCache = """
        {
          "models": [
            {"slug": "gpt-5.3-codex", "supported_in_api": true},
            {"slug": "gpt-5.2", "supported_in_api": true}
          ]
        }
        """
        try config.write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try modelsCache.write(to: codexHome.appendingPathComponent("models_cache.json"), atomically: true, encoding: .utf8)
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)

        let ids = RemoteProviderClient.fallbackModelIdsIfApplicable(
            backend: "openai_compatible",
            baseURL: "https://aispeed.store/openai",
            error: RemoteProviderClient.ProviderError.httpError(status: 404, body: "")
        )

        XCTAssertEqual(ids, ["gpt-5.4", "gpt-5.3-codex", "gpt-5.2"])
    }

    func testRemoteProviderClientDoesNotFallbackForUnauthorizedModelsEndpoint() throws {
        let codexHome = try makeTempCodexHome()
        try "{}".write(to: codexHome.appendingPathComponent("models_cache.json"), atomically: true, encoding: .utf8)
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)

        let ids = RemoteProviderClient.fallbackModelIdsIfApplicable(
            backend: "openai_compatible",
            baseURL: "https://aispeed.store/openai",
            error: RemoteProviderClient.ProviderError.httpError(status: 401, body: "")
        )

        XCTAssertTrue(ids.isEmpty)
    }

    func testProviderImportErrorsStayUserFacing() {
        XCTAssertEqual(
            ProviderAuthImport.ImportError.unsupportedFormat.errorDescription,
            "不支持这种 auth.json 格式。"
        )
        XCTAssertEqual(
            ProviderConfigImport.ImportError.noSupportedProvider.errorDescription,
            "这个配置里没有找到带 base_url 的 OpenAI 鉴权 provider。"
        )
        XCTAssertEqual(
            RemoteProviderClient.ProviderError.httpError(status: 503, body: "").errorDescription,
            "Provider 请求失败（status=503）。"
        )
        XCTAssertEqual(
            RemoteProviderClient.ProviderError.bridgeFailure(reason: "gateway timeout").errorDescription,
            "Bridge 请求失败：gateway timeout"
        )
    }

    func testProviderHTTPErrorHighlightsQuotaExhaustion() {
        let description = RemoteProviderClient.ProviderError.httpError(
            status: 429,
            body: "You exceeded your current quota, please check your plan and billing details."
        ).errorDescription

        XCTAssertEqual(
            description,
            "Provider 配额不足或额度已用尽（status=429）：You exceeded your current quota, please check your plan and billing details."
        )
    }

    func testProviderHTTPErrorHighlightsRateLimit() {
        let description = RemoteProviderClient.ProviderError.httpError(
            status: 429,
            body: "Rate limit reached for requests per min."
        ).errorDescription

        XCTAssertEqual(
            description,
            "Provider 当前正在限流，请稍后重试（status=429）：Rate limit reached for requests per min."
        )
    }

    func testProviderHTTPErrorHighlightsUsageLimitRetryTime() {
        let description = RemoteProviderClient.ProviderError.httpError(
            status: 429,
            body: "You've hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Apr 15th, 2026 8:58 AM."
        ).errorDescription

        XCTAssertEqual(
            description,
            "当前额度已用完，可升级 Plus，或到 Apr 15th, 2026 8:58 AM 再试。"
        )
    }

    func testProviderHTTPErrorHighlightsRateLimitResetRetryTime() {
        let description = RemoteProviderClient.ProviderError.httpError(
            status: 429,
            body: "Your rate limit resets on Apr 15, 2026, 8:58 AM. To continue using Codex, upgrade to Plus today."
        ).errorDescription

        XCTAssertEqual(
            description,
            "当前额度已用完，可升级 Plus，或到 Apr 15, 2026, 8:58 AM 再试。"
        )
    }

    func testProviderHTTPErrorHighlightsMissingResponsesWriteScope() {
        let description = RemoteProviderClient.ProviderError.httpError(
            status: 403,
            body: #"{"error":"You have insufficient permissions for this operation. Missing scopes: api.responses.write. Check that you have the correct role."}"#
        ).errorDescription

        XCTAssertEqual(
            description,
            "Provider 权限不足，缺少生成 scope：api.responses.write。请更换具备 Responses 写权限的 key。"
        )
    }

    func testBridgeFailureHumanizesRemoteModelNotFound() {
        let description = RemoteProviderClient.ProviderError.bridgeFailure(
            reason: "remote_model_not_found"
        ).errorDescription

        XCTAssertEqual(
            description,
            "Bridge 请求失败：Hub 当前没有把这个远程模型挂到可执行面。请先 Load 再试。"
        )
    }

    private func makeTempCodexHome() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("relflowhub-codex-home-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTempImportDir() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("relflowhub-provider-import-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
