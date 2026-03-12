import Foundation

struct VoiceWakeProfileStoreState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.voice_wake_profile_store.v1"

    var schemaVersion: String
    var pairedProfile: VoiceWakeProfile?
    var localOverrideProfile: VoiceWakeProfile?
    var lastSyncAtMs: Int64?
}

@MainActor
final class VoiceWakeProfileStore: ObservableObject {
    static let shared = VoiceWakeProfileStore()

    @Published private(set) var snapshot: VoiceWakeProfileSnapshot

    private let url: URL
    private let syncClient: any VoiceWakeSyncClient
    private let nowProvider: () -> Date
    private let staleAfterMs: Int64
    private var state: VoiceWakeProfileStoreState
    private var desiredWakeMode: VoiceWakeMode
    private var lastPairingReady: Bool = false

    init(
        url: URL? = nil,
        syncClient: any VoiceWakeSyncClient = HubVoiceWakeSyncClient(),
        nowProvider: @escaping () -> Date = Date.init,
        staleAfterSec: TimeInterval = 86_400,
        seededState: VoiceWakeProfileStoreState? = nil
    ) {
        self.syncClient = syncClient
        self.nowProvider = nowProvider
        self.staleAfterMs = Int64(max(60, staleAfterSec) * 1000)

        let fm = FileManager.default
        let resolvedURL: URL = {
            if let url { return url }
            let supportBase = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("voice_wake_profile.json")
        }()
        self.url = resolvedURL

        if let seededState {
            self.state = seededState
        } else if let data = try? Data(contentsOf: resolvedURL),
                  let decoded = try? JSONDecoder().decode(VoiceWakeProfileStoreState.self, from: data) {
            self.state = decoded
        } else {
            self.state = VoiceWakeProfileStoreState(
                schemaVersion: VoiceWakeProfileStoreState.currentSchemaVersion,
                pairedProfile: nil,
                localOverrideProfile: nil,
                lastSyncAtMs: nil
            )
        }

        self.desiredWakeMode = .pushToTalk
        self.snapshot = .empty
        self.snapshot = buildSnapshot(pairingReady: false, remoteResult: nil)
    }

    func applyPreferences(_ preferences: VoiceRuntimePreferences) {
        desiredWakeMode = preferences.wakeMode
        if desiredWakeMode != .pushToTalk {
            ensureLocalOverrideProfile(for: desiredWakeMode)
        }
        snapshot = buildSnapshot(pairingReady: lastPairingReady, remoteResult: nil)
        persist()
    }

    func setLocalOverrideTriggerWords(_ rawText: String) {
        let wakeMode = resolvedEditableWakeMode()
        state.localOverrideProfile = VoiceWakeProfile.migratedLocalOverride(
            wakeMode: wakeMode,
            triggerWords: VoiceWakeProfile.parseTriggerWordsText(rawText),
            now: nowProvider()
        )
        snapshot = buildSnapshot(pairingReady: lastPairingReady, remoteResult: nil)
        persist()
    }

    func restoreDefaultLocalOverrideTriggerWords() {
        let wakeMode = resolvedEditableWakeMode()
        state.localOverrideProfile = VoiceWakeProfile.migratedLocalOverride(
            wakeMode: wakeMode,
            triggerWords: VoiceWakeProfile.defaultTriggerWords,
            now: nowProvider()
        )
        snapshot = buildSnapshot(pairingReady: lastPairingReady, remoteResult: nil)
        persist()
    }

    func refresh(pairingReady: Bool) async {
        lastPairingReady = pairingReady
        snapshot = buildSnapshot(pairingReady: pairingReady, remoteResult: nil)

        guard desiredWakeMode != .pushToTalk else { return }
        guard pairingReady else { return }

        let remote = await syncClient.fetchWakeProfile(desiredWakeMode: desiredWakeMode)
        applyRemoteResult(remote)
        snapshot = buildSnapshot(pairingReady: pairingReady, remoteResult: remote)
        persist()
    }

