import Foundation

enum HubTransportMode: String, CaseIterable, Codable {
    case auto
    case grpc
    case fileIPC = "file"
}

struct HubAIResponseFailureContext: Equatable, Sendable {
    var reason: String
    var deviceName: String
    var modelId: String?
}

struct XTPaidModelAccessResolution: Codable, Equatable, Sendable {
    enum State: String, Codable, CaseIterable, Sendable {
        case allowedByDevicePolicy = "allowed_by_device_policy"
        case blockedPaidModelDisabled = "blocked_paid_model_disabled"
        case blockedModelNotInCustomAllowlist = "blocked_model_not_in_custom_allowlist"
        case blockedDailyBudgetExceeded = "blocked_daily_budget_exceeded"
        case blockedSingleRequestBudgetExceeded = "blocked_single_request_budget_exceeded"
        case legacyGrantFlowRequired = "legacy_grant_flow_required"
    }

    let schemaVersion: String
    let state: State
    let headline: String
    let whyItHappened: String
    let nextAction: String
    let deviceName: String
    let modelId: String
    let policyRef: String
    let policyMode: String
    let denyCode: String?
    let rawReasonCode: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state
        case headline
        case whyItHappened = "why_it_happened"
        case nextAction = "next_action"
        case deviceName = "device_name"
        case modelId = "model_id"
        case policyRef = "policy_ref"
        case policyMode = "policy_mode"
        case denyCode = "deny_code"
        case rawReasonCode = "raw_reason_code"
    }

    var renderedExplanation: String {
        [
            headline,
            "access_state=\(state.rawValue)",
            "device_name=\(deviceName)",
            "model_id=\(modelId)",
            "policy_mode=\(policyMode)",
            "policy_ref=\(policyRef)",
            denyCode.map { "deny_code=\($0)" },
            "why_it_happened=\(whyItHappened)",
            "next_action=\(nextAction)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

enum XTPaidModelAccessExplainability {
    private struct ParsedReason {
        var denyCode: String?
        var state: String?
        var deviceName: String?
        var modelId: String?
        var policyMode: String?
        var policyRef: String?
        var rawReasonCode: String?
    }

    static func allowedByDevicePolicy(
        deviceName: String,
        modelId: String,
        policyMode: String = "new_profile"
    ) -> XTPaidModelAccessResolution {
        makeResolution(
            state: .allowedByDevicePolicy,
            deviceName: fallbackDeviceName(deviceName),
            modelId: fallbackModelID(modelId),
            policyMode: normalizedPolicyMode(policyMode) ?? "new_profile",
            denyCode: nil,
            rawReasonCode: "allowed_by_device_policy",
            whyItHappened: "device_name=\(fallbackDeviceName(deviceName)) 已命中新 trust profile 的 paid model 允许策略；model_id=\(fallbackModelID(modelId)) 在当前设备策略与额度范围内可直接使用。",
            nextAction: "继续当前请求；该设备已被设备策略允许访问此 paid model，无需额外 grant 审批。"
        )
    }

    static func resolve(
        rawReasonCode: String?,
        deviceName: String,
        modelId: String
    ) -> XTPaidModelAccessResolution? {
        let parsed = parse(rawReasonCode: rawReasonCode, deviceName: deviceName, modelId: modelId)
        let resolvedDeviceName = fallbackDeviceName(parsed.deviceName ?? deviceName)
        let resolvedModelId = fallbackModelID(parsed.modelId ?? modelId)
        let raw = parsed.rawReasonCode ?? rawReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedState = normalizeStateToken(parsed.state)
        let normalizedDenyCode = normalizeDenyCode(parsed.denyCode ?? raw)
        let policyMode = parsed.policyMode ?? inferredPolicyMode(for: normalizedState, denyCode: normalizedDenyCode)

        switch normalizedState ?? normalizedDenyCode {
        case XTPaidModelAccessResolution.State.allowedByDevicePolicy.rawValue?:
            return allowedByDevicePolicy(deviceName: resolvedDeviceName, modelId: resolvedModelId, policyMode: policyMode ?? "new_profile")
        case XTPaidModelAccessResolution.State.blockedPaidModelDisabled.rawValue?, "device_paid_model_disabled", "device_paid_model_policy_missing":
            return makeResolution(
                state: .blockedPaidModelDisabled,
                deviceName: resolvedDeviceName,
                modelId: resolvedModelId,
                policyMode: policyMode ?? "new_profile",
                denyCode: normalizedDenyCode ?? "device_paid_model_disabled",
                rawReasonCode: raw,
                policyRefOverride: parsed.policyRef,
                whyItHappened: "device_name=\(resolvedDeviceName) 的 paid model 策略当前为关闭或缺少可用 paid model policy，因此 model_id=\(resolvedModelId) 被设备策略直接拦截。",
                nextAction: "到 Hub Settings → Pairing & Device Trust 为该设备开启 paid model 访问，或切换到本地/已授权模型后重试。"
            )
        case XTPaidModelAccessResolution.State.blockedModelNotInCustomAllowlist.rawValue?, "device_paid_model_not_allowed":
            return makeResolution(
                state: .blockedModelNotInCustomAllowlist,
                deviceName: resolvedDeviceName,
                modelId: resolvedModelId,
                policyMode: policyMode ?? "new_profile",
                denyCode: normalizedDenyCode ?? "device_paid_model_not_allowed",
                rawReasonCode: raw,
                policyRefOverride: parsed.policyRef,
                whyItHappened: "device_name=\(resolvedDeviceName) 当前走自定义 paid model 白名单策略，但 model_id=\(resolvedModelId) 不在 allowed_model_ids 中，因此被 fail-closed 阻断。",
                nextAction: "到 Hub Settings → Pairing & Device Trust 把该模型加入 allowlist，或切换到该设备已授权的 paid/local model 后重试。"
            )
        case XTPaidModelAccessResolution.State.blockedDailyBudgetExceeded.rawValue?, "device_daily_token_budget_exceeded":
            return makeResolution(
                state: .blockedDailyBudgetExceeded,
                deviceName: resolvedDeviceName,
                modelId: resolvedModelId,
                policyMode: policyMode ?? "new_profile",
                denyCode: normalizedDenyCode ?? "device_daily_token_budget_exceeded",
                rawReasonCode: raw,
                policyRefOverride: parsed.policyRef,
                whyItHappened: "device_name=\(resolvedDeviceName) 的每日 paid model token 额度已经耗尽，因此 model_id=\(resolvedModelId) 被当日预算硬门槛阻断。",
                nextAction: "到 Hub Settings → Models & Paid Access 查看并提升 daily_token_limit，或等待下一个日配额窗口后重试。"
            )
        case XTPaidModelAccessResolution.State.blockedSingleRequestBudgetExceeded.rawValue?, "device_single_request_token_exceeded":
            return makeResolution(
                state: .blockedSingleRequestBudgetExceeded,
                deviceName: resolvedDeviceName,
                modelId: resolvedModelId,
                policyMode: policyMode ?? "new_profile",
                denyCode: normalizedDenyCode ?? "device_single_request_token_exceeded",
                rawReasonCode: raw,
                policyRefOverride: parsed.policyRef,
                whyItHappened: "当前请求对 device_name=\(resolvedDeviceName) 来说超出了单次 paid model token 上限，因此 model_id=\(resolvedModelId) 在提交前被预算策略拒绝。",
                nextAction: "缩小本次请求、降低 max tokens，或到 Hub Settings → Models & Paid Access 提升 single_request_token_limit 后再试。"
            )
        case XTPaidModelAccessResolution.State.legacyGrantFlowRequired.rawValue?, "legacy_grant_flow_required", "grant_required", "grant_pending", "grant_denied", "permission_denied", "forbidden", "denied":
            return makeResolution(
                state: .legacyGrantFlowRequired,
                deviceName: resolvedDeviceName,
                modelId: resolvedModelId,
                policyMode: policyMode ?? "legacy_grant",
                denyCode: normalizedDenyCode ?? "legacy_grant_flow_required",
                rawReasonCode: raw,
                policyRefOverride: parsed.policyRef,
                whyItHappened: "device_name=\(resolvedDeviceName) 仍在旧的 capability/grant 路径上，尚未由新 trust profile 直接接管；因此 model_id=\(resolvedModelId) 这次仍按 legacy grant 语义处理。",
                nextAction: "若只是临时放行，可先到 Hub Settings → Grants & Permissions 完成 legacy grant；若想消除重复审批，请到 Hub Settings → Pairing & Device Trust 将该设备升级到新 trust profile。"
            )
        default:
            return nil
        }
    }

    private static func makeResolution(
        state: XTPaidModelAccessResolution.State,
        deviceName: String,
        modelId: String,
        policyMode: String,
        denyCode: String?,
        rawReasonCode: String?,
        policyRefOverride: String? = nil,
        whyItHappened: String,
        nextAction: String
    ) -> XTPaidModelAccessResolution {
        let headline: String = {
            switch state {
            case .allowedByDevicePolicy:
                return "当前设备策略已允许此 paid model"
            case .blockedPaidModelDisabled:
                return "这台设备未被授权使用 paid model"
            case .blockedModelNotInCustomAllowlist:
                return "当前模型不在这台设备的 paid model 白名单中"
            case .blockedDailyBudgetExceeded:
                return "这台设备的每日 paid model 额度已用尽"
            case .blockedSingleRequestBudgetExceeded:
                return "这次 paid model 请求超过了单次额度上限"
            case .legacyGrantFlowRequired:
                return "旧设备仍走 legacy grant 路径，当前 paid model 需要旧式授权"
            }
        }()

        let normalizedPolicyMode = canonicalPolicyMode(for: state, proposed: policyMode)
        let ref = compatiblePolicyRefOverride(
            policyRefOverride,
            state: state,
            policyMode: normalizedPolicyMode,
            denyCode: denyCode
        ) ?? canonicalPolicyRef(
            state: state,
            policyMode: normalizedPolicyMode,
            denyCode: denyCode
        )

        return XTPaidModelAccessResolution(
            schemaVersion: "xt.paid_model_access_resolution.v1",
            state: state,
            headline: headline,
            whyItHappened: whyItHappened,
            nextAction: nextAction,
            deviceName: deviceName,
            modelId: modelId,
            policyRef: ref,
            policyMode: normalizedPolicyMode,
            denyCode: denyCode,
            rawReasonCode: rawReasonCode
        )
    }

    private static func canonicalPolicyMode(
        for state: XTPaidModelAccessResolution.State,
        proposed raw: String?
    ) -> String {
        switch state {
        case .legacyGrantFlowRequired:
            return "legacy_grant"
        case .allowedByDevicePolicy,
             .blockedPaidModelDisabled,
             .blockedModelNotInCustomAllowlist,
             .blockedDailyBudgetExceeded,
             .blockedSingleRequestBudgetExceeded:
            return "new_profile"
        }
    }

    private static func canonicalPolicyRef(
        state: XTPaidModelAccessResolution.State,
        policyMode: String,
        denyCode: String?
    ) -> String {
        [
            "schema=xt.paid_model_access_resolution.v1",
            "policy_mode=\(policyMode)",
            "resolution_state=\(state.rawValue)",
            "deny_code=\(sanitizeToken(denyCode ?? "none"))"
        ].joined(separator: ";")
    }

    private static func compatiblePolicyRefOverride(
        _ raw: String?,
        state: XTPaidModelAccessResolution.State,
        policyMode: String,
        denyCode: String?
    ) -> String? {
        guard let raw = nonEmpty(raw) else { return nil }
        let normalized = raw.lowercased()
        let expectedDenyCode = sanitizeToken(denyCode ?? "none")
        guard normalized.contains("policy_mode=\(policyMode)"),
              normalized.contains("resolution_state=\(state.rawValue)"),
              normalized.contains("deny_code=\(expectedDenyCode)") else {
            return nil
        }
        return raw
    }

    private static func parse(
        rawReasonCode: String?,
        deviceName: String,
        modelId: String
    ) -> ParsedReason {
        var parsed = ParsedReason(
            denyCode: nil,
            state: nil,
            deviceName: nonEmpty(deviceName),
            modelId: nonEmpty(modelId),
            policyMode: nil,
            policyRef: nil,
            rawReasonCode: nonEmpty(rawReasonCode)
        )

        if let raw = nonEmpty(rawReasonCode) {
            if let jsonParsed = parseJSONReason(raw) {
                parsed.denyCode = nonEmpty(jsonParsed["deny_code"]) ?? parsed.denyCode
                parsed.state = nonEmpty(jsonParsed["state"]) ?? parsed.state
                parsed.deviceName = nonEmpty(jsonParsed["device_name"]) ?? parsed.deviceName
                parsed.modelId = nonEmpty(jsonParsed["model_id"]) ?? parsed.modelId
                parsed.policyMode = nonEmpty(jsonParsed["policy_mode"]) ?? parsed.policyMode
                parsed.policyRef = nonEmpty(jsonParsed["policy_ref"]) ?? parsed.policyRef
            }

            let kvParsed = parseKeyValueReason(raw)
            parsed.denyCode = nonEmpty(kvParsed["deny_code"] ?? kvParsed["reason_code"]) ?? parsed.denyCode
            parsed.state = nonEmpty(kvParsed["state"]) ?? parsed.state
            parsed.deviceName = nonEmpty(kvParsed["device_name"]) ?? parsed.deviceName
            parsed.modelId = nonEmpty(kvParsed["model_id"]) ?? parsed.modelId
            parsed.policyMode = nonEmpty(kvParsed["policy_mode"]) ?? parsed.policyMode
            parsed.policyRef = nonEmpty(kvParsed["policy_ref"]) ?? parsed.policyRef

            if parsed.denyCode == nil {
                parsed.denyCode = normalizeDenyCode(raw)
            }
            if parsed.state == nil {
                parsed.state = normalizeStateToken(raw)
            }
        }

        return parsed
    }

    private static func parseJSONReason(_ raw: String) -> [String: String]? {
        guard raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let source: [String: Any]
        if let nested = object["access_resolution"] as? [String: Any] {
            source = nested
        } else {
            source = object
        }
        var out: [String: String] = [:]
        for (key, value) in source {
            let normalizedKey = normalizeFieldKey(key)
            switch value {
            case let string as String:
                out[normalizedKey] = string
            case let number as NSNumber:
                out[normalizedKey] = number.stringValue
            default:
                continue
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func parseKeyValueReason(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        let normalized = raw
            .replacingOccurrences(of: "|", with: ";")
            .replacingOccurrences(of: ",", with: ";")
        for segment in normalized.split(separator: ";") {
            let token = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            if let equals = token.firstIndex(of: "=") {
                let key = normalizeFieldKey(String(token[..<equals]))
                let value = String(token[token.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !value.isEmpty {
                    out[key] = value
                }
                continue
            }
            if let colon = token.firstIndex(of: ":") {
                let keyCandidate = normalizeFieldKey(String(token[..<colon]))
                let value = String(token[token.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if ["deny_code", "state", "policy_mode", "device_name", "model_id", "policy_ref", "reason_code"].contains(keyCandidate), !value.isEmpty {
                    out[keyCandidate] = value
                    continue
                }
            }
        }
        return out
    }

    private static func normalizeFieldKey(_ raw: String) -> String {
        sanitizeToken(raw)
    }

    private static func normalizeStateToken(_ raw: String?) -> String? {
        guard let token = nonEmpty(raw).map(sanitizeToken) else { return nil }
        let known = XTPaidModelAccessResolution.State.allCases.map(\.rawValue)
        return known.contains(token) ? token : nil
    }

    private static func normalizeDenyCode(_ raw: String?) -> String? {
        guard let token = nonEmpty(raw).map(sanitizeToken) else { return nil }
        let known = [
            "device_paid_model_disabled",
            "device_paid_model_not_allowed",
            "device_paid_model_policy_missing",
            "device_daily_token_budget_exceeded",
            "device_single_request_token_exceeded",
            "legacy_grant_flow_required",
            "grant_required",
            "grant_pending",
            "grant_denied",
            "permission_denied",
            "forbidden",
            "denied"
        ]
        if known.contains(token) {
            return token
        }
        return known.first(where: { token.contains($0) })
    }

    private static func inferredPolicyMode(for state: String?, denyCode: String?) -> String? {
        switch state ?? denyCode {
        case XTPaidModelAccessResolution.State.allowedByDevicePolicy.rawValue?,
             XTPaidModelAccessResolution.State.blockedPaidModelDisabled.rawValue?,
             XTPaidModelAccessResolution.State.blockedModelNotInCustomAllowlist.rawValue?,
             XTPaidModelAccessResolution.State.blockedDailyBudgetExceeded.rawValue?,
             XTPaidModelAccessResolution.State.blockedSingleRequestBudgetExceeded.rawValue?,
             "device_paid_model_disabled",
             "device_paid_model_not_allowed",
             "device_paid_model_policy_missing",
             "device_daily_token_budget_exceeded",
             "device_single_request_token_exceeded":
            return "new_profile"
        case XTPaidModelAccessResolution.State.legacyGrantFlowRequired.rawValue?,
             "legacy_grant_flow_required",
             "grant_required",
             "grant_pending",
             "grant_denied",
             "permission_denied",
             "forbidden",
             "denied":
            return "legacy_grant"
        default:
            return nil
        }
    }

    private static func normalizedPolicyMode(_ raw: String?) -> String? {
        guard let token = nonEmpty(raw).map(sanitizeToken) else { return nil }
        switch token {
        case "legacy_grant", "legacy":
            return "legacy_grant"
        case "new_profile", "trusted_daily", "device_policy":
            return "new_profile"
        default:
            return token.isEmpty ? nil : token
        }
    }

    private static func fallbackDeviceName(_ raw: String?) -> String {
        nonEmpty(raw) ?? Host.current().localizedName ?? "X-Terminal"
    }

    private static func fallbackModelID(_ raw: String?) -> String {
        nonEmpty(raw) ?? "unknown_model"
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizeToken(_ raw: String) -> String {
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        return token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

enum HubAIError: Error, LocalizedError {
    case runtimeNotRunning
    case grpcRouteUnavailable
    case requestWriteFailed(String)
    case responseTimeout
    case responseDoneNotOk(HubAIResponseFailureContext)

    var errorDescription: String? {
        switch self {
        case .runtimeNotRunning:
            return "Hub AI runtime is not running. Open REL Flow Hub -> Settings -> AI Runtime -> Start."
        case .grpcRouteUnavailable:
            return "Hub gRPC route is unavailable (missing pairing profile). Run Hub one-click pairing first, or switch to `/hub route auto` / `/hub route file`."
        case .requestWriteFailed(let msg):
            return "Failed to write AI request: \(msg)"
        case .responseTimeout:
            return "AI response timed out"
        case .responseDoneNotOk(let failure):
            let r = failure.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedReason = HubRouteStateMachine.normalizedReasonToken(r) ?? ""
            if let resolution = XTPaidModelAccessExplainability.resolve(
                rawReasonCode: r,
                deviceName: failure.deviceName,
                modelId: failure.modelId ?? "unknown_model"
            ) {
                return resolution.renderedExplanation
            }
            if normalizedReason.contains("grpc_unavailable")
                || normalizedReason.contains("14_unavailable")
                || normalizedReason.contains("no_connection_established")
                || normalizedReason.contains("connection_refused")
                || normalizedReason.contains("hub_unreachable")
                || normalizedReason.contains("failed_to_connect_to_all_addresses") {
                return "Hub gRPC is unavailable. If you want to keep using local models, switch XT to `/hub route auto` or `/hub route file`. Otherwise reopen Hub and confirm Hub gRPC is running."
            }
            if r == "model_path_missing" {
                return "Hub could not auto-load a model (model_path_missing). Open Hub -> Models, register a model with a valid modelPath, then try again."
            }
            if r == "no_models_registered" || r == "no_model_routed" {
                return "Hub has no loadable model for this task. Open Hub -> Models and register/load at least one model."
            }
            if r == "model_not_loaded" {
                return "No model is loaded. Open Hub -> Models and load a model (or enable auto-load)."
            }
            if r == "model_not_found" {
                return "The selected model id is not found in Hub state. Open Hub -> Models, confirm the model is loaded, then run `/models` and `/model <id>` in X-Terminal to reselect."
            }
            if r == "bridge_disabled" {
                return "Selected model is remote/paid, but Hub Bridge is not enabled. In X-Terminal input box, run `/network 30m` (or `need network 30m`) and approve in Hub if required."
            }
            if r == "remote_model_not_found" {
                return "Hub Bridge cannot find this remote model configuration. Reopen Hub -> Settings -> Remote Models and re-add/import it, then retry."
            }
            if r == "api_key_missing" {
                return "Remote model API key is missing. Set the key in Hub -> Settings -> Remote Models."
            }
            if r == "base_url_invalid" {
                return "Remote model base URL is invalid. Check Base URL in Hub -> Settings -> Remote Models."
            }
            if r == "node_missing" {
                return "This X-Terminal install cannot find a usable Node runtime for the Hub client kit. Re-run Hub pairing One-Click / install-client, or install Node.js on this Mac. If you distribute X-Terminal as a packaged app, bundle relflowhub_node to avoid this dependency."
            }
            if r == "node_runtime_killed" {
                return "Remote Hub client runtime was killed by macOS. In Hub Setup run Reset Pairing + One-Click to reinstall/sign client kit, or install system Node.js on this Mac."
            }
            if r.hasPrefix("mlx_lm_unavailable") {
                return "Hub runtime is running but MLX is unavailable: \(r)"
            }
            return "AI failed: \(r.isEmpty ? "unknown" : r)"
        }
    }
}

actor HubAIClient {
    static let shared = HubAIClient()
    private static let hubTransportModeKey = "xterminal_hub_transport_mode"
    private static let legacyHubTransportModeKey = "xterminal_hub_transport_mode"
    private static let hubPairingPortKey = "xterminal_hub_pairing_port"
    private static let legacyHubPairingPortKey = "xterminal_hub_pairing_port"
    private static let hubGrpcPortKey = "xterminal_hub_grpc_port"
    private static let legacyHubGrpcPortKey = "xterminal_hub_grpc_port"
    private static let hubInternetHostKey = "xterminal_hub_internet_host"
    private static let legacyHubInternetHostKey = "xterminal_hub_internet_host"
    private static let hubAxhubctlPathKey = "xterminal_hub_axhubctl_path"
    private static let legacyHubAxhubctlPathKey = "xterminal_hub_axhubctl_path"
    private static let testingOverrideLock = NSLock()
    private static var remoteGenerateOverrideForTesting: (@Sendable (RemoteGenerateInvocation) async -> HubRemoteGenerateResult)?
    private static var cancelWriteOverrideForTesting: (@Sendable (Data, URL, URL) throws -> Void)?

    struct CachedRemoteProfile: Equatable, Sendable {
        var host: String?
        var internetHost: String?
        var pairingPort: Int?
        var grpcPort: Int?
        var hubInstanceID: String?
        var lanDiscoveryName: String?
    }

    struct RemoteGenerateInvocation: Equatable, Sendable {
        var requestId: String
        var modelId: String?
        var prompt: String
        var maxTokens: Int
        var temperature: Double
        var topP: Double
        var taskType: String
        var appId: String
        var projectId: String?
        var sessionId: String?
        var failClosedOnDowngrade: Bool
    }

    struct RemoteRetryResolutionForTesting: Equatable, Sendable {
        var requestedModelId: String
        var actualModelId: String
        var ok: Bool
        var reasonCode: String?
        var remoteRetryAttempted: Bool
        var remoteRetryFromModelId: String?
        var remoteRetryToModelId: String?
        var remoteRetryReasonCode: String?
    }

    struct CancelRequestStatus: Equatable, Sendable {
        var requestQueued: Bool? = nil
        var requestError: String = ""
    }

    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    private let jsonDecoder = JSONDecoder()

    private struct RemoteRetryMetadata {
        var attempted: Bool
        var fromModelId: String?
        var toModelId: String?
        var reasonCode: String?

        static let none = RemoteRetryMetadata(
            attempted: false,
            fromModelId: nil,
            toModelId: nil,
            reasonCode: nil
        )
    }

    private struct RemoteAttemptResolution {
        var requestedModelId: String
        var report: HubRemoteGenerateResult
        var retryMetadata: RemoteRetryMetadata
    }

    private struct PendingRemoteGenerate {
        var prompt: String
        var preferredModelId: String?
        var explicitModelId: String?
        var maxTokens: Int
        var temperature: Double
        var topP: Double
        var taskType: String
        var appId: String
        var projectId: String?
        var sessionId: String?
        var autoLoad: Bool
        var transportMode: HubTransportMode
        var remoteBackupModelId: String?
    }

    private struct PendingGenerateContext {
        var deviceName: String
        var preferredModelId: String?
        var explicitModelId: String?
        var runtimeProvider: String
        var executionPath: String
        var fallbackReasonCode: String?
        var remoteRetryAttempted: Bool
        var remoteRetryFromModelId: String?
        var remoteRetryToModelId: String?
        var remoteRetryReasonCode: String?

        var resolvedModelId: String {
            if let explicitModelId, !explicitModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explicitModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let preferredModelId, !preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "unknown_model"
        }
    }

    private var pendingRemoteGenerates: [String: PendingRemoteGenerate] = [:]
    private var pendingGenerateContexts: [String: PendingGenerateContext] = [:]
    private var remoteModelsCache: ModelStateSnapshot = .empty()
    private var remoteModelsLastFetchAt: Date = .distantPast

    private static func withTestingOverrideLock<T>(_ body: () -> T) -> T {
        testingOverrideLock.lock()
        defer { testingOverrideLock.unlock() }
        return body()
    }

    private static func writeCancelData(_ data: Data, tmp: URL, out: URL) throws {
        if let override = withTestingOverrideLock({ cancelWriteOverrideForTesting }) {
            try override(data, tmp, out)
            return
        }
        try data.write(to: tmp, options: .atomic)
        try FileManager.default.moveItem(at: tmp, to: out)
    }

    private static func summarized(_ error: Error) -> String {
        "\(type(of: error)):\(error.localizedDescription)"
    }

    static func transportMode() -> HubTransportMode {
        let d = UserDefaults.standard
        let raw = (d.string(forKey: hubTransportModeKey) ?? d.string(forKey: legacyHubTransportModeKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mode = HubTransportMode(rawValue: raw) {
            return mode
        }
        return .auto
    }

    static func setTransportMode(_ mode: HubTransportMode) {
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: hubTransportModeKey)
        d.set(mode.rawValue, forKey: legacyHubTransportModeKey)
    }

    static func parseTransportModeToken(_ token: String) -> HubTransportMode? {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto":
            return .auto
        case "grpc", "remote":
            return .grpc
        case "file", "fileipc", "ipc", "local":
            return .fileIPC
        default:
            return nil
        }
    }

    static func remoteConnectOptionsFromDefaults(stateDir: URL? = nil) -> HubRemoteConnectOptions {
        let d = UserDefaults.standard
        let effectiveStateDir = stateDir ?? defaultAxhubStateDir()
        let cached = cachedRemoteProfile(stateDir: effectiveStateDir)
        let pairing = d.object(forKey: hubPairingPortKey) as? Int
            ?? d.object(forKey: legacyHubPairingPortKey) as? Int
            ?? cached.pairingPort
            ?? 50052
        let grpc = d.object(forKey: hubGrpcPortKey) as? Int
            ?? d.object(forKey: legacyHubGrpcPortKey) as? Int
            ?? cached.grpcPort
            ?? 50051
        let explicitInternetHost = normalizedNonEmpty(
            d.string(forKey: hubInternetHostKey)
                ?? d.string(forKey: legacyHubInternetHostKey)
                ?? ""
        )
        let internetHost = explicitInternetHost
            ?? cached.internetHost
            ?? inferredReusableInternetHost(
                from: cached.host,
                hubInstanceID: cached.hubInstanceID,
                lanDiscoveryName: cached.lanDiscoveryName
            )
            ?? ""
        let axhubctlPath = d.string(forKey: hubAxhubctlPathKey)
            ?? d.string(forKey: legacyHubAxhubctlPathKey)
            ?? ""

        return HubRemoteConnectOptions(
            grpcPort: max(1, min(65_535, grpc)),
            pairingPort: max(1, min(65_535, pairing)),
            deviceName: Host.current().localizedName ?? "X-Terminal",
            internetHost: internetHost,
            axhubctlPath: axhubctlPath,
            stateDir: effectiveStateDir
        )
    }

    static func cachedRemoteProfile(stateDir: URL? = nil) -> CachedRemoteProfile {
        let base = stateDir ?? defaultAxhubStateDir()
        let pairingEnv = base.appendingPathComponent("pairing.env")
        let hubEnv = base.appendingPathComponent("hub.env")

        let hostFromPairing = normalizedNonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_HUB_HOST"))
        let hostFromHub = normalizedNonEmpty(readEnvValue(from: hubEnv, key: "HUB_HOST"))
        let internetFromPairing = normalizedNonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_INTERNET_HOST"))
        let hubInstanceID = normalizedNonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_HUB_INSTANCE_ID"))
        let lanDiscoveryName = normalizedNonEmpty(readEnvValue(from: pairingEnv, key: "AXHUB_LAN_DISCOVERY_NAME"))
        let host = hostFromPairing ?? hostFromHub
        let pairingPort = normalizePort(readEnvValue(from: pairingEnv, key: "AXHUB_PAIRING_PORT"))
        let grpcFromPairing = normalizePort(readEnvValue(from: pairingEnv, key: "AXHUB_GRPC_PORT"))
        let grpcPort = grpcFromPairing ?? normalizePort(readEnvValue(from: hubEnv, key: "HUB_PORT"))
        let reusableInternetHost = internetFromPairing ?? inferredReusableInternetHost(
            from: host,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )

        return CachedRemoteProfile(
            host: host,
            internetHost: reusableInternetHost,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
    }

    private static func defaultAxhubStateDir() -> URL {
        XTProcessPaths.defaultAxhubStateDir()
    }

    private static func readEnvValue(from fileURL: URL, key: String) -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let idx = trimmed.firstIndex(of: "=") else { continue }
            let lhs = trimmed[..<idx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard lhs == key else { continue }
            let rhs = trimmed[trimmed.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if rhs.hasPrefix("'"), rhs.hasSuffix("'"), rhs.count >= 2 {
                return String(rhs.dropFirst().dropLast())
            }
            return String(rhs)
        }
        return nil
    }

    private static func normalizePort(_ raw: String?) -> Int? {
        guard let value = normalizedNonEmpty(raw), let port = Int(value), (1...65_535).contains(port) else {
            return nil
        }
        return port
    }

    private static func normalizedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func inferredReusableInternetHost(
        from host: String?,
        hubInstanceID: String? = nil,
        lanDiscoveryName: String? = nil
    ) -> String? {
        guard let host = normalizedNonEmpty(host) else { return nil }
        let lowered = host.lowercased()
        if lowered == "localhost" || lowered == "127.0.0.1" || lowered.hasSuffix(".local") {
            return nil
        }
        if isPrivateIPv4Host(lowered) {
            return nil
        }
        if isIPv4Host(lowered),
           normalizedNonEmpty(hubInstanceID) != nil || normalizedNonEmpty(lanDiscoveryName) != nil {
            return nil
        }
        return host
    }

    private static func isIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { (0...255).contains($0) }
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        guard isIPv4Host(host) else { return false }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        let a = octets[0]
        let b = octets[1]
        if a == 10 { return true }
        if a == 127 { return true }
        if a == 169, b == 254 { return true }
        if a == 172, b >= 16, b <= 31 { return true }
        if a == 192, b == 168 { return true }
        return false
    }

    func loadRuntimeStatus() -> AIRuntimeStatus? {
        let url = HubPaths.runtimeStatusURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? jsonDecoder.decode(AIRuntimeStatus.self, from: data)
    }

    func loadModelsState(transportOverride: HubTransportMode? = nil) async -> ModelStateSnapshot {
        let mode = transportOverride ?? Self.transportMode()
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        let decision = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: hasRemote)
        switch decision.mode {
        case .grpc:
            guard hasRemote else { return .empty() }
            return await loadRemoteModelsThrottled() ?? .empty()
        case .fileIPC:
            return loadLocalModelsState()
        case .auto:
            if hasRemote, let remote = await loadRemoteModelsThrottled() {
                return remote
            }
            let local = loadLocalModelsState()
            if !local.models.isEmpty {
                return local
            }
            if hasRemote, let remote = await loadRemoteModelsThrottled() {
                return remote
            }
            return local
        }
    }

    func enqueueGenerate(
        prompt: String,
        taskType: String,
        preferredModelId: String? = nil,
        explicitModelId: String? = nil,
        appId: String = "x_terminal",
        projectId: String? = nil,
        sessionId: String? = nil,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true,
        transportOverride: HubTransportMode? = nil
    ) async throws -> String {
        let mode = transportOverride ?? Self.transportMode()
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        let decision = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: hasRemote)
        let runtimeAlive = (loadRuntimeStatus()?.isAlive(ttl: 3.0) == true)
        let modelSnapshot = await loadModelsState(transportOverride: transportOverride)
        let resolvedPreferredModelId = Self.sanitizedInteractiveGenerateModelID(
            preferredModelId,
            snapshot: modelSnapshot,
            taskType: taskType
        )
        let resolvedExplicitModelId = Self.sanitizedInteractiveGenerateModelID(
            explicitModelId,
            snapshot: modelSnapshot,
            taskType: taskType
        )
        let effectiveRemoteModelId = resolvedExplicitModelId ?? resolvedPreferredModelId
        let remoteBackupModelId = Self.preferredRemoteRetryBackupModelID(
            requestedModelId: effectiveRemoteModelId,
            snapshot: modelSnapshot,
            transportMode: decision.mode,
            projectId: projectId
        )

        if decision.preferRemote {
            return enqueueRemoteGenerate(
                prompt: prompt,
                preferredModelId: resolvedPreferredModelId,
                explicitModelId: resolvedExplicitModelId,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                taskType: taskType,
                appId: appId,
                projectId: projectId,
                sessionId: sessionId,
                autoLoad: autoLoad,
                transportMode: decision.mode,
                remoteBackupModelId: remoteBackupModelId
            )
        }

        if decision.requiresRemote {
            throw HubAIError.grpcRouteUnavailable
        }

        guard runtimeAlive || autoLoad else {
            throw HubAIError.runtimeNotRunning
        }

        return try await enqueueLocalGenerate(
            prompt: prompt,
            taskType: taskType,
            preferredModelId: resolvedPreferredModelId,
            explicitModelId: resolvedExplicitModelId,
            appId: appId,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            autoLoad: autoLoad,
            forcedReqId: nil
        )
    }

    private func enqueueLocalGenerate(
        prompt: String,
        taskType: String,
        preferredModelId: String?,
        explicitModelId: String?,
        appId: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        autoLoad: Bool,
        forcedReqId: String?
    ) async throws -> String {
        let rid = forcedReqId ?? UUID().uuidString
        let req = HubAIRequest(
            req_id: rid,
            app_id: appId,
            task_type: taskType,
            preferred_model_id: preferredModelId,
            model_id: explicitModelId,
            prompt: prompt,
            max_tokens: max(1, min(8192, maxTokens)),
            temperature: temperature,
            top_p: topP,
            created_at: Date().timeIntervalSince1970,
            auto_load: autoLoad
        )

        let reqDir = HubPaths.reqDir()
        let respDir = HubPaths.respDir()
        let cancelDir = HubPaths.cancelDir()
        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cancelDir, withIntermediateDirectories: true)

        let reqURL = reqDir.appendingPathComponent("req_\(rid).json")
        let tmpURL = reqDir.appendingPathComponent(".req_\(rid).tmp")

        do {
            let data = try jsonEncoder.encode(req)
            try data.write(to: tmpURL, options: .atomic)
            if FileManager.default.fileExists(atPath: reqURL.path) {
                try? FileManager.default.removeItem(at: reqURL)
            }
            try FileManager.default.moveItem(at: tmpURL, to: reqURL)
        } catch {
            throw HubAIError.requestWriteFailed("\(type(of: error)):\(error.localizedDescription)")
        }

        pendingGenerateContexts[rid] = PendingGenerateContext(
            deviceName: Host.current().localizedName ?? "X-Terminal",
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            runtimeProvider: "Hub (Local)",
            executionPath: "local_runtime",
            fallbackReasonCode: nil,
            remoteRetryAttempted: false,
            remoteRetryFromModelId: nil,
            remoteRetryToModelId: nil,
            remoteRetryReasonCode: nil
        )

        return rid
    }

    private func enqueueRemoteGenerate(
        prompt: String,
        preferredModelId: String?,
        explicitModelId: String?,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        taskType: String,
        appId: String,
        projectId: String?,
        sessionId: String?,
        autoLoad: Bool,
        transportMode: HubTransportMode,
        remoteBackupModelId: String?
    ) -> String {
        let rid = UUID().uuidString
        pendingRemoteGenerates[rid] = PendingRemoteGenerate(
            prompt: prompt,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            maxTokens: max(1, min(8192, maxTokens)),
            temperature: temperature,
            topP: topP,
            taskType: taskType,
            appId: appId,
            projectId: projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionId: sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            autoLoad: autoLoad,
            transportMode: transportMode,
            remoteBackupModelId: remoteBackupModelId
        )
        pendingGenerateContexts[rid] = PendingGenerateContext(
            deviceName: loadRemoteConnectOptions().deviceName,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: nil,
            remoteRetryAttempted: false,
            remoteRetryFromModelId: nil,
            remoteRetryToModelId: nil,
            remoteRetryReasonCode: nil
        )
        return rid
    }

    private func loadLocalModelsState() -> ModelStateSnapshot {
        let url = HubPaths.modelsStateURL()
        if let data = try? Data(contentsOf: url),
           let decoded = try? jsonDecoder.decode(ModelStateSnapshot.self, from: data) {
            return decoded
        }
        return .empty()
    }

    private func loadRemoteModelsThrottled() async -> ModelStateSnapshot? {
        let now = Date()
        if now.timeIntervalSince(remoteModelsLastFetchAt) < 8.0, !remoteModelsCache.models.isEmpty {
            return remoteModelsCache
        }

        remoteModelsLastFetchAt = now
        let report = await HubPairingCoordinator.shared.fetchRemoteModels(options: loadRemoteConnectOptions())
        if report.ok {
            let snap = ModelStateSnapshot(models: report.models, updatedAt: Date().timeIntervalSince1970)
            remoteModelsCache = snap
            return snap
        }

        if !remoteModelsCache.models.isEmpty {
            return remoteModelsCache
        }
        return nil
    }

    func cancel(reqId: String) -> CancelRequestStatus {
        pendingRemoteGenerates.removeValue(forKey: reqId)
        pendingGenerateContexts.removeValue(forKey: reqId)

        var requestQueued: Bool? = nil
        var requestErrors: [String] = []
        let cancelDir = HubPaths.cancelDir()
        do {
            try FileManager.default.createDirectory(at: cancelDir, withIntermediateDirectories: true)
        } catch {
            requestErrors.append("cancel_dir_create_failed=\(Self.summarized(error))")
        }
        let url = cancelDir.appendingPathComponent("cancel_\(reqId).json")
        let tmp = cancelDir.appendingPathComponent(".cancel_\(reqId).tmp")
        let obj: [String: Any] = ["req_id": reqId, "created_at": Date().timeIntervalSince1970]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [])
            try Self.writeCancelData(data, tmp: tmp, out: url)
            requestQueued = true
        } catch {
            requestQueued = false
            requestErrors.append("cancel_command_write_failed=\(Self.summarized(error))")
        }

        return CancelRequestStatus(
            requestQueued: requestQueued,
            requestError: requestErrors.joined(separator: " | ")
        )
    }

    func streamResponse(
        reqId: String,
        timeoutSec: Double = 120.0,
        pollMs: UInt64 = 50
    ) -> AsyncThrowingStream<HubAIResponseEvent, Error> {
        let context = pendingGenerateContexts.removeValue(forKey: reqId)
        if let remote = pendingRemoteGenerates.removeValue(forKey: reqId) {
            return remoteStreamResponse(reqId: reqId, pending: remote, context: context, timeoutSec: timeoutSec, pollMs: pollMs)
        }
        return localFileStreamResponse(reqId: reqId, context: context, timeoutSec: timeoutSec, pollMs: pollMs)
    }

    private static func responseMetadata(
        requestedModelId: String,
        actualModelId: String,
        runtimeProvider: String,
        executionPath: String,
        fallbackReasonCode: String,
        remoteRetryAttempted: Bool = false,
        remoteRetryFromModelId: String? = nil,
        remoteRetryToModelId: String? = nil,
        remoteRetryReasonCode: String? = nil
    ) -> [String: JSONValue] {
        var raw: [String: JSONValue] = [:]
        if !requestedModelId.isEmpty {
            raw["requested_model_id"] = .string(requestedModelId)
        }
        if !actualModelId.isEmpty {
            raw["actual_model_id"] = .string(actualModelId)
        }
        if !runtimeProvider.isEmpty {
            raw["runtime_provider"] = .string(runtimeProvider)
        }
        if !executionPath.isEmpty {
            raw["execution_path"] = .string(executionPath)
        }
        if !fallbackReasonCode.isEmpty {
            raw["fallback_reason_code"] = .string(fallbackReasonCode)
        }
        if remoteRetryAttempted {
            raw["remote_retry_attempted"] = .bool(true)
        }
        if let from = remoteRetryFromModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !from.isEmpty {
            raw["remote_retry_from_model_id"] = .string(from)
        }
        if let to = remoteRetryToModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !to.isEmpty {
            raw["remote_retry_to_model_id"] = .string(to)
        }
        if let reason = remoteRetryReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            raw["remote_retry_reason_code"] = .string(reason)
        }
        return raw
    }

    private static func mergeMetadata(
        into event: HubAIResponseEvent,
        requestedModelId: String,
        actualModelId: String,
        runtimeProvider: String,
        executionPath: String,
        fallbackReasonCode: String,
        remoteRetryAttempted: Bool = false,
        remoteRetryFromModelId: String? = nil,
        remoteRetryToModelId: String? = nil,
        remoteRetryReasonCode: String? = nil
    ) -> HubAIResponseEvent {
        var merged = event
        let metadata = Self.responseMetadata(
            requestedModelId: requestedModelId,
            actualModelId: actualModelId,
            runtimeProvider: runtimeProvider,
            executionPath: executionPath,
            fallbackReasonCode: fallbackReasonCode,
            remoteRetryAttempted: remoteRetryAttempted,
            remoteRetryFromModelId: remoteRetryFromModelId,
            remoteRetryToModelId: remoteRetryToModelId,
            remoteRetryReasonCode: remoteRetryReasonCode
        )
        if metadata.isEmpty {
            return merged
        }
        var raw = merged.raw ?? [:]
        for (key, value) in metadata {
            raw[key] = value
        }
        merged.raw = raw
        return merged
    }

    private func localFileStreamResponse(
        reqId: String,
        context: PendingGenerateContext?,
        timeoutSec: Double,
        pollMs: UInt64
    ) -> AsyncThrowingStream<HubAIResponseEvent, Error> {
        let respURL = HubPaths.respDir().appendingPathComponent("resp_\(reqId).jsonl")
        let decoder = jsonDecoder

        return AsyncThrowingStream { continuation in
            let task = Task {
                let deadline = Date().addingTimeInterval(timeoutSec)
                var offset: UInt64 = 0
                var buf = Data()
                var startedModelId: String = ""

                func drainLines() {
                    while true {
                        if let range = buf.firstRange(of: Data([0x0A])) { // '\n'
                            let lineData = buf.subdata(in: buf.startIndex ..< range.lowerBound)
                            buf.removeSubrange(buf.startIndex ... range.lowerBound)

                            let trimmed = lineData.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D } // space/tab/CR
                            if trimmed.isEmpty { continue }

                            do {
                                var ev = try decoder.decode(HubAIResponseEvent.self, from: Data(trimmed))
                                if ev.type == "start",
                                   let modelId = ev.model_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !modelId.isEmpty {
                                    startedModelId = modelId
                                }

                                if (ev.model_id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                                   !startedModelId.isEmpty,
                                   ev.type == "done" {
                                    ev.model_id = startedModelId
                                }

                                let requestedModelId = context?.resolvedModelId ?? ""
                                let actualModelId = ev.model_id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                    ? ev.model_id!.trimmingCharacters(in: .whitespacesAndNewlines)
                                    : startedModelId
                                let fallbackReasonCode = context?.fallbackReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                let runtimeProvider = context?.runtimeProvider ?? "Hub (Local)"
                                let executionPath = fallbackReasonCode.isEmpty
                                    ? (context?.executionPath ?? "local_runtime")
                                    : "local_fallback_after_remote_error"
                                ev = Self.mergeMetadata(
                                    into: ev,
                                    requestedModelId: requestedModelId,
                                    actualModelId: actualModelId,
                                    runtimeProvider: runtimeProvider,
                                    executionPath: executionPath,
                                    fallbackReasonCode: fallbackReasonCode,
                                    remoteRetryAttempted: context?.remoteRetryAttempted == true,
                                    remoteRetryFromModelId: context?.remoteRetryFromModelId,
                                    remoteRetryToModelId: context?.remoteRetryToModelId,
                                    remoteRetryReasonCode: context?.remoteRetryReasonCode
                                )
                                continuation.yield(ev)
                                if ev.type == "done" {
                                    if ev.ok == true {
                                        continuation.finish()
                                    } else {
                                        continuation.finish(
                                            throwing: HubAIError.responseDoneNotOk(
                                                HubAIResponseFailureContext(
                                                    reason: ev.reason ?? "",
                                                    deviceName: context?.deviceName ?? Host.current().localizedName ?? "X-Terminal",
                                                    modelId: context?.resolvedModelId
                                                )
                                            )
                                        )
                                    }
                                    return
                                }
                            } catch {
                                // Ignore malformed lines (best-effort tailing).
                                continue
                            }
                        } else {
                            break
                        }
                    }
                }

                while Date() < deadline {
                    try Task.checkCancellation()

                    if FileManager.default.fileExists(atPath: respURL.path) {
                        do {
                            let fh = try FileHandle(forReadingFrom: respURL)
                            defer { try? fh.close() }
                            try fh.seek(toOffset: offset)
                            if let chunk = try fh.readToEnd(), !chunk.isEmpty {
                                offset += UInt64(chunk.count)
                                buf.append(chunk)
                                drainLines()
                            }
                        } catch {
                            // Read races are expected; just retry.
                        }
                    }

                    try await Task.sleep(nanoseconds: pollMs * 1_000_000)
                }

                continuation.finish(throwing: HubAIError.responseTimeout)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func remoteStreamResponse(
        reqId: String,
        pending: PendingRemoteGenerate,
        context: PendingGenerateContext?,
        timeoutSec: Double,
        pollMs: UInt64
    ) -> AsyncThrowingStream<HubAIResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let preferred = pending.explicitModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? pending.explicitModelId
                    : pending.preferredModelId

                let resolution = await resolveRemoteGenerateWithRetry(
                    reqId: reqId,
                    pending: pending,
                    preferredModelId: preferred
                )
                let report = resolution.report

                if report.ok {
                    let requestedModelId = resolution.requestedModelId.isEmpty
                        ? (
                            report.requestedModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? report.requestedModelId!.trimmingCharacters(in: .whitespacesAndNewlines)
                                : (preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                        )
                        : resolution.requestedModelId
                    let actualModelId = report.actualModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? report.actualModelId!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : (report.modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? requestedModelId)
                    let runtimeProvider = report.runtimeProvider?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? report.runtimeProvider!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : (actualModelId == requestedModelId ? "Hub (Remote)" : "Hub (Local)")
                    let executionPath = report.executionPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? report.executionPath!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : "remote_model"
                    let fallbackReasonCode = report.fallbackReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let raw = Self.responseMetadata(
                        requestedModelId: requestedModelId,
                        actualModelId: actualModelId,
                        runtimeProvider: runtimeProvider,
                        executionPath: executionPath,
                        fallbackReasonCode: fallbackReasonCode,
                        remoteRetryAttempted: resolution.retryMetadata.attempted,
                        remoteRetryFromModelId: resolution.retryMetadata.fromModelId,
                        remoteRetryToModelId: resolution.retryMetadata.toModelId,
                        remoteRetryReasonCode: resolution.retryMetadata.reasonCode
                    )
                    continuation.yield(
                        HubAIResponseEvent(
                            type: "delta",
                            req_id: reqId,
                            ok: true,
                            reason: nil,
                            text: report.text,
                            seq: 1,
                            model_id: report.modelId,
                            raw: raw
                        )
                    )
                    continuation.yield(
                        HubAIResponseEvent(
                            type: "done",
                            req_id: reqId,
                            ok: true,
                            reason: "eos",
                            model_id: report.modelId,
                            promptTokens: report.promptTokens,
                            generationTokens: report.completionTokens,
                            raw: raw
                        )
                    )
                    continuation.finish()
                } else {
                    let reason = report.reasonCode ?? "remote_chat_failed"
                    if pending.transportMode == .auto,
                       HubRouteStateMachine.shouldFallbackToFile(afterRemoteReasonCode: reason),
                       loadRuntimeStatus()?.isAlive(ttl: 3.0) == true {
                        do {
                            let localReqId = try await enqueueLocalGenerate(
                                prompt: pending.prompt,
                                taskType: pending.taskType,
                                preferredModelId: pending.preferredModelId,
                                explicitModelId: pending.explicitModelId,
                                appId: pending.appId,
                                maxTokens: pending.maxTokens,
                                temperature: pending.temperature,
                                topP: pending.topP,
                                autoLoad: pending.autoLoad,
                                forcedReqId: reqId
                            )
                            var fallbackContext = pendingGenerateContexts.removeValue(forKey: localReqId) ?? context
                            if fallbackContext != nil {
                                fallbackContext?.fallbackReasonCode = reason
                                fallbackContext?.executionPath = "local_fallback_after_remote_error"
                                fallbackContext?.remoteRetryAttempted = resolution.retryMetadata.attempted
                                fallbackContext?.remoteRetryFromModelId = resolution.retryMetadata.fromModelId
                                fallbackContext?.remoteRetryToModelId = resolution.retryMetadata.toModelId
                                fallbackContext?.remoteRetryReasonCode = resolution.retryMetadata.reasonCode
                            }
                            for try await event in localFileStreamResponse(
                                reqId: localReqId,
                                context: fallbackContext,
                                timeoutSec: timeoutSec,
                                pollMs: pollMs
                            ) {
                                continuation.yield(event)
                            }
                            continuation.finish()
                            return
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    continuation.finish(
                        throwing: HubAIError.responseDoneNotOk(
                            HubAIResponseFailureContext(
                                reason: reason,
                                deviceName: context?.deviceName ?? loadRemoteConnectOptions().deviceName,
                                modelId: context?.resolvedModelId ?? preferred
                            )
                        )
                    )
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func loadRemoteConnectOptions() -> HubRemoteConnectOptions {
        Self.remoteConnectOptionsFromDefaults(stateDir: nil)
    }

    private func performRemoteGenerate(
        reqId: String,
        pending: PendingRemoteGenerate,
        modelId: String?
    ) async -> HubRemoteGenerateResult {
        let invocation = RemoteGenerateInvocation(
            requestId: reqId,
            modelId: modelId,
            prompt: pending.prompt,
            maxTokens: pending.maxTokens,
            temperature: pending.temperature,
            topP: pending.topP,
            taskType: pending.taskType,
            appId: pending.appId,
            projectId: pending.projectId,
            sessionId: pending.sessionId,
            failClosedOnDowngrade: false
        )
        if let override = Self.withTestingOverrideLock({ Self.remoteGenerateOverrideForTesting }) {
            return await override(invocation)
        }
        return await HubPairingCoordinator.shared.generateRemoteText(
            options: loadRemoteConnectOptions(),
            modelId: modelId,
            prompt: pending.prompt,
            maxTokens: pending.maxTokens,
            temperature: pending.temperature,
            topP: pending.topP,
            taskType: pending.taskType,
            appId: pending.appId,
            projectId: pending.projectId,
            sessionId: pending.sessionId,
            failClosedOnDowngrade: false,
            requestId: reqId
        )
    }

    private func resolveRemoteGenerateWithRetry(
        reqId: String,
        pending: PendingRemoteGenerate,
        preferredModelId: String?
    ) async -> RemoteAttemptResolution {
        let requestedModelId = preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initialReport = await performRemoteGenerate(
            reqId: reqId,
            pending: pending,
            modelId: preferredModelId
        )
        let backupModelId = pending.remoteBackupModelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let retryReasonCode = Self.retryableRemoteBackupReasonCode(
            report: initialReport,
            backupModelId: backupModelId
        ) else {
            return RemoteAttemptResolution(
                requestedModelId: requestedModelId,
                report: initialReport,
                retryMetadata: .none
            )
        }

        let retriedReport = await performRemoteGenerate(
            reqId: reqId,
            pending: pending,
            modelId: backupModelId
        )
        return RemoteAttemptResolution(
            requestedModelId: requestedModelId,
            report: retriedReport,
            retryMetadata: RemoteRetryMetadata(
                attempted: true,
                fromModelId: requestedModelId,
                toModelId: backupModelId,
                reasonCode: retryReasonCode
            )
        )
    }

    static func normalizeConfiguredModelID(
        _ raw: String?,
        availableModels: [HubModel]
    ) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        if let exact = availableModels.first(where: {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return exact.id.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.contains("/") else { return trimmed }

        let needle = trimmed.lowercased()
        let suffixMatches = availableModels.filter { model in
            let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty else { return false }
            return id == needle || id.hasSuffix("/\(needle)")
        }
        if suffixMatches.count == 1,
           let resolved = suffixMatches.first?.id.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolved.isEmpty {
            return resolved
        }

        return trimmed
    }

    static func sanitizedInteractiveGenerateModelID(
        _ raw: String?,
        snapshot: ModelStateSnapshot,
        taskType: String
    ) -> String? {
        let normalized = normalizeConfiguredModelID(
            raw,
            availableModels: snapshot.models
        )
        guard shouldGuardInteractiveGenerateModel(taskType: taskType),
              let normalized,
              !normalized.isEmpty else {
            return normalized
        }

        guard let assessment = HubModelSelectionAdvisor.assess(
            requestedId: normalized,
            snapshot: snapshot
        ),
        assessment.nonInteractiveExactMatch != nil else {
            return normalized
        }

        if let fallback = assessment.loadedCandidates.first?.id.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    private static func shouldGuardInteractiveGenerateModel(taskType: String) -> Bool {
        let normalized = taskType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        switch normalized {
        case "embedding", "embed", "retrieval_embedding":
            return false
        default:
            return true
        }
    }

    static func preferredRemoteRetryBackupModelID(
        requestedModelId rawRequestedModelId: String?,
        snapshot: ModelStateSnapshot,
        transportMode: HubTransportMode,
        projectId: String?
    ) -> String? {
        guard transportMode == .auto else { return nil }
        let trimmedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedProjectId.isEmpty else { return nil }

        let requestedModelId = normalizeConfiguredModelID(
            rawRequestedModelId,
            availableModels: snapshot.models
        ) ?? rawRequestedModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requestedModelId.isEmpty else { return nil }

        return HubModelSelectionAdvisor.remoteLoadedFallbackCandidates(
            requestedId: requestedModelId,
            snapshot: snapshot,
            excludingModelIDs: [requestedModelId],
            candidateLimit: 1
        ).first?.id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shouldRetryRemoteWithBackup(
        afterRemoteReasonCode rawReason: String?,
        backupModelId: String?
    ) -> Bool {
        let backup = backupModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !backup.isEmpty else { return false }
        guard let token = HubRouteStateMachine.normalizedReasonToken(rawReason) else { return false }

        if token == "model_not_found" || token == "requested_model_not_found" {
            return true
        }
        if token.contains("model") && token.contains("not_found") {
            return true
        }
        if token.contains("model") && token.contains("missing") {
            return true
        }
        if token.contains("model") && token.contains("unavailable") {
            return true
        }
        if token.contains("model") && token.contains("not_loaded") {
            return true
        }
        if token.contains("model") && token.contains("unloaded") {
            return true
        }
        if token.contains("model") && token.contains("sleep") {
            return true
        }
        if token == "downgrade_to_local" {
            return true
        }
        if token.contains("downgrade") && token.contains("local") {
            return true
        }
        return false
    }

    private static func retryableRemoteBackupReasonCode(
        report: HubRemoteGenerateResult,
        backupModelId: String?
    ) -> String? {
        if !report.ok {
            let reason = report.reasonCode ?? "remote_chat_failed"
            return shouldRetryRemoteWithBackup(
                afterRemoteReasonCode: reason,
                backupModelId: backupModelId
            ) ? reason : nil
        }

        let executionPath = report.executionPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard executionPath == "hub_downgraded_to_local" else { return nil }

        let fallbackReason = report.fallbackReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = fallbackReason.isEmpty ? "downgrade_to_local" : fallbackReason
        return shouldRetryRemoteWithBackup(
            afterRemoteReasonCode: reason,
            backupModelId: backupModelId
        ) ? reason : nil
    }

    func generateText(
        prompt: String,
        taskType: String,
        preferredModelId: String? = nil,
        explicitModelId: String? = nil,
        appId: String = "x_terminal",
        projectId: String? = nil,
        sessionId: String? = nil,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true,
        transportOverride: HubTransportMode? = nil,
        timeoutSec: Double = 120.0
    ) async throws -> String {
        let (rid, text, _) = try await generateTextWithReqId(
            prompt: prompt,
            taskType: taskType,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            appId: appId,
            projectId: projectId,
            sessionId: sessionId,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            autoLoad: autoLoad,
            transportOverride: transportOverride
        )
        _ = rid
        return text
    }

    func generateTextWithReqId(
        prompt: String,
        taskType: String,
        preferredModelId: String? = nil,
        explicitModelId: String? = nil,
        appId: String = "x_terminal",
        projectId: String? = nil,
        sessionId: String? = nil,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true,
        transportOverride: HubTransportMode? = nil,
        timeoutSec: Double = 120.0
    ) async throws -> (reqId: String, text: String, usage: HubAIUsage?) {
        let rid = try await enqueueGenerate(
            prompt: prompt,
            taskType: taskType,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            appId: appId,
            projectId: projectId,
            sessionId: sessionId,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            autoLoad: autoLoad,
            transportOverride: transportOverride
        )

        var out = ""
        var usage: HubAIUsage? = nil
        for try await ev in streamResponse(reqId: rid, timeoutSec: timeoutSec) {
            if ev.type == "delta", let t = ev.text {
                out += t
            }
            if ev.type == "done" {
                if let pt = ev.promptTokens, let gt = ev.generationTokens {
                    usage = HubAIUsage(
                        promptTokens: pt,
                        generationTokens: gt,
                        generationTPS: ev.generationTPS ?? 0.0,
                        requestedModelId: ev.requestedModelIdFromMetadata,
                        actualModelId: ev.actualModelIdFromMetadata,
                        runtimeProvider: ev.runtimeProviderFromMetadata,
                        executionPath: ev.executionPathFromMetadata,
                        fallbackReasonCode: ev.fallbackReasonCodeFromMetadata,
                        remoteRetryAttempted: ev.remoteRetryAttemptedFromMetadata,
                        remoteRetryFromModelId: ev.remoteRetryFromModelIdFromMetadata,
                        remoteRetryToModelId: ev.remoteRetryToModelIdFromMetadata,
                        remoteRetryReasonCode: ev.remoteRetryReasonCodeFromMetadata
                    )
                }
            }
        }
        return (rid, out, usage)
    }

    func remoteRetryResolutionForTesting(
        reqId: String = "test-request",
        prompt: String = "test prompt",
        preferredModelId: String?,
        explicitModelId: String? = nil,
        remoteBackupModelId: String?,
        projectId: String? = "test-project",
        sessionId: String? = nil,
        transportMode: HubTransportMode = .auto
    ) async -> RemoteRetryResolutionForTesting {
        let pending = PendingRemoteGenerate(
            prompt: prompt,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            maxTokens: 128,
            temperature: 0.2,
            topP: 0.95,
            taskType: "chat_plan",
            appId: "x_terminal",
            projectId: projectId,
            sessionId: sessionId,
            autoLoad: true,
            transportMode: transportMode,
            remoteBackupModelId: remoteBackupModelId
        )
        let preferred = explicitModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? explicitModelId
            : preferredModelId
        let resolution = await resolveRemoteGenerateWithRetry(
            reqId: reqId,
            pending: pending,
            preferredModelId: preferred
        )
        return RemoteRetryResolutionForTesting(
            requestedModelId: resolution.requestedModelId,
            actualModelId: resolution.report.actualModelId ?? resolution.report.modelId ?? "",
            ok: resolution.report.ok,
            reasonCode: resolution.report.reasonCode,
            remoteRetryAttempted: resolution.retryMetadata.attempted,
            remoteRetryFromModelId: resolution.retryMetadata.fromModelId,
            remoteRetryToModelId: resolution.retryMetadata.toModelId,
            remoteRetryReasonCode: resolution.retryMetadata.reasonCode
        )
    }

    static func installRemoteGenerateOverrideForTesting(
        _ override: (@Sendable (RemoteGenerateInvocation) async -> HubRemoteGenerateResult)?
    ) {
        withTestingOverrideLock {
            remoteGenerateOverrideForTesting = override
        }
    }

    static func resetRemoteGenerateOverrideForTesting() {
        withTestingOverrideLock {
            remoteGenerateOverrideForTesting = nil
        }
    }

    static func installCancelWriteOverrideForTesting(
        _ override: (@Sendable (Data, URL, URL) throws -> Void)?
    ) {
        withTestingOverrideLock {
            cancelWriteOverrideForTesting = override
        }
    }

    static func resetCancelWriteOverrideForTesting() {
        withTestingOverrideLock {
            cancelWriteOverrideForTesting = nil
        }
    }
}
