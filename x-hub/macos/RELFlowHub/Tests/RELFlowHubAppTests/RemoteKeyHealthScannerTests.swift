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

    private func makeTempDir() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("relflowhub-remote-key-health-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
