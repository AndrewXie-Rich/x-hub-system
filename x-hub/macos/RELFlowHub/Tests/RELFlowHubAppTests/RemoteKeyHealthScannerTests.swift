import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class RemoteKeyHealthScannerTests: XCTestCase {
    func testScanMarksHealthyKeyWhenProbeSucceeds() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-test"
        )
        RemoteModelStorage.save(.init(models: [model], updatedAt: Date().timeIntervalSince1970))

        RemoteModelTrialRunner.providerCallOverride = { _, _, _, _, _, _ in
            .init(ok: true, status: 200, text: "OK", error: "", usage: [:])
        }

        let group = try XCTUnwrap(RemoteKeyHealthScanner.groups(from: [model]).first)
        let record = await RemoteKeyHealthScanner.scan(group: group)

        XCTAssertEqual(record.state, .healthy)
        XCTAssertEqual(record.keyReference, "openai_compatible:wxs.lat")
        XCTAssertEqual(record.retryAtText, nil)
        XCTAssertEqual(record.canaryModelID, "gpt-5.4")
        XCTAssertNotNil(record.lastSuccessAt)
    }

    func testScanMarksQuotaAndRetryTimeWhenProviderReturnsResetMessage() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-test"
        )
        RemoteModelStorage.save(.init(models: [model], updatedAt: Date().timeIntervalSince1970))

        RemoteModelTrialRunner.providerCallOverride = { _, _, _, _, _, _ in
            .init(
                ok: false,
                status: 429,
                text: "",
                error: "Your rate limit resets on Apr 15, 2026, 8:58 AM. To continue using Codex, upgrade to Plus today.",
                usage: [:]
            )
        }

        let group = try XCTUnwrap(RemoteKeyHealthScanner.groups(from: [model]).first)
        let record = await RemoteKeyHealthScanner.scan(group: group)

        XCTAssertEqual(record.state, .blockedQuota)
        XCTAssertEqual(record.retryAtText, "Apr 15, 2026, 8:58 AM")
        XCTAssertEqual(
            record.detail,
            "当前额度已用完，可升级 Plus，或到 Apr 15, 2026, 8:58 AM 再试。"
        )
    }

    func testScanMarksConfigBlockedWhenKeyCannotRun() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: nil
        )

        let group = try XCTUnwrap(RemoteKeyHealthScanner.groups(from: [model]).first)
        let record = await RemoteKeyHealthScanner.scan(group: group)

        XCTAssertEqual(record.state, .blockedConfig)
        XCTAssertEqual(record.detail, HubUIStrings.Settings.RemoteModels.healthMissingAPIKeyDetail)
        XCTAssertNil(record.lastSuccessAt)
    }

    func testScanBackfillsAuthRetryTimeFromCodexUsageWindows() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            CodexUsageService.httpDataOverride = nil
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
                  "account_key": "openai:codex-auth",
                  "provider": "openai",
                  "email": "pool@test.local",
                  "api_key": "ey-auth-scope-missing",
                  "refresh_token": "refresh-codex-token",
                  "base_url": "https://api.openai.com/v1",
                  "enabled": true,
                  "auth_type": "oauth",
                  "account_id": "acct-codex-1",
                  "oauth_source_key": "chatgpt"
                }
              ]
            }
          }
        }
        """
        try providerStore.write(to: providerStoreURL, atomically: true, encoding: .utf8)

        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai",
            enabled: true,
            baseURL: "https://api.openai.com/v1",
            apiKeyRef: "openai:api.openai.com",
            upstreamModelId: "gpt-5.4",
            wireAPI: "chat_completions",
            apiKey: "ey-auth-scope-missing"
        )
        RemoteModelStorage.save(.init(models: [model], updatedAt: Date().timeIntervalSince1970))
        let futureResetAt = Date().addingTimeInterval(4 * 60 * 60)
        let futureResetAtSeconds = Int(futureResetAt.timeIntervalSince1970.rounded())
        let expectedRetryAtText = formattedUTCRetryText(TimeInterval(futureResetAtSeconds))

        RemoteModelTrialRunner.providerCallOverride = { _, _, _, _, _, _ in
            .init(
                ok: false,
                status: 403,
                text: "",
                error: #"{"detail":"missing scopes: api.responses.write"}"#,
                usage: [:]
            )
        }

        CodexUsageService.httpDataOverride = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct-codex-1")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = try JSONSerialization.data(withJSONObject: [
                "rate_limit": [
                    "allowed": true,
                    "limit_reached": false,
                    "primary_window": [
                        "used_percent": 42.0,
                        "limit_window_seconds": 10_800,
                        "reset_at": futureResetAtSeconds,
                    ],
                ],
            ])
            return (payload, response)
        }

        let resolvedCredential = ProviderKeyStorage.loadResolvedCredential(
            apiKey: "ey-auth-scope-missing",
            provider: "openai",
            baseURL: "https://api.openai.com/v1"
        )
        XCTAssertEqual(resolvedCredential?.accountId, "acct-codex-1")

        let directRetryAtText = await RemoteRetryTimeSupport.retryAtText(
            from: "Provider 权限不足，缺少生成 scope：api.responses.write。请更换具备 Responses 写权限的 key。",
            state: .blockedAuth,
            model: model
        )
        XCTAssertEqual(directRetryAtText, expectedRetryAtText)

        let group = try XCTUnwrap(RemoteKeyHealthScanner.groups(from: [model]).first)
        let record = await RemoteKeyHealthScanner.scan(group: group)

        XCTAssertEqual(record.state, .blockedAuth)
        XCTAssertEqual(record.retryAtText, expectedRetryAtText)
        XCTAssertTrue(record.detail.contains("api.responses.write"))
    }

    func testFullScanMarksKeyDegradedWhenOnlySubsetOfModelsCanRun() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let models = [
            RemoteModelEntry(
                id: "gpt-5.4",
                name: "GPT 5.4",
                backend: "openai_compatible",
                enabled: true,
                baseURL: "https://provider.example/v1",
                apiKeyRef: "pool:shared",
                upstreamModelId: "gpt-5.4",
                wireAPI: "responses",
                apiKey: "sk-test"
            ),
            RemoteModelEntry(
                id: "glm-5",
                name: "GLM 5",
                backend: "openai_compatible",
                enabled: true,
                baseURL: "https://provider.example/v1",
                apiKeyRef: "pool:shared",
                upstreamModelId: "glm-5",
                wireAPI: "responses",
                apiKey: "sk-test"
            ),
        ]
        RemoteModelStorage.save(.init(models: models, updatedAt: Date().timeIntervalSince1970))

        RemoteModelTrialRunner.providerCallOverride = { remote, _, _, _, _, _ in
            if remote.id == "gpt-5.4" {
                return .init(ok: true, status: 200, text: "OK", error: "", usage: [:])
            }
            return .init(
                ok: false,
                status: 503,
                text: "",
                error: "No available channel for model glm-5 under group zhuoge [model_not_found]",
                usage: [:]
            )
        }

        let group = try XCTUnwrap(RemoteKeyHealthScanner.groups(from: models).first)
        let report = await RemoteKeyHealthScanner.scanReport(group: group, mode: .full)

        XCTAssertEqual(report.record.state, .degraded)
        XCTAssertEqual(report.record.canaryModelID, "gpt-5.4")
        XCTAssertTrue(report.record.detail.contains("已检测 2 个模型"))
        XCTAssertTrue(report.record.detail.contains("1 个可用"))
        XCTAssertEqual(report.modelResults.count, 2)
        XCTAssertEqual(report.modelResults.filter(\.isHealthy).count, 1)
        XCTAssertEqual(report.modelResults.first(where: { $0.modelID == "glm-5" })?.state, .blockedProvider)
    }

    func testFullScanIncludesModelsThatFailPreflightConfiguration() async throws {
        let home = try makeTempDir()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        defer {
            RemoteModelTrialRunner.providerCallOverride = nil
            RemoteModelTrialRunner.httpDataOverride = nil
            CodexUsageService.httpDataOverride = nil
            unsetenv("XHUB_SOURCE_RUN_HOME")
        }

        let models = [
            RemoteModelEntry(
                id: "gpt-5.4",
                name: "GPT 5.4",
                backend: "openai_compatible",
                enabled: true,
                baseURL: "https://provider.example/v1",
                apiKeyRef: "pool:shared",
                upstreamModelId: "gpt-5.4",
                wireAPI: "responses",
                apiKey: "sk-test"
            ),
            RemoteModelEntry(
                id: "qwen3.6-plus",
                name: "Qwen 3.6 Plus",
                backend: "openai_compatible",
                enabled: true,
                baseURL: "https://provider.example/v1",
                apiKeyRef: "pool:shared",
                upstreamModelId: "qwen3.6-plus",
                wireAPI: "responses",
                apiKey: nil
            ),
        ]
        RemoteModelStorage.save(.init(models: models, updatedAt: Date().timeIntervalSince1970))

        RemoteModelTrialRunner.providerCallOverride = { remote, _, _, _, _, _ in
            XCTAssertEqual(remote.id, "gpt-5.4")
            return .init(ok: true, status: 200, text: "OK", error: "", usage: [:])
        }

        let group = try XCTUnwrap(RemoteKeyHealthScanner.groups(from: models).first)
        let report = await RemoteKeyHealthScanner.scanReport(group: group, mode: .full)

        XCTAssertEqual(report.record.state, .degraded)
        XCTAssertEqual(report.modelResults.count, 2)
        XCTAssertEqual(report.modelResults.first(where: { $0.modelID == "qwen3.6-plus" })?.state, .blockedConfig)
        XCTAssertEqual(
            report.modelResults.first(where: { $0.modelID == "qwen3.6-plus" })?.detail,
            HubUIStrings.Settings.RemoteModels.healthMissingAPIKeyDetail
        )
    }

    private func makeTempDir() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("relflowhub-remote-key-health-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func formattedUTCRetryText(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
