import Foundation

struct HubPendingGrantRequest: Identifiable, Codable, Equatable, Sendable {
    struct Client: Codable, Equatable, Sendable {
        var deviceId: String
        var userId: String
        var appId: String
        var projectId: String
        var sessionId: String

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
            case sessionId = "session_id"
        }
    }

    var grantRequestId: String
    var requestId: String
    var client: Client
    var capability: String
    var modelId: String
    var reason: String
    var requestedTtlSec: Int
    var requestedTokenCap: Int64
    var status: String
    var decision: String
    var createdAtMs: Int64
    var decidedAtMs: Int64

    var id: String { grantRequestId }

    enum CodingKeys: String, CodingKey {
        case grantRequestId = "grant_request_id"
        case requestId = "request_id"
        case client
        case capability
        case modelId = "model_id"
        case reason
        case requestedTtlSec = "requested_ttl_sec"
        case requestedTokenCap = "requested_token_cap"
        case status
        case decision
        case createdAtMs = "created_at_ms"
        case decidedAtMs = "decided_at_ms"
    }

    var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isPending: Bool {
        normalizedStatus == "pending"
    }

    var displayCapability: String {
        let normalized = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "skills.execute":
            return "Skill 执行"
        case "web.fetch":
            return "网页抓取"
        case "ai.generate.paid":
            return "付费模型"
        case "ai.generate.local":
            return "本地模型"
        default:
            return normalized.isEmpty ? "Capability" : normalized
        }
    }

    var scopeSummary: String {
        let projectId = client.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceId = client.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let appId = client.appId.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !projectId.isEmpty { parts.append("project \(projectId)") }
        if !deviceId.isEmpty { parts.append("device \(deviceId)") }
        if !appId.isEmpty { parts.append(appId) }
        return parts.joined(separator: " · ")
    }
}

private struct PendingGrantListResponse: Codable {
    var ok: Bool
    var updatedAtMs: Int64?
    var requests: [HubPendingGrantRequest]?
    var error: PendingGrantAPIError?

    enum CodingKeys: String, CodingKey {
        case ok
        case updatedAtMs = "updated_at_ms"
        case requests
        case error
    }
}

private struct PendingGrantDecisionResponse: Codable {
    var ok: Bool
    var grantRequestId: String?
    var status: String?
    var error: PendingGrantAPIError?

    enum CodingKeys: String, CodingKey {
        case ok
        case grantRequestId = "grant_request_id"
        case status
        case error
    }
}

private struct PendingGrantAPIError: Codable {
    var code: String
    var message: String
    var retryable: Bool?
}

enum PendingGrantHTTPClient {
    enum PendingGrantError: LocalizedError {
        case badURL
        case badResponse
        case apiError(code: String, message: String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Hub grant admin URL is invalid."
            case .badResponse:
                return "Hub grant admin response is unsupported."
            case .apiError(let code, let message):
                let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty ? code : "\(code): \(detail)"
            }
        }
    }

    static func pairingPort(grpcPort: Int) -> Int {
        max(1, min(65535, grpcPort + 1))
    }

    private static func baseURL(pairingPort: Int) -> URL? {
        URL(string: "http://127.0.0.1:\(pairingPort)")
    }

    private static func request(
        path: String,
        method: String,
        bodyJSON: [String: Any]?,
        adminToken: String,
        pairingPort: Int,
        timeoutSec: Double = 3.0
    ) async throws -> Data {
        guard let base = baseURL(pairingPort: pairingPort),
              let url = URL(string: path, relativeTo: base) else {
            throw PendingGrantError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = max(1.0, min(30.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")

        if let bodyJSON {
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyJSON, options: [])
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard resp is HTTPURLResponse else {
            throw PendingGrantError.badResponse
        }
        return data
    }

    static func listPending(adminToken: String, grpcPort: Int, limit: Int = 240) async throws -> [HubPendingGrantRequest] {
        let p = pairingPort(grpcPort: grpcPort)
        let boundedLimit = max(1, min(500, limit))
        let data = try await request(
            path: "/admin/grant-requests?status=pending&limit=\(boundedLimit)",
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(PendingGrantListResponse.self, from: data) else {
            throw PendingGrantError.badResponse
        }
        if obj.ok {
            return (obj.requests ?? []).filter(\.isPending)
        }
        let err = obj.error
        throw PendingGrantError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }

    static func approve(
        grantRequestId: String,
        ttlSec: Int? = nil,
        tokenCap: Int64? = nil,
        note: String? = nil,
        adminToken: String,
        grpcPort: Int
    ) async throws {
        let id = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pairingPort(grpcPort: grpcPort)
        var body: [String: Any] = [
            "approver_id": "hub_inbox",
        ]
        if let ttlSec {
            body["ttl_sec"] = max(10, ttlSec)
        }
        if let tokenCap {
            body["token_cap"] = max(0, tokenCap)
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["note"] = note
        }
        let data = try await request(
            path: "/admin/grant-requests/\(id)/approve",
            method: "POST",
            bodyJSON: body,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(PendingGrantDecisionResponse.self, from: data) else {
            throw PendingGrantError.badResponse
        }
        if obj.ok { return }
        let err = obj.error
        throw PendingGrantError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }

    static func deny(
        grantRequestId: String,
        reason: String? = nil,
        adminToken: String,
        grpcPort: Int
    ) async throws {
        let id = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pairingPort(grpcPort: grpcPort)
        let body: [String: Any] = [
            "approver_id": "hub_inbox",
            "reason": reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? reason!.trimmingCharacters(in: .whitespacesAndNewlines)
                : "denied_via_hub_inbox",
        ]
        let data = try await request(
            path: "/admin/grant-requests/\(id)/deny",
            method: "POST",
            bodyJSON: body,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(PendingGrantDecisionResponse.self, from: data) else {
            throw PendingGrantError.badResponse
        }
        if obj.ok { return }
        let err = obj.error
        throw PendingGrantError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }
}
