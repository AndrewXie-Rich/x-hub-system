import Foundation
import RELFlowHubCore

// Status snapshot exported by the embedded Node gRPC server into the Hub base dir.
// This keeps the Swift UI simple (no Swift gRPC client needed).

struct GRPCTokenSeriesPoint: Codable, Equatable, Sendable {
    var tMs: Int64
    var tokens: Int64

    enum CodingKeys: String, CodingKey {
        case tMs = "t_ms"
        case tokens
    }

    init(tMs: Int64, tokens: Int64) {
        self.tMs = tMs
        self.tokens = tokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tMs = (try? c.decode(Int64.self, forKey: .tMs)) ?? 0
        tokens = (try? c.decode(Int64.self, forKey: .tokens)) ?? 0
    }
}

struct GRPCTokenSeries: Codable, Equatable, Sendable {
    var windowMs: Int64
    var bucketMs: Int64
    var startMs: Int64
    var points: [GRPCTokenSeriesPoint]

    enum CodingKeys: String, CodingKey {
        case windowMs = "window_ms"
        case bucketMs = "bucket_ms"
        case startMs = "start_ms"
        case points
    }

    init(windowMs: Int64, bucketMs: Int64, startMs: Int64, points: [GRPCTokenSeriesPoint]) {
        self.windowMs = windowMs
        self.bucketMs = bucketMs
        self.startMs = startMs
        self.points = points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windowMs = (try? c.decode(Int64.self, forKey: .windowMs)) ?? 0
        bucketMs = (try? c.decode(Int64.self, forKey: .bucketMs)) ?? 0
        startMs = (try? c.decode(Int64.self, forKey: .startMs)) ?? 0
        points = (try? c.decode([GRPCTokenSeriesPoint].self, forKey: .points)) ?? []
    }
}

struct GRPCDeviceLastActivity: Codable, Equatable, Sendable {
    var eventType: String
    var createdAtMs: Int64
    var capability: String
    var modelId: String
    var totalTokens: Int64
    var networkAllowed: Bool
    var ok: Bool
    var errorCode: String
    var errorMessage: String

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case createdAtMs = "created_at_ms"
        case capability
        case modelId = "model_id"
        case totalTokens = "total_tokens"
        case networkAllowed = "network_allowed"
        case ok
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }

    init(
        eventType: String,
        createdAtMs: Int64,
        capability: String,
        modelId: String,
        totalTokens: Int64,
        networkAllowed: Bool,
        ok: Bool,
        errorCode: String,
        errorMessage: String
    ) {
        self.eventType = eventType
        self.createdAtMs = createdAtMs
        self.capability = capability
        self.modelId = modelId
        self.totalTokens = totalTokens
        self.networkAllowed = networkAllowed
        self.ok = ok
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventType = (try? c.decode(String.self, forKey: .eventType)) ?? ""
        createdAtMs = (try? c.decode(Int64.self, forKey: .createdAtMs)) ?? 0
        capability = (try? c.decode(String.self, forKey: .capability)) ?? ""
        modelId = (try? c.decode(String.self, forKey: .modelId)) ?? ""
        totalTokens = (try? c.decode(Int64.self, forKey: .totalTokens)) ?? 0
        networkAllowed = (try? c.decode(Bool.self, forKey: .networkAllowed)) ?? false
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        errorCode = (try? c.decode(String.self, forKey: .errorCode)) ?? ""
        errorMessage = (try? c.decode(String.self, forKey: .errorMessage)) ?? ""
    }
}

struct GRPCDeviceModelBreakdownEntry: Codable, Identifiable, Equatable, Sendable {
    var deviceId: String
    var deviceName: String
    var modelId: String
    var dayBucket: String
    var promptTokens: Int64
    var completionTokens: Int64
    var totalTokens: Int64
    var requestCount: Int
    var blockedCount: Int
    var lastUsedAtMs: Int64
    var lastBlockedAtMs: Int64
    var lastBlockedReason: String
    var lastDenyCode: String

