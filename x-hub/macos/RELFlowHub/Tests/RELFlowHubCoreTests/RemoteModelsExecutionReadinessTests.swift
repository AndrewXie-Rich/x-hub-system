import XCTest
@testable import RELFlowHubCore

final class RemoteModelsExecutionReadinessTests: XCTestCase {
    override func tearDown() {
        unsetenv("XHUB_SOURCE_RUN_HOME")
        super.tearDown()
    }

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

    func testResponsesWireAPICountsAsExecutionReadyForOpenAICompatibleModel() {
        let model = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            wireAPI: "responses",
            apiKey: "sk-test"
        )

        XCTAssertTrue(RemoteModelStorage.isExecutionReadyRemoteModel(model))
    }

    func testExportableEnabledModelsPreferHealthyKeysWhenScanSnapshotExists() throws {
        let home = try makeIsolatedHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let snapshot = RemoteModelSnapshot(
            models: [
                RemoteModelEntry(
                    id: "a-blocked",
                    name: "A Blocked",
                    backend: "openai_compatible",
                    enabled: true,
                    baseURL: "https://provider.example/v1",
                    apiKeyRef: "team-blocked",
                    upstreamModelId: "a-blocked",
                    wireAPI: "responses",
                    apiKey: "sk-blocked"
                ),
                RemoteModelEntry(
                    id: "z-healthy",
                    name: "Z Healthy",
                    backend: "openai_compatible",
                    enabled: true,
                    baseURL: "https://provider.example/v1",
                    apiKeyRef: "team-healthy",
                    upstreamModelId: "z-healthy",
                    wireAPI: "responses",
                    apiKey: "sk-healthy"
                ),
            ],
            updatedAt: 0
        )
        RemoteModelStorage.save(snapshot)
        RemoteKeyHealthStorage.replace(records: [
            RemoteKeyHealthRecord(
                keyReference: "team-blocked",
                backend: "openai_compatible",
                providerHost: "provider.example",
                canaryModelID: "a-blocked",
                state: .blockedQuota,
                summary: "",
                detail: "",
                lastCheckedAt: 10,
                lastSuccessAt: nil
            ),
            RemoteKeyHealthRecord(
                keyReference: "team-healthy",
                backend: "openai_compatible",
                providerHost: "provider.example",
                canaryModelID: "z-healthy",
                state: .healthy,
                summary: "",
                detail: "",
                lastCheckedAt: 20,
                lastSuccessAt: 20
            ),
        ])

        let exported = RemoteModelStorage.exportableEnabledModels().map(\.id)

        XCTAssertEqual(exported, ["z-healthy", "a-blocked"])
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

    func testEffectiveGroupDisplayNameFallsBackToLegacyCustomName() {
        let model = RemoteModelEntry(
            id: "openai/team-prod",
            name: "Team Pro",
            backend: "openai",
            upstreamModelId: "gpt-5.2"
        )

        XCTAssertEqual(model.effectiveGroupDisplayName, "Team Pro")
        XCTAssertEqual(model.nestedDisplayName, "gpt-5.2")
    }

    func testExplicitGroupDisplayNameDoesNotOverrideChildModelTitle() {
        let model = RemoteModelEntry(
            id: "openai/gpt-5.2",
            name: "GPT-5.2",
            groupDisplayName: "Research Cluster",
            backend: "openai",
            upstreamModelId: "gpt-5.2"
        )

        XCTAssertEqual(model.effectiveGroupDisplayName, "Research Cluster")
        XCTAssertEqual(model.nestedDisplayName, "GPT-5.2")
    }

    func testHumanizedModelNameIsNotMisclassifiedAsGroupAlias() {
        let model = RemoteModelEntry(
            id: "openai/gpt-5.3-codex",
            name: "GPT 5.3 Codex",
            backend: "openai",
            upstreamModelId: "gpt-5.3-codex"
        )

        XCTAssertNil(model.effectiveGroupDisplayName)
        XCTAssertEqual(model.nestedDisplayName, "GPT 5.3 Codex")
    }

    func testHubStateModelPreservesAliasAndKeyIdentityForXT() throws {
        let model = RemoteModelEntry(
            id: "openai/gpt-5.4",
            name: "GPT 5.4",
            groupDisplayName: "Team Pro",
            backend: "openai",
            baseURL: "https://aispeed.store/openai",
            apiKeyRef: "crs",
            upstreamModelId: "gpt-5.4",
            apiKey: "sk-test"
        )

        let projected = try XCTUnwrap(RemoteModelStorage.hubStateModel(for: model))
        XCTAssertEqual(projected.name, "GPT 5.4")
        XCTAssertEqual(projected.remoteGroupDisplayName, "Team Pro")
        XCTAssertEqual(projected.remoteKeyReference, "crs")
        XCTAssertEqual(projected.remoteEndpointHost, "aispeed.store")
        XCTAssertEqual(projected.remoteProviderModelID, "gpt-5.4")
    }

    func testUpsertDisambiguatesDifferentKeysForSameRemoteModel() throws {
        let home = try makeIsolatedHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let first = RemoteModelEntry(
            id: "gpt-5.4",
            name: "gpt-5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-first"
        )
        let second = RemoteModelEntry(
            id: "gpt-5.4",
            name: "gpt-5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-second"
        )

        _ = RemoteModelStorage.upsert(first)
        let snapshot = RemoteModelStorage.upsert(second)

        XCTAssertEqual(snapshot.models.count, 2)
        XCTAssertEqual(
            Set(snapshot.models.map(\.id)),
            ["gpt-5.4", "gpt-5.4#2"]
        )
        XCTAssertEqual(
            Set(snapshot.models.map { RemoteModelStorage.keyReference(for: $0) }),
            ["openai_compatible:wxs.lat", "openai_compatible:wxs.lat#2"]
        )
        XCTAssertEqual(
            Set(snapshot.models.compactMap(\.apiKey)),
            ["sk-first", "sk-second"]
        )
    }

    func testUpsertReusesExistingDisambiguatedSlotForSameCredential() throws {
        let home = try makeIsolatedHome()
        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let first = RemoteModelEntry(
            id: "gpt-5.4",
            name: "gpt-5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-first"
        )
        let second = RemoteModelEntry(
            id: "gpt-5.4",
            name: "gpt-5.4",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-second"
        )

        _ = RemoteModelStorage.upsert(first)
        _ = RemoteModelStorage.upsert(second)

        let reimportedSecond = RemoteModelEntry(
            id: "gpt-5.4",
            name: "GPT 5.4 Alt",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://wxs.lat/openai",
            apiKeyRef: "openai_compatible:wxs.lat",
            upstreamModelId: "gpt-5.4",
            wireAPI: "responses",
            apiKey: "sk-second"
        )
        let snapshot = RemoteModelStorage.upsert(reimportedSecond)

        XCTAssertEqual(snapshot.models.count, 2)
        let alternate = try XCTUnwrap(
            snapshot.models.first(where: {
                RemoteModelStorage.keyReference(for: $0) == "openai_compatible:wxs.lat#2"
            })
        )
        XCTAssertEqual(alternate.id, "gpt-5.4#2")
        XCTAssertEqual(alternate.name, "GPT 5.4 Alt")
        XCTAssertEqual(alternate.apiKey, "sk-second")
    }

    private func makeIsolatedHome() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let home = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}
