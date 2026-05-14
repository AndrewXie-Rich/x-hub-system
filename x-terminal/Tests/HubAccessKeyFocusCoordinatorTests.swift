import Foundation
import Testing
@testable import XTerminal

struct HubAccessKeyFocusCoordinatorTests {
    @Test
    func returnsBlockedKeyWhenFocusedRepairArrives() {
        let focusContext = XTSectionFocusContext(
            title: "修复非 XT Terminal 访问",
            detail: "定位到当前受阻的 access key"
        )
        let projection = XTUnifiedDoctorExternalTerminalAccessProjection(
            accessKeys: [
                makeAccessKey(accessKeyID: "hk_ready", name: "Ready Key", status: "ready"),
                makeAccessKey(
                    accessKeyID: "hk_expired",
                    name: "Expired Key",
                    status: "expired",
                    statusReason: "token_expired"
                )
            ],
            sourceStatus: "ready",
            observedAt: Date(timeIntervalSince1970: 1_741_300_060),
            dataUpdatedAtMs: 1_741_300_000_000
        )

        let decision = HubAccessKeyFocusCoordinator.autoFocusDecision(
            focusContext: focusContext,
            projection: projection,
            accessKeys: [
                makeAccessKey(accessKeyID: "hk_ready", name: "Ready Key", status: "ready"),
                makeAccessKey(
                    accessKeyID: "hk_expired",
                    name: "Expired Key",
                    status: "expired",
                    statusReason: "token_expired"
                )
            ],
            previouslyHandledSignature: ""
        )

        #expect(decision?.accessKeyID == "hk_expired")
        #expect(decision?.signature.contains("hk_expired") == true)
    }

    @Test
    func returnsNilWhenSameFocusSignatureAlreadyHandled() {
        let focusContext = XTSectionFocusContext(
            title: "修复非 XT Terminal 访问",
            detail: "定位到当前受阻的 access key"
        )
        let projection = XTUnifiedDoctorExternalTerminalAccessProjection(
            accessKeys: [
                makeAccessKey(
                    accessKeyID: "hk_revoked",
                    name: "Revoked Key",
                    status: "revoked",
                    statusReason: "token_revoked"
                )
            ],
            sourceStatus: "ready",
            observedAt: Date(timeIntervalSince1970: 1_741_300_060),
            dataUpdatedAtMs: 1_741_300_000_000
        )
        let firstDecision = HubAccessKeyFocusCoordinator.autoFocusDecision(
            focusContext: focusContext,
            projection: projection,
            accessKeys: [
                makeAccessKey(
                    accessKeyID: "hk_revoked",
                    name: "Revoked Key",
                    status: "revoked",
                    statusReason: "token_revoked"
                )
            ],
            previouslyHandledSignature: ""
        )

        let secondDecision = HubAccessKeyFocusCoordinator.autoFocusDecision(
            focusContext: focusContext,
            projection: projection,
            accessKeys: [
                makeAccessKey(
                    accessKeyID: "hk_revoked",
                    name: "Revoked Key",
                    status: "revoked",
                    statusReason: "token_revoked"
                )
            ],
            previouslyHandledSignature: firstDecision?.signature ?? ""
        )

        #expect(firstDecision?.accessKeyID == "hk_revoked")
        #expect(secondDecision == nil)
    }

    @Test
    func returnsNilWhenBlockedKeyIsMissingFromCurrentList() {
        let decision = HubAccessKeyFocusCoordinator.autoFocusDecision(
            focusContext: XTSectionFocusContext(
                title: "修复非 XT Terminal 访问",
                detail: "定位到当前受阻的 access key"
            ),
            projection: XTUnifiedDoctorExternalTerminalAccessProjection(
                accessKeys: [
                    makeAccessKey(
                        accessKeyID: "hk_missing",
                        name: "Missing Key",
                        status: "expired",
                        statusReason: "token_expired"
                    )
                ],
                sourceStatus: "ready",
                observedAt: Date(timeIntervalSince1970: 1_741_300_060),
                dataUpdatedAtMs: 1_741_300_000_000
            ),
            accessKeys: [
                makeAccessKey(accessKeyID: "hk_other", name: "Other Key", status: "ready")
            ],
            previouslyHandledSignature: ""
        )

        #expect(decision == nil)
    }

    @Test
    func anchorIDUsesStableRowPrefix() {
        #expect(
            HubAccessKeyFocusCoordinator.anchorID(for: "hk_expired")
                == "hub_access_key_row_hk_expired"
        )
    }
}

private func makeAccessKey(
    accessKeyID: String,
    name: String,
    status: String,
    statusReason: String = ""
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
        expiresAtMs: 0,
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
