import Foundation

struct HubRouteDecision: Equatable {
    var mode: HubTransportMode
    var hasRemoteProfile: Bool
    var preferRemote: Bool
    var allowFileFallback: Bool
    var requiresRemote: Bool
    var remoteUnavailableReasonCode: String?
}

struct HubRouteRuleCheck: Equatable, Identifiable {
    var id: String { name }
    var name: String
    var ok: Bool
    var detail: String
}

enum HubRouteStateMachine {
    static func resolve(mode: HubTransportMode, hasRemoteProfile: Bool) -> HubRouteDecision {
        switch mode {
        case .grpc:
            return HubRouteDecision(
                mode: .grpc,
                hasRemoteProfile: hasRemoteProfile,
                preferRemote: hasRemoteProfile,
                allowFileFallback: false,
                requiresRemote: true,
                remoteUnavailableReasonCode: "hub_env_missing"
            )
        case .auto:
            return HubRouteDecision(
                mode: .auto,
                hasRemoteProfile: hasRemoteProfile,
                preferRemote: hasRemoteProfile,
                allowFileFallback: true,
                requiresRemote: false,
                remoteUnavailableReasonCode: nil
            )
        case .fileIPC:
            return HubRouteDecision(
                mode: .fileIPC,
                hasRemoteProfile: hasRemoteProfile,
                preferRemote: false,
                allowFileFallback: false,
                requiresRemote: false,
                remoteUnavailableReasonCode: nil
            )
        }
    }

    static func shouldFallbackToFile(afterRemoteReasonCode rawReason: String?) -> Bool {
        guard let token = normalizedReasonToken(rawReason) else { return false }

        if token == "hub_env_missing" || token == "grpc_route_unavailable" {
            return true
        }
        if token.contains("client_kit_missing") || token.contains("node_missing") {
            return true
        }
        if token.contains("discover_failed") || token.contains("bootstrap_failed") {
            return true
        }
        if token.contains("connect_failed") || token.contains("connection_refused") {
            return true
        }
        if token.contains("network_unreachable") || token.contains("service_unavailable") {
            return true
        }
        if token.contains("timeout") || token.contains("tls_error") || token.contains("ssl") {
            return true
        }
        return false
    }

    static func normalizedReasonToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return token.isEmpty ? nil : token
    }

    static func runSelfChecks() -> [HubRouteRuleCheck] {
        var checks: [HubRouteRuleCheck] = []
        func add(_ name: String, _ condition: Bool, _ detail: String) {
            checks.append(HubRouteRuleCheck(name: name, ok: condition, detail: detail))
        }

        let autoWithRemote = resolve(mode: .auto, hasRemoteProfile: true)
        add(
            "auto_remote_preferred",
            autoWithRemote.preferRemote && autoWithRemote.allowFileFallback && !autoWithRemote.requiresRemote,
            "auto + remote profile => remote first, file fallback allowed"
        )

        let autoNoRemote = resolve(mode: .auto, hasRemoteProfile: false)
        add(
            "auto_no_remote_file_only",
            !autoNoRemote.preferRemote && autoNoRemote.allowFileFallback && !autoNoRemote.requiresRemote,
            "auto + no remote profile => direct file route"
        )

        let grpcWithRemote = resolve(mode: .grpc, hasRemoteProfile: true)
        add(
            "grpc_remote_only",
            grpcWithRemote.preferRemote && !grpcWithRemote.allowFileFallback && grpcWithRemote.requiresRemote,
            "grpc + remote profile => remote only (no silent fallback)"
        )

        let grpcNoRemote = resolve(mode: .grpc, hasRemoteProfile: false)
        add(
            "grpc_missing_profile_fail_closed",
            !grpcNoRemote.preferRemote && grpcNoRemote.requiresRemote && grpcNoRemote.remoteUnavailableReasonCode == "hub_env_missing",
            "grpc + no remote profile => fail closed (hub_env_missing)"
        )

        let fileAny = resolve(mode: .fileIPC, hasRemoteProfile: true)
        add(
            "file_forces_local",
            !fileAny.preferRemote && !fileAny.allowFileFallback && !fileAny.requiresRemote,
            "file mode => local file IPC only"
        )

        add(
            "fallback_on_route_unavailable",
            shouldFallbackToFile(afterRemoteReasonCode: "hub_env_missing"),
            "remote route unavailable should fallback in auto"
        )
        add(
            "fallback_on_timeout",
            shouldFallbackToFile(afterRemoteReasonCode: "timeout"),
            "timeout should fallback in auto"
        )
        add(
            "no_fallback_on_model_not_found",
            !shouldFallbackToFile(afterRemoteReasonCode: "model_not_found"),
            "model_not_found should surface error without fallback"
        )
        add(
            "no_fallback_on_api_key_missing",
            !shouldFallbackToFile(afterRemoteReasonCode: "api_key_missing"),
            "api_key_missing should surface error without fallback"
        )

        return checks
    }
}
