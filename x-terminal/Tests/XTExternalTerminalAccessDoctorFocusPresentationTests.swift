import Foundation
import Testing
@testable import XTerminal

struct XTExternalTerminalAccessDoctorFocusPresentationTests {
    @Test
    func blockedKeyPresentationCarriesKeyReasonRecoveryAndSnapshotFacts() throws {
        let projection = XTUnifiedDoctorExternalTerminalAccessProjection(
            accessKeys: [
                makeAccessKey(
                    accessKeyID: "hk_expired",
                    name: "Expired External Terminal",
                    status: "expired",
                    statusReason: "token_expired",
                    expiresAtMs: 1_741_386_400_000
                )
            ],
            sourceStatus: "ready",
            observedAt: Date(timeIntervalSince1970: 1_741_300_060),
            dataUpdatedAtMs: 1_741_300_000_000
        )

        let presentation = try #require(
            XTExternalTerminalAccessDoctorFocusPresentation.build(
                projection: projection,
                now: Date(timeIntervalSince1970: 1_741_300_120)
            )
        )

        #expect(presentation.state == .diagnosticRequired)
        #expect(presentation.headline.contains("Expired External Terminal"))
        #expect(presentation.summary.contains("expired"))
        #expect(presentation.summary.contains("token_expired"))
        #expect(presentation.detailLines.contains(where: { $0.contains("当前快照 1 个受阻") }))
        #expect(presentation.detailLines.contains(where: { $0.contains("状态原因") && $0.contains("token_expired") }))
        #expect(presentation.detailLines.contains(where: { $0.contains("不会自动恢复") && $0.contains("轮换或新签发") }))
        #expect(presentation.detailLines.contains(where: { $0.contains("到期时间：") }))
    }

    @Test
    func fetchFailurePresentationKeepsCachedSnapshotReasonVisible() throws {
        let projection = XTUnifiedDoctorExternalTerminalAccessProjection(
            accessKeys: [
                makeAccessKey(
                    accessKeyID: "hk_revoked",
                    name: "Revoked External Terminal",
                    status: "revoked",
                    statusReason: "token_revoked"
                )
            ],
            sourceStatus: "fetch_failed",
            observedAt: Date(timeIntervalSince1970: 1_741_300_060),
            dataUpdatedAtMs: 1_741_300_000_000,
            errorCode: "access_key_refresh_failed",
            errorMessage: "timeout"
        )

        let presentation = try #require(
            XTExternalTerminalAccessDoctorFocusPresentation.build(
                projection: projection,
                now: Date(timeIntervalSince1970: 1_741_300_120)
            )
        )

        #expect(presentation.headline.contains("Revoked External Terminal"))
        #expect(presentation.detailLines.contains(where: { $0.contains("最近刷新失败：access_key_refresh_failed") }))
        #expect(presentation.detailLines.contains(where: { $0.contains("timeout") }))
    }
}

private func makeAccessKey(
    accessKeyID: String,
    name: String,
    status: String,
    statusReason: String,
    expiresAtMs: Double = 0
) -> HubAccessKeysClient.AccessKey {
    HubAccessKeysClient.AccessKey(
        schemaVersion: "hub.access_key.v1",
        accessKeyID: accessKeyID,
        authKind: "hub_access_key",
        status: status,
        statusReason: statusReason,
        deviceID: "device-1",
        userID: "user-1",
        appID: "external_terminal",
        name: name,
        note: "",
        tokenRedacted: "axh_***",
        enabled: true,
        createdAtMs: 1_741_299_000_000,
        updatedAtMs: 1_741_300_000_000,
        expiresAtMs: expiresAtMs,
        lastUsedAtMs: 1_741_300_010_000,
        lastUsedPeerIP: "127.0.0.1",
        lastUsedTransport: "grpc",
        revokedAtMs: 0,
        revokeReason: "",
        revokedByUserID: "",
        revokedVia: "",
        createdByUserID: "user-1",
        createdByAppID: "xt",
        createdVia: "xt_ui",
        lastRotatedAtMs: 0,
        rotationCount: 0,
        capabilities: [],
        scopes: ["hub.connect"],
        allowedCIDRs: [],
        policyMode: "default",
        trustProfilePresent: true,
        connect: HubAccessKeysClient.AccessKeyConnect(
            hubHost: "hub.example.test",
            hubPort: 50051,
            tlsMode: "disabled",
            tlsServerName: "",
            authEnvKey: "HUB_CLIENT_TOKEN"
        ),
        connectEnvTemplate: "export HUB_CLIENT_TOKEN=redacted",
        connectEnv: nil
    )
}
