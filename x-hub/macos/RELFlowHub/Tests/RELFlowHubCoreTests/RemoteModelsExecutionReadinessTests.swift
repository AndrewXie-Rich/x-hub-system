import XCTest
@testable import RELFlowHubCore

final class RemoteModelsExecutionReadinessTests: XCTestCase {
    func testExportableEnabledModelsExcludeMissingAPIKey() {
        let snapshot = RemoteModelSnapshot(
            models: [
                RemoteModelEntry(
                    id: "openai/gpt-5.3-codex",
                    name: "GPT 5.3 Codex",
                    backend: "openai",
                    enabled: true,
                    apiKey: nil
                )
            ],
            updatedAt: 0
        )

        XCTAssertTrue(RemoteModelStorage.exportableEnabledModels(from: snapshot).isEmpty)
        XCTAssertFalse(RemoteModelStorage.isExecutionReadyRemoteModel(snapshot.models[0]))
    }

    func testExportableEnabledModelsExcludeInvalidBaseURL() {
        let snapshot = RemoteModelSnapshot(
            models: [
                RemoteModelEntry(
                    id: "custom/gpt-5",
                    name: "Custom GPT 5",
                    backend: "custom_openai",
                    enabled: true,
                    baseURL: "://bad-url",
                    apiKey: "sk-test"
                )
            ],
            updatedAt: 0
        )

        XCTAssertTrue(RemoteModelStorage.exportableEnabledModels(from: snapshot).isEmpty)
    }

    func testExportableEnabledModelsKeepRunnableOpenAIAndGeminiEntries() {
        let snapshot = RemoteModelSnapshot(
            models: [
                RemoteModelEntry(
                    id: "openai/gpt-5.3-codex",
                    name: "GPT 5.3 Codex",
                    backend: "openai",
                    enabled: true,
                    apiKey: "sk-test"
                ),
                RemoteModelEntry(
                    id: "models/gemini-2.5-pro",
                    name: "Gemini 2.5 Pro",
                    backend: "gemini",
                    enabled: true,
                    apiKey: "gm-test"
                ),
            ],
            updatedAt: 0
        )

        let exported = RemoteModelStorage.exportableEnabledModels(from: snapshot).map(\.id)
        XCTAssertEqual(exported, ["openai/gpt-5.3-codex", "models/gemini-2.5-pro"])
    }

    func testKeyReferenceUsesSharedAPIKeyRefWhenPresent() {
        let shared = RemoteModelEntry(
            id: "openai/gpt-5-low",
            name: "gpt-5-low",
            backend: "openai",
            enabled: true,
            apiKeyRef: "openai:team-prod",
            apiKey: "sk-test"
        )
        let fallback = RemoteModelEntry(
            id: "anthropic/claude-3-7-sonnet",
            name: "claude-3-7-sonnet",
            backend: "anthropic",
            enabled: true,
            apiKey: "sk-test"
        )

        XCTAssertEqual(RemoteModelStorage.keyReference(for: shared), "openai:team-prod")
        XCTAssertEqual(RemoteModelStorage.keyReference(for: fallback), "anthropic/claude-3-7-sonnet")
    }
}
