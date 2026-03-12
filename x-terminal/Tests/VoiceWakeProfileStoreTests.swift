import Foundation
import Testing
@testable import XTerminal

@MainActor
struct VoiceWakeProfileStoreTests {
    @Test
    func localTriggerWordsNormalizeAndFallbackToDefaults() {
        #expect(
            VoiceWakeProfile.parseTriggerWordsText(" x hub, supervisor , x hub ,,  ")
                == ["x hub", "supervisor"]
        )
        #expect(
            VoiceWakeProfile.parseTriggerWordsText(" , , ")
                == VoiceWakeProfile.defaultTriggerWords
        )
    }

    @Test
    func localOverrideKeepsWakeModeUsableWhenRemoteSyncIsUnavailable() async throws {
        let client = MockVoiceWakeSyncClient(
            result: VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "voice_wake_profile_remote_not_supported",
                logLines: [],
                syncedAtMs: nil
            )
        )
        let store = VoiceWakeProfileStore(
            url: temporaryWakeProfileURL(),
            syncClient: client,
            nowProvider: { Date(timeIntervalSince1970: 10_000) }
        )

        var preferences = VoiceRuntimePreferences.default()
        preferences.wakeMode = .wakePhrase
        store.applyPreferences(preferences)
        await store.refresh(pairingReady: true)

        #expect(store.snapshot.syncState == .localOverrideActive)
        #expect(store.snapshot.effectiveWakeMode == .wakePhrase)
        #expect(store.snapshot.reasonCode == "wake_profile_local_override_fallback")
        #expect(store.snapshot.lastRemoteReasonCode == "voice_wake_profile_remote_not_supported")
        #expect(store.snapshot.triggerWords == VoiceWakeProfile.defaultTriggerWords)
    }

    @Test
    func remoteSyncOverridesLocalFallbackWhenPairProfileArrives() async throws {
        let seededState = VoiceWakeProfileStoreState(
            schemaVersion: VoiceWakeProfileStoreState.currentSchemaVersion,
            pairedProfile: nil,
            localOverrideProfile: VoiceWakeProfile(
                schemaVersion: VoiceWakeProfile.currentSchemaVersion,
                profileID: "default",
                triggerWords: ["x hub"],
                updatedAtMs: 9_000_000,
                scope: .localDevice,
                source: .localOverride,
                wakeMode: .wakePhrase,
                requiresPairingReady: false,
                auditRef: nil
            ),
            lastSyncAtMs: nil
        )
        let client = MockVoiceWakeSyncClient(
            result: VoiceWakeProfileSyncResult(
                ok: true,
                source: "hub_memory_v1_grpc",
                profile: VoiceWakeProfile(
                    schemaVersion: VoiceWakeProfile.currentSchemaVersion,
                    profileID: "team-default",
                    triggerWords: ["x hub ops"],
                    updatedAtMs: 200_000_000,
                    scope: .pairedDeviceGroup,
                    source: .hubPairingSync,
                    wakeMode: .promptPhraseOnly,
                    requiresPairingReady: true,
                    auditRef: "audit-1"
                ),
                reasonCode: nil,
                logLines: [],
                syncedAtMs: 200_000_000
            )
        )
        let store = VoiceWakeProfileStore(
            url: temporaryWakeProfileURL(),
            syncClient: client,
            nowProvider: { Date(timeIntervalSince1970: 200_000) },
            seededState: seededState
        )

        var preferences = VoiceRuntimePreferences.default()
        preferences.wakeMode = .wakePhrase
        store.applyPreferences(preferences)
        await store.refresh(pairingReady: true)

        #expect(store.snapshot.syncState == .pairedSynced)
        #expect(store.snapshot.effectiveWakeMode == .promptPhraseOnly)
        #expect(store.snapshot.profile?.profileID == "team-default")
    }

    @Test
    func editingLocalOverrideTriggerWordsUpdatesSnapshotImmediately() async throws {
        let store = VoiceWakeProfileStore(
            url: temporaryWakeProfileURL(),
            syncClient: MockVoiceWakeSyncClient(
                result: VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "hub_memory_v1_grpc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_remote_not_supported",
                    logLines: [],
                    syncedAtMs: nil
                )
            ),
            nowProvider: { Date(timeIntervalSince1970: 50_000) }
        )

        var preferences = VoiceRuntimePreferences.default()
        preferences.wakeMode = .wakePhrase
        store.applyPreferences(preferences)
        store.setLocalOverrideTriggerWords(" alpha , beta, alpha ")

        #expect(store.snapshot.triggerWords == ["alpha", "beta"])
        #expect(store.snapshot.syncState == .localOverrideActive)
        #expect(store.snapshot.effectiveWakeMode == .wakePhrase)
    }

    @Test
    func pushingLocalOverridePromotesHubPairProfileWhenSetSucceeds() async throws {
        let pushedProfile = VoiceWakeProfile(
            schemaVersion: VoiceWakeProfile.currentSchemaVersion,
            profileID: "team-default",
            triggerWords: ["ops hub", "supervisor"],
            updatedAtMs: 300_000_000,
            scope: .pairedDeviceGroup,
            source: .hubPairingSync,
            wakeMode: .wakePhrase,
            requiresPairingReady: true,
            auditRef: "audit-push"
        )
        let store = VoiceWakeProfileStore(
            url: temporaryWakeProfileURL(),
            syncClient: MockVoiceWakeSyncClient(
                result: VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "hub_memory_v1_grpc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_sync_unavailable",
                    logLines: [],
                    syncedAtMs: nil
                ),
                setResult: VoiceWakeProfileSyncResult(
                    ok: true,
                    source: "hub_memory_v1_grpc",
                    profile: pushedProfile,
                    reasonCode: nil,
                    logLines: [],
                    syncedAtMs: pushedProfile.updatedAtMs
                )
            ),
            nowProvider: { Date(timeIntervalSince1970: 300_000) }
        )

        var preferences = VoiceRuntimePreferences.default()
        preferences.wakeMode = .wakePhrase
        store.applyPreferences(preferences)
        store.setLocalOverrideTriggerWords("ops hub, supervisor")

        let result = await store.pushLocalOverrideToHub(pairingReady: true)

        #expect(result.ok == true)
        #expect(store.snapshot.syncState == .pairedSynced)
        #expect(store.snapshot.triggerWords == ["ops hub", "supervisor"])
        #expect(store.snapshot.profile?.profileID == "team-default")
    }
}

private struct MockVoiceWakeSyncClient: VoiceWakeSyncClient {
    var result: VoiceWakeProfileSyncResult
    var setResult: VoiceWakeProfileSyncResult? = nil

    func fetchWakeProfile(desiredWakeMode: VoiceWakeMode) async -> VoiceWakeProfileSyncResult {
        result
    }

    func setWakeProfile(_ profile: VoiceWakeProfile) async -> VoiceWakeProfileSyncResult {
        setResult ?? result
    }
}

private func temporaryWakeProfileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
}
