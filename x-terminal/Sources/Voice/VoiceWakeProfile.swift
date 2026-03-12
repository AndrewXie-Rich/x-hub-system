import Foundation

enum VoiceWakeProfileScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case pairedDeviceGroup = "paired_device_group"
    case localDevice = "local_device"

    var id: String { rawValue }
}

enum VoiceWakeProfileSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case hubPairingSync = "hub_pairing_sync"
    case localOverride = "local_override"
    case cachedFallback = "cached_fallback"

    var id: String { rawValue }
}

enum VoiceWakeProfileSyncState: String, Codable, Equatable, Sendable {
    case notRequired = "not_required"
    case pairedSynced = "paired_synced"
    case localOverrideActive = "local_override_active"
    case waitingForPairing = "waiting_for_pairing"
    case stale = "stale"
    case syncUnavailable = "sync_unavailable"
    case invalid = "invalid"
}

struct VoiceWakeProfile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_voice_wake_profile.v1"
    static let defaultTriggerWords = ["x hub", "supervisor"]
    static let maxTriggerCount = 6
    static let maxTriggerLength = 48

    var schemaVersion: String
    var profileID: String
    var triggerWords: [String]
    var updatedAtMs: Int64
    var scope: VoiceWakeProfileScope
    var source: VoiceWakeProfileSource
    var wakeMode: VoiceWakeMode
    var requiresPairingReady: Bool
    var auditRef: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case profileID = "profile_id"
        case triggerWords = "trigger_words"
        case updatedAtMs = "updated_at_ms"
        case scope
        case source
        case wakeMode = "wake_mode"
        case requiresPairingReady = "requires_pairing_ready"
        case auditRef = "audit_ref"
    }

    var normalizedTriggerWords: [String] {
        Self.sanitizeTriggerWords(triggerWords)
    }

    var isValid: Bool {
        !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !normalizedTriggerWords.isEmpty &&
        wakeMode != .pushToTalk
    }

    func sanitized() -> VoiceWakeProfile {
        var copy = self
        copy.schemaVersion = Self.currentSchemaVersion
        let trimmedProfileID = copy.profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.profileID = trimmedProfileID.isEmpty ? "default" : trimmedProfileID
        copy.triggerWords = normalizedTriggerWords
        if copy.updatedAtMs < 0 {
            copy.updatedAtMs = 0
        }
        return copy
    }

    static func migratedLocalOverride(
        wakeMode: VoiceWakeMode,
        triggerWords: [String] = VoiceWakeProfile.defaultTriggerWords,
        now: Date = Date()
    ) -> VoiceWakeProfile {
        VoiceWakeProfile(
            schemaVersion: currentSchemaVersion,
            profileID: "default",
            triggerWords: sanitizeTriggerWords(triggerWords),
            updatedAtMs: Int64(now.timeIntervalSince1970 * 1000),
            scope: .localDevice,
            source: .localOverride,
            wakeMode: wakeMode,
            requiresPairingReady: false,
            auditRef: "xt_w3_29_p1_local_override_migration"
        )
    }

    static func parseTriggerWordsText(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n\r\t|/\\，、")
        return sanitizeTriggerWords(raw.components(separatedBy: separators))
    }

    static func sanitizeTriggerWords(
        _ raw: [String],
        fallbackToDefaults: Bool = true
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in raw {
            let token = item
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .prefix(maxTriggerLength)
            guard !token.isEmpty else { continue }
            let value = String(token)
            guard seen.insert(value).inserted else { continue }
            ordered.append(value)
            if ordered.count >= maxTriggerCount {
                break
            }
        }
        if ordered.isEmpty, fallbackToDefaults {
            return defaultTriggerWords
        }
        return ordered
    }

    static func formatTriggerWords(_ raw: [String]) -> String {
        sanitizeTriggerWords(raw).joined(separator: ", ")
    }
}

struct VoiceWakeProfileSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.voice_wake_profile_snapshot.v1"

    var schemaVersion: String
    var generatedAtMs: Int64
    var desiredWakeMode: VoiceWakeMode
    var effectiveWakeMode: VoiceWakeMode
    var syncState: VoiceWakeProfileSyncState
    var reasonCode: String
    var profile: VoiceWakeProfile?
    var usedCachedProfile: Bool
    var lastSyncAtMs: Int64?
    var lastRemoteReasonCode: String?

    var triggerWords: [String] {
        profile?.normalizedTriggerWords ?? []
    }

    var runtimeReady: Bool {
        effectiveWakeMode != .pushToTalk || syncState == .notRequired
    }

    var profileSource: VoiceWakeProfileSource? {
        profile?.source
    }

    static let empty = VoiceWakeProfileSnapshot(
        schemaVersion: currentSchemaVersion,
        generatedAtMs: 0,
        desiredWakeMode: .pushToTalk,
        effectiveWakeMode: .pushToTalk,
        syncState: .notRequired,
        reasonCode: "wake_profile_not_required",
        profile: nil,
        usedCachedProfile: false,
        lastSyncAtMs: nil,
        lastRemoteReasonCode: nil
    )
}
