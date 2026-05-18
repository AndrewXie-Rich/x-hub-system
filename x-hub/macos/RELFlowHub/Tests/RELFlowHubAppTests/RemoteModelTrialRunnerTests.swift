import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class RemoteModelTrialRunnerTests: XCTestCase {
    func testOpenAIProviderModelIdNormalizesCommonGPTAliasTypos() {
        let model = RemoteModelEntry(
            id: "openai/GPT5.5",
            name: "GPT5.5",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            upstreamModelId: "openai/gpt5.5"
        )

        XCTAssertEqual(RemoteModelTrialRunner.providerModelId(for: model), "gpt-5.5")
    }

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

    func testEnabledLookupCanFailoverAcrossSiblingKeysAfterAuthScopeFailure() async throws {
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
            apiKeyRef: "openai:api.openai.com",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-primary"
        )
        let sibling = RemoteModelEntry(
            id: "paid-model-sibling",
            name: "Sibling",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            apiKeyRef: "openai:api.openai.com#2",
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
                return .init(
                    ok: false,
                    status: 403,
                    text: "",
                    error: "Provider 权限不足，缺少生成 scope：api.responses.write。请更换具备 Responses 写权限的 key。",
                    usage: [:]
                )
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

    func testProviderPoolSkipsCoolingAccountAndUsesReadySiblingCredential() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "openai/gpt-5.5",
            name: "gpt-5.5",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            apiKeyRef: "openai:cooling",
            upstreamModelId: "gpt-5.5",
            wireAPI: "chat_completions",
            apiKey: "sk-cooling"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "openai": {
              "routing_strategy": "fill-first",
              "accounts": [
                {
                  "account_key": "openai:cooling",
                  "provider": "openai",
                  "api_key": "sk-cooling",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "api_key",
                  "wire_api": "chat_completions",
                  "models": ["gpt-5.5"],
                  "quota": {"cooldown_until_ms": 4102444800000},
                  "error_state": {
                    "status": "blocked_quota",
                    "reason_code": "quota_exceeded",
                    "next_retry_at_ms": 4102444800000
                  }
                },
                {
                  "account_key": "openai:ready",
                  "provider": "openai",
                  "api_key": "sk-ready",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "api_key",
                  "wire_api": "chat_completions",
                  "models": ["gpt-5.5"]
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        var calledKeys: [String] = []
        RemoteModelTrialRunner.providerCallOverride = { remote, _, _, _, _, _ in
            calledKeys.append(remote.apiKey ?? "")
            return .init(ok: true, status: 200, text: "HUB_OK", error: "", usage: [:])
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.accountKey, "openai:ready")
        XCTAssertEqual(calledKeys, ["sk-ready"])
    }

    func testProviderPoolRoundRobinRotatesReadyCredentialsForSameLogicalModel() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "rr/gpt-5.5",
            name: "gpt-5.5",
            backend: "openai",
            enabled: true,
            baseURL: "https://rr.example.com/v1",
            apiKeyRef: "openai:rr-a",
            upstreamModelId: "gpt-5.5",
            wireAPI: "chat_completions",
            apiKey: "sk-rr-a"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "round-robin",
          "providers": {
            "openai": {
              "routing_strategy": "round-robin",
              "accounts": [
                {
                  "account_key": "openai:rr-a",
                  "provider": "openai",
                  "api_key": "sk-rr-a",
                  "base_url": "https://rr.example.com/v1",
                  "enabled": true,
                  "auth_type": "api_key",
                  "wire_api": "chat_completions",
                  "models": ["gpt-5.5"]
                },
                {
                  "account_key": "openai:rr-b",
                  "provider": "openai",
                  "api_key": "sk-rr-b",
                  "base_url": "https://rr.example.com/v1",
                  "enabled": true,
                  "auth_type": "api_key",
                  "wire_api": "chat_completions",
                  "models": ["gpt-5.5"]
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        var calledKeys: [String] = []
        RemoteModelTrialRunner.providerCallOverride = { remote, _, _, _, _, _ in
            calledKeys.append(remote.apiKey ?? "")
            return .init(ok: true, status: 200, text: "HUB_OK", error: "", usage: [:])
        }

        let first = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK."
        )
        let second = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertTrue(first.ok)
        XCTAssertTrue(second.ok)
        XCTAssertEqual(calledKeys, ["sk-rr-a", "sk-rr-b"])
    }

    func testResultCarriesProviderKeyRuntimeMetadata() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        RemoteModelTrialRunner.providerCallOverride = nil
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4-pooled",
            name: "GPT 5.4",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            apiKeyRef: "openai:pool-primary",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-primary"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        RemoteModelTrialRunner.providerCallOverride = { _, _, _, _, _, _ in
            .init(ok: true, status: 200, text: "HUB_OK", error: "", usage: [:])
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.accountKey, "openai:pool-primary")
        XCTAssertEqual(result.provider, "openai")
        XCTAssertEqual(result.modelID, model.id)
        XCTAssertGreaterThan(result.occurredAtMs, 0)
        XCTAssertGreaterThanOrEqual(result.latencyMs, 0)
    }

    func testGenerateWritesRuntimeFailureBackIntoProviderKeyStore() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        RemoteModelTrialRunner.providerCallOverride = nil
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "openai": {
              "accounts": [
                {
                  "account_key": "openai:pool-primary",
                  "provider": "openai",
                  "email": "pool@test.local",
                  "api_key": "sk-primary",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "api_key",
                  "quota": {
                    "daily_token_cap": 0,
                    "daily_tokens_used": 0,
                    "daily_tokens_remaining": 0,
                    "total_tokens_used": 0,
                    "last_used_at_ms": 0,
                    "last_error_at_ms": 0,
                    "consecutive_errors": 0,
                    "cooldown_until_ms": 0
                  },
                  "error_state": {
                    "status": "healthy",
                    "last_error_code": "",
                    "last_error_at_ms": 0,
                    "auto_disabled": false,
                    "status_message": "",
                    "reason_code": "",
                    "next_retry_at_ms": 0,
                    "retry_at_source": ""
                  }
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let model = RemoteModelEntry(
            id: "gpt-5.4-pooled",
            name: "GPT 5.4",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            apiKeyRef: "openai:pool-primary",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-primary"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        RemoteModelTrialRunner.providerCallOverride = { _, _, _, _, _, _ in
            .init(
                ok: false,
                status: 403,
                text: "",
                error: "Provider 权限不足，缺少生成 scope：api.responses.write。",
                usage: [:]
            )
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK."
        )

        XCTAssertFalse(result.ok)
        let snapshot = ProviderKeyStorage.load()
        let account = try XCTUnwrap(snapshot.allAccounts.first(where: { $0.accountKey == "openai:pool-primary" }))
        XCTAssertEqual(account.errorState.status, "blocked_auth")
        XCTAssertEqual(account.errorState.reasonCode, "missing_scope")
        XCTAssertFalse(account.errorState.autoDisabled)
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
        let input = try XCTUnwrap(capturedBody["input"] as? [[String: Any]])
        let firstMessage = try XCTUnwrap(input.first)
        XCTAssertEqual(firstMessage["role"] as? String, "user")
        let content = try XCTUnwrap(firstMessage["content"] as? [[String: Any]])
        let firstPart = try XCTUnwrap(content.first)
        XCTAssertEqual(firstPart["type"] as? String, "input_text")
        XCTAssertEqual(firstPart["text"] as? String, "Reply with HUB_OK.")
        XCTAssertEqual(capturedBody["max_output_tokens"] as? Int, 24)
        XCTAssertNil(capturedBody["messages"])
        XCTAssertEqual(result.usage["prompt_tokens"] as? Int, 5)
        XCTAssertEqual(result.usage["completion_tokens"] as? Int, 2)
    }

    func testChatGPTOAuthBundlePrefersChatCompletionsOverResponses() async throws {
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
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJjaGF0Z3B0In0.sig"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        var capturedURLs: [String] = []
        RemoteModelTrialRunner.httpDataOverride = { request in
            let url = try XCTUnwrap(request.url)
            capturedURLs.append(url.absoluteString)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
                        ],
                    ],
                ],
                "usage": [
                    "prompt_tokens": 4,
                    "completion_tokens": 2,
                    "total_tokens": 6,
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
        XCTAssertEqual(
            capturedURLs,
            ["https://api.openai.com/v1/chat/completions"]
        )
    }

    func testCodexProviderOverridePrefersChatCompletionsOverResponses() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-4o-mini-pooled",
            name: "GPT 4o Mini",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            upstreamModelId: "gpt-4o-mini",
            wireAPI: "responses"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "codex": {
              "accounts": [
                {
                  "account_key": "codex:oauth-primary.json",
                  "provider": "codex",
                  "email": "pool@test.local",
                  "api_key": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJjb2RleCJ9.sig",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "oauth"
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        var capturedURLs: [String] = []
        RemoteModelTrialRunner.httpDataOverride = { request in
            let url = try XCTUnwrap(request.url)
            capturedURLs.append(url.absoluteString)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
                        ],
                    ],
                ],
            ])
            return (payload, response)
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            prompt: "Reply with HUB_OK.",
            providerKeyOverride: .init(
                accountKey: "codex:oauth-primary.json",
                provider: "codex",
                apiKey: "",
                baseURL: "",
                proxyURL: "",
                authType: "oauth",
                customHeaders: [:]
            )
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.text, "HUB_OK")
        XCTAssertEqual(
            capturedURLs,
            ["https://api.openai.com/v1/chat/completions"]
        )
    }

    func testOpenAICompatibleGatewayWithOpenAIOAuthJWTUsesChatCompletions() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let oauthJWT = makeJWT(payload: [
            "iss": "https://auth.openai.com",
            "aud": ["https://api.openai.com/v1"],
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-picfix",
            ],
        ])

        let model = RemoteModelEntry(
            id: "gpt-5.4-picfix",
            name: "GPT 5.4 Picfix",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://api.picfix.pro/v1",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: oauthJWT
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        var capturedURLs: [String] = []
        RemoteModelTrialRunner.httpDataOverride = { request in
            let url = try XCTUnwrap(request.url)
            capturedURLs.append(url.absoluteString)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
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
        XCTAssertEqual(
            capturedURLs,
            ["https://api.picfix.pro/v1/chat/completions"]
        )
    }

    func testOpenAICompatibleGatewayFallsBackToChatCompletionsAfterResponsesTimeout() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4-picfix",
            name: "GPT 5.4 Picfix",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://api.picfix.pro/v1",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-picfix-gateway-token"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        var capturedURLs: [String] = []
        RemoteModelTrialRunner.httpDataOverride = { request in
            let url = try XCTUnwrap(request.url)
            capturedURLs.append(url.absoluteString)
            if url.absoluteString.hasSuffix("/responses") {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
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
        XCTAssertEqual(result.text, "HUB_OK")
        XCTAssertEqual(
            capturedURLs,
            [
                "https://api.picfix.pro/v1/responses",
                "https://api.picfix.pro/v1/chat/completions",
            ]
        )
    }

    func testOpenAICustomGatewayFallsBackToChatCompletionsAfterResponsesUnsupportedParameter() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "glm-4.5-picfix",
            name: "GLM 4.5 Picfix",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.picfix.pro/v1",
            upstreamModelId: "glm-4.5",
            wireAPI: "responses",
            apiKey: "sk-picfix-gateway-token"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        var capturedURLs: [String] = []
        RemoteModelTrialRunner.httpDataOverride = { request in
            let url = try XCTUnwrap(request.url)
            capturedURLs.append(url.absoluteString)
            if url.absoluteString.hasSuffix("/responses") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let payload = try JSONSerialization.data(withJSONObject: [
                    "error": [
                        "message": "Unsupported parameter: reasoning_effort",
                        "code": "bad_response_status_code",
                    ],
                ])
                return (payload, response)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
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
        XCTAssertEqual(result.text, "HUB_OK")
        XCTAssertEqual(
            capturedURLs,
            [
                "https://api.picfix.pro/v1/responses",
                "https://api.picfix.pro/v1/chat/completions",
            ]
        )
    }

    func testOpenAICustomGatewayFallsBackToChatCompletionsAfterResponsesGatewayTimeoutHTML() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "glm-4.5-picfix",
            name: "GLM 4.5 Picfix",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.picfix.pro/v1",
            upstreamModelId: "glm-4.5",
            wireAPI: "responses",
            apiKey: "sk-picfix-gateway-token"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        var capturedURLs: [String] = []
        RemoteModelTrialRunner.httpDataOverride = { request in
            let url = try XCTUnwrap(request.url)
            capturedURLs.append(url.absoluteString)
            if url.absoluteString.hasSuffix("/responses") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 504,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let payload = Data("""
                <!DOCTYPE html>
                <html>
                <head><title>504 Gateway time-out</title></head>
                <body>Gateway time-out</body>
                </html>
                """.utf8)
                return (payload, response)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
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
        XCTAssertEqual(result.text, "HUB_OK")
        XCTAssertEqual(
            capturedURLs,
            [
                "https://api.picfix.pro/v1/responses",
                "https://api.picfix.pro/v1/chat/completions",
            ]
        )
    }

    func testStoredOAuthCredentialMetadataUsesChatCompletionsForCustomGateway() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4-picfix",
            name: "GPT 5.4 Picfix",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://api.picfix.pro/v1",
            apiKeyRef: "openai_compatible:api.picfix.pro",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "token-from-model-cache"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "codex": {
              "accounts": [
                {
                  "account_key": "openai_compatible:api.picfix.pro",
                  "provider": "codex",
                  "email": "aa11@picfix.pro",
                  "api_key": "token-from-provider-store",
                  "base_url": "https://api.picfix.pro/v1",
                  "enabled": true,
                  "auth_type": "oauth",
                  "custom_headers": {
                    "ChatGPT-Account-Id": "acct-picfix"
                  }
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        var capturedURL: URL?
        var capturedAuthorization = ""
        var capturedAccountID = ""
        RemoteModelTrialRunner.httpDataOverride = { request in
            capturedURL = request.url
            capturedAuthorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            capturedAccountID = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") ?? ""
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
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
        XCTAssertEqual(capturedAuthorization, "Bearer token-from-provider-store")
        XCTAssertEqual(capturedAccountID, "acct-picfix")
        XCTAssertEqual(capturedURL?.absoluteString, "https://api.picfix.pro/v1/chat/completions")
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

    func testProviderKeyOverrideResolvesAccountSecretAndHeadersWithoutModelStoredAPIKey() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-4o-mini-pooled",
            name: "GPT 4o Mini",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://fallback.invalid/openai",
            upstreamModelId: "gpt-4o-mini"
        )
        RemoteModelStorage.save(
            RemoteModelSnapshot(models: [model], updatedAt: Date().timeIntervalSince1970)
        )

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "openai": {
              "accounts": [
                {
                  "account_key": "openai:pooled-primary.json",
                  "provider": "openai",
                  "email": "pool@test.local",
                  "api_key": "sk-pooled-secret-1234567890",
                  "base_url": "https://override.example/openai",
                  "enabled": true,
                  "auth_type": "api_key",
                  "custom_headers": {
                    "X-Provider-Account": "primary"
                  }
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        var capturedURL: URL?
        var capturedAuthorization = ""
        var capturedHeader = ""
        RemoteModelTrialRunner.httpDataOverride = { request in
            capturedURL = request.url
            capturedAuthorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            capturedHeader = request.value(forHTTPHeaderField: "X-Provider-Account") ?? ""
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": "HUB_OK",
                        ],
                    ],
                ],
                "usage": [
                    "prompt_tokens": 3,
                    "completion_tokens": 2,
                    "total_tokens": 5,
                ],
            ])
            return (payload, response)
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: model.id,
            allowDisabledModelLookup: true,
            prompt: "Reply with HUB_OK.",
            providerKeyOverride: .init(
                accountKey: "openai:pooled-primary.json",
                provider: "openai",
                apiKey: "",
                baseURL: "",
                proxyURL: "",
                authType: "api_key",
                customHeaders: [:]
            )
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.text, "HUB_OK")
        XCTAssertEqual(capturedAuthorization, "Bearer sk-pooled-secret-1234567890")
        XCTAssertEqual(capturedHeader, "primary")
        XCTAssertEqual(capturedURL?.absoluteString, "https://override.example/openai/v1/chat/completions")
    }

    func testProviderKeyStoragePreservesAuthMetadataForResolvedCredential() throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer { unsetenv("XHUB_SOURCE_RUN_HOME") }

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "codex": {
              "accounts": [
                {
                  "account_key": "codex:oauth-primary.json",
                  "provider": "codex",
                  "email": "pool@test.local",
                  "api_key": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJjb2RleCJ9.sig",
                  "refresh_token": "refresh-codex-token",
                  "base_url": "https://api.openai.com/v1",
                  "proxy_url": "https://proxy.example/openai",
                  "enabled": true,
                  "auth_type": "oauth",
                  "pool_id": "openai:api.openai.com:chat_completions",
                  "provider_host": "api.openai.com",
                  "wire_api": "chat_completions",
                  "account_id": "acct-codex-1",
                  "oauth_source_key": "chatgpt",
                  "auth_index": 4,
                  "source_type": "auth_file",
                  "source_ref": "/tmp/auth19.json",
                  "last_refresh_at_ms": 1717001234000,
                  "error_state": {
                    "status": "blocked_auth",
                    "status_message": "missing scope: api.responses.write",
                    "reason_code": "missing_scope",
                    "last_error_code": "missing_scope",
                    "last_error_at_ms": 1717001300000,
                    "next_retry_at_ms": 1776729600000,
                    "retry_at_source": "codex_usage",
                    "auto_disabled": false
                  }
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let resolved = try XCTUnwrap(ProviderKeyStorage.loadResolvedCredential(accountKey: "codex:oauth-primary.json"))
        XCTAssertEqual(resolved.refreshToken, "refresh-codex-token")
        XCTAssertEqual(resolved.proxyURL, "https://proxy.example/openai")
        XCTAssertEqual(resolved.accountId, "acct-codex-1")
        XCTAssertEqual(resolved.oauthSourceKey, "chatgpt")
        XCTAssertEqual(resolved.authIndex, 4)
        XCTAssertEqual(resolved.sourceType, "auth_file")
        XCTAssertEqual(resolved.sourceRef, "/tmp/auth19.json")
        XCTAssertEqual(resolved.poolID, "openai:api.openai.com:chat_completions")
        XCTAssertEqual(resolved.providerHost, "api.openai.com")
        XCTAssertEqual(resolved.wireAPI, "chat_completions")
        XCTAssertEqual(resolved.statusMessage, "missing scope: api.responses.write")
        XCTAssertEqual(resolved.reasonCode, "missing_scope")
        XCTAssertEqual(resolved.lastRefreshAtMs, 1717001234000)
        XCTAssertEqual(resolved.nextRetryAtMs, 1776729600000)
        XCTAssertEqual(resolved.retryAtSource, "usage_window")
    }

    func testProviderKeyStorageDerivesPoolMetadataWhenExplicitFieldsAreMissing() throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer { unsetenv("XHUB_SOURCE_RUN_HOME") }

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "openai_compatible": {
              "accounts": [
                {
                  "account_key": "openai_compatible:compat-primary",
                  "provider": "openai_compatible",
                  "email": "pool@test.local",
                  "api_key": "sk-compat-secret",
                  "base_url": "https://api.example.net/v1",
                  "enabled": true,
                  "auth_type": "api_key",
                  "quota": {
                    "cooldown_until_ms": 1776729600000
                  },
                  "error_state": {
                    "status": "blocked_quota",
                    "last_error_code": "quota_exceeded"
                  }
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let resolved = try XCTUnwrap(
            ProviderKeyStorage.loadResolvedCredential(
                accountKey: "openai_compatible:compat-primary"
            )
        )
        XCTAssertEqual(resolved.providerHost, "api.example.net")
        XCTAssertEqual(resolved.poolID, "openai_compatible:api.example.net:default")
        XCTAssertEqual(resolved.reasonCode, "quota_exceeded")
        XCTAssertEqual(resolved.nextRetryAtMs, 1776729600000)
        XCTAssertEqual(resolved.retryAtSource, "quota")
    }

    func testProviderKeyStorageCanonicalizesCodexFamilyPoolIdentityWhenHostMetadataIsMissing() throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer { unsetenv("XHUB_SOURCE_RUN_HOME") }

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "codex": {
              "accounts": [
                {
                  "account_key": "codex:oauth-missing-host",
                  "provider": "codex",
                  "email": "pool@test.local",
                  "api_key": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJjb2RleCJ9.sig",
                  "refresh_token": "refresh-codex-token",
                  "enabled": true,
                  "auth_type": "oauth"
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let resolved = try XCTUnwrap(
            ProviderKeyStorage.loadResolvedCredential(accountKey: "codex:oauth-missing-host")
        )
        XCTAssertEqual(resolved.providerHost, "api.openai.com")
        XCTAssertEqual(resolved.poolID, "openai:api.openai.com:default")
    }

    func testProviderKeyStorageDerivesDistinctPoolBoundaryFingerprintFromCustomHeaders() throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer { unsetenv("XHUB_SOURCE_RUN_HOME") }

        let providerStoreURL = SharedPaths.ensureHubDirectory().appendingPathComponent("hub_provider_keys.json")
        try FileManager.default.createDirectory(
            at: providerStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let providerStore = """
        {
          "schema_version": "hub_provider_keys.v1",
          "updated_at_ms": 1717000000000,
          "routing_strategy": "fill-first",
          "providers": {
            "openai": {
              "accounts": [
                {
                  "account_key": "openai:alpha",
                  "provider": "openai",
                  "api_key": "sk-alpha",
                  "base_url": "https://api.example.com/v1",
                  "auth_type": "api_key",
                  "custom_headers": {
                    "X-Tenant": "alpha"
                  }
                },
                {
                  "account_key": "openai:beta",
                  "provider": "openai",
                  "api_key": "sk-beta",
                  "base_url": "https://api.example.com/v1",
                  "auth_type": "api_key",
                  "custom_headers": {
                    "X-Tenant": "beta"
                  }
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let alpha = try XCTUnwrap(ProviderKeyStorage.loadResolvedCredential(accountKey: "openai:alpha"))
        let beta = try XCTUnwrap(ProviderKeyStorage.loadResolvedCredential(accountKey: "openai:beta"))
        XCTAssertTrue(alpha.poolID.hasPrefix("openai:api.example.com:default:"))
        XCTAssertTrue(beta.poolID.hasPrefix("openai:api.example.com:default:"))
        XCTAssertNotEqual(alpha.poolID, beta.poolID)
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

    private func makeJWT(payload: [String: Any]) -> String {
        let header = ["alg": "HS256", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return [
            base64url(headerData),
            base64url(payloadData),
            "sig",
        ].joined(separator: ".")
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
