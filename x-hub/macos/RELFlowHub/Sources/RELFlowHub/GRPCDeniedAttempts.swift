import Foundation
import RELFlowHubCore

// Snapshot exported by the embedded Node gRPC server into the Hub base dir.
// Used to surface common operator mistakes (e.g. Allowed CIDRs too strict for VPN IPs).

struct GRPCDeniedAttemptEntry: Codable, Identifiable, Equatable, Sendable {
    var deviceId: String
    var clientName: String
    var peerIp: String
    var reason: String
    var message: String
    var expectedAllowedCidrs: [String]
    var firstSeenAtMs: Int64
    var lastSeenAtMs: Int64
    var count: Int64

    var id: String { "\(deviceId)|\(peerIp)|\(reason)" }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case clientName = "client_name"
        case peerIp = "peer_ip"
        case reason
        case message
        case expectedAllowedCidrs = "expected_allowed_cidrs"
        case firstSeenAtMs = "first_seen_at_ms"
        case lastSeenAtMs = "last_seen_at_ms"
        case count
    }

    init(
        deviceId: String,
        clientName: String,
        peerIp: String,
        reason: String,
        message: String,
        expectedAllowedCidrs: [String] = [],
        firstSeenAtMs: Int64,
        lastSeenAtMs: Int64,
        count: Int64
    ) {
        self.deviceId = deviceId
        self.clientName = clientName
        self.peerIp = peerIp
        self.reason = reason
        self.message = message
        self.expectedAllowedCidrs = expectedAllowedCidrs
        self.firstSeenAtMs = firstSeenAtMs
        self.lastSeenAtMs = lastSeenAtMs
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = (try? c.decode(String.self, forKey: .deviceId)) ?? ""
        clientName = (try? c.decode(String.self, forKey: .clientName)) ?? ""
        peerIp = (try? c.decode(String.self, forKey: .peerIp)) ?? ""
        reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        expectedAllowedCidrs = (try? c.decode([String].self, forKey: .expectedAllowedCidrs)) ?? []
        firstSeenAtMs = (try? c.decode(Int64.self, forKey: .firstSeenAtMs)) ?? 0
        lastSeenAtMs = (try? c.decode(Int64.self, forKey: .lastSeenAtMs)) ?? 0
        count = (try? c.decode(Int64.self, forKey: .count)) ?? 0
    }
}

struct GRPCDeniedAttemptsSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: String
    var updatedAtMs: Int64
    var attempts: [GRPCDeniedAttemptEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case attempts
    }

    static func empty() -> GRPCDeniedAttemptsSnapshot {
        GRPCDeniedAttemptsSnapshot(schemaVersion: "grpc_denied_attempts.v1", updatedAtMs: 0, attempts: [])
    }

    init(schemaVersion: String, updatedAtMs: Int64, attempts: [GRPCDeniedAttemptEntry]) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.attempts = attempts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? ""
        updatedAtMs = (try? c.decode(Int64.self, forKey: .updatedAtMs)) ?? 0
        attempts = (try? c.decode([GRPCDeniedAttemptEntry].self, forKey: .attempts)) ?? []
    }
}

enum GRPCDeniedAttemptsStorage {
    static let fileName = "grpc_denied_attempts.json"

    static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    static func load() -> GRPCDeniedAttemptsSnapshot {
        let u = url()
        guard let data = try? Data(contentsOf: u),
              let obj = try? JSONDecoder().decode(GRPCDeniedAttemptsSnapshot.self, from: data) else {
            return .empty()
        }
        return obj
    }
}

