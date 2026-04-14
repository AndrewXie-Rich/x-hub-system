import XCTest
import LocalAuthentication
@testable import RELFlowHub
@testable import RELFlowHubCore

@MainActor
final class HubStorePairingApprovalTests: XCTestCase {
    func testPairingApprovalAuthenticationReasonUsesNormalizedPreferredDeviceName() {
        let reason = HubStore.pairingApprovalAuthenticationReasonForDisplay(
            makeRequest(
                deviceName: "XT Fallback",
                claimedDeviceId: "xt-1",
                appId: "paired-terminal"
            ),
            approval: HubPairingApprovalDraft(
                deviceName: "  Andrew XT  ",
                paidModelSelectionMode: .off,
                allowedPaidModels: [],
                defaultWebFetchEnabled: true,
                dailyTokenLimit: 5000
            )
        )

        XCTAssertEqual(reason, "Approve first pairing for Andrew XT")
    }

    func testPairingApprovalAuthenticationReasonFallsBackToRequestAndGenericLabel() {
        let requestFallback = HubStore.pairingApprovalAuthenticationReasonForDisplay(
            makeRequest(
                deviceName: " ",
                claimedDeviceId: " xt-device-9 ",
                appId: "paired-terminal"
            ),
            approval: HubPairingApprovalDraft(
                deviceName: " ",
                paidModelSelectionMode: .off,
                allowedPaidModels: [],
                defaultWebFetchEnabled: true,
                dailyTokenLimit: 5000
            )
        )
        XCTAssertEqual(requestFallback, "Approve first pairing for xt-device-9")

        let genericFallback = HubStore.pairingApprovalAuthenticationReasonForDisplay(
            makeRequest(deviceName: " ", claimedDeviceId: " ", appId: " "),
            approval: HubPairingApprovalDraft(
                deviceName: " ",
                paidModelSelectionMode: .off,
                allowedPaidModels: [],
                defaultWebFetchEnabled: true,
                dailyTokenLimit: 5000
            )
        )
        XCTAssertEqual(genericFallback, "Approve first pairing for Paired Device")
    }

    func testRecommendedPairingApprovalPresetStartsWithMinimalAccess() {
        let request = makeRequest(deviceName: "XT Recommended")
        let draft = HubPairingApprovalDraft.recommended(for: request)

        XCTAssertEqual(draft.matchedPreset, .recommendedMinimal)
        XCTAssertEqual(draft.paidModelSelectionMode, .off)
        XCTAssertEqual(draft.defaultWebFetchEnabled, false)
        XCTAssertEqual(draft.dailyTokenLimit, 200_000)
    }

    func testApprovedOutcomeDetailIncludesPresetAndBoundarySummary() {
        let request = makeRequest(deviceName: "XT Recommended")
        let draft = HubPairingApprovalDraft.recommended(for: request)

        XCTAssertTrue(draft.approvedOutcomeDetailText.contains("最小接入"))
        XCTAssertTrue(draft.approvedOutcomeDetailText.contains("付费模型关闭"))
        XCTAssertTrue(draft.approvedOutcomeDetailText.contains("网页抓取关闭"))
    }

    func testShouldPromotePendingPairingNotificationOnlyForHubPairingRequests() {
        let pairing = HubNotification.make(
            source: "Hub",
            title: "Pairing request",
            body: "pending",
            dedupeKey: "pairing_request:req-1"
        )
        let wrongSource = HubNotification.make(
            source: "X-Terminal",
            title: "Pairing request",
            body: "pending",
            dedupeKey: "pairing_request:req-2"
        )
        let wrongKey = HubNotification.make(
            source: "Hub",
            title: "Other",
            body: "pending",
            dedupeKey: "operator_channel:req-1"
        )

        XCTAssertTrue(HubStore.shouldPromotePendingPairingNotification(pairing))
        XCTAssertFalse(HubStore.shouldPromotePendingPairingNotification(wrongSource))
        XCTAssertFalse(HubStore.shouldPromotePendingPairingNotification(wrongKey))
    }