    var id: String { "\(deviceId)::\(modelId)::\(dayBucket)" }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case modelId = "model_id"
        case dayBucket = "day_bucket"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case requestCount = "request_count"
        case blockedCount = "blocked_count"
        case lastUsedAtMs = "last_used_at_ms"
        case lastBlockedAtMs = "last_blocked_at_ms"
        case lastBlockedReason = "last_blocked_reason"
        case lastDenyCode = "last_deny_code"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = (try? c.decode(String.self, forKey: .deviceId)) ?? ""
        deviceName = (try? c.decode(String.self, forKey: .deviceName)) ?? ""
        modelId = (try? c.decode(String.self, forKey: .modelId)) ?? ""
        dayBucket = (try? c.decode(String.self, forKey: .dayBucket)) ?? ""
        promptTokens = (try? c.decode(Int64.self, forKey: .promptTokens)) ?? 0
        completionTokens = (try? c.decode(Int64.self, forKey: .completionTokens)) ?? 0
        totalTokens = (try? c.decode(Int64.self, forKey: .totalTokens)) ?? 0
        requestCount = (try? c.decode(Int.self, forKey: .requestCount)) ?? 0
        blockedCount = (try? c.decode(Int.self, forKey: .blockedCount)) ?? 0
        lastUsedAtMs = (try? c.decode(Int64.self, forKey: .lastUsedAtMs)) ?? 0
        lastBlockedAtMs = (try? c.decode(Int64.self, forKey: .lastBlockedAtMs)) ?? 0
        lastBlockedReason = (try? c.decode(String.self, forKey: .lastBlockedReason)) ?? ""
        lastDenyCode = (try? c.decode(String.self, forKey: .lastDenyCode)) ?? ""
    }
}

struct GRPCDeviceStatusEntry: Codable, Identifiable, Equatable, Sendable {
    var deviceId: String
    var name: String
    var peerIp: String
    var connected: Bool
    var activeEventSubscriptions: Int
    var connectedAtMs: Int64
    var lastSeenAtMs: Int64
    var quotaDay: String
    var dailyTokenUsed: Int64
    var dailyTokenCap: Int64
    var dailyTokenLimit: Int64
    var dailyTokenRemaining: Int64
    var remainingDailyTokenBudget: Int64
    var requestsToday: Int
    var blockedToday: Int
    var paidModelPolicyMode: String
    var defaultWebFetchEnabled: Bool
    var trustProfilePresent: Bool
    var trustMode: String
    var topModel: String
    var lastBlockedReason: String
    var lastDenyCode: String
    var modelBreakdown: [GRPCDeviceModelBreakdownEntry]
    var lastActivity: GRPCDeviceLastActivity?
    var tokenSeries5m1h: GRPCTokenSeries?

