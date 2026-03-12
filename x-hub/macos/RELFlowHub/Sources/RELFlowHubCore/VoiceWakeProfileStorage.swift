import Foundation

private struct StoredVoiceWakeProfile: Codable {
    var schemaVersion: String
    var profileID: String
    var triggerWords: [String]
    var updatedAtMs: Int64
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case profileID = "profile_id"
        case triggerWords = "trigger_words"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }
}

public enum HubVoiceWakeProfileStorage {
    public static let storeSchemaVersion = "hub.voice_wake_profile_store.v1"
    public static let profileSchemaVersion = "xt.supervisor_voice_wake_profile.v1"
    public static let defaultAuditRef = "hub.voice_wake_profile_sync.v1"
    public static let defaultProfileID = "default"
    public static let defaultTriggerWords = ["x hub", "supervisor"]
    public static let maxTriggerCount = 6
    public static let maxTriggerLength = 48
    public static let fileName = "voice_wake_profile.json"

    public static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func fetch(desiredWakeMode: String) -> IPCVoiceWakeProfile {
        projectedProfile(from: loadStoredProfile(), desiredWakeMode: desiredWakeMode)
    }

    public static func update(profile: IPCVoiceWakeProfile) -> IPCVoiceWakeProfile {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let stored = StoredVoiceWakeProfile(
            schemaVersion: storeSchemaVersion,
            profileID: normalizedProfileID(profile.profileID),
            triggerWords: sanitizeTriggerWords(profile.triggerWords),
            updatedAtMs: nowMs,
            auditRef: normalizedAuditRef(profile.auditRef)
        )
        saveStoredProfile(stored)
        return projectedProfile(from: stored, desiredWakeMode: profile.wakeMode)
    }

    public static func sanitizeTriggerWords(_ raw: [String], fallbackToDefaults: Bool = true) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in raw {
            let token = String(
                item
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .prefix(maxTriggerLength)
            )
            guard !token.isEmpty else { continue }
            guard seen.insert(token).inserted else { continue }
            ordered.append(token)
            if ordered.count >= maxTriggerCount {
                break
            }
        }
        if ordered.isEmpty, fallbackToDefaults {
            return defaultTriggerWords
        }
        return ordered
    }

    public static func normalizedWakeMode(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "prompt_phrase_only":
            return "prompt_phrase_only"
        case "wake_phrase":
            return "wake_phrase"
        default:
            return "wake_phrase"
        }
    }

    private static func normalizedProfileID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultProfileID : trimmed
    }

    private static func normalizedAuditRef(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultAuditRef : trimmed
    }

    private static func projectedProfile(from stored: StoredVoiceWakeProfile, desiredWakeMode: String) -> IPCVoiceWakeProfile {
        IPCVoiceWakeProfile(
            schemaVersion: profileSchemaVersion,
            profileID: normalizedProfileID(stored.profileID),
            triggerWords: sanitizeTriggerWords(stored.triggerWords),
            updatedAtMs: max(0, stored.updatedAtMs),
            scope: "paired_device_group",
            source: "hub_pairing_sync",
            wakeMode: normalizedWakeMode(desiredWakeMode),
            requiresPairingReady: true,
            auditRef: normalizedAuditRef(stored.auditRef)
        )
    }

    private static func loadStoredProfile() -> StoredVoiceWakeProfile {
        let fileURL = url()
        guard let data = try? Data(contentsOf: fileURL) else {
            return StoredVoiceWakeProfile(
                schemaVersion: storeSchemaVersion,
                profileID: defaultProfileID,
                triggerWords: defaultTriggerWords,
                updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                auditRef: defaultAuditRef
            )
        }

        if let stored = try? JSONDecoder().decode(StoredVoiceWakeProfile.self, from: data) {
            return StoredVoiceWakeProfile(
                schemaVersion: storeSchemaVersion,
                profileID: normalizedProfileID(stored.profileID),
                triggerWords: sanitizeTriggerWords(stored.triggerWords),
                updatedAtMs: max(0, stored.updatedAtMs),
                auditRef: normalizedAuditRef(stored.auditRef)
            )
        }

        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let profile = (root["profile"] as? [String: Any]) ?? root as [String: Any]? {
            let triggerWords = profile["trigger_words"] as? [String] ?? profile["triggerWords"] as? [String] ?? []
            let updatedAtMs = (profile["updated_at_ms"] as? NSNumber)?.int64Value
                ?? (profile["updatedAtMs"] as? NSNumber)?.int64Value
                ?? Int64(Date().timeIntervalSince1970 * 1000)
            return StoredVoiceWakeProfile(
                schemaVersion: storeSchemaVersion,
                profileID: normalizedProfileID((profile["profile_id"] as? String) ?? (profile["profileID"] as? String) ?? defaultProfileID),
                triggerWords: sanitizeTriggerWords(triggerWords),
                updatedAtMs: max(0, updatedAtMs),
                auditRef: normalizedAuditRef((profile["audit_ref"] as? String) ?? (profile["auditRef"] as? String))
            )
        }

        return StoredVoiceWakeProfile(
            schemaVersion: storeSchemaVersion,
            profileID: defaultProfileID,
            triggerWords: defaultTriggerWords,
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            auditRef: defaultAuditRef
        )
    }

    private static func saveStoredProfile(_ stored: StoredVoiceWakeProfile) {
        let fileURL = url()
        let tmpURL = fileURL.appendingPathExtension("tmp")
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: tmpURL, options: .atomic)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.moveItem(at: tmpURL, to: fileURL)
    }
}