    func pushLocalOverrideToHub(pairingReady: Bool) async -> VoiceWakeProfileSyncResult {
        lastPairingReady = pairingReady
        snapshot = buildSnapshot(pairingReady: pairingReady, remoteResult: nil)

        guard desiredWakeMode != .pushToTalk else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "voice_wake_profile_store",
                profile: nil,
                reasonCode: "wake_profile_not_required",
                logLines: ["voice wake profile push skipped for push-to-talk mode"],
                syncedAtMs: nil
            )
        }
        guard pairingReady else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "voice_wake_profile_store",
                profile: nil,
                reasonCode: "wake_profile_waiting_for_pairing",
                logLines: ["voice wake profile push requires pairing-ready route"],
                syncedAtMs: nil
            )
        }
        guard let profile = validLocalOverrideProfile() else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "voice_wake_profile_store",
                profile: nil,
                reasonCode: "wake_profile_local_override_missing",
                logLines: ["voice wake profile push missing valid local override"],
                syncedAtMs: nil
            )
        }

        let remote = await syncClient.setWakeProfile(profile)
        applyRemoteResult(remote)
        snapshot = buildSnapshot(pairingReady: pairingReady, remoteResult: remote)
        persist()
        return remote
    }

    private func applyRemoteResult(_ remote: VoiceWakeProfileSyncResult) {
        guard remote.ok else { return }
        guard let profile = remote.profile?.sanitized(), profile.isValid else { return }
        state.pairedProfile = VoiceWakeProfile(
            schemaVersion: VoiceWakeProfile.currentSchemaVersion,
            profileID: profile.profileID,
            triggerWords: profile.normalizedTriggerWords,
            updatedAtMs: profile.updatedAtMs,
            scope: .pairedDeviceGroup,
            source: .hubPairingSync,
            wakeMode: profile.wakeMode,
            requiresPairingReady: true,
            auditRef: profile.auditRef
        )
        state.lastSyncAtMs = remote.syncedAtMs ?? Int64(nowProvider().timeIntervalSince1970 * 1000)
    }

    private func buildSnapshot(
        pairingReady: Bool,
        remoteResult: VoiceWakeProfileSyncResult?
    ) -> VoiceWakeProfileSnapshot {
        let nowMs = Int64(nowProvider().timeIntervalSince1970 * 1000)
        let normalizedRemoteReason = normalizedReasonCode(remoteResult?.reasonCode)
        let localOverride = validLocalOverrideProfile()
        let pairedProfile = validPairedProfile()
        let pairedProfileFresh = isFresh(lastSyncAtMs: state.lastSyncAtMs, nowMs: nowMs)

        if desiredWakeMode == .pushToTalk {
            return VoiceWakeProfileSnapshot(
                schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                generatedAtMs: nowMs,
                desiredWakeMode: desiredWakeMode,
                effectiveWakeMode: .pushToTalk,
                syncState: .notRequired,
                reasonCode: "wake_profile_not_required",
                profile: nil,
                usedCachedProfile: false,
                lastSyncAtMs: state.lastSyncAtMs,
                lastRemoteReasonCode: normalizedRemoteReason
            )
        }

        if let remoteResult, remoteResult.ok == true, let pairedProfile {
            return VoiceWakeProfileSnapshot(
                schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                generatedAtMs: nowMs,
                desiredWakeMode: desiredWakeMode,
                effectiveWakeMode: pairedProfile.wakeMode,
                syncState: .pairedSynced,
                reasonCode: "wake_profile_pair_synced",
                profile: pairedProfile,
                usedCachedProfile: false,
                lastSyncAtMs: state.lastSyncAtMs,
                lastRemoteReasonCode: nil
            )
        }

        if pairingReady, let pairedProfile, pairedProfileFresh {
            return VoiceWakeProfileSnapshot(
                schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                generatedAtMs: nowMs,
                desiredWakeMode: desiredWakeMode,
                effectiveWakeMode: pairedProfile.wakeMode,
                syncState: .pairedSynced,
                reasonCode: remoteResult == nil ? "wake_profile_cached_pair_sync" : "wake_profile_pair_sync_cached_after_remote_failure",
                profile: pairedProfile,
                usedCachedProfile: true,
                lastSyncAtMs: state.lastSyncAtMs,
                lastRemoteReasonCode: normalizedRemoteReason
            )
        }

        if let localOverride {
            return VoiceWakeProfileSnapshot(
                schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                generatedAtMs: nowMs,
                desiredWakeMode: desiredWakeMode,
                effectiveWakeMode: localOverride.wakeMode,
                syncState: .localOverrideActive,
                reasonCode: normalizedRemoteReason == nil
                    ? "wake_profile_local_override_active"
                    : "wake_profile_local_override_fallback",
                profile: localOverride,
                usedCachedProfile: true,
                lastSyncAtMs: state.lastSyncAtMs,
                lastRemoteReasonCode: normalizedRemoteReason
            )
        }

        if let pairedProfile {
            return VoiceWakeProfileSnapshot(
                schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                generatedAtMs: nowMs,
                desiredWakeMode: desiredWakeMode,
                effectiveWakeMode: .pushToTalk,
                syncState: .stale,
                reasonCode: "wake_profile_stale",
                profile: pairedProfile,
                usedCachedProfile: true,
                lastSyncAtMs: state.lastSyncAtMs,
                lastRemoteReasonCode: normalizedRemoteReason
            )
        }

        if pairingReady {
            return VoiceWakeProfileSnapshot(
                schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
                generatedAtMs: nowMs,
                desiredWakeMode: desiredWakeMode,
                effectiveWakeMode: .pushToTalk,
                syncState: remoteResult == nil ? .waitingForPairing : .syncUnavailable,
                reasonCode: normalizedRemoteReason ?? (remoteResult == nil ? "wake_profile_sync_pending" : "voice_wake_profile_sync_unavailable"),
                profile: nil,
                usedCachedProfile: false,
                lastSyncAtMs: state.lastSyncAtMs,
                lastRemoteReasonCode: normalizedRemoteReason
            )
        }

        return VoiceWakeProfileSnapshot(
            schemaVersion: VoiceWakeProfileSnapshot.currentSchemaVersion,
            generatedAtMs: nowMs,
            desiredWakeMode: desiredWakeMode,
            effectiveWakeMode: .pushToTalk,
            syncState: .waitingForPairing,
            reasonCode: "wake_profile_waiting_for_pairing",
            profile: nil,
            usedCachedProfile: false,
            lastSyncAtMs: state.lastSyncAtMs,
            lastRemoteReasonCode: normalizedRemoteReason
        )
    }

    private func ensureLocalOverrideProfile(for wakeMode: VoiceWakeMode) {
        let triggerWords = state.localOverrideProfile?.normalizedTriggerWords ?? VoiceWakeProfile.defaultTriggerWords
        state.localOverrideProfile = VoiceWakeProfile.migratedLocalOverride(
            wakeMode: wakeMode,
            triggerWords: triggerWords,
            now: nowProvider()
        )
    }

    private func validLocalOverrideProfile() -> VoiceWakeProfile? {
        guard var profile = state.localOverrideProfile?.sanitized(), profile.isValid else { return nil }
        profile.wakeMode = desiredWakeMode
        profile.updatedAtMs = max(profile.updatedAtMs, Int64(nowProvider().timeIntervalSince1970 * 1000))
        return profile
    }

    private func validPairedProfile() -> VoiceWakeProfile? {
        guard let profile = state.pairedProfile?.sanitized(), profile.isValid else { return nil }
        return profile
    }

    private func resolvedEditableWakeMode() -> VoiceWakeMode {
        if desiredWakeMode != .pushToTalk {
            return desiredWakeMode
        }
        if let local = state.localOverrideProfile?.wakeMode, local != .pushToTalk {
            return local
        }
        return .wakePhrase
    }

    private func isFresh(lastSyncAtMs: Int64?, nowMs: Int64) -> Bool {
        guard let lastSyncAtMs, lastSyncAtMs > 0 else { return false }
        return nowMs - lastSyncAtMs <= staleAfterMs
    }

    private func normalizedReasonCode(_ raw: String?) -> String? {
        guard var token = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        token = token.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return token.isEmpty ? nil : token
    }

    private func persist() {
        var copy = state
        copy.schemaVersion = VoiceWakeProfileStoreState.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(copy) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