    func testApprovePairingRequestBlocksDuplicateSubmitWhileInFlight() async {
        let store = HubStore(startServices: false)
        let request = makeRequest(deviceName: "XT Test")
        let approval = HubPairingApprovalDraft.suggested(for: request)

        let submitStarted = expectation(description: "submit started")
        let submitFinished = expectation(description: "submit finished")

        var submitCount = 0
        var releaseSubmit: CheckedContinuation<Void, Never>?

        store.pairingApprovalAuthenticationOverride = { _, _ in }
        store.pairingApprovalSubmitOverride = { _, _, _ in
            submitCount += 1
            submitStarted.fulfill()
            await withCheckedContinuation { continuation in
                releaseSubmit = continuation
            }
            submitFinished.fulfill()
            return "dev-xt-test"
        }

        defer {
            store.pairingApprovalAuthenticationOverride = nil
            store.pairingApprovalSubmitOverride = nil
            releaseSubmit?.resume()
        }

        store.approvePairingRequest(request, approval: approval)
        XCTAssertTrue(store.isPairingApprovalInFlight(request))

        store.approvePairingRequest(request, approval: approval)

        await fulfillment(of: [submitStarted], timeout: 1.0)
        XCTAssertEqual(submitCount, 1)
        XCTAssertTrue(store.isPairingApprovalInFlight(request))

        releaseSubmit?.resume()
        releaseSubmit = nil

        await fulfillment(of: [submitFinished], timeout: 1.0)
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(submitCount, 1)
        XCTAssertFalse(store.isPairingApprovalInFlight(request))
        XCTAssertEqual(store.latestPairingApprovalOutcome?.kind, .approved)
        XCTAssertEqual(store.latestPairingApprovalOutcome?.deviceTitle, approval.normalizedDeviceName)
        XCTAssertEqual(store.latestPairingApprovalOutcome?.deviceID, "dev-xt-test")
    }

    func testApprovePairingRequestFailsClosedWhenOwnerAuthenticationFails() async {
        let store = HubStore(startServices: false)
        let request = makeRequest(deviceName: "XT Test")
        let approval = HubPairingApprovalDraft.suggested(for: request)

        var submitCount = 0
        store.pairingApprovalAuthenticationOverride = { _, _ in
            throw NSError(
                domain: "HubStorePairingApprovalTests",
                code: 23,
                userInfo: [NSLocalizedDescriptionKey: "owner auth failed"]
            )
        }
        store.pairingApprovalSubmitOverride = { _, _, _ in
            submitCount += 1
            return nil
        }

        defer {
            store.pairingApprovalAuthenticationOverride = nil
            store.pairingApprovalSubmitOverride = nil
        }

        store.approvePairingRequest(request, approval: approval)
        XCTAssertTrue(store.isPairingApprovalInFlight(request))

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(submitCount, 0)
        XCTAssertFalse(store.isPairingApprovalInFlight(request))
        XCTAssertEqual(store.latestPairingApprovalOutcome?.kind, .ownerAuthenticationFailed)
        XCTAssertEqual(store.latestPairingApprovalOutcome?.deviceTitle, approval.normalizedDeviceName)
    }

    func testApprovePairingRequestRecordsCancelledOwnerAuthenticationOutcome() async {
        let store = HubStore(startServices: false)
        let request = makeRequest(deviceName: "XT Cancelled")
        let approval = HubPairingApprovalDraft.suggested(for: request)

        store.pairingApprovalAuthenticationOverride = { _, _ in
            throw NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue)
        }
        store.pairingApprovalSubmitOverride = { _, _, _ in
            XCTFail("submit should not run when owner authentication is cancelled")
            return nil
        }

        defer {
            store.pairingApprovalAuthenticationOverride = nil
            store.pairingApprovalSubmitOverride = nil
        }

