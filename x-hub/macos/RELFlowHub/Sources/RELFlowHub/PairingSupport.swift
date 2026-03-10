import Foundation

// Pairing (MVP): unauth device requests access via HTTP; admin approves locally in Hub UI.
//
// - HTTP server runs inside the embedded Node gRPC server process.
// - Admin endpoints are local-only by default (loopback) and require HUB_ADMIN_TOKEN.
// - This is a control-plane convenience layer; the real auth boundary remains hub_grpc_clients.json (per-device tokens).

struct HubPairingRequest: Identifiable, Codable, Equatable, Sendable {
    var pairingRequestId: String
    var requestId: String
    var status: String
    var appId: String
    var claimedDeviceId: String
    var userId: String
    var deviceName: String
    var peerIp: String
    var createdAtMs: Int64
    var decidedAtMs: Int64
    var denyReason: String
    var requestedScopes: [String]

    var id: String { pairingRequestId }

    enum CodingKeys: String, CodingKey {
        case pairingRequestId = "pairing_request_id"
        case requestId = "request_id"
        case status
        case appId = "app_id"
        case claimedDeviceId = "claimed_device_id"
        case userId = "user_id"
        case deviceName = "device_name"
        case peerIp = "peer_ip"
        case createdAtMs = "created_at_ms"
        case decidedAtMs = "decided_at_ms"
        case denyReason = "deny_reason"
        case requestedScopes = "requested_scopes"
    }
}

private struct HubPairingListResponse: Codable {
    var ok: Bool
    var requests: [HubPairingRequest]?
    var error: HubAPIErrorObj?
}

private struct HubPairingApproveResponse: Codable {
    var ok: Bool
    var pairingRequestId: String?
    var status: String?
    var deviceId: String?
    var clientToken: String?
    var error: HubAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case pairingRequestId = "pairing_request_id"
        case status
        case deviceId = "device_id"
        case clientToken = "client_token"
        case error
    }
}

private struct HubPairingDenyResponse: Codable {
    var ok: Bool
    var pairingRequestId: String?
    var status: String?
    var error: HubAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case pairingRequestId = "pairing_request_id"
        case status
        case error
    }
}

private struct HubAPIErrorObj: Codable {
    var code: String
    var message: String
    var retryable: Bool?
}

struct HubPairingApprovalDraft: Equatable, Sendable {
    var deviceName: String
    var paidModelSelectionMode: HubPaidModelSelectionMode
    var allowedPaidModels: [String]
    var defaultWebFetchEnabled: Bool
    var dailyTokenLimit: Int

    static func suggested(for req: HubPairingRequest) -> HubPairingApprovalDraft {
        let suggestedName = HubGRPCClientEntry.normalizedStrings([
            req.deviceName,
            req.claimedDeviceId,
            req.appId,
            "Paired Device",
        ]).first ?? "Paired Device"
        return HubPairingApprovalDraft(
            deviceName: suggestedName,
            paidModelSelectionMode: .off,
            allowedPaidModels: [],
            defaultWebFetchEnabled: true,
            dailyTokenLimit: HubTrustProfileDefaults.dailyTokenLimit
        )
    }

    var normalizedDeviceName: String {
        HubGRPCClientEntry.normalizedStrings([deviceName]).first ?? "Paired Device"
    }

    var normalizedAllowedPaidModels: [String] {
        HubGRPCClientEntry.normalizedStrings(allowedPaidModels)
    }

    func effectiveCapabilities(requestedScopes: [String]) -> [String] {
        HubGRPCClientEntry.derivedCapabilities(
            requestedCapabilities: requestedScopes,
            paidModelSelectionMode: paidModelSelectionMode,
            defaultWebFetchEnabled: defaultWebFetchEnabled
        )
    }
}

enum PairingHTTPClient {
    enum PairingError: LocalizedError {
        case badURL
        case badResponse
        case apiError(code: String, message: String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Invalid pairing server URL."
            case .badResponse:
                return "Pairing server returned an unsupported response."
            case .apiError(let code, let message):
                if message.isEmpty { return "Pairing failed (\(code))." }
                return "Pairing failed (\(code)): \(message)"
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
    ) async throws -> (Data, HTTPURLResponse) {
        guard let base = baseURL(pairingPort: pairingPort) else {
            throw PairingError.badURL
        }
        guard let url = URL(string: path, relativeTo: base) else {
            throw PairingError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = max(1.0, min(30.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")

        if let bodyJSON {
            let data = try JSONSerialization.data(withJSONObject: bodyJSON, options: [])
            req.httpBody = data
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw PairingError.badResponse
        }
        return (data, http)
    }

    static func listPending(adminToken: String, grpcPort: Int) async throws -> [HubPairingRequest] {
        let p = pairingPort(grpcPort: grpcPort)
        let (data, _) = try await request(
            path: "/admin/pairing/requests?status=pending&limit=200",
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(HubPairingListResponse.self, from: data) else {
            throw PairingError.badResponse
        }
        if obj.ok {
            return (obj.requests ?? []).filter { $0.status.lowercased() == "pending" }
        }
        let err = obj.error
        throw PairingError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }

    static func approve(
        pairingRequestId: String,
        approval: HubPairingApprovalDraft,
        capabilities: [String]?,
        allowedCidrs: [String]?,
        adminToken: String,
        grpcPort: Int
    ) async throws {
        let p = pairingPort(grpcPort: grpcPort)
        var body: [String: Any] = [
            "device_name": approval.normalizedDeviceName,
            "policy_mode": HubGRPCClientPolicyMode.newProfile.rawValue,
            "paid_model_selection_mode": approval.paidModelSelectionMode.rawValue,
            "allowed_paid_models": approval.normalizedAllowedPaidModels,
            "default_web_fetch_enabled": approval.defaultWebFetchEnabled,
            "daily_token_limit": max(1, approval.dailyTokenLimit),
        ]
        if let capabilities {
            body["capabilities"] = capabilities
        }
        if let allowedCidrs {
            body["allowed_cidrs"] = allowedCidrs
        }

        let (data, _) = try await request(
            path: "/admin/pairing/requests/\(pairingRequestId)/approve",
            method: "POST",
            bodyJSON: body,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(HubPairingApproveResponse.self, from: data) else {
            throw PairingError.badResponse
        }
        if obj.ok { return }
        let err = obj.error
        throw PairingError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }

    static func deny(pairingRequestId: String, reason: String?, adminToken: String, grpcPort: Int) async throws {
        let p = pairingPort(grpcPort: grpcPort)
        var body: [String: Any] = [:]
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["deny_reason"] = reason
        }
        let (data, _) = try await request(
            path: "/admin/pairing/requests/\(pairingRequestId)/deny",
            method: "POST",
            bodyJSON: body,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(HubPairingDenyResponse.self, from: data) else {
            throw PairingError.badResponse
        }
        if obj.ok { return }
        let err = obj.error
        throw PairingError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }
}

