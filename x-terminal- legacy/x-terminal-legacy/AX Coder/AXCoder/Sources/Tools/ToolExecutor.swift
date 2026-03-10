import Foundation

enum ToolExecutor {
    static func execute(call: ToolCall, projectRoot: URL, stream: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> ToolResult {
        switch call.tool {
        case .read_file:
            let path = strArg(call, "path")
            let s = try FileTool.readText(path: path, projectRoot: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: s)

        case .write_file:
            let path = strArg(call, "path")
            let content = strArg(call, "content")
            try FileTool.writeText(path: path, content: content, projectRoot: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")

        case .list_dir:
            let path = strArg(call, "path")
            let items = try FileTool.listDir(path: path, projectRoot: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: items.joined(separator: "\n"))

        case .search:
            let pattern = strArg(call, "pattern")
            let glob = optStrArg(call, "glob")
            let lines = try FileTool.search(pattern: pattern, projectRoot: projectRoot, glob: glob)
            let out = lines.isEmpty ? "(no matches)" : lines.joined(separator: "\n")
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)

        case .run_command:
            let cmd = strArg(call, "command")
            let timeout = optDoubleArg(call, "timeout_sec") ?? 60.0
            if requiresTTY(cmd) {
                let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                let hint = trimmed.isEmpty ? "(empty command)" : trimmed
                let out = """
tty_required: this command likely needs an interactive TTY (ShellSession is non-PTY).

Please switch to Terminal mode (Chat/Terminal toggle) and run it there:
\(hint)
"""
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: out)
            }
            let res = try await ShellSessionManager.shared.run(command: cmd, root: projectRoot, timeoutSec: timeout, onOutput: stream)
            let out = "exit: \(res.exitCode)\n" + (res.combined.isEmpty ? "(no output)" : res.combined)
            return ToolResult(id: call.id, tool: call.tool, ok: res.exitCode == 0, output: out)

        case .git_status:
            let res = try GitTool.status(root: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: res.exitCode == 0, output: res.combined.isEmpty ? "(clean)" : res.combined)

        case .git_diff:
            let cached = optBoolArg(call, "cached") ?? false
            let res = try GitTool.diff(root: projectRoot, cached: cached)
            return ToolResult(id: call.id, tool: call.tool, ok: res.exitCode == 0, output: res.combined.isEmpty ? "(empty diff)" : res.combined)

        case .git_apply:
            let patch = strArg(call, "patch")
            let res = try GitApplier.applyPatch(patch, cwd: projectRoot)
            let ok = res.exit == 0
            let out = "exit: \(res.exit)\n" + (res.output.isEmpty ? "(no output)" : res.output)
            return ToolResult(id: call.id, tool: call.tool, ok: ok, output: out)

        case .git_apply_check:
            let patch = strArg(call, "patch")
            let res = try ProcessCapture.run(
                "/usr/bin/git",
                ["apply", "--check", "-"],
                cwd: projectRoot,
                stdin: patch.data(using: .utf8),
                timeoutSec: 20.0
            )
            let ok = res.exitCode == 0
            let out = "exit: \(res.exitCode)\n" + (res.combined.isEmpty ? "(ok)" : res.combined)
            return ToolResult(id: call.id, tool: call.tool, ok: ok, output: out)

        case .bridge_status:
            let st = HubBridgeClient.status()
            let out = "alive=\(st.alive) enabled=\(st.enabled) enabledUntil=\(st.enabledUntil)"
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)

        case .need_network:
            let seconds = Int(optDoubleArg(call, "seconds") ?? 900)
            let reason = optStrArg(call, "reason")
            let reasonText = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = reasonText.isEmpty ? "" : " reason=\(reasonText)"
            let access = await HubIPCClient.requestNetworkAccess(root: projectRoot, seconds: seconds, reason: reason)
            let route = access.source.lowercased()

            switch access.state {
            case .enabled:
                let rem = max(0, access.remainingSeconds ?? 0)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "network_already_enabled (remaining=\(rem)s)")

            case .autoApproved:
                if let rem = access.remainingSeconds, rem > 0 {
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "network_auto_approved_and_enabled (remaining=\(rem)s)")
                }
                let grantSuffix: String
                if let gid = access.grantRequestId, !gid.isEmpty {
                    grantSuffix = " (grant=\(gid))"
                } else {
                    grantSuffix = ""
                }
                let prefix = route == "grpc" ? "network_auto_approved_via_grpc" : "network_auto_approved"
                let out = "\(prefix)\(grantSuffix) (bridge_starting)\(suffix)"
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)

            case .queued:
                let grantSuffix: String
                if let gid = access.grantRequestId, !gid.isEmpty {
                    grantSuffix = " (grant=\(gid))"
                } else {
                    grantSuffix = ""
                }
                if route == "grpc" {
                    let out = "network_request_queued_via_grpc\(grantSuffix) (seconds=\(seconds))\(suffix) — waiting for Hub approval"
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)
                }
                if access.reasonCode == "ack_timeout" {
                    let out = "network_request_sent (seconds=\(seconds))\(suffix) — waiting for Hub approval"
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)
                }
                let out = "network_request_queued\(grantSuffix) (seconds=\(seconds))\(suffix) — waiting for Hub approval"
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)

            case .denied:
                let why = HubIPCClient.normalizedReasonCode(access.reasonCode, fallback: "denied") ?? "denied"
                let out = why == "denied" ? "network_denied" : "network_denied (\(why))"
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: out)

            case .failed:
                let why = HubIPCClient.normalizedReasonCode(access.reasonCode, fallback: "grant_failed") ?? "grant_failed"
                if why == "hub_not_connected" {
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "hub_not_connected (cannot request network)")
                }
                if route == "grpc" {
                    let out = why == "grant_failed" ? "network_grpc_grant_failed" : "network_grpc_grant_failed (\(why))"
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: out)
                }
                let out = why == "grant_failed" ? "network_request_failed" : "network_request_failed (\(why))"
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: out)
            }

        case .web_fetch:
            let url = strArg(call, "url")
            let timeout = optDoubleArg(call, "timeout_sec") ?? 12.0
            let maxBytes = Int(optDoubleArg(call, "max_bytes") ?? 1_000_000)
            let mode = HubAIClient.transportMode()
            let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
            let preferRemote = hasRemote && (mode == .grpc || mode == .auto)

            if mode == .grpc, !hasRemote {
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "remote_web_fetch_failed (hub_env_missing)")
            }

            if preferRemote {
                let remote = await HubPairingCoordinator.shared.requestRemoteWebFetch(
                    options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                    url: url,
                    timeoutSec: timeout,
                    maxBytes: maxBytes
                )
                if remote.ok {
                    let head = "ok=\(remote.ok) status=\(remote.status) truncated=\(remote.truncated) bytes=\(remote.bytes)\nfinal_url=\(remote.finalURL)\ncontent_type=\(remote.contentType)"
                    let body = remote.text.count > 50_000 ? String(remote.text.prefix(50_000)) + "\n[truncated]" : remote.text
                    let out = head + "\n\n" + body
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)
                }

                let reason = HubIPCClient.normalizedReasonCode(
                    remote.reasonCode ?? remote.errorMessage,
                    fallback: "remote_web_fetch_failed"
                ) ?? "remote_web_fetch_failed"
                if HubIPCClient.isBridgeGrantRequiredReason(reason) {
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "bridge_not_enabled (call need_network first)")
                }

                let summary = reason == "remote_web_fetch_failed"
                    ? "remote_web_fetch_failed"
                    : "remote_web_fetch_failed (\(reason))"
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: summary)
            }

            if mode == .grpc {
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "remote_web_fetch_failed (grpc_route_unavailable)")
            }

            let st = HubBridgeClient.status()
            if !st.enabled {
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: "bridge_not_enabled (call need_network first)")
            }
            let res = try HubWebFetchClient.fetch(url: url, timeoutSec: timeout, maxBytes: maxBytes)
            let head = "ok=\(res.ok) status=\(res.status) truncated=\(res.truncated) bytes=\(res.bytes)\nfinal_url=\(res.finalURL)\ncontent_type=\(res.contentType)"
            let body = res.text.count > 50_000 ? String(res.text.prefix(50_000)) + "\n[truncated]" : res.text
            let out = head + "\n\n" + body
            return ToolResult(id: call.id, tool: call.tool, ok: res.ok, output: out)
        }
    }

    private static func strArg(_ call: ToolCall, _ key: String) -> String {
        if case .string(let s)? = call.args[key] { return s }
        // Some models may emit numbers/bools; coerce.
        if let v = call.args[key] {
            switch v {
            case .number(let n): return String(n)
            case .bool(let b): return b ? "true" : "false"
            case .null: return ""
            case .string(let s): return s
            case .array(_), .object(_): break
            }
        }
        return ""
    }

    private static func optStrArg(_ call: ToolCall, _ key: String) -> String? {
        let s = strArg(call, key).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func optBoolArg(_ call: ToolCall, _ key: String) -> Bool? {
        if case .bool(let b)? = call.args[key] { return b }
        if case .string(let s)? = call.args[key] {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "true" { return true }
            if t == "false" { return false }
        }
        return nil
    }

    private static func optDoubleArg(_ call: ToolCall, _ key: String) -> Double? {
        if case .number(let n)? = call.args[key] { return n }
        if case .string(let s)? = call.args[key] {
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func requiresTTY(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|&;()<>"))
        var cleaned = ""
        for scalar in trimmed.lowercased().unicodeScalars {
            if separators.contains(scalar) {
                cleaned.append(" ")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }

        let rawTokens = cleaned.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        let tokens = rawTokens.map { tok in
            tok.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        }.filter { !$0.isEmpty }

        if tokens.isEmpty { return false }

        let interactiveBins: Set<String> = [
            "vim", "vi", "nano", "emacs",
            "less", "more",
            "top", "htop", "watch",
            "ssh", "sftp", "scp", "ftp", "telnet",
        ]

        func baseName(_ t: String) -> String {
            if let last = t.split(separator: "/").last {
                return String(last)
            }
            return t
        }

        for t in tokens {
            let b = baseName(t)
            if interactiveBins.contains(b) {
                return true
            }
        }

        // Common git flows that spawn an editor / pager.
        if let first = tokens.first, baseName(first) == "git" {
            if tokens.contains("commit") {
                let hasMsg = tokens.contains("-m") || tokens.contains("--message") || tokens.contains("-F") || tokens.contains("--file")
                if !hasMsg { return true }
            }
            if tokens.contains("rebase") && tokens.contains("-i") { return true }
        }

        // Explicit interactive shells.
        if tokens.contains("-i") || tokens.contains("--interactive") {
            for t in tokens {
                let b = baseName(t)
                if b == "bash" || b == "zsh" || b == "sh" || b == "python" || b == "node" {
                    return true
                }
            }
        }

        return false
    }
}
