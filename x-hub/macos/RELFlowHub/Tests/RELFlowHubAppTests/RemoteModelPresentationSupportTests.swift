import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class RemoteModelPresentationSupportTests: XCTestCase {
    func testStateDistinguishesLoadedAvailableAndNeedsSetup() {
        let loaded = RemoteModelEntry(
            id: "openai/gpt-5.2",
            name: "GPT-5.2",
            backend: "openai",
            enabled: true,
            apiKey: "sk-test"
        )
        let available = RemoteModelEntry(
            id: "openai/gpt-5.2-mini",
            name: "GPT-5.2 Mini",
            backend: "openai",
            enabled: false,
            apiKey: "sk-test"
        )
        let needsSetup = RemoteModelEntry(
            id: "openai/gpt-5.2-nokey",
            name: "GPT-5.2 No Key",
            backend: "openai",
            enabled: true,
            apiKey: nil
        )

        XCTAssertEqual(RemoteModelPresentationSupport.state(for: loaded), .loaded)
        XCTAssertEqual(RemoteModelPresentationSupport.state(for: available), .available)
        XCTAssertEqual(RemoteModelPresentationSupport.state(for: needsSetup), .needsSetup)
    }

    func testGroupsUseExplicitAliasAndKeepDifferentKeyReferencesSeparate() {
        let models = [
            RemoteModelEntry(
                id: "openai/gpt-5.2",
                name: "GPT-5.2",
                groupDisplayName: "Research",
                backend: "openai",
                enabled: true,
                apiKeyRef: "openai:research",
                upstreamModelId: "gpt-5.2",
                apiKey: "sk-test"
            ),
            RemoteModelEntry(
                id: "openai/gpt-5.2-mini",
                name: "GPT-5.2 Mini",
                groupDisplayName: "Research",
                backend: "openai",
                enabled: false,
                apiKeyRef: "openai:research",
                upstreamModelId: "gpt-5.2-mini",
                apiKey: "sk-test"
            ),
            RemoteModelEntry(
                id: "openai/gpt-5.2-team2",
                name: "GPT-5.2",
                groupDisplayName: "Research",
                backend: "openai",
                enabled: true,
                apiKeyRef: "openai:team-2",
                upstreamModelId: "gpt-5.2",
                apiKey: "sk-test"
            )
        ]

        let groups = RemoteModelPresentationSupport.groups(from: models)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].title, "Research")
        XCTAssertEqual(groups[0].models.count, 2)
        XCTAssertEqual(groups[0].loadedCount, 1)
        XCTAssertEqual(groups[0].availableCount, 1)
        XCTAssertEqual(groups[0].needsSetupCount, 0)
        XCTAssertEqual(groups[1].title, "Research")
        XCTAssertEqual(groups[1].models.count, 1)
        XCTAssertNotEqual(groups[0].id, groups[1].id)
    }

    func testGroupsFallBackToKeyReferenceWhenAliasMissing() {
        let model = RemoteModelEntry(
            id: "anthropic/claude-sonnet",
            name: "Claude Sonnet",
            backend: "anthropic",
            enabled: false,
            apiKeyRef: "anthropic:prod",
            upstreamModelId: "claude-sonnet",
            apiKey: "sk-test"
        )

        let groups = RemoteModelPresentationSupport.groups(from: [model])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "anthropic:prod")
        XCTAssertTrue(groups[0].detail?.contains("Anthropic") == true)
    }

    func testGroupsPreferHealthyKeysBeforeBlockedKeys() {
        let blocked = RemoteModelEntry(
            id: "a-blocked",
            name: "A Blocked",
            backend: "openai_compatible",
            enabled: true,
            baseURL: "https://provider.example/v1",
            apiKeyRef: "team-blocked",
            upstreamModelId: "a-blocked",
            wireAPI: "responses",
            apiKey: "sk-blocked"
        )
        let healthy = RemoteModelEntry(
            id: "z-healthy",
            name: "Z Healthy",
            backend: "openai_compatible",
            enabled: false,
            baseURL: "https://provider.example/v1",
            apiKeyRef: "team-healthy",
            upstreamModelId: "z-healthy",
            wireAPI: "responses",
            apiKey: "sk-healthy"
        )
        let healthSnapshot = RemoteKeyHealthSnapshot(
            records: [
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
            ],
            updatedAt: 20
        )

        let groups = RemoteModelPresentationSupport.groups(
            from: [blocked, healthy],
            healthSnapshot: healthSnapshot
        )

        XCTAssertEqual(groups.map(\.keyReference), ["team-healthy", "team-blocked"])
    }
}
