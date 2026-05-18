import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class RemoteProviderKeyBootstrapperTests: XCTestCase {
    override func tearDown() {
        unsetenv("XHUB_SOURCE_RUN_HOME")
        unsetenv("XHUB_CODEX_HOME_OVERRIDE")
        super.tearDown()
    }

    func testBootstrapCreatesFormalProviderKeyStoreFromExistingRemoteModelsAndAuthFiles() throws {
        let home = try makeTempHome()
        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        let hubDir = home.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hubDir, withIntermediateDirectories: true)

        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)
        setenv("XHUB_CODEX_HOME_OVERRIDE", codexHome.path, 1)

        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "ey-test-access-token-17",
            "refresh_token": "refresh-token-17",
            "account_id": "acct-17"
          }
        }
        """.write(
            to: codexHome.appendingPathComponent("auth17.json"),
            atomically: true,
            encoding: .utf8
        )

        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "ey-test-access-token-19",
            "refresh_token": "refresh-token-19",
            "account_id": "acct-19"
          }
        }
        """.write(
            to: codexHome.appendingPathComponent("auth19.json"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = RemoteModelSnapshot(
            models: [
                RemoteModelEntry(
                    id: "gpt-5.4",
                    name: "GPT 5.4",
                    backend: "openai_compatible",
                    enabled: true,
                    baseURL: "https://sub.picfix.pro/v1",
                    apiKeyRef: "openai_compatible:sub.picfix.pro",
                    upstreamModelId: "gpt-5.4",
                    wireAPI: "responses",
                    apiKey: "ey-test-access-token-17"
                ),
                RemoteModelEntry(
                    id: "glm-5",
                    name: "GLM 5",
                    backend: "openai_compatible",
                    enabled: true,
                    baseURL: "https://sub.picfix.pro/v1",
                    apiKeyRef: "openai_compatible:sub.picfix.pro#2",
                    upstreamModelId: "glm-5",
                    wireAPI: "responses",
                    apiKey: "ey-test-access-token-19"
                ),
            ],
            updatedAt: Date().timeIntervalSince1970
        )
        RemoteModelStorage.save(snapshot)

        let changed = RemoteProviderKeyBootstrapper.bootstrapIfNeeded()
        XCTAssertTrue(changed)

        let storeURL = hubDir.appendingPathComponent("hub_provider_keys.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        let providerSnapshot = ProviderKeyStorage.load()
        XCTAssertEqual(providerSnapshot.schemaVersion, "hub_provider_keys.v1")
        XCTAssertEqual(providerSnapshot.totalAccounts, 2)
        XCTAssertEqual(Set(providerSnapshot.allAccounts.map(\.authIndex)), Set([17, 19]))
        XCTAssertEqual(Set(providerSnapshot.allAccounts.map(\.accountId)), Set(["acct-17", "acct-19"]))
        XCTAssertTrue(providerSnapshot.quotaPools.contains(where: { $0.familyKey == "openai" }))
        XCTAssertTrue(providerSnapshot.quotaPools.contains(where: { $0.familyKey == "glm" }))
    }

    func testBootstrapRepairsExistingFormalStoreUsingJWTMetadataWhenAuthFilesAreUnavailable() throws {
        let home = try makeTempHome()
        let hubDir = home.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: hubDir, withIntermediateDirectories: true)

        setenv("XHUB_SOURCE_RUN_HOME", home.path, 1)

        let accessToken = makeJWT([
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct-existing-42",
            ],
            "https://api.openai.com/profile": [
                "email": "existing@test.local",
            ],
            "exp": Int(Date().timeIntervalSince1970) + 3600,
        ])

        let remoteModels = RemoteModelSnapshot(
            models: [
                RemoteModelEntry(
                    id: "gpt-5.4",
                    name: "GPT 5.4",
                    backend: "openai_compatible",
                    enabled: true,
                    baseURL: "https://sub.picfix.pro/v1",
                    apiKeyRef: "openai_compatible:sub.picfix.pro",
                    upstreamModelId: "gpt-5.4",
                    wireAPI: "responses",
                    apiKey: accessToken
                ),
            ],
            updatedAt: Date().timeIntervalSince1970
        )
        RemoteModelStorage.save(remoteModels)

        let seeded = ProviderKeyStorage.syncImportedAccounts(
            [
                ProviderKeyImportedAccountInput(
                    provider: "openai",
                    email: "",
                    apiKey: accessToken,
                    refreshToken: "",
                    baseURL: "https://sub.picfix.pro/v1",
                    proxyURL: "",
                    enabled: true,
                    authType: "api_key",
                    wireAPI: "responses",
                    expiresAtMs: 0,
                    tier: "",
                    customHeaders: [:],
                    models: ["gpt-5.4"],
                    notes: "Seeded legacy formal store",
                    priority: 0,
                    accountID: "",
                    sourceType: "",
                    sourceRef: "",
                    oauthSourceKey: "",
                    authIndex: 0,
                    sourceOwners: []
                ),
            ]
        )
        XCTAssertTrue(seeded.ok)

        let repaired = RemoteProviderKeyBootstrapper.bootstrapIfNeeded()
        XCTAssertTrue(repaired)

        let snapshot = ProviderKeyStorage.load()
        XCTAssertEqual(snapshot.totalAccounts, 1)
        let account = try XCTUnwrap(snapshot.allAccounts.first)
        XCTAssertEqual(account.accountId, "acct-existing-42")
        XCTAssertEqual(account.oauthSourceKey, "chatgpt")
        XCTAssertGreaterThan(account.expiresAtMs, 0)
    }

    private func makeTempHome() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("relflowhub-provider-bootstrap-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeJWT(_ payload: [String: Any]) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"], options: [])
        let bodyData = try! JSONSerialization.data(withJSONObject: payload, options: [])
        let header = headerData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let body = bodyData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(body)."
    }
}
