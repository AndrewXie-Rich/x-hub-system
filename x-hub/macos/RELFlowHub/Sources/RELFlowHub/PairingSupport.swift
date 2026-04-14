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

enum HubPairingApprovalPreset: String, Equatable, Sendable {
    case recommendedMinimal = "recommended_minimal"
    case standard = "standard"
    case fullAccess = "full_access"
    case custom = "custom"

    static let visibleCases: [HubPairingApprovalPreset] = [
        .recommendedMinimal,
        .standard,
        .fullAccess,
    ]

    var title: String {
        switch self {
        case .recommendedMinimal:
            return "最小接入"
        case .standard:
            return "标准设备"
        case .fullAccess:
            return "完整设备"
        case .custom:
            return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .recommendedMinimal:
            return "先完成首配，付费模型和网页抓取后续按需开启。"
        case .standard:
            return "默认允许网页抓取，不开放付费模型。"
        case .fullAccess:
            return "开放网页抓取与付费模型，适合你自己的主力 XT。"
        case .custom:
            return "手动调整这台设备的首配策略。"
        }
    }

    var badgeText: String? {
        switch self {
        case .recommendedMinimal:
            return "推荐"
        case .standard, .fullAccess, .custom:
            return nil
        }
    }

    var paidModelSelectionMode: HubPaidModelSelectionMode {
        switch self {
        case .recommendedMinimal, .standard, .custom:
            return .off
        case .fullAccess:
            return .allPaidModels
        }
    }

    var defaultWebFetchEnabled: Bool {
        switch self {
        case .recommendedMinimal:
            return false
        case .standard, .fullAccess:
            return true
        case .custom:
            return false
        }
    }

    var dailyTokenLimit: Int {
        switch self {
        case .recommendedMinimal:
            return 200_000
        case .standard:
            return HubTrustProfileDefaults.dailyTokenLimit
        case .fullAccess:
            return 1_000_000
        case .custom:
            return HubTrustProfileDefaults.dailyTokenLimit
        }
    }

    var recommendationText: String {
        switch self {
        case .recommendedMinimal:
            return "先让设备安全连上 Hub，后面真的需要付费模型或网页抓取时再单独放开。"
        case .standard:
            return "适合多数常规终端：先开放网页抓取，付费模型继续收紧。"
        case .fullAccess:
            return "只建议给你自己的主力 XT；首配后可直接使用网页抓取和付费模型。"
        case .custom:
            return "你正在手动决定这台设备的首配边界。"
        }
    }

    var nextStepText: String {
        switch self {
        case .recommendedMinimal:
            return "批准后 XT 会先完成基础接入；后续用到付费模型或网页抓取时再按需提权。"
        case .standard:
            return "批准后 XT 可直接继续基础任务和网页抓取；付费模型继续按需开启。"
        case .fullAccess:
            return "批准后 XT 可直接继续基础任务、网页抓取与付费模型调用。"
        case .custom:
            return "批准后会按你当前配置写入这台设备的信任档案。"
        }
    }

    func buildDraft(for req: HubPairingRequest) -> HubPairingApprovalDraft {
        let suggestedName = HubGRPCClientEntry.normalizedStrings([
            req.deviceName,
            req.claimedDeviceId,
            req.appId,
            "Paired Device",
        ]).first ?? "Paired Device"
        return HubPairingApprovalDraft(
            deviceName: suggestedName,
            paidModelSelectionMode: paidModelSelectionMode,
            allowedPaidModels: [],
            defaultWebFetchEnabled: defaultWebFetchEnabled,
            dailyTokenLimit: dailyTokenLimit
        )
    }
}

struct HubPairingApprovalDraft: Equatable, Sendable {
    var deviceName: String
    var paidModelSelectionMode: HubPaidModelSelectionMode
    var allowedPaidModels: [String]
    var defaultWebFetchEnabled: Bool
    var dailyTokenLimit: Int

    static func suggested(for req: HubPairingRequest) -> HubPairingApprovalDraft {
        recommended(for: req)
    }

    static func recommended(for req: HubPairingRequest) -> HubPairingApprovalDraft {
        HubPairingApprovalPreset.recommendedMinimal.buildDraft(for: req)
    }

    static func preset(_ preset: HubPairingApprovalPreset, for req: HubPairingRequest) -> HubPairingApprovalDraft {
        preset.buildDraft(for: req)
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

    var matchedPreset: HubPairingApprovalPreset {
        for preset in HubPairingApprovalPreset.visibleCases {
            let presetDraft = HubPairingApprovalDraft(
                deviceName: normalizedDeviceName,
                paidModelSelectionMode: preset.paidModelSelectionMode,
                allowedPaidModels: [],
                defaultWebFetchEnabled: preset.defaultWebFetchEnabled,
                dailyTokenLimit: preset.dailyTokenLimit
            )
            if paidModelSelectionMode == presetDraft.paidModelSelectionMode,
               normalizedAllowedPaidModels.isEmpty,
               defaultWebFetchEnabled == presetDraft.defaultWebFetchEnabled,
               max(1, dailyTokenLimit) == presetDraft.dailyTokenLimit {
                return preset
            }
        }
        return .custom
    }

    var paidModelSummaryText: String {
        switch paidModelSelectionMode {
        case .off:
            return "付费模型关闭"
        case .allPaidModels:
            return "付费模型全部开放"
        case .customSelectedModels:
            return normalizedAllowedPaidModels.isEmpty
                ? "付费模型自定义"
                : "付费模型限定 \(normalizedAllowedPaidModels.count) 个"
        }
    }

    var webFetchSummaryText: String {
        defaultWebFetchEnabled ? "网页抓取开启" : "网页抓取关闭"
    }

    var dailyBudgetSummaryText: String {
        "每日上限 \(max(1, dailyTokenLimit)) token"
    }

    var accessSummaryText: String {
        [
            "基础接入已包含",
            paidModelSummaryText,
            webFetchSummaryText,
            dailyBudgetSummaryText,
        ].joined(separator: " · ")
    }

    var approvedOutcomeDetailText: String {
        let presetText: String = {
            let matched = matchedPreset
            if matched == .custom {
                return "已按自定义策略接入"
            }
            return "已按\(matched.title)接入"
        }()
        return "\(presetText)：\(accessSummaryText)。"
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
                return HubUIStrings.Settings.GRPC.PairingHTTP.invalidServerURL
            case .badResponse:
                return HubUIStrings.Settings.GRPC.PairingHTTP.unsupportedResponse
            case .apiError(let code, let message):
                return HubUIStrings.Settings.GRPC.PairingHTTP.failed(code: code, message: message)
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
    ) async throws -> String? {
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
        if obj.ok {
            let normalizedDeviceID = obj.deviceId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedDeviceID?.isEmpty == true ? nil : normalizedDeviceID
        }
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
