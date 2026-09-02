import Foundation

extension SupervisorManager {
    func supervisorRemotePromptBlockIfApplicable(
        preferredModelId: String?
    ) -> XTHubRemotePromptBlockPresentation? {
        guard let appModel else { return nil }
        let preferredModel = preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !preferredModel.isEmpty else { return nil }
        guard supervisorConfiguredModelRequiresRemoteRoute(preferredModel) else { return nil }
        guard appModel.hubRemoteConnected == false else { return nil }

        let rawFailureCode = appModel.hubSetupFailureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFailureCode = UITroubleshootKnowledgeBase.normalizedFailureCode(rawFailureCode)
        let failureIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: rawFailureCode)
        let remoteRouteBlocked =
            normalizedFailureCode.contains("local_network_permission_required")
            || normalizedFailureCode.contains("local_network_discovery_blocked")
            || failureIssue == .hubUnreachable
            || failureIssue == .pairingRepairRequired
        guard remoteRouteBlocked else { return nil }

        let transportMode = HubAIClient.transportMode()
        let launchStatus = XTHubLaunchStatusStore.load(
            baseDir: appModel.hubBaseDir ?? HubPaths.baseDir()
        )
        let localFallbackBlocked = launchStatus?.blocksPaidOrWebCapabilities == true

        switch transportMode {
        case .grpc:
            break
        case .auto:
            guard localFallbackBlocked else { return nil }
        case .fileIPC:
            return nil
        }

        let reasonCode = normalizedFailureCode.isEmpty
            ? (failureIssue?.rawValue ?? "remote_route_preflight_blocked")
            : normalizedFailureCode
        return supervisorRemotePromptBlockPresentation(
            preferredModelId: preferredModel,
            reasonCode: reasonCode,
            transportMode: transportMode,
            localConnected: appModel.hubConnected,
            localLaunchStatus: launchStatus
        )
    }

    func supervisorRemotePromptBlockPresentation(
        preferredModelId: String,
        reasonCode: String,
        transportMode: HubTransportMode,
        localConnected: Bool,
        localLaunchStatus: XTHubLaunchStatusSnapshot?
    ) -> XTHubRemotePromptBlockPresentation {
        let normalizedReasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let blockedCapabilities = localLaunchStatus?.blockedCapabilitiesSummary ?? "none"
        let localBlockerLine: String? = {
            guard let localLaunchStatus,
                  localLaunchStatus.blocksPaidOrWebCapabilities else {
                return nil
            }
            var parts: [String] = ["本机 fallback Hub 当前已降级"]
            if !localLaunchStatus.rootCauseErrorCode.isEmpty {
                parts.append(localLaunchStatus.rootCauseErrorCode)
            }
            if blockedCapabilities != "none" {
                parts.append("blocked=\(blockedCapabilities)")
            }
            return parts.joined(separator: "：").replacingOccurrences(of: "：blocked=", with: " · blocked=")
        }()

        var lines: [String] = [
            "⚠️ Supervisor 这轮先不继续空转。",
            "",
            "当前配置模型 \(preferredModelId) 需要远端 Hub，但 XT 还没连上远端。",
            "当前状态：transport=\(transportMode.rawValue) · local_connected=\(localConnected) · remote_connected=false · failure_code=\(normalizedReasonCode)"
        ]

        switch transportMode {
        case .grpc:
            lines.append("当前 transport 是 grpc-only，所以这轮按 fail-closed 直接拦住，不会静默掉回本地。")
        case .auto:
            lines.append("当前 transport 是 auto，但本机 fallback Hub 也不具备这轮需要的 paid / web 能力，所以这轮同样按 fail-closed 拦住。")
        case .fileIPC:
            lines.append("当前 transport 是 fileIPC；这个入口不会去拉远端 Hub。")
        }

        if let localBlockerLine {
            lines.append(localBlockerLine)
        }
        if let detail = localLaunchStatus?.rootCauseDetail,
           !detail.isEmpty,
           localLaunchStatus?.blocksPaidOrWebCapabilities == true {
            lines.append("本地降级原因：\(detail)")
        }

        lines.append("")
        lines.append("下一步：")
        if normalizedReasonCode.contains("local_network_") {
            lines.append("1. 先到系统设置 → 隐私与安全性 → 本地网络允许 X-Terminal；如果已经允许，再检查当前 Wi-Fi / AP 是否开启了 client isolation。")
        } else {
            lines.append("1. 先修复远端 Hub 的 pairing / reachability，确认 XT 能连到 Hub 的 pairing / gRPC 入口。")
        }
        if localLaunchStatus?.blocksPaidOrWebCapabilities == true {
            lines.append("2. 如果暂时只能走本机路径，到 X-Hub → Diagnostics & Recovery 修复 bridge，至少先解除 ai.generate.paid / web.fetch 的阻塞。")
        } else {
            lines.append("2. 远端连接恢复后，再重试当前请求。")
        }

        return XTHubRemotePromptBlockPresentation(
            reasonCode: normalizedReasonCode,
            responseText: lines.joined(separator: "\n")
        )
    }

    func supervisorConfiguredModelRequiresRemoteRoute(_ preferredModelId: String) -> Bool {
        let normalizedModelId = preferredModelId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedModelId.isEmpty else { return false }

        if let matched = supervisorModelInventory().first(where: {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == normalizedModelId
        }) {
            return !matched.isLocalModel
        }

        let remoteProviderPrefixes = [
            "openai/",
            "anthropic/",
            "google/",
            "gemini/",
            "xai/",
            "grok/",
            "deepseek/",
            "mistral/",
            "perplexity/",
            "moonshot/",
            "bedrock/",
            "vertex/",
            "azure/"
        ]
        return remoteProviderPrefixes.contains(where: normalizedModelId.hasPrefix)
    }
}
