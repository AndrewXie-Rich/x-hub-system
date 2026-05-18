import XCTest
@testable import RELFlowHub

final class TerminalAccessKeySupportTests: XCTestCase {
    func testDraftRequestBodyIncludesQuotaAndCapabilities() throws {
        var draft = HubTerminalAccessKeyDraft()
        draft.name = "Ops Bot"
        draft.userID = ""
        draft.appID = ""
        draft.note = "night shift"
        draft.dailyTokenLimit = 123_456
        draft.ttlHours = 12
        draft.allowPaidModels = true
        draft.defaultWebFetchEnabled = true

        let body = draft.requestBody

        XCTAssertEqual(body["name"] as? String, "Ops Bot")
        XCTAssertEqual(body["user_id"] as? String, "ops_bot")
        XCTAssertEqual(body["app_id"] as? String, "external_terminal")
        XCTAssertEqual(body["note"] as? String, "night shift")
        XCTAssertEqual(body["ttl_sec"] as? Int, 43_200)
        XCTAssertEqual(body["policy_mode"] as? String, HubGRPCClientPolicyMode.newProfile.rawValue)
        XCTAssertEqual(
            body["paid_model_selection_mode"] as? String,
            HubPaidModelSelectionMode.allPaidModels.rawValue
        )
        XCTAssertEqual(body["default_web_fetch_enabled"] as? Bool, true)
        XCTAssertEqual(body["daily_token_limit"] as? Int, 123_456)
        XCTAssertEqual(
            body["capabilities"] as? [String],
            ["models", "ai.generate.local", "ai.generate.paid", "web.fetch"]
        )
        XCTAssertEqual(
            body["scopes"] as? [String],
            ["models", "ai.generate.local", "ai.generate.paid", "web.fetch"]
        )
    }

    func testAccessKeyDecodesOpenAICompatFieldsAndTrustProfileBudget() throws {
        let accessKey = try JSONDecoder().decode(HubTerminalAccessKey.self, from: sampleAccessKeyJSON())

        XCTAssertEqual(accessKey.accessKeyID, "axhub_key_1")
        XCTAssertEqual(accessKey.status, "ready")
        XCTAssertEqual(accessKey.policyMode, .newProfile)
        XCTAssertEqual(accessKey.dailyTokenLimit, 250_000)
        XCTAssertTrue(accessKey.supportsDirectBudgetAdjustment)
        XCTAssertEqual(accessKey.paidModelSelectionMode, .allPaidModels)
        XCTAssertTrue(accessKey.defaultWebFetchEnabled)
        XCTAssertEqual(accessKey.openAICompat?.baseURL, "http://hub.example.com:7789/v1")
        XCTAssertEqual(accessKey.openAICompat?.modelsURL, "http://hub.example.com:7789/v1/models")
        XCTAssertEqual(
            accessKey.openAICompat?.chatCompletionsURL,
            "http://hub.example.com:7789/v1/chat/completions"
        )
        XCTAssertEqual(
            accessKey.openAICompat?.responsesURL,
            "http://hub.example.com:7789/v1/responses"
        )
        XCTAssertEqual(accessKey.openAICompatEnvTemplate, "OPENAI_BASE_URL='http://hub.example.com:7789/v1'\nOPENAI_API_KEY='axhub_client_***'\n")
        XCTAssertEqual(accessKey.openAICompatEnv, "OPENAI_BASE_URL='http://hub.example.com:7789/v1'\nOPENAI_API_KEY='axhub_client_secret'\n")
    }

    func testSecretEnvelopeBuildsSmokeCurlCommand() throws {
        let accessKey = try JSONDecoder().decode(HubTerminalAccessKey.self, from: sampleAccessKeyJSON())
        let envelope = HubTerminalAccessKeySecretEnvelope(
            clientToken: "axhub_client_secret",
            accessKey: accessKey
        )

        XCTAssertEqual(envelope.openAIBaseURL, "http://hub.example.com:7789/v1")
        XCTAssertEqual(
            envelope.smokeCurlCommand,
            """
            curl -fsS 'http://hub.example.com:7789/v1/models' \\
              -H 'Authorization: Bearer axhub_client_secret'
            """
        )
    }

