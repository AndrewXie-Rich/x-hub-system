import XCTest
@testable import RELFlowHub

final class RemoteProviderClientTests: XCTestCase {
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
}