    var id: String { deviceId }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case name
        case peerIp = "peer_ip"
        case connected
        case activeEventSubscriptions = "active_event_subscriptions"
        case connectedAtMs = "connected_at_ms"
        case lastSeenAtMs = "last_seen_at_ms"
        case quotaDay = "quota_day"
        case dailyTokenUsed = "daily_token_used"
        case dailyTokenCap = "daily_token_cap"
        case dailyTokenLimit = "daily_token_limit"
        case dailyTokenRemaining = "daily_token_remaining"
        case remainingDailyTokenBudget = "remaining_daily_token_budget"
        case requestsToday = "requests_today"
        case blockedToday = "blocked_today"
        case paidModelPolicyMode = "paid_model_policy_mode"
        case defaultWebFetchEnabled = "default_web_fetch_enabled"
        case trustProfilePresent = "trust_profile_present"
        case trustMode = "trust_mode"
        case topModel = "top_model"
        case lastBlockedReason = "last_blocked_reason"
        case lastDenyCode = "last_deny_code"
        case modelBreakdown = "model_breakdown"
        case lastActivity = "last_activity"
        case tokenSeries5m1h = "token_series_5m_1h"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = (try? c.decode(String.self, forKey: .deviceId)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        peerIp = (try? c.decode(String.self, forKey: .peerIp)) ?? ""
        connected = (try? c.decode(Bool.self, forKey: .connected)) ?? false
        activeEventSubscriptions = (try? c.decode(Int.self, forKey: .activeEventSubscriptions)) ?? 0
        connectedAtMs = (try? c.decode(Int64.self, forKey: .connectedAtMs)) ?? 0
        lastSeenAtMs = (try? c.decode(Int64.self, forKey: .lastSeenAtMs)) ?? 0
        quotaDay = (try? c.decode(String.self, forKey: .quotaDay)) ?? ""
        dailyTokenUsed = (try? c.decode(Int64.self, forKey: .dailyTokenUsed)) ?? 0
        dailyTokenCap = (try? c.decode(Int64.self, forKey: .dailyTokenCap)) ?? 0
        dailyTokenLimit = (try? c.decode(Int64.self, forKey: .dailyTokenLimit)) ?? dailyTokenCap
        dailyTokenRemaining = (try? c.decode(Int64.self, forKey: .dailyTokenRemaining)) ?? 0
        remainingDailyTokenBudget = (try? c.decode(Int64.self, forKey: .remainingDailyTokenBudget)) ?? dailyTokenRemaining
        requestsToday = (try? c.decode(Int.self, forKey: .requestsToday)) ?? 0
        blockedToday = (try? c.decode(Int.self, forKey: .blockedToday)) ?? 0
        paidModelPolicyMode = (try? c.decode(String.self, forKey: .paidModelPolicyMode)) ?? ""
        defaultWebFetchEnabled = (try? c.decode(Bool.self, forKey: .defaultWebFetchEnabled)) ?? false
        trustProfilePresent = (try? c.decode(Bool.self, forKey: .trustProfilePresent)) ?? false
        trustMode = (try? c.decode(String.self, forKey: .trustMode)) ?? ""
        topModel = (try? c.decode(String.self, forKey: .topModel)) ?? ""
        lastBlockedReason = (try? c.decode(String.self, forKey: .lastBlockedReason)) ?? ""
        lastDenyCode = (try? c.decode(String.self, forKey: .lastDenyCode)) ?? ""
        modelBreakdown = (try? c.decode([GRPCDeviceModelBreakdownEntry].self, forKey: .modelBreakdown)) ?? []
        lastActivity = try? c.decode(GRPCDeviceLastActivity.self, forKey: .lastActivity)
        tokenSeries5m1h = try? c.decode(GRPCTokenSeries.self, forKey: .tokenSeries5m1h)
    }
}

struct GRPCDevicesStatusSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: String
    var updatedAtMs: Int64
    var devices: [GRPCDeviceStatusEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case devices
    }

    static func empty() -> GRPCDevicesStatusSnapshot {
        GRPCDevicesStatusSnapshot(schemaVersion: "grpc_devices_status.v2", updatedAtMs: 0, devices: [])
    }

    init(schemaVersion: String, updatedAtMs: Int64, devices: [GRPCDeviceStatusEntry]) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.devices = devices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? ""
        updatedAtMs = (try? c.decode(Int64.self, forKey: .updatedAtMs)) ?? 0
        devices = (try? c.decode([GRPCDeviceStatusEntry].self, forKey: .devices)) ?? []
    }
}

enum GRPCDevicesStatusStorage {
    static let fileName = "grpc_devices_status.json"

    static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    static func load() -> GRPCDevicesStatusSnapshot {
        let u = url()
        guard let data = try? Data(contentsOf: u),
              let obj = try? JSONDecoder().decode(GRPCDevicesStatusSnapshot.self, from: data) else {
            return .empty()
        }
        return obj
    }
}