        store.approvePairingRequest(request, approval: approval)
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(store.latestPairingApprovalOutcome?.kind, .ownerAuthenticationCancelled)
        XCTAssertEqual(store.latestPairingApprovalOutcome?.deviceTitle, approval.normalizedDeviceName)
    }

    func testApprovePairingRequestDismissesPendingPairingNotificationAfterSuccess() async {
        let store = HubStore(startServices: false)
        let request = makeRequest(deviceName: "XT Inbox")
        let approval = HubPairingApprovalDraft.suggested(for: request)
        let dedupeKey = "pairing_request:\(request.pairingRequestId)"

        store.push(
            HubNotification.make(
                source: "Hub",
                title: "Pairing request",
                body: "pending",
                dedupeKey: dedupeKey
            )
        )

        store.pairingApprovalAuthenticationOverride = { _, _ in }
        store.pairingApprovalSubmitOverride = { _, _, _ in
            "dev-xt-inbox"
        }

        defer {
            store.pairingApprovalAuthenticationOverride = nil
            store.pairingApprovalSubmitOverride = nil
        }

        store.approvePairingRequest(request, approval: approval)
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertFalse(store.notifications.contains(where: { $0.dedupeKey == dedupeKey }))
        XCTAssertTrue(
            store.notifications.contains(where: {
                $0.title == HubStoreNotificationCopy.pairingApprovedTitle()
            })
        )
        XCTAssertTrue(
            store.notifications.contains(where: {
                $0.title == HubStoreNotificationCopy.pairingApprovedTitle()
                    && $0.actionURL == "relflowhub://settings/paired-devices?device_id=dev-xt-inbox"
            })
        )
    }

    func testOpenNotificationActionRoutesPairedDeviceSettingsInHub() {
        let store = HubStore(startServices: false)
        let notification = HubNotification.make(
            source: "Hub",
            title: "Open paired device settings",
            body: "",
            actionURL: "relflowhub://settings/paired-devices?device_id=dev-xt-42"
        )

        store.openNotificationAction(notification)

        XCTAssertEqual(
            store.settingsNavigationTarget,
            .pairedDevices(deviceID: "dev-xt-42", capabilityKey: nil)
        )
    }

    func testOpenNotificationActionRoutesPairedDeviceCapabilityFocusInHub() {
        let store = HubStore(startServices: false)
        let notification = HubNotification.make(
            source: "Hub",
            title: "Open paired device settings",
            body: "",
            actionURL: "relflowhub://settings/paired-devices?device_id=dev-xt-42&capability=web.fetch"
        )

        store.openNotificationAction(notification)

        XCTAssertEqual(
            store.settingsNavigationTarget,
            .pairedDevices(deviceID: "dev-xt-42", capabilityKey: "web.fetch")
        )
    }

    func testOpenPairedDevicesSettingsNormalizesCapabilityFocusKey() {
        let store = HubStore(startServices: false)

        store.openPairedDevicesSettings(deviceID: "dev-xt-7", capabilityKey: "付费 AI")

        XCTAssertEqual(
            store.settingsNavigationTarget,
            .pairedDevices(deviceID: "dev-xt-7", capabilityKey: "ai.generate.paid")
        )
    }

    private func makeRequest(
        deviceName: String,
        claimedDeviceId: String = "xt-device",
        appId: String = "paired-terminal"
    ) -> HubPairingRequest {
        HubPairingRequest(
            pairingRequestId: "pairing-\(UUID().uuidString)",
            requestId: "request-\(UUID().uuidString)",
            status: "pending",
            appId: appId,
            claimedDeviceId: claimedDeviceId,
            userId: "owner",
            deviceName: deviceName,
            peerIp: "192.168.1.8",
            createdAtMs: 1,
            decidedAtMs: 0,
            denyReason: "",
            requestedScopes: ["chat", "web_fetch"]
        )
    }
}
