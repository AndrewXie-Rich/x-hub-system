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
        XCTAssertEqual(imported.refreshToken, "")
        XCTAssertEqual(imported.authType, "api_key")
        XCTAssertEqual(imported.kind, .apiKey)
    }

    func testProviderAuthImportReadsChatGPTTokenBundleAsOpenAIChatCompletionsCredentials() throws {
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
        XCTAssertEqual(imported.wireAPI, "chat_completions")
        XCTAssertEqual(imported.authType, "api_key")
        XCTAssertEqual(imported.kind, .chatGPTTokenBundle)
    }

    func testProviderAuthImportReadsWrappedChatGPTTokenBundleFromDataEnvelope() throws {
        let data = Data(#"""
        {
          "data": {
            "auth_mode": "chatgpt",
            "tokens": {
              "access_token": "ey-wrapped-access-token"
            }
          }
        }
        """#.utf8)

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.backend, "openai")
        XCTAssertEqual(imported.apiKey, "ey-wrapped-access-token")
        XCTAssertEqual(imported.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(imported.apiKeyRef, "openai:api.openai.com")
        XCTAssertEqual(imported.wireAPI, "chat_completions")
        XCTAssertEqual(imported.authType, "api_key")
        XCTAssertEqual(imported.kind, .chatGPTTokenBundle)
    }

    func testProviderAuthImportKeepsRefreshTokenAndAccountMetadataForChatGPTBundle() throws {
        let idTokenPayload = Data(#"{"email":"person@example.com","chatgpt_account_id":"acct-42","exp":4102444800}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let idToken = "eyJhbGciOiJub25lIn0.\(idTokenPayload)."
        let data = Data(
            """
            {
              "auth_mode": "chatgpt",
              "tokens": {
                "id_token": "\(idToken)",
                "access_token": "ey-live-access-token",
                "refresh_token": "refresh-live-token",
                "account_id": "acct-42"
              }
            }
            """.utf8
        )

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.apiKey, "ey-live-access-token")
        XCTAssertEqual(imported.refreshToken, "refresh-live-token")
        XCTAssertEqual(imported.authType, "oauth")
        XCTAssertEqual(imported.email, "person@example.com")
        XCTAssertEqual(imported.accountID, "acct-42")
        XCTAssertEqual(imported.oauthSourceKey, "chatgpt")
        XCTAssertGreaterThan(imported.expiresAtMs, 0)
    }

    func testProviderAuthImportReadsLegacyCodexTokenFile() throws {
        let data = Data(#"""
        {
          "type": "codex",
          "access_token": "ey-legacy-access-token",
          "base_url": "https://api.openai.com/v1"
        }
        """#.utf8)

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.backend, "openai")
        XCTAssertEqual(imported.apiKey, "ey-legacy-access-token")
        XCTAssertEqual(imported.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(imported.apiKeyRef, "openai:api.openai.com")
        XCTAssertEqual(imported.wireAPI, "chat_completions")
        XCTAssertEqual(imported.kind, .chatGPTTokenBundle)
    }

    func testProviderAuthImportReadsClaudeOAuthBundle() throws {
        let data = Data(#"""
        {
          "type": "claude",
          "access_token": "claude-access-token",
          "refresh_token": "claude-refresh-token",
          "email": "claude-user@example.com",
          "expired": "2026-05-01T00:00:00Z"
        }
        """#.utf8)

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.backend, "anthropic")
        XCTAssertEqual(imported.apiKey, "claude-access-token")
        XCTAssertEqual(imported.refreshToken, "claude-refresh-token")
        XCTAssertEqual(imported.baseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(imported.apiKeyRef, "anthropic:api.anthropic.com")
        XCTAssertEqual(imported.authType, "oauth")
        XCTAssertEqual(imported.email, "claude-user@example.com")
        XCTAssertEqual(imported.oauthSourceKey, "claude")
        XCTAssertGreaterThan(imported.expiresAtMs, 0)
    }

    func testProviderAuthImportReadsGeminiOAuthBundleFromNestedToken() throws {
        let data = Data(#"""
        {
          "type": "gemini",
          "email": "gemini-user@example.com",
          "project_id": "proj-123",
          "token": {
            "access_token": "ya29.nested-access-token",
            "refresh_token": "gemini-refresh-token",
            "expires_at": 4102444800
          }
        }
        """#.utf8)

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.backend, "gemini")
        XCTAssertEqual(imported.apiKey, "ya29.nested-access-token")
        XCTAssertEqual(imported.refreshToken, "gemini-refresh-token")
        XCTAssertEqual(imported.baseURL, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertEqual(imported.apiKeyRef, "gemini:generativelanguage.googleapis.com")
        XCTAssertEqual(imported.authType, "oauth")
        XCTAssertEqual(imported.email, "gemini-user@example.com")
        XCTAssertEqual(imported.accountID, "proj-123")
        XCTAssertEqual(imported.oauthSourceKey, "gemini")
        XCTAssertGreaterThan(imported.expiresAtMs, 0)
    }

    func testProviderAuthImportReadsKimiOAuthBundle() throws {
        let data = Data(#"""
        {
          "type": "kimi",
          "access_token": "kimi-access-token",
          "refresh_token": "kimi-refresh-token",
          "device_id": "device-42",
          "expired": "2026-05-02T00:00:00Z"
        }
        """#.utf8)

        let imported = try ProviderAuthImport.parse(data: data)

        XCTAssertEqual(imported.backend, "kimi")
        XCTAssertEqual(imported.apiKey, "kimi-access-token")
        XCTAssertEqual(imported.refreshToken, "kimi-refresh-token")
        XCTAssertEqual(imported.baseURL, "https://api.moonshot.cn/v1")
        XCTAssertEqual(imported.apiKeyRef, "kimi:api.moonshot.cn")
        XCTAssertEqual(imported.authType, "oauth")
        XCTAssertEqual(imported.accountID, "device-42")
        XCTAssertEqual(imported.oauthSourceKey, "kimi")
        XCTAssertGreaterThan(imported.expiresAtMs, 0)
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

    func testProviderConfigImportAcceptsSelectedOpenAICompatibleProviderWithoutRequiresFlag() throws {
        let text = """
        model_provider = "flu"
        model = "gpt-5.5"

        [model_providers.flu]
        name = "flu"
        base_url = "https://sub.picfix.pro/v1"
        wire_api = "responses"
        """

        let imported = try ProviderConfigImport.parse(text: text)

        XCTAssertEqual(imported.providerName, "flu")
        XCTAssertEqual(imported.backend, "openai_compatible")
        XCTAssertEqual(imported.baseURL, "https://sub.picfix.pro/v1")
        XCTAssertEqual(imported.apiKeyRef, "openai_compatible:sub.picfix.pro")
        XCTAssertEqual(imported.preferredModelID, "gpt-5.5")
        XCTAssertEqual(imported.wireAPI, "responses")
        XCTAssertEqual(imported.source, .explicitProvider)
    }

    func testProviderConfigImportRecognizesMinimalCodexConfigAsOpenAIResponses() throws {
        let text = """
        model = "gpt-5.4"
        model_reasoning_effort = "xhigh"

        [projects."$HOME/x-hub-system"]
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
        XCTAssertEqual(resolved.credentialVariants.count, 1)
        XCTAssertEqual(resolved.credentialVariants.first?.sourceURL?.lastPathComponent, "auth.json")
        XCTAssertEqual(credentials.kind, .apiKey)
        XCTAssertEqual(credentials.apiKey, "sk-import-123")
        XCTAssertEqual(credentials.backend, "openai_compatible")
        XCTAssertEqual(credentials.baseURL, "https://wxs.lat/openai")
        XCTAssertEqual(credentials.apiKeyRef, "openai_compatible:wxs.lat")
        XCTAssertEqual(credentials.wireAPI, "responses")
        XCTAssertEqual(providerConfig.preferredModelID, "gpt-5.4")
    }

    func testCodexProviderImportResolverPairsSuffixedAuthDuringConfigImport() throws {
        let importRoot = try makeTempImportDir()
        try """
        {
          "OPENAI_API_KEY": "sk-default"
        }
        """.write(
            to: importRoot.appendingPathComponent("auth.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "OPENAI_API_KEY": "sk-suffixed"
        }
        """.write(
            to: importRoot.appendingPathComponent("auth A.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        model_provider = "flu"
        model = "gpt-5.5"

        [model_providers.flu]
        base_url = "https://api.dabuguoni.me/v1"
        wire_api = "responses"
        """.write(
            to: importRoot.appendingPathComponent("config A.toml"),
            atomically: true,
            encoding: .utf8
        )

        let resolved = try CodexProviderImportResolver.resolveConfigImport(
            from: importRoot.appendingPathComponent("config A.toml")
        )

        let credentials = try XCTUnwrap(resolved.credentials)
        XCTAssertEqual(credentials.apiKey, "sk-suffixed")
        XCTAssertEqual(credentials.backend, "openai_compatible")
        XCTAssertEqual(credentials.baseURL, "https://api.dabuguoni.me/v1")
        XCTAssertEqual(credentials.apiKeyRef, "openai_compatible:api.dabuguoni.me")
        XCTAssertEqual(credentials.wireAPI, "responses")
        XCTAssertEqual(resolved.providerConfig?.preferredModelID, "gpt-5.5")
        XCTAssertEqual(resolved.credentialVariants.first?.sourceURL?.lastPathComponent, "auth A.json")
    }

    func testCodexProviderImportResolverPairsSuffixedConfigDuringAuthImport() throws {
        let importRoot = try makeTempImportDir()
        try """
        {
          "OPENAI_API_KEY": "sk-suffixed"
        }
        """.write(
            to: importRoot.appendingPathComponent("auth A.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        model_provider = "flu"
        model = "gpt-5.5"

        [model_providers.flu]
        base_url = "https://api.dabuguoni.me/v1"
        wire_api = "responses"
        """.write(
            to: importRoot.appendingPathComponent("config A.toml"),
            atomically: true,
            encoding: .utf8
        )

        let resolved = try CodexProviderImportResolver.resolveAuthImport(
            from: importRoot.appendingPathComponent("auth A.json")
        )

        let credentials = try XCTUnwrap(resolved.credentials)
        XCTAssertEqual(credentials.apiKey, "sk-suffixed")
        XCTAssertEqual(credentials.backend, "openai_compatible")
        XCTAssertEqual(credentials.baseURL, "https://api.dabuguoni.me/v1")
        XCTAssertEqual(credentials.apiKeyRef, "openai_compatible:api.dabuguoni.me")
        XCTAssertEqual(credentials.wireAPI, "responses")
        XCTAssertEqual(resolved.providerConfig?.preferredModelID, "gpt-5.5")
        XCTAssertEqual(resolved.providerConfig?.source, .explicitProvider)
    }

    func testCodexProviderImportResolverKeepsChatGPTCompatWireAPIForFallbackConfigImport() throws {
        let codexHome = try makeTempCodexHome()
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)
        defer {
            unsetenv("XHUB_CODEX_HOME_OVERRIDE")
        }

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

        let resolved = try CodexProviderImportResolver.resolveConfigImport(
            from: importRoot.appendingPathComponent("config.toml")
        )

        let credentials = try XCTUnwrap(resolved.credentials)
        let providerConfig = try XCTUnwrap(resolved.providerConfig)
        XCTAssertEqual(resolved.credentialVariants.count, 1)
        XCTAssertEqual(resolved.credentialVariants.first?.sourceURL?.lastPathComponent, "auth.json")
        XCTAssertEqual(credentials.kind, .chatGPTTokenBundle)
        XCTAssertEqual(providerConfig.source, .fallbackOpenAI)
        XCTAssertEqual(providerConfig.wireAPI, "responses")
        XCTAssertEqual(credentials.wireAPI, "chat_completions")
    }

    func testCodexProviderImportResolverLoadsNewestSiblingAuthFileDuringConfigImport() throws {
        let importRoot = try makeTempImportDir()
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "ey-auth17-access-token"
          }
        }
        """.write(
            to: importRoot.appendingPathComponent("auth17.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "ey-auth19-access-token"
          }
        }
        """.write(
            to: importRoot.appendingPathComponent("auth19.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        model = "gpt-5.4"
        model_reasoning_effort = "xhigh"
        """.write(
            to: importRoot.appendingPathComponent("config149.toml"),
            atomically: true,
            encoding: .utf8
        )

        let resolved = try CodexProviderImportResolver.resolveConfigImport(
            from: importRoot.appendingPathComponent("config149.toml")
        )

        let credentials = try XCTUnwrap(resolved.credentials)
        XCTAssertEqual(
            resolved.credentialVariants.map { $0.credentials.apiKey },
            ["ey-auth19-access-token", "ey-auth17-access-token"]
        )
        XCTAssertEqual(
            resolved.credentialVariants.map { $0.credentials.authIndex },
            [19, 17]
        )
        XCTAssertEqual(
            resolved.credentialVariants.map { $0.sourceURL?.lastPathComponent ?? "" },
            ["auth19.json", "auth17.json"]
        )
        XCTAssertEqual(credentials.kind, .chatGPTTokenBundle)
        XCTAssertEqual(credentials.apiKey, "ey-auth19-access-token")
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

    func testRemoteProviderClientFallsBackToCodexCatalogForChatGPTOAuthBackendAlias() throws {
        let codexHome = try makeTempCodexHome()
        let modelsCache = """
        {
          "models": [
            {"slug": "gpt-5.5", "supported_in_api": true},
            {"slug": "gpt-5.4-mini", "supported_in_api": true}
          ]
        }
        """
        try modelsCache.write(to: codexHome.appendingPathComponent("models_cache.json"), atomically: true, encoding: .utf8)
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)

        let ids = RemoteProviderClient.fallbackModelIdsIfApplicable(
            backend: "codex",
            baseURL: "https://api.openai.com/v1",
            error: RemoteProviderClient.ProviderError.httpError(
                status: 403,
                body: #"{"error":"Provider permissions insufficient. Missing scopes: api.model.read"}"#
            )
        )

        XCTAssertEqual(ids, ["gpt-5.5", "gpt-5.4-mini"])
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

    func testProviderHTTPErrorHighlightsInvalidAPIKeyWithoutEchoingSecret() {
        let description = RemoteProviderClient.ProviderError.httpError(
            status: 401,
            body: #"{"error":{"message":"Incorrect API key provided: sk-test-secret","type":"invalid_request_error","code":"invalid_api_key"}}"#
        ).errorDescription

        XCTAssertEqual(
            description,
            "Provider API Key 无效或已被撤销（status=401）。请重新粘贴有效的 Provider API Key，或在服务商后台轮换后再导入。"
        )
        XCTAssertFalse(description?.contains("sk-test-secret") ?? true)
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
