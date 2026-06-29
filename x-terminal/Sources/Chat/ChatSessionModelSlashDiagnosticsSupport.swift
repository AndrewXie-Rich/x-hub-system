import Foundation

extension ChatSessionModel {
    func performSlashSandboxSelfTest(
        ctx: AXProjectContext,
        userText: String,
        assistantIndex: Int
    ) {
        Task {
            let previousMode = ToolExecutor.sandboxMode()
            let token = "XTERMINAL_SANDBOX_SELFTEST_TOKEN_\(UUID().uuidString)"
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("xterminal-sandbox-selftest-\(UUID().uuidString)", isDirectory: true)

            defer {
                ToolExecutor.setSandboxMode(previousMode)
                try? FileManager.default.removeItem(at: tempRoot)
            }

            do {
                let srcDir = tempRoot.appendingPathComponent("src", isDirectory: true)
                try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
                let file = srcDir.appendingPathComponent("selftest.txt")
                let content = """
                line one
                \(token)
                line three
                """
                guard let data = content.data(using: .utf8) else {
                    throw NSError(domain: "xterminal", code: 1, userInfo: [NSLocalizedDescriptionKey: "selftest content encode failed"])
                }
                try data.write(to: file, options: .atomic)

                let explicitSandboxCall = ToolCall(
                    id: "sandbox_selftest_explicit",
                    tool: .search,
                    args: [
                        "pattern": .string(token),
                        "sandbox": .bool(true),
                    ]
                )
                let explicitSandbox = try await ToolExecutor.execute(call: explicitSandboxCall, projectRoot: tempRoot)
                let explicitSandboxOK = explicitSandbox.ok &&
                    explicitSandbox.output.contains("sandbox: true") &&
                    explicitSandbox.output.contains(token)

                ToolExecutor.setSandboxMode(.sandbox)
                let defaultSandboxCall = ToolCall(
                    id: "sandbox_selftest_default",
                    tool: .search,
                    args: [
                        "pattern": .string(token),
                    ]
                )
                let defaultSandbox = try await ToolExecutor.execute(call: defaultSandboxCall, projectRoot: tempRoot)
                let defaultSandboxOK = defaultSandbox.ok &&
                    defaultSandbox.output.contains("sandbox: true") &&
                    defaultSandbox.output.contains(token)

                let hostOverrideCall = ToolCall(
                    id: "sandbox_selftest_host_override",
                    tool: .search,
                    args: [
                        "pattern": .string(token),
                        "sandbox": .bool(false),
                    ]
                )
                let hostOverride = try await ToolExecutor.execute(call: hostOverrideCall, projectRoot: tempRoot)
                let hostOverrideOK = hostOverride.ok &&
                    !hostOverride.output.contains("sandbox: true") &&
                    hostOverride.output.contains(token)

                try? await SandboxManager.shared.destroySandbox(forProjectRoot: tempRoot)

                let overall = explicitSandboxOK && defaultSandboxOK && hostOverrideOK
                let summary = """
工具执行路径自检：\(localizedPassFail(overall))
- 明确指定 `sandbox=true`：\(localizedPassFail(explicitSandboxOK))
- 默认模式为 sandbox：\(localizedPassFail(defaultSandboxOK))
- 明确指定 `sandbox=false` 覆盖：\(localizedPassFail(hostOverrideOK))
"""
                finalizeTurn(ctx: ctx, userText: userText, assistantText: summary, assistantIndex: assistantIndex)
            } catch {
                let msg = String(describing: error)
                let out = "工具执行路径自检：失败\n- 错误：\(msg)"
                finalizeTurn(ctx: ctx, userText: userText, assistantText: out, assistantIndex: assistantIndex)
            }
        }
    }

    func performSlashGrantCommand(
        ctx: AXProjectContext,
        userText: String,
        args: [String],
        assistantIndex: Int
    ) {
        Task {
            let head = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            switch head {
            case "", "show", "status", "list":
                let runtime = await ToolExecutor.highRiskGrantRuntimeStatus(projectRoot: ctx.root)
                let reply = """
高风险授权状态：
- 当前受控能力：联网抓取（web_fetch，请求参数里需要 `grant_id`）
\(frontstageHighRiskGrantRuntimeStatus(runtime))

命令：
- /grant status
- /grant scan
- /grant selftest
"""
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            case "scan":
                let runtime = await ToolExecutor.highRiskGrantRuntimeStatus(projectRoot: ctx.root)
                let report = ToolExecutor.scanHighRiskGrantBypass(ctx: ctx)
                let scanText = frontstageHighRiskGrantBypassScanReport(report)
                let reply = scanText + "\n\n" + frontstageHighRiskGrantRuntimeStatus(runtime)
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            case "selftest":
                let checks = await ToolExecutor.runHighRiskGrantSelfChecks(projectRoot: ctx.root)
                let scan = ToolExecutor.scanHighRiskGrantBypass(ctx: ctx, maxBytes: 180_000, maxFindings: 8)
                let reply = frontstageHighRiskGrantSelfTestSummary(checks: checks, scan: scan)
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            default:
                let runtime = await ToolExecutor.highRiskGrantRuntimeStatus(projectRoot: ctx.root)
                let reply = """
用法：
- /grant status
- /grant scan
- /grant selftest

\(frontstageHighRiskGrantRuntimeStatus(runtime))
"""
                finalizeTurn(ctx: ctx, userText: userText, assistantText: reply, assistantIndex: assistantIndex)
            }
        }
    }
}
