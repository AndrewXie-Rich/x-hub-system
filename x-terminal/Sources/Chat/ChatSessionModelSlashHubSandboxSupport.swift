import Foundation

extension ChatSessionModel {
    func handleSlashHub(args: [String]) -> String {
        guard let headRaw = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !headRaw.isEmpty else {
            return slashHubRouteText()
        }

        switch headRaw {
        case "status", "show", "list":
            return slashHubRouteText()
        case "route":
            guard args.count >= 2 else {
                return slashHubRouteText()
            }
            let rawMode = args[1]
            if rawMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "selftest" {
                return slashHubRouteSelfTestText()
            }
            guard let mode = HubAIClient.parseTransportModeToken(rawMode) else {
                return "未知 route：\(rawMode)\n可选：auto / grpc / file"
            }
            HubAIClient.setTransportMode(mode)
            return "已设置 Hub 会话通道：\(mode.rawValue)\n\n" + slashHubRouteText()
        default:
            return """
用法：
- /hub route
- /hub route <auto|grpc|file>
- /hub route selftest
"""
        }
    }

    func slashHubRouteText() -> String {
        let mode = HubAIClient.transportMode()
        let withRemote = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: true)
        let withoutRemote = HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: false)
        let withRemoteBehavior = routeDecisionText(withRemote)
        let withoutRemoteBehavior = routeDecisionText(withoutRemote)
        return """
Hub 传输模式：
- 当前模式：\(mode.rawValue)
- 有远端 profile 时：\(withRemoteBehavior)
- 无远端 profile 时：\(withoutRemoteBehavior)

命令：
- /hub route
- /hub route <auto|grpc|file>
- /hub route selftest
"""
    }

    func slashHubRouteSelfTestText() -> String {
        let checks = HubRouteStateMachine.runSelfChecks()
        let okCount = checks.filter(\.ok).count
        let total = checks.count
        let status = okCount == total ? "通过" : "失败"
        let lines = checks.map { check in
            "- [\(localizedPassFail(check.ok))] \(hubRouteSelfCheckNameText(check.name))：\(hubRouteSelfCheckDetailText(check.detail))"
        }
        return "Hub 路由自检：\(status) (\(okCount)/\(total))\n\n" + lines.joined(separator: "\n")
    }

    func handleSlashSandbox(args: [String]) -> String {
        guard let headRaw = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !headRaw.isEmpty else {
            return slashSandboxText()
        }

        switch headRaw {
        case "show", "status", "list":
            return slashSandboxText()
        case "mode":
            guard args.count >= 2 else {
                return slashSandboxText()
            }
            let token = args[1]
            guard let mode = ToolExecutor.parseSandboxModeToken(token) else {
                return "未知工具执行路径模式：\(token)\n可选：host / sandbox"
            }
            ToolExecutor.setSandboxMode(mode)
            return "已设置工具默认执行路径：\(sandboxModeDisplayText(mode))（\(mode.rawValue)）\n\n" + slashSandboxText()
        default:
            return """
用法：
- /sandbox
- /sandbox mode <host|sandbox>
- /sandbox selftest
"""
        }
    }

    func slashSandboxText() -> String {
        let mode = ToolExecutor.sandboxMode()
        let behavior: String
        switch mode {
        case .host:
            behavior = "默认走宿主环境；传 `sandbox=true` 时临时改走沙箱。"
        case .sandbox:
            behavior = "默认走沙箱环境；传 `sandbox=false` 时临时改走宿主。"
        }
        return """
工具执行路径：
- 当前默认：\(sandboxModeDisplayText(mode))（\(mode.rawValue)）
- 生效方式：\(behavior)

命令：
- /sandbox
- /sandbox mode <host|sandbox>
- /sandbox selftest
"""
    }
}