    func testSecretEnvelopeBuildsDeliveryPack() throws {
        let accessKey = try JSONDecoder().decode(HubTerminalAccessKey.self, from: sampleAccessKeyJSON())
        let envelope = HubTerminalAccessKeySecretEnvelope(
            clientToken: "axhub_client_secret",
            accessKey: accessKey
        )

        let pack = envelope.deliveryPack

        XCTAssertTrue(pack.includesSecret)
        XCTAssertEqual(
            pack.shellExports,
            """
            export OPENAI_BASE_URL='http://hub.example.com:7789/v1'
            export OPENAI_API_KEY='axhub_client_secret'
            """
        )
        XCTAssertTrue(pack.pythonSnippet.contains("client.responses.create"))
        XCTAssertTrue(pack.pythonSnippet.contains("os.environ[\"OPENAI_API_KEY\"]"))
        XCTAssertTrue(pack.nodeSnippet.contains("new OpenAI"))
        XCTAssertTrue(pack.nodeSnippet.contains("process.env[\"OPENAI_BASE_URL\"]"))
        XCTAssertTrue(pack.curlCommand.contains("Reply with pong."))
        XCTAssertTrue(pack.curlCommand.contains("Authorization: Bearer ${OPENAI_API_KEY}"))
        XCTAssertTrue(pack.setupPackText.contains("# Hub terminal delivery pack"))
        XCTAssertTrue(pack.setupPackText.contains("# access_key_id: axhub_key_1"))
        XCTAssertTrue(pack.setupPackText.contains("POST http://hub.example.com:7789/v1/responses"))
        XCTAssertTrue(pack.setupPackText.contains("export OPENAI_API_KEY='axhub_client_secret'"))
        XCTAssertTrue(pack.setupPackText.contains("# python example"))
        XCTAssertTrue(pack.setupPackText.contains("# node example"))
        XCTAssertTrue(pack.setupPackText.contains("# curl example"))
    }

    private func sampleAccessKeyJSON() -> Data {
        Data(
            """
            {
              "schema_version": "hub.client_access_key.v1",
              "access_key_id": "axhub_key_1",
              "auth_kind": "hub_access_key",
              "status": "ready",
              "status_reason": "",
              "device_id": "device-alpha",
              "user_id": "alice",
              "app_id": "external_terminal",
              "name": "Alice CLI",
              "note": "primary key",
              "token_redacted": "axhub_client_***",
              "enabled": true,
              "created_at_ms": 1717000000000,
              "updated_at_ms": 1717000001000,
              "expires_at_ms": 1717086400000,
              "last_used_at_ms": 1717000002000,
              "last_used_peer_ip": "10.0.0.2",
              "last_used_transport": "http",
              "revoked_at_ms": 0,
              "revoke_reason": "",
              "revoked_by_user_id": "",
              "revoked_via": "",
              "created_by_user_id": "ops_admin",
              "created_by_app_id": "hub_local_ui",
              "created_via": "hub_local_ui",
              "last_rotated_at_ms": 1717000003000,
              "rotation_count": 2,
              "capabilities": ["models", "ai.generate.local", "ai.generate.paid", "web.fetch"],
              "scopes": ["models", "ai.generate.local", "ai.generate.paid", "web.fetch"],
              "allowed_cidrs": [],
              "policy_mode": "new_profile",
              "trust_profile_present": true,
              "approved_trust_profile": {
                "schema_version": "hub.paired_terminal_trust_profile.v1",
                "device_id": "device-alpha",
                "device_name": "Alice CLI",
                "trust_mode": "trusted_daily",
                "mode": "standard",
                "state": "active",
                "capabilities": ["models", "ai.generate.local", "ai.generate.paid", "web.fetch"],
                "allowed_project_ids": [],
                "allowed_workspace_roots": [],
                "xt_binding_required": false,
                "auto_grant_profile": "default",
                "device_permission_owner_ref": "user:alice",
                "paid_model_policy": {
                  "schema_version": "hub.paired_terminal_paid_model_policy.v1",
                  "mode": "all_paid_models",
                  "allowed_model_ids": []
                },
                "network_policy": {
                  "default_web_fetch_enabled": true
                },
                "budget_policy": {
                  "daily_token_limit": 250000,
                  "single_request_token_limit": 12000
                },
                "audit_ref": "audit-1"
              },
              "connect_env_template": "",
              "connect_env": "",
              "openai_compat": {
                "base_url": "http://hub.example.com:7789/v1",
                "models_url": "http://hub.example.com:7789/v1/models",
                "chat_completions_url": "http://hub.example.com:7789/v1/chat/completions",
                "responses_url": "http://hub.example.com:7789/v1/responses",
                "auth_scheme": "bearer",
                "api_key_env_key": "OPENAI_API_KEY",
                "base_url_env_key": "OPENAI_BASE_URL"
              },
              "openai_compat_env_template": "OPENAI_BASE_URL='http://hub.example.com:7789/v1'\\nOPENAI_API_KEY='axhub_client_***'\\n",
              "openai_compat_env": "OPENAI_BASE_URL='http://hub.example.com:7789/v1'\\nOPENAI_API_KEY='axhub_client_secret'\\n"
            }
            """.utf8
        )
    }
}
