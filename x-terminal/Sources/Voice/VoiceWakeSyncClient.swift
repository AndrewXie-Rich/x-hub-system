import Foundation

struct VoiceWakeProfileSyncResult: Equatable, Sendable {
    var ok: Bool
    var source: String
    var profile: VoiceWakeProfile?
    var reasonCode: String?
    var logLines: [String]
    var syncedAtMs: Int64?
}

protocol VoiceWakeSyncClient {
    func fetchWakeProfile(desiredWakeMode: VoiceWakeMode) async -> VoiceWakeProfileSyncResult
    func setWakeProfile(_ profile: VoiceWakeProfile) async -> VoiceWakeProfileSyncResult
}

struct HubVoiceWakeSyncClient: VoiceWakeSyncClient {
    func fetchWakeProfile(desiredWakeMode: VoiceWakeMode) async -> VoiceWakeProfileSyncResult {
        await HubIPCClient.fetchVoiceWakeProfile(desiredWakeMode: desiredWakeMode)
    }

    func setWakeProfile(_ profile: VoiceWakeProfile) async -> VoiceWakeProfileSyncResult {
        await HubIPCClient.setVoiceWakeProfile(profile)
    }
}
