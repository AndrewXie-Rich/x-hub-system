import Foundation

struct VoiceNodeSyncSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.voice_node_sync_snapshot.v1"

    var schemaVersion: String
    var generatedAtMs: Int64
    var localConnected: Bool
    var remoteConnected: Bool
    var linking: Bool
    var remoteRoute: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
    var currentVoiceRoute: String
    var desiredWakeMode: String
    var effectiveWakeMode: String
    var wakeCapability: String
    var wakeProfileSyncState: String
    var wakeProfileSource: String
    var wakeProfileReasonCode: String
    var wakeTriggerWords: [String]
    var bridgeAlive: Bool
    var bridgeEnabled: Bool
    var toolRouteExecutable: Bool
    var sessionID: String?
    var sessionTitle: String?
    var sessionState: String
    var conversationWindowState: String

    static let empty = VoiceNodeSyncSnapshot(
        schemaVersion: currentSchemaVersion,
        generatedAtMs: 0,
        localConnected: false,
        remoteConnected: false,
        linking: false,
        remoteRoute: HubRemoteRoute.none.rawValue,
        pairingPort: 50052,
        grpcPort: 50051,
        internetHost: "",
        currentVoiceRoute: VoiceRouteMode.manualText.rawValue,
        desiredWakeMode: VoiceWakeMode.pushToTalk.rawValue,
        effectiveWakeMode: VoiceWakeMode.pushToTalk.rawValue,
        wakeCapability: "push_to_talk_only",
        wakeProfileSyncState: VoiceWakeProfileSyncState.notRequired.rawValue,
        wakeProfileSource: "none",
        wakeProfileReasonCode: "wake_profile_not_required",
        wakeTriggerWords: [],
        bridgeAlive: false,
        bridgeEnabled: false,
        toolRouteExecutable: false,
        sessionID: nil,
        sessionTitle: nil,
        sessionState: AXSessionRuntimeState.idle.rawValue,
        conversationWindowState: SupervisorConversationWindowState.hidden.rawValue
    )
}
