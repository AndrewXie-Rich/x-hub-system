import Foundation

enum HubFirstPairApprovalState: Equatable {
    case pending
    case authenticating
}

enum HubPairingApprovalOutcomeKind: Equatable {
    case approved
    case denied
    case ownerAuthenticationCancelled
    case ownerAuthenticationFailed
    case approvalFailed
    case denyFailed

    var titleText: String {
        switch self {
        case .approved:
            return "首配已批准"
        case .denied:
            return "首配已拒绝"
        case .ownerAuthenticationCancelled:
            return "本机确认已取消"
        case .ownerAuthenticationFailed:
            return "本机确认失败"
        case .approvalFailed:
            return "批准首配失败"
        case .denyFailed:
            return "拒绝首配失败"
        }
    }

    var systemImageName: String {
        switch self {
        case .approved:
            return "checkmark.shield"
        case .denied:
            return "xmark.shield"
        case .ownerAuthenticationCancelled:
            return "arrow.uturn.backward.circle"
        case .ownerAuthenticationFailed:
            return "exclamationmark.shield"
        case .approvalFailed, .denyFailed:
            return "exclamationmark.triangle"
        }
    }

    func summaryText(deviceTitle: String) -> String {
        switch self {
        case .approved:
            return "\(deviceTitle) 已完成首次配对批准。"
        case .denied:
            return "\(deviceTitle) 的首次配对请求已被拒绝。"
        case .ownerAuthenticationCancelled:
            return "已取消 \(deviceTitle) 的本机 owner 验证；请求仍保持待处理。"
        case .ownerAuthenticationFailed:
            return "未能完成 \(deviceTitle) 的本机 owner 验证；请求仍保持待处理。"
        case .approvalFailed:
            return "Hub 在提交 \(deviceTitle) 的批准结果时失败；请求仍保持待处理。"
        case .denyFailed:
            return "Hub 在拒绝 \(deviceTitle) 时失败；请稍后重试。"
        }
    }

    var nextStepText: String {
        switch self {
        case .approved:
            return "XT 会自动继续连接 Hub；付费模型和网页抓取建议后续按需开启。"
        case .denied:
            return "如果这是误拒绝，让 XT 重新发起首配即可再次进入队列。"
        case .ownerAuthenticationCancelled:
            return "请求仍保留在队列里；准备好后可以重新发起批准。"
        case .ownerAuthenticationFailed:
            return "先确认本机 owner 验证可用，再重新批准这台设备。"
        case .approvalFailed:
            return "请求还在队列里；建议先看错误明细，再重试批准。"
        case .denyFailed:
            return "请求还在队列里；可以稍后再次拒绝，或先审阅详情。"
        }
    }
}

struct HubPairingApprovalOutcomeSnapshot: Equatable {
    var requestID: String
    var deviceTitle: String
    var deviceID: String?
    var kind: HubPairingApprovalOutcomeKind
    var detailText: String?
    var occurredAt: TimeInterval

    var titleText: String {
        kind.titleText
    }

    var summaryText: String {
        kind.summaryText(deviceTitle: deviceTitle)
    }

    var nextStepText: String {
        kind.nextStepText
    }

    func isFresh(
        at now: TimeInterval,
        ttl: TimeInterval = 120
    ) -> Bool {
        guard occurredAt > 0 else { return false }
        return now - occurredAt <= ttl
    }
}

struct HubFirstPairApprovalSummary: Equatable {
    var state: HubFirstPairApprovalState
    var pendingCount: Int
    var leadRequest: HubPairingRequest
    var leadDeviceTitle: String
    var sourceAddress: String
    var requestedScopesSummary: String
    var headline: String
    var statusLine: String
    var queueHint: String?
    var reviewButtonTitle: String
    var approveRecommendedButtonTitle: String
    var customizeButtonTitle: String
    var denyButtonTitle: String
    var recentOutcome: HubPairingApprovalOutcomeSnapshot?
}

enum HubFirstPairApprovalSummaryBuilder {
    static func build(
        requests: [HubPairingRequest],
        approvalInFlightRequestIDs: Set<String>,
        recentOutcome: HubPairingApprovalOutcomeSnapshot? = nil
    ) -> HubFirstPairApprovalSummary? {
        let normalizedRequests = requests.sorted { lhs, rhs in
            lhs.createdAtMs > rhs.createdAtMs
        }
        guard let leadRequest = normalizedRequests.first else {
            return nil
        }

        let inFlightIDs = Set(
            approvalInFlightRequestIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let pendingCount = normalizedRequests.count
        let anyInFlight = normalizedRequests.contains { request in
            inFlightIDs.contains(request.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let state: HubFirstPairApprovalState = anyInFlight ? .authenticating : .pending

        return HubFirstPairApprovalSummary(
            state: state,
            pendingCount: pendingCount,
            leadRequest: leadRequest,
            leadDeviceTitle: displayDeviceTitle(for: leadRequest),
            sourceAddress: sourceAddress(for: leadRequest),
            requestedScopesSummary: requestedScopesSummary(for: leadRequest),
            headline: pendingCount == 1 ? "1 台新设备等待首配" : "\(pendingCount) 台新设备等待首配",
            statusLine: state == .authenticating
                ? "正在等待本机 owner 验证完成。验证通过后才会真正下发首配 token 和 profile。"
                : "推荐先做最小接入，让 XT 完成基础连接；付费模型和网页抓取后续按需开启。",
            queueHint: pendingCount > 1 ? "队列里还有 \(pendingCount - 1) 台设备等待你核对。" : nil,
            reviewButtonTitle: pendingCount > 1 ? "查看队列" : "查看详情",
            approveRecommendedButtonTitle: anyInFlight ? "批准中…" : "按推荐批准",
            customizeButtonTitle: "自定义策略",
            denyButtonTitle: "拒绝",
            recentOutcome: recentOutcome
        )
    }

    static func displayDeviceTitle(for request: HubPairingRequest) -> String {
        let preferred = HubGRPCClientEntry.normalizedStrings([
            request.deviceName,
            request.claimedDeviceId,
            request.appId,
            "Paired Device",
        ]).first ?? "Paired Device"
        let appId = request.appId.trimmingCharacters(in: .whitespacesAndNewlines)
        if appId.isEmpty || preferred == appId {
            return preferred
        }
        return "\(preferred) · \(appId)"
    }

    static func sourceAddress(for request: HubPairingRequest) -> String {
        let peerIp = request.peerIp.trimmingCharacters(in: .whitespacesAndNewlines)
        return peerIp.isEmpty ? "同一局域网已验证" : peerIp
    }

    static func requestedScopesSummary(for request: HubPairingRequest) -> String {
        let scopes = request.requestedScopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if scopes.isEmpty {
            return "默认最小权限模板"
        }
        return HubUIStrings.Formatting.commaSeparated(scopes)
    }
}
