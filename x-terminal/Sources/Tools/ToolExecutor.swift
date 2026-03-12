import Foundation

enum ToolSandboxMode: String, CaseIterable {
    case host
    case sandbox
}

enum ToolExecutor {
    private static let sandboxModeDefaultsKey = "xterminal_tool_sandbox_mode"
    private static let legacySandboxModeDefaultsKey = "xterminal_tool_sandbox_mode"
    private static let highRiskGrantLedger = HighRiskGrantLedger()
    private static let uiObservationProofLedger = UIObservationProofLedger()
    private static let uiObservationProofTTLSeconds: TimeInterval = 180

    struct HighRiskGrantBypassFinding: Identifiable, Equatable {
        var id: String
        var createdAt: TimeInterval
        var action: String
        var detail: String
    }

    struct HighRiskGrantBypassScanReport: Equatable {
        var generatedAt: TimeInterval
        var scannedToolEvents: Int
        var webFetchEvents: Int
        var deniedEvents: Int
        var bypassCount: Int
        var findings: [HighRiskGrantBypassFinding]

        var ok: Bool { bypassCount == 0 }
    }

    struct HighRiskGrantSelfCheck: Equatable {
        var name: String
        var ok: Bool
        var detail: String
    }

    private enum HighRiskCapability: String {
        case webFetch = "CAPABILITY_WEB_FETCH"
    }

    private enum HighRiskGrantRejectCode: String {
        case missing = "high_risk_grant_missing"
        case invalid = "high_risk_grant_invalid"
        case expired = "high_risk_grant_expired"
        case bridgeDisabled = "high_risk_bridge_disabled"
    }

    private struct HighRiskGrantGateDecision {
        var ok: Bool
        var grantId: String?
        var rejectCode: HighRiskGrantRejectCode?
        var detail: String
    }

    private struct HighRiskMemoryRecheckDecision {
        var required: Bool
        var ok: Bool
        var useMode: XTMemoryUseMode
        var source: String
        var freshness: String
        var cacheHit: Bool
        var denyCode: String?
        var reasonCode: String?
        var detail: String
    }

    private struct SearchResultItem: Equatable {
        var title: String
        var url: String
        var snippet: String
    }

    private struct UIObservationProof: Equatable {
        var selectorSignature: String
        var observedAt: TimeInterval
        var matchCount: Int
    }

    private actor UIObservationProofLedger {
        private var proofsByProject: [String: [String: UIObservationProof]] = [:]

        func record(projectRoot: URL, proof: UIObservationProof) {
            let key = projectRoot.standardizedFileURL.path
            var bucket = proofsByProject[key] ?? [:]
            bucket[proof.selectorSignature] = proof
            proofsByProject[key] = bucket
        }

        func latest(projectRoot: URL, selectorSignature: String) -> UIObservationProof? {
            let key = projectRoot.standardizedFileURL.path
            return proofsByProject[key]?[selectorSignature]
        }
    }

    static func sandboxMode() -> ToolSandboxMode {
        let d = UserDefaults.standard
        let raw = (d.string(forKey: sandboxModeDefaultsKey) ?? d.string(forKey: legacySandboxModeDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let mode = ToolSandboxMode(rawValue: raw) {
            return mode
        }
        return .host
    }

    static func setSandboxMode(_ mode: ToolSandboxMode) {
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: sandboxModeDefaultsKey)
        d.set(mode.rawValue, forKey: legacySandboxModeDefaultsKey)
    }

    static func parseSandboxModeToken(_ token: String) -> ToolSandboxMode? {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "host", "local", "default":
            return .host
        case "sandbox", "isolated", "safe":
            return .sandbox
        default:
            return nil
        }
    }

    static func execute(call: ToolCall, projectRoot: URL, stream: (@MainActor @Sendable (String) -> Void)? = nil) async throws -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        if !isDeviceAutomationTool(call.tool) {
            let runtimePolicyDecision = xtToolRuntimePolicyDecision(call: call, config: config)
            if !runtimePolicyDecision.allowed {
                return deniedRuntimePolicyResult(
                    call: call,
                    projectRoot: projectRoot,
                    config: config,
                    decision: runtimePolicyDecision
                )
            }
        }
        if let precheckDenied = await deniedHighRiskMemoryRecheckResultIfNeeded(
            call: call,
            projectRoot: projectRoot,
            config: config
        ) {
            return precheckDenied
        }

        switch call.tool {
        case .read_file:
            let path = strArg(call, "path")
            let useSandbox = shouldUseSandbox(call)
            if useSandbox {
                let sandboxManager = await MainActor.run { SandboxManager.shared }
                let sandbox = try await sandboxManager.createSandbox(forProjectRoot: projectRoot)
                let s = try await sandbox.readFile(path: path)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "sandbox: true\n" + s)
            }
            let s = try FileTool.readText(path: path, projectRoot: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: s)

        case .write_file:
            let path = strArg(call, "path")
            let content = strArg(call, "content")
            let useSandbox = shouldUseSandbox(call)
            if useSandbox {
                let sandboxManager = await MainActor.run { SandboxManager.shared }
                let sandbox = try await sandboxManager.createSandbox(forProjectRoot: projectRoot)
                try await sandbox.writeFile(path: path, content: content)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "sandbox: true\nok")
            }
            try FileTool.writeText(path: path, content: content, projectRoot: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")

        case .list_dir:
            let path = strArg(call, "path")
            let useSandbox = shouldUseSandbox(call)
            if useSandbox {
                let sandboxManager = await MainActor.run { SandboxManager.shared }
                let sandbox = try await sandboxManager.createSandbox(forProjectRoot: projectRoot)
                let items = try await sandbox.listFiles(path: path)
                let output = items.map { $0.path }.joined(separator: "\n")
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: "sandbox: true\n" + (output.isEmpty ? "(empty)" : output)
                )
            }
            let items = try FileTool.listDir(path: path, projectRoot: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: items.joined(separator: "\n"))

        case .search:
            let pattern = strArg(call, "pattern")
            let glob = optStrArg(call, "glob")
            let useSandbox = shouldUseSandbox(call)
            if useSandbox {
                let sandboxManager = await MainActor.run { SandboxManager.shared }
                let sandbox = try await sandboxManager.createSandbox(forProjectRoot: projectRoot)
                let lines = try await searchInSandbox(
                    pattern: pattern,
                    glob: glob,
                    sandbox: sandbox,
                    maxResults: 200
                )
                let out = lines.isEmpty ? "(no matches)" : lines.joined(separator: "\n")
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: "sandbox: true\n" + out
                )
            }
            let lines = try FileTool.search(pattern: pattern, projectRoot: projectRoot, glob: glob)
            let out = lines.isEmpty ? "(no matches)" : lines.joined(separator: "\n")
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)

        case .run_command:
            let cmd = strArg(call, "command")
            let timeout = optDoubleArg(call, "timeout_sec") ?? 60.0
            let useSandbox = shouldUseSandbox(call)
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

            if useSandbox {
                let sandboxManager = await MainActor.run { SandboxManager.shared }
                let sandbox = try await sandboxManager.createSandbox(forProjectRoot: projectRoot)
                let res = try await sandbox.execute(command: cmd, timeout: timeout)
                let combined = [res.stdout, res.stderr]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let out = "sandbox: true\nexit: \(res.exitCode)\n" + (combined.isEmpty ? "(no output)" : combined)
                return ToolResult(id: call.id, tool: call.tool, ok: res.exitCode == 0, output: out)
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

        case .session_list:
            return await executeSessionList(call: call, projectRoot: projectRoot)

        case .session_resume:
            return await executeSessionResume(call: call, projectRoot: projectRoot)

        case .session_compact:
            return await executeSessionCompact(call: call, projectRoot: projectRoot)

        case .memory_snapshot:
            return await executeMemorySnapshot(call: call, projectRoot: projectRoot)

        case .project_snapshot:
            return await executeProjectSnapshot(call: call, projectRoot: projectRoot)

        case .deviceUIObserve:
            return await executeDeviceUIObserve(call: call, projectRoot: projectRoot)

        case .deviceUIAct:
            return await executeDeviceUIAct(call: call, projectRoot: projectRoot)

        case .deviceUIStep:
            return await executeDeviceUIStep(call: call, projectRoot: projectRoot)

        case .deviceClipboardRead:
            return await executeDeviceClipboardRead(call: call, projectRoot: projectRoot)

        case .deviceClipboardWrite:
            return await executeDeviceClipboardWrite(call: call, projectRoot: projectRoot)

        case .deviceScreenCapture:
            return await executeDeviceScreenCapture(call: call, projectRoot: projectRoot)

        case .deviceBrowserControl:
            return await executeDeviceBrowserControl(call: call, projectRoot: projectRoot)

        case .deviceAppleScript:
            return await executeDeviceAppleScript(call: call, projectRoot: projectRoot)

        case .bridge_status:
            let st = HubBridgeClient.status()
            let out = "alive=\(st.alive) enabled=\(st.enabled) enabledUntil=\(st.enabledUntil)"
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)

        case .need_network:
            let seconds = max(60, Int(optDoubleArg(call, "seconds") ?? 900))
            let reason = optStrArg(call, "reason")
            let reasonText = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = reasonText.isEmpty ? "" : " reason=\(reasonText)"
            let access = await HubIPCClient.requestNetworkAccess(root: projectRoot, seconds: seconds, reason: reason)
            let route = access.source.lowercased()
            var activeGrantId: String?
            switch access.state {
            case .enabled, .autoApproved:
                activeGrantId = await noteActiveHighRiskGrant(
                    projectRoot: projectRoot,
                    capability: .webFetch,
                    grantRequestId: access.grantRequestId,
                    fallbackSeconds: access.remainingSeconds ?? seconds
                )
            case .queued, .denied, .failed:
                activeGrantId = nil
            }

            switch access.state {
            case .enabled:
                let rem = max(0, access.remainingSeconds ?? 0)
                let grantSuffix = activeGrantId.map { " (grant=\($0))" } ?? ""
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: "network_already_enabled (remaining=\(rem)s)\(grantSuffix)"
                )

            case .autoApproved:
                let grantSuffix = activeGrantId.map { " (grant=\($0))" } ?? ""
                if let rem = access.remainingSeconds, rem > 0 {
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: "network_auto_approved_and_enabled (remaining=\(rem)s)\(grantSuffix)"
                    )
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
            let grantDecision = await gateHighRiskWebFetch(call: call, projectRoot: projectRoot)
            if !grantDecision.ok {
                let reject = grantDecision.rejectCode ?? .invalid
                let denied = "high_risk_denied (code=\(reject.rawValue), capability=\(HighRiskCapability.webFetch.rawValue.lowercased())) - \(grantDecision.detail)"
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: denied)
            }
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
                    let head = """
ok=\(remote.ok) status=\(remote.status) truncated=\(remote.truncated) bytes=\(remote.bytes)
grant_id=\(grantDecision.grantId ?? "")
final_url=\(remote.finalURL)
content_type=\(remote.contentType)
"""
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
                if let ingressHint = connectorIngressDenyHint(reason) {
                    let out = "remote_web_fetch_failed (\(reason)) - \(ingressHint)"
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: out)
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
            let head = """
ok=\(res.ok) status=\(res.status) truncated=\(res.truncated) bytes=\(res.bytes)
grant_id=\(grantDecision.grantId ?? "")
final_url=\(res.finalURL)
content_type=\(res.contentType)
"""
            let body = res.text.count > 50_000 ? String(res.text.prefix(50_000)) + "\n[truncated]" : res.text
            let out = head + "\n\n" + body
            return ToolResult(id: call.id, tool: call.tool, ok: res.ok, output: out)

        case .web_search:
            return try await executeWebSearch(call: call, projectRoot: projectRoot)

        case .browser_read:
            return try await executeBrowserRead(call: call, projectRoot: projectRoot)
        }
    }


    @MainActor
    private static func resolveSessionTarget(sessionId: String?, projectId: String?, projectRoot: URL) -> AXSessionInfo? {
        let manager = AXSessionManager.shared
        let currentProjectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let requestedProjectId = projectId ?? currentProjectId

        if let sessionId,
           let session = manager.session(for: sessionId) {
            return session
        }

        if let activeId = manager.activeSessionId,
           let active = manager.session(for: activeId),
           active.projectId == requestedProjectId {
            return active
        }

        if let primary = manager.primarySession(for: requestedProjectId) {
            return primary
        }

        guard requestedProjectId == currentProjectId else {
            return nil
        }

        return manager.ensurePrimarySession(
            projectId: currentProjectId,
            title: projectRoot.lastPathComponent,
            directory: projectRoot.standardizedFileURL.path
        )
    }

    private static func executeSessionList(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let currentProjectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let requestedProjectId = optStrArg(call, "project_id") ?? currentProjectId
        let limit = max(1, min(50, Int(optDoubleArg(call, "limit") ?? 12)))
        let includeAllProjects = optBoolArg(call, "all_projects") ?? false

        let snapshot = await MainActor.run { () -> (String?, [AXSessionInfo]) in
            let manager = AXSessionManager.shared
            let filtered = includeAllProjects
                ? manager.sessions
                : manager.sessions.filter { $0.projectId == requestedProjectId }
            let sorted = filtered.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            return (manager.activeSessionId, Array(sorted.prefix(limit)))
        }

        let rows = snapshot.1.map { session -> JSONValue in
            .object([
                "id": .string(session.id),
                "project_id": .string(session.projectId),
                "title": .string(session.title),
                "directory": .string(session.directory),
                "parent_id": session.parentId.map(JSONValue.string) ?? .null,
                "updated_at": .number(session.updatedAt),
                "runtime_state": .string(session.runtime?.state.rawValue ?? AXSessionRuntimeState.idle.rawValue),
                "pending_tool_call_count": .number(Double(session.runtime?.pendingToolCallCount ?? 0)),
                "recoverable": .bool(session.runtime?.recoverable ?? false),
                "is_active": .bool(snapshot.0 == session.id),
            ])
        }

        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "project_id": .string(requestedProjectId),
            "active_session_id": snapshot.0.map(JSONValue.string) ?? .null,
            "session_count": .number(Double(snapshot.1.count)),
            "sessions": .array(rows),
        ]
        let body = snapshot.1.isEmpty
            ? "(no sessions)"
            : snapshot.1.map { session in
                let state = session.runtime?.state.rawValue ?? AXSessionRuntimeState.idle.rawValue
                let pending = session.runtime?.pendingToolCallCount ?? 0
                let active = snapshot.0 == session.id ? " active" : ""
                return "- \(session.id) | \(session.title) | state=\(state) pending=\(pending)\(active)"
            }.joined(separator: "\n")
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeSessionResume(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let pendingApproval = AXPendingActionsStore.pendingToolApproval(for: ctx)
        let requestedSessionId = optStrArg(call, "session_id")
        let requestedProjectId = optStrArg(call, "project_id")
        let currentProjectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let hasPendingApproval = pendingApproval?.status == "pending"
        let pendingApprovalCount = pendingApproval?.toolCalls?.count ?? 0
        let now = Date().timeIntervalSince1970

        let outcome = await MainActor.run { () -> (AXSessionInfo?, String?) in
            guard let target = resolveSessionTarget(sessionId: requestedSessionId, projectId: requestedProjectId, projectRoot: projectRoot) else {
                return (nil, nil)
            }

            let manager = AXSessionManager.shared
            manager.activeSessionId = target.id
            let beforeState = target.runtime?.state.rawValue ?? AXSessionRuntimeState.idle.rawValue
            let shouldRestorePending = target.projectId == currentProjectId && hasPendingApproval
            let restoredPendingCount = shouldRestorePending ? pendingApprovalCount : 0
            let updated = manager.updateRuntime(sessionId: target.id, at: now) { runtime in
                runtime.runID = runtime.runID ?? UUID().uuidString
                runtime.startedAt = runtime.startedAt ?? now
                runtime.completedAt = nil
                runtime.lastFailureCode = nil
                if shouldRestorePending {
                    runtime.state = .awaiting_tool_approval
                    runtime.pendingToolCallCount = restoredPendingCount
                    runtime.resumeToken = runtime.resumeToken ?? "tool_approval:\(runtime.runID ?? target.id)"
                    runtime.recoverable = true
                    runtime.lastRuntimeSummary = "session resumed with pending tool approval"
                } else {
                    runtime.state = .planning
                    runtime.pendingToolCallCount = 0
                    runtime.resumeToken = runtime.runID
                    runtime.recoverable = false
                    runtime.lastRuntimeSummary = "session resumed"
                }
            }
            return (updated ?? target, beforeState)
        }

        guard let updated = outcome.0 else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string("session_not_found"),
            ]
            return ToolResult(id: call.id, tool: call.tool, ok: false, output: structuredOutput(summary: summary, body: "session_not_found"))
        }

        let runtime = updated.runtime ?? .idle(at: now)
        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(true),
            "session_id": .string(updated.id),
            "project_id": .string(updated.projectId),
            "state_before": outcome.1.map(JSONValue.string) ?? .null,
            "state_after": .string(runtime.state.rawValue),
            "pending_tool_call_count": .number(Double(runtime.pendingToolCallCount)),
            "resume_token": runtime.resumeToken.map(JSONValue.string) ?? .null,
            "recoverable": .bool(runtime.recoverable),
        ]
        let body = "session_resume -> \(updated.id) state=\(runtime.state.rawValue) pending=\(runtime.pendingToolCallCount)"
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeSessionCompact(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let requestedSessionId = optStrArg(call, "session_id")
        let requestedProjectId = optStrArg(call, "project_id")
        guard let target = await resolveSessionTarget(sessionId: requestedSessionId, projectId: requestedProjectId, projectRoot: projectRoot) else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string("session_not_found"),
            ]
            return ToolResult(id: call.id, tool: call.tool, ok: false, output: structuredOutput(summary: summary, body: "session_not_found"))
        }

        let manager = await MainActor.run { AXSessionManager.shared }
        await manager.compactSession(target.id)
        let updated = await manager.session(for: target.id) ?? target
        let summaryInfo = updated.summary
        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(true),
            "session_id": .string(updated.id),
            "project_id": .string(updated.projectId),
            "runtime_state": .string(updated.runtime?.state.rawValue ?? AXSessionRuntimeState.idle.rawValue),
            "summary": .object([
                "files": .number(Double(summaryInfo?.files ?? 0)),
                "additions": .number(Double(summaryInfo?.additions ?? 0)),
                "deletions": .number(Double(summaryInfo?.deletions ?? 0)),
            ]),
        ]
        let body = "session_compact -> \(updated.id) files=\(summaryInfo?.files ?? 0) additions=\(summaryInfo?.additions ?? 0) deletions=\(summaryInfo?.deletions ?? 0)"
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeMemorySnapshot(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let projectId = optStrArg(call, "project_id") ?? AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let modeToken = optStrArg(call, "mode") ?? XTMemoryUseMode.projectChat.rawValue
        guard let useMode = XTMemoryUseMode.parse(modeToken) else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "project_id": .string(projectId),
                "mode": .string(modeToken),
                "deny_code": .string(XTMemoryUseDenyCode.memoryModeContractMissing.rawValue),
                "reason": .string(XTMemoryUseDenyCode.memoryModeContractMissing.rawValue),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: XTMemoryUseDenyCode.memoryModeContractMissing.rawValue)
            )
        }
        let response = await HubIPCClient.requestMemoryContext(
            useMode: useMode,
            requesterRole: .tool,
            projectId: projectId,
            projectRoot: projectRoot.standardizedFileURL.path,
            displayName: projectRoot.lastPathComponent,
            latestUser: "(memory_snapshot_tool)",
            constitutionHint: nil,
            canonicalText: nil,
            observationsText: nil,
            workingSetText: nil,
            rawEvidenceText: nil,
            budgets: nil,
            timeoutSec: 2.0
        )

        guard let response else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "project_id": .string(projectId),
                "mode": .string(useMode.rawValue),
                "reason": .string("hub_memory_snapshot_unavailable"),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "hub_memory_snapshot_unavailable")
            )
        }

        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: true,
            output: renderMemorySnapshotOutput(response: response, projectId: projectId, mode: useMode.rawValue)
        )
    }

    static func renderMemorySnapshotOutput(
        response: HubIPCClient.MemoryContextResponsePayload,
        projectId: String,
        mode: String
    ) -> String {
        let layerUsage = response.layerUsage.map { layer -> JSONValue in
            .object([
                "layer": .string(layer.layer),
                "used_tokens": .number(Double(layer.usedTokens)),
                "budget_tokens": .number(Double(layer.budgetTokens)),
            ])
        }
        let summary: [String: JSONValue] = [
            "tool": .string(ToolName.memory_snapshot.rawValue),
            "ok": .bool(true),
            "project_id": .string(projectId),
            "mode": .string(mode),
            "source": .string(response.source),
            "resolved_mode": response.resolvedMode.map(JSONValue.string) ?? .null,
            "freshness": response.freshness.map(JSONValue.string) ?? .null,
            "cache_hit": response.cacheHit.map(JSONValue.bool) ?? .null,
            "deny_code": response.denyCode.map(JSONValue.string) ?? .null,
            "downgrade_code": response.downgradeCode.map(JSONValue.string) ?? .null,
            "budget_total_tokens": .number(Double(response.budgetTotalTokens)),
            "used_total_tokens": .number(Double(response.usedTotalTokens)),
            "truncated_layers": .array(response.truncatedLayers.map(JSONValue.string)),
            "redacted_items": .number(Double(response.redactedItems)),
            "private_drops": .number(Double(response.privateDrops)),
            "layer_usage": .array(layerUsage),
        ]
        let body = response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(empty memory snapshot)" : response.text
        return structuredOutput(summary: summary, body: body)
    }

    private static func executeProjectSnapshot(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let ctx = AXProjectContext(root: projectRoot)
        let registry = AXProjectRegistryStore.load()
        let entry = registry.project(for: projectId)
        let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
        let resolvedConfig = config ?? .default(forProjectRoot: projectRoot)
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: resolvedConfig
        )
        let effectiveAutonomy = autonomyState.effectivePolicy
        let configuredAutonomySurfaces = resolvedConfig.configuredAutonomySurfaceLabels
        let effectiveTools = ToolPolicy.sortedTools(
            ToolPolicy.effectiveAllowedTools(
                profileRaw: resolvedConfig.toolProfile,
                allowTokens: resolvedConfig.toolAllow,
                denyTokens: resolvedConfig.toolDeny
            )
        ).map { $0.rawValue }
        let session = await MainActor.run { () -> AXSessionInfo? in
            let manager = AXSessionManager.shared
            if let activeId = manager.activeSessionId,
               let active = manager.session(for: activeId),
               active.projectId == projectId {
                return active
            }
            return manager.primarySession(for: projectId)
        }
        let isGitRepo = GitTool.isGitRepo(root: projectRoot)
        let gitStatus = isGitRepo ? (try? GitTool.status(root: projectRoot)) : nil
        let gitSummary = gitStatus?.combined.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modelOverrides: [String: JSONValue] = Dictionary(uniqueKeysWithValues: AXRole.allCases.compactMap { role in
            guard let value = config?.modelOverride(for: role), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (role.rawValue, .string(value))
        })
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let trustedAutomationStatus = (config ?? .default(forProjectRoot: projectRoot))
            .trustedAutomationStatus(forProjectRoot: projectRoot, permissionReadiness: permissionReadiness)
        let trustedRequiredPermissions = AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(
            forDeviceToolGroups: trustedAutomationStatus.deviceToolGroups
        )
        let trustedOpenSettingsActions = permissionReadiness.suggestedOpenSettingsActions(
            forDeviceToolGroups: trustedAutomationStatus.deviceToolGroups
        )
        let trustedPermissionStatuses: [String: JSONValue] = Dictionary(
            uniqueKeysWithValues: AXTrustedAutomationPermissionKey.allCases.map { key in
                (key.rawValue, .string(permissionReadiness.permissionStatus(for: key).rawValue))
            }
        )
        let autonomyPolicyObject: JSONValue = .object([
            "configured_mode": .string(resolvedConfig.autonomyMode.rawValue),
            "effective_mode": .string(effectiveAutonomy.effectiveMode.rawValue),
            "hub_override_mode": .string(effectiveAutonomy.hubOverrideMode.rawValue),
            "local_override_mode": .string(effectiveAutonomy.localOverrideMode.rawValue),
            "remote_override_mode": .string(effectiveAutonomy.remoteOverrideMode.rawValue),
            "remote_override_source": .string(effectiveAutonomy.remoteOverrideSource),
            "remote_override_updated_at_ms": .number(Double(effectiveAutonomy.remoteOverrideUpdatedAtMs)),
            "ttl_sec": .number(Double(resolvedConfig.autonomyTTLSeconds)),
            "remaining_sec": .number(Double(effectiveAutonomy.remainingSeconds)),
            "expired": .bool(effectiveAutonomy.expired),
            "kill_switch_engaged": .bool(effectiveAutonomy.killSwitchEngaged),
            "configured_surfaces": .array(configuredAutonomySurfaces.map(JSONValue.string)),
            "effective_surfaces": .array(effectiveAutonomy.allowedSurfaceLabels.map(JSONValue.string)),
            "updated_at_ms": .number(Double(resolvedConfig.autonomyUpdatedAtMs)),
        ])
        let browserRuntimeSession = XTBrowserRuntimeStore.loadSession(for: ctx)
        let browserRuntimeObject: JSONValue = {
            guard let browserRuntimeSession else { return .null }
            return .object([
                "session_id": .string(browserRuntimeSession.sessionID),
                "profile_id": .string(browserRuntimeSession.profileID),
                "profile_path": .string(XTBrowserRuntimeStore.managedProfilePath(for: ctx, session: browserRuntimeSession)),
                "snapshot_ref": .string(browserRuntimeSession.snapshotRef),
                "action_mode": .string(browserRuntimeSession.actionMode.rawValue),
                "transport": .string(browserRuntimeSession.transport),
                "browser_engine": .string(browserRuntimeSession.browserEngine),
                "current_url": .string(browserRuntimeSession.currentURL),
                "open_tabs": .number(Double(browserRuntimeSession.openTabs)),
                "grant_policy_ref": .string(browserRuntimeSession.grantPolicyRef),
                "audit_ref": .string(browserRuntimeSession.auditRef),
            ])
        }()

        let sessionIDValue: JSONValue = {
            guard let session else { return .null }
            return .string(session.id)
        }()
        let sessionTitleValue: JSONValue = {
            guard let session else { return .null }
            return .string(session.title)
        }()
        let sessionSummary: [String: JSONValue] = [
            "id": sessionIDValue,
            "title": sessionTitleValue,
            "runtime_state": .string(session?.runtime?.state.rawValue ?? AXSessionRuntimeState.idle.rawValue),
            "pending_tool_call_count": .number(Double(session?.runtime?.pendingToolCallCount ?? 0)),
        ]
        var summary: [String: JSONValue] = [:]
        summary["tool"] = .string(call.tool.rawValue)
        summary["ok"] = .bool(true)
        summary["project_id"] = .string(projectId)
        summary["display_name"] = .string(entry?.displayName ?? projectRoot.lastPathComponent)
        summary["root"] = .string(projectRoot.standardizedFileURL.path)
        summary["status_digest"] = entry?.statusDigest.map(JSONValue.string) ?? .null
        summary["current_state_summary"] = entry?.currentStateSummary.map(JSONValue.string) ?? .null
        summary["next_step_summary"] = entry?.nextStepSummary.map(JSONValue.string) ?? .null
        summary["blocker_summary"] = entry?.blockerSummary.map(JSONValue.string) ?? .null
        summary["verify_commands"] = .array((config?.verifyCommands ?? []).map(JSONValue.string))
        summary["tool_profile"] = .string(config?.toolProfile ?? ToolPolicy.defaultProfile.rawValue)
        summary["effective_tools"] = .array(effectiveTools.map(JSONValue.string))
        summary["model_overrides"] = .object(modelOverrides)
        summary["trusted_automation_mode"] = .string(trustedAutomationStatus.mode.rawValue)
        summary["trusted_automation_state"] = .string(trustedAutomationStatus.state.rawValue)
        summary["trusted_automation_device_id"] = .string(trustedAutomationStatus.boundDeviceID)
        summary["trusted_automation_workspace_binding_hash"] = .string(trustedAutomationStatus.workspaceBindingHash)
        summary["trusted_automation_expected_workspace_binding_hash"] = .string(trustedAutomationStatus.expectedWorkspaceBindingHash)
        summary["trusted_automation_ready"] = .bool(trustedAutomationStatus.trustedAutomationReady)
        summary["trusted_automation_permission_owner_ready"] = .bool(trustedAutomationStatus.permissionOwnerReady)
        summary["trusted_automation_device_tool_groups"] = .array(trustedAutomationStatus.deviceToolGroups.map(JSONValue.string))
        summary["trusted_automation_required_permissions"] = .array(trustedRequiredPermissions.map(JSONValue.string))
        summary["trusted_automation_permission_statuses"] = .object(trustedPermissionStatuses)
        summary["trusted_automation_open_settings_actions"] = .array(trustedOpenSettingsActions.map(JSONValue.string))
        summary["trusted_automation_missing_prerequisites"] = .array(trustedAutomationStatus.missingPrerequisites.map(JSONValue.string))
        summary["autonomy_policy"] = autonomyPolicyObject
        summary["browser_runtime"] = browserRuntimeObject
        summary["is_git_repo"] = .bool(isGitRepo)
        summary["git_dirty"] = .bool(isGitRepo && !gitSummary.isEmpty)
        summary["session"] = .object(sessionSummary)

        let verifyText = resolvedConfig.verifyCommands.isEmpty ? "(none)" : resolvedConfig.verifyCommands.joined(separator: " | ")
        let browserRuntimeText: String = {
            guard let browserRuntimeSession else { return "(none)" }
            let currentURL = browserRuntimeSession.currentURL.isEmpty ? "(none)" : browserRuntimeSession.currentURL
            let snapshotRef = browserRuntimeSession.snapshotRef.isEmpty ? "(none)" : browserRuntimeSession.snapshotRef
            return "session=\(browserRuntimeSession.sessionID) mode=\(browserRuntimeSession.actionMode.rawValue) url=\(currentURL) snapshot=\(snapshotRef)"
        }()
        let configuredAutonomySurfaceText = configuredAutonomySurfaces.isEmpty ? "(none)" : configuredAutonomySurfaces.joined(separator: ",")
        let effectiveAutonomySurfaceText = effectiveAutonomy.allowedSurfaceLabels.isEmpty ? "(none)" : effectiveAutonomy.allowedSurfaceLabels.joined(separator: ",")
        let autonomyRemainingText: String = {
            if effectiveAutonomy.killSwitchEngaged {
                return "kill_switch"
            }
            if effectiveAutonomy.expired {
                return "expired"
            }
            if resolvedConfig.autonomyMode == .manual {
                return "n/a"
            }
            return String(effectiveAutonomy.remainingSeconds)
        }()
        let body = """
project=\(entry?.displayName ?? projectRoot.lastPathComponent)
root=\(projectRoot.standardizedFileURL.path)
status_digest=\(entry?.statusDigest ?? "(none)")
verify_commands=\(verifyText)
tool_profile=\(resolvedConfig.toolProfile)
effective_tools=\(effectiveTools.isEmpty ? "(none)" : effectiveTools.joined(separator: ", "))
trusted_automation_mode=\(trustedAutomationStatus.mode.rawValue)
trusted_automation_state=\(trustedAutomationStatus.state.rawValue)
trusted_automation_device_id=\(trustedAutomationStatus.boundDeviceID.isEmpty ? "(none)" : trustedAutomationStatus.boundDeviceID)
trusted_automation_required_permissions=\(trustedRequiredPermissions.isEmpty ? "(none)" : trustedRequiredPermissions.joined(separator: ","))
trusted_automation_open_settings_actions=\(trustedOpenSettingsActions.isEmpty ? "(none)" : trustedOpenSettingsActions.joined(separator: ","))
trusted_automation_missing=\(trustedAutomationStatus.missingPrerequisites.isEmpty ? "(none)" : trustedAutomationStatus.missingPrerequisites.joined(separator: ","))
autonomy_mode=\(resolvedConfig.autonomyMode.rawValue)
autonomy_effective_mode=\(effectiveAutonomy.effectiveMode.rawValue)
autonomy_hub_override_mode=\(effectiveAutonomy.hubOverrideMode.rawValue)
autonomy_local_override_mode=\(effectiveAutonomy.localOverrideMode.rawValue)
autonomy_remote_override_mode=\(effectiveAutonomy.remoteOverrideMode.rawValue)
autonomy_remote_override_source=\(effectiveAutonomy.remoteOverrideSource.isEmpty ? "(none)" : effectiveAutonomy.remoteOverrideSource)
autonomy_remote_override_updated_at_ms=\(effectiveAutonomy.remoteOverrideUpdatedAtMs)
autonomy_configured_surfaces=\(configuredAutonomySurfaceText)
autonomy_effective_surfaces=\(effectiveAutonomySurfaceText)
autonomy_ttl_remaining=\(autonomyRemainingText)
browser_runtime=\(browserRuntimeText)
session_state=\(session?.runtime?.state.rawValue ?? AXSessionRuntimeState.idle.rawValue)
git=\(isGitRepo ? (gitSummary.isEmpty ? "clean" : gitSummary) : "not_git_repo")
"""
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeDeviceClipboardRead(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let decision = DeviceAutomationTools.evaluateGate(
            for: call.tool,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard decision.allowed else {
            return deniedDeviceAutomationResult(call: call, projectRoot: projectRoot, decision: decision)
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        let text = await MainActor.run {
            DeviceAutomationTools.readClipboardText()
        }
        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: true
        )
        summary["text_present"] = .bool(!text.isEmpty)
        summary["character_count"] = .number(Double(text.count))
        let body = text.isEmpty ? "(empty clipboard)" : text
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeDeviceUIObserve(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let decision = DeviceAutomationTools.evaluateGate(
            for: call.tool,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard decision.allowed else {
            return deniedDeviceAutomationResult(call: call, projectRoot: projectRoot, decision: decision)
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        let observationRequest = XTDeviceUIObservationRequest(
            selector: XTDeviceUISelector(
                role: normalizedToolTextArg(call, "target_role"),
                title: normalizedToolTextArg(call, "target_title"),
                identifier: normalizedToolTextArg(call, "target_identifier"),
                elementDescription: normalizedToolTextArg(call, "target_description"),
                valueContains: normalizedToolTextArg(call, "target_value_contains"),
                matchIndex: 0
            ),
            maxResults: min(20, max(1, Int(optDoubleArg(call, "max_results") ?? 5)))
        )

        guard let observation = await MainActor.run(resultType: XTDeviceUIObservationResult?.self, body: {
            DeviceAutomationTools.captureFrontmostUIObservation(observationRequest)
        }) else {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.uiObserveUnavailable.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "ui_observe_unavailable")
            )
        }
        let snapshot = observation.snapshot
        if !observationRequest.selector.isEmpty {
            await uiObservationProofLedger.record(
                projectRoot: projectRoot,
                proof: UIObservationProof(
                    selectorSignature: uiObservationSelectorSignature(observationRequest.selector),
                    observedAt: Date().timeIntervalSince1970,
                    matchCount: observation.matchedElements.count
                )
            )
        }

        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: true
        )
        summary["target_resolution_mode"] = .string(observationRequest.selector.isEmpty ? "focused" : "selector")
        summary["requested_max_results"] = .number(Double(observationRequest.maxResults))
        summary["match_count"] = .number(Double(observation.matchedElements.count))
        if !observationRequest.selector.role.isEmpty {
            summary["target_selector_role"] = .string(observationRequest.selector.role)
        }
        if !observationRequest.selector.title.isEmpty {
            summary["target_selector_title"] = .string(observationRequest.selector.title)
        }
        if !observationRequest.selector.identifier.isEmpty {
            summary["target_selector_identifier"] = .string(observationRequest.selector.identifier)
        }
        if !observationRequest.selector.elementDescription.isEmpty {
            summary["target_selector_description"] = .string(observationRequest.selector.elementDescription)
        }
        if !observationRequest.selector.valueContains.isEmpty {
            summary["target_selector_value_contains"] = .string(observationRequest.selector.valueContains)
        }
        summary["frontmost_app_name"] = .string(snapshot.frontmostAppName)
        summary["frontmost_app_bundle_id"] = .string(snapshot.frontmostBundleID)
        summary["frontmost_app_pid"] = .number(Double(snapshot.frontmostPID))
        summary["focused_window_title"] = .string(snapshot.focusedWindowTitle)
        summary["focused_window_role"] = .string(snapshot.focusedWindowRole)
        summary["focused_window_subrole"] = .string(snapshot.focusedWindowSubrole)
        if let element = snapshot.focusedElement {
            summary["focused_element_role"] = .string(element.role)
            summary["focused_element_subrole"] = .string(element.subrole)
            summary["focused_element_title"] = .string(element.title)
            summary["focused_element_description"] = .string(element.elementDescription)
            summary["focused_element_value_preview"] = .string(element.valuePreview)
            summary["focused_element_identifier"] = .string(element.identifier)
            summary["focused_element_help"] = .string(element.help)
            summary["focused_element_child_count"] = .number(Double(element.childCount))
        } else {
            summary["focused_element_role"] = .string("")
            summary["focused_element_subrole"] = .string("")
            summary["focused_element_title"] = .string("")
            summary["focused_element_description"] = .string("")
            summary["focused_element_value_preview"] = .string("")
            summary["focused_element_identifier"] = .string("")
            summary["focused_element_help"] = .string("")
            summary["focused_element_child_count"] = .number(0)
        }
        summary["matched_elements"] = .array(observation.matchedElements.map { element in
            .object([
                "role": .string(element.role),
                "subrole": .string(element.subrole),
                "title": .string(element.title),
                "description": .string(element.elementDescription),
                "value_preview": .string(element.valuePreview),
                "identifier": .string(element.identifier),
                "help": .string(element.help),
                "child_count": .number(Double(element.childCount)),
            ])
        })

        var bodyLines = [
            "app_name=\(snapshot.frontmostAppName.isEmpty ? "(unknown)" : snapshot.frontmostAppName)",
            "bundle_id=\(snapshot.frontmostBundleID.isEmpty ? "(unknown)" : snapshot.frontmostBundleID)",
            "pid=\(snapshot.frontmostPID)",
            "focused_window_title=\(snapshot.focusedWindowTitle.isEmpty ? "(none)" : snapshot.focusedWindowTitle)",
            "focused_window_role=\(snapshot.focusedWindowRole.isEmpty ? "(none)" : snapshot.focusedWindowRole)",
        ]
        if let element = snapshot.focusedElement {
            bodyLines.append("focused_element_role=\(element.role.isEmpty ? "(none)" : element.role)")
            bodyLines.append("focused_element_title=\(element.title.isEmpty ? "(none)" : element.title)")
            bodyLines.append("focused_element_description=\(element.elementDescription.isEmpty ? "(none)" : element.elementDescription)")
            bodyLines.append("focused_element_value=\(element.valuePreview.isEmpty ? "(none)" : element.valuePreview)")
            bodyLines.append("focused_element_identifier=\(element.identifier.isEmpty ? "(none)" : element.identifier)")
            bodyLines.append("focused_element_child_count=\(element.childCount)")
        } else {
            bodyLines.append("focused_element=(none)")
        }
        if observationRequest.selector.isEmpty {
            bodyLines.append("candidate_count=0")
        } else {
            bodyLines.append("candidate_count=\(observation.matchedElements.count)")
            if observation.matchedElements.isEmpty {
                bodyLines.append("candidate_matches=(none)")
            } else {
                for (index, candidate) in observation.matchedElements.enumerated() {
                    bodyLines.append("candidate[\(index)].role=\(candidate.role.isEmpty ? "(none)" : candidate.role)")
                    bodyLines.append("candidate[\(index)].title=\(candidate.title.isEmpty ? "(none)" : candidate.title)")
                    bodyLines.append("candidate[\(index)].identifier=\(candidate.identifier.isEmpty ? "(none)" : candidate.identifier)")
                    bodyLines.append("candidate[\(index)].description=\(candidate.elementDescription.isEmpty ? "(none)" : candidate.elementDescription)")
                    bodyLines.append("candidate[\(index)].value=\(candidate.valuePreview.isEmpty ? "(none)" : candidate.valuePreview)")
                }
            }
        }
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: true,
            output: structuredOutput(summary: summary, body: bodyLines.joined(separator: "\n"))
        )
    }

    private static func executeDeviceUIAct(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let decision = DeviceAutomationTools.evaluateGate(
            for: call.tool,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard decision.allowed else {
            return deniedDeviceAutomationResult(call: call, projectRoot: projectRoot, decision: decision)
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        let action = (optStrArg(call, "action") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedValue = [
            optStrArg(call, "value"),
            optStrArg(call, "text"),
            optStrArg(call, "content"),
        ]
        .compactMap { raw in
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        .first
        let selector = XTDeviceUISelector(
            role: normalizedToolTextArg(call, "target_role"),
            title: normalizedToolTextArg(call, "target_title"),
            identifier: normalizedToolTextArg(call, "target_identifier"),
            elementDescription: normalizedToolTextArg(call, "target_description"),
            valueContains: normalizedToolTextArg(call, "target_value_contains"),
            matchIndex: max(0, Int(optDoubleArg(call, "target_index") ?? 0))
        )
        let selectorRequiresObservationProof = !selector.isEmpty
        let targetIndexWasExplicit = call.args["target_index"] != nil
        let supported = Set(["press_focused", "press", "set_focused_value", "set_value", "type_text"])
        guard supported.contains(action) else {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["action"] = .string(action)
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.uiActionUnsupported.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "unsupported_ui_action")
            )
        }

        if selectorRequiresObservationProof, !targetIndexWasExplicit {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["action"] = .string(action)
            summary["target_resolution_mode"] = .string("selector")
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.uiTargetIndexRequired.rawValue)
            if !selector.role.isEmpty {
                summary["target_selector_role"] = .string(selector.role)
            }
            if !selector.title.isEmpty {
                summary["target_selector_title"] = .string(selector.title)
            }
            if !selector.identifier.isEmpty {
                summary["target_selector_identifier"] = .string(selector.identifier)
            }
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "target_index_required")
            )
        }

        if selectorRequiresObservationProof {
            guard let proof = await uiObservationProofLedger.latest(
                projectRoot: projectRoot,
                selectorSignature: uiObservationSelectorSignature(selector)
            ) else {
                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: false
                )
                summary["action"] = .string(action)
                summary["target_resolution_mode"] = .string("selector")
                summary["target_index"] = .number(Double(selector.matchIndex))
                summary["deny_code"] = .string(XTDeviceAutomationRejectCode.uiObservationRequired.rawValue)
                if !selector.role.isEmpty {
                    summary["target_selector_role"] = .string(selector.role)
                }
                if !selector.title.isEmpty {
                    summary["target_selector_title"] = .string(selector.title)
                }
                if !selector.identifier.isEmpty {
                    summary["target_selector_identifier"] = .string(selector.identifier)
                }
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(summary: summary, body: "observe_candidates_first")
                )
            }

            let ageSeconds = max(0, Date().timeIntervalSince1970 - proof.observedAt)
            if ageSeconds > uiObservationProofTTLSeconds {
                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: false
                )
                summary["action"] = .string(action)
                summary["target_resolution_mode"] = .string("selector")
                summary["target_index"] = .number(Double(selector.matchIndex))
                summary["observation_proof_age_sec"] = .number(ageSeconds)
                summary["observation_match_count"] = .number(Double(proof.matchCount))
                summary["deny_code"] = .string(XTDeviceAutomationRejectCode.uiObservationExpired.rawValue)
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(summary: summary, body: "observation_proof_expired")
                )
            }

            if selector.matchIndex >= proof.matchCount {
                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: false
                )
                summary["action"] = .string(action)
                summary["target_resolution_mode"] = .string("selector")
                summary["target_index"] = .number(Double(selector.matchIndex))
                summary["observation_proof_age_sec"] = .number(ageSeconds)
                summary["observation_match_count"] = .number(Double(proof.matchCount))
                summary["deny_code"] = .string(XTDeviceAutomationRejectCode.uiObservationTargetIndexOutOfRange.rawValue)
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(summary: summary, body: "target_index_out_of_range_for_last_observation")
                )
            }
        }

        if ["set_focused_value", "set_value", "type_text"].contains(action), normalizedValue == nil {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["action"] = .string(action)
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.uiActionValueMissing.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "missing_value")
            )
        }

        let result = await MainActor.run {
            DeviceAutomationTools.performUIAction(
                XTDeviceUIActionRequest(
                    action: action,
                    value: normalizedValue,
                    selector: selector
                )
            )
        }
        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: result.ok
        )
        summary["action"] = .string(action)
        summary["target_resolution_mode"] = .string(selector.isEmpty ? "focused" : "selector")
        summary["target_index"] = .number(Double(selector.matchIndex))
        if !selector.role.isEmpty {
            summary["target_selector_role"] = .string(selector.role)
        }
        if !selector.title.isEmpty {
            summary["target_selector_title"] = .string(selector.title)
        }
        if !selector.identifier.isEmpty {
            summary["target_selector_identifier"] = .string(selector.identifier)
        }
        if !selector.elementDescription.isEmpty {
            summary["target_selector_description"] = .string(selector.elementDescription)
        }
        if !selector.valueContains.isEmpty {
            summary["target_selector_value_contains"] = .string(selector.valueContains)
        }
        if let normalizedValue {
            summary["value_length"] = .number(Double(normalizedValue.count))
        }
        if let target = result.targetElement {
            summary["target_element_role"] = .string(target.role)
            summary["target_element_title"] = .string(target.title)
            summary["target_element_identifier"] = .string(target.identifier)
        }
        if !result.ok {
            summary["deny_code"] = .string((result.rejectCode ?? .uiActionFailed).rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: result.errorMessage.isEmpty ? "ui_action_failed" : result.errorMessage)
            )
        }
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: true,
            output: structuredOutput(summary: summary, body: result.output.isEmpty ? "ok" : result.output)
        )
    }

    private static func executeDeviceUIStep(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let observeGateDecision = DeviceAutomationTools.evaluateGate(
            for: .deviceUIObserve,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard observeGateDecision.allowed else {
            return deniedDeviceAutomationResult(
                call: call,
                projectRoot: projectRoot,
                decision: observeGateDecision,
                detailOverride: xtDeviceAutomationGateDeniedDetail(
                    tool: call.tool,
                    gateTool: .deviceUIObserve,
                    decision: observeGateDecision
                )
            )
        }
        let actGateDecision = DeviceAutomationTools.evaluateGate(
            for: .deviceUIAct,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard actGateDecision.allowed else {
            return deniedDeviceAutomationResult(
                call: call,
                projectRoot: projectRoot,
                decision: actGateDecision,
                detailOverride: xtDeviceAutomationGateDeniedDetail(
                    tool: call.tool,
                    gateTool: .deviceUIAct,
                    decision: actGateDecision
                )
            )
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        let observeArgs = uiSelectorObserveArgs(from: call)
        let preObserve = await executeDeviceUIObserve(
            call: ToolCall(id: "\(call.id)_preobserve", tool: .deviceUIObserve, args: observeArgs),
            projectRoot: projectRoot
        )
        guard preObserve.ok else {
            return uiStepFailureResult(
                call: call,
                stage: "pre_observe",
                inner: preObserve,
                selectedIndex: nil,
                autoSelected: false
            )
        }

        let preParsed = parseStructuredToolOutput(preObserve.output)
        guard case .object(let preSummary)? = preParsed.summary else {
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(false),
                        "deny_code": .string(XTDeviceAutomationRejectCode.uiObserveUnavailable.rawValue),
                    ],
                    body: "ui_step_preobserve_parse_failed"
                )
            )
        }

        let targetIndexArg = call.args["target_index"]
        let preMatches = jsonArrayValue(preSummary["matched_elements"]) ?? []
        let selectedIndex: Int
        let autoSelected: Bool
        if let rawTargetIndex = targetIndexArg {
            if case .number(let n) = rawTargetIndex {
                selectedIndex = max(0, Int(n))
            } else if case .string(let s) = rawTargetIndex, let n = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                selectedIndex = max(0, Int(n))
            } else {
                selectedIndex = 0
            }
            autoSelected = false
        } else {
            if preMatches.isEmpty {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(
                        summary: uiStepSummaryBase(
                            tool: call.tool,
                            preSummary: preSummary,
                            action: normalizedToolTextArg(call, "action").lowercased(),
                            selectedIndex: nil,
                            autoSelected: false,
                            ok: false,
                            denyCode: XTDeviceAutomationRejectCode.uiStepNoCandidates.rawValue
                        ),
                        body: preParsed.body + "\n\nui_step_no_candidates"
                    )
                )
            }
            if preMatches.count > 1 {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(
                        summary: uiStepSummaryBase(
                            tool: call.tool,
                            preSummary: preSummary,
                            action: normalizedToolTextArg(call, "action").lowercased(),
                            selectedIndex: nil,
                            autoSelected: false,
                            ok: false,
                            denyCode: XTDeviceAutomationRejectCode.uiStepTargetAmbiguous.rawValue
                        ),
                        body: preParsed.body + "\n\nui_step_target_ambiguous"
                    )
                )
            }
            selectedIndex = 0
            autoSelected = true
        }

        let actArgs = uiSelectorActArgs(from: call, selectedIndex: selectedIndex)
        let act = await executeDeviceUIAct(
            call: ToolCall(id: "\(call.id)_act", tool: .deviceUIAct, args: actArgs),
            projectRoot: projectRoot
        )
        guard act.ok else {
            return uiStepFailureResult(
                call: call,
                stage: "act",
                inner: act,
                selectedIndex: selectedIndex,
                autoSelected: autoSelected
            )
        }

        let postObserve = await executeDeviceUIObserve(
            call: ToolCall(id: "\(call.id)_postobserve", tool: .deviceUIObserve, args: observeArgs),
            projectRoot: projectRoot
        )
        guard postObserve.ok else {
            return uiStepFailureResult(
                call: call,
                stage: "post_observe",
                inner: postObserve,
                selectedIndex: selectedIndex,
                autoSelected: autoSelected
            )
        }

        let actParsed = parseStructuredToolOutput(act.output)
        let postParsed = parseStructuredToolOutput(postObserve.output)
        guard case .object(let actSummary)? = actParsed.summary,
              case .object(let postSummary)? = postParsed.summary else {
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(
                    summary: [
                        "tool": .string(call.tool.rawValue),
                        "ok": .bool(false),
                        "deny_code": .string(XTDeviceAutomationRejectCode.uiActionFailed.rawValue),
                    ],
                    body: "ui_step_summary_parse_failed"
                )
            )
        }

        var summary = actSummary
        summary["tool"] = .string(call.tool.rawValue)
        summary["ok"] = .bool(true)
        summary["side_effect_class"] = .string("ui_step")
        summary["step_mode"] = .string("observe_act_reobserve")
        summary["pre_match_count"] = preSummary["match_count"] ?? .number(Double(preMatches.count))
        summary["post_match_count"] = postSummary["match_count"] ?? .number(0)
        summary["selected_target_index"] = .number(Double(selectedIndex))
        summary["selected_target_auto"] = .bool(autoSelected)
        summary["pre_matched_elements"] = preSummary["matched_elements"] ?? .array([])
        summary["post_matched_elements"] = postSummary["matched_elements"] ?? .array([])
        let body = """
PREPARE
\(preParsed.body)

ACTION
\(actParsed.body)

VERIFY
\(postParsed.body)
"""
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: true,
            output: structuredOutput(summary: summary, body: body)
        )
    }

    private static func executeDeviceClipboardWrite(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let decision = DeviceAutomationTools.evaluateGate(
            for: call.tool,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard decision.allowed else {
            return deniedDeviceAutomationResult(call: call, projectRoot: projectRoot, decision: decision)
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        let text = [
            optStrArg(call, "text"),
            optStrArg(call, "content"),
            optStrArg(call, "value"),
        ]
        .compactMap { $0 }
        .first

        guard let text else {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.clipboardTextMissing.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "missing_text")
            )
        }

        let wrote = await MainActor.run {
            DeviceAutomationTools.writeClipboardText(text)
        }
        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: wrote
        )
        summary["character_count"] = .number(Double(text.count))
        if !wrote {
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.clipboardWriteFailed.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "clipboard_write_failed")
            )
        }
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: "ok"))
    }

    private static func executeDeviceScreenCapture(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let decision = DeviceAutomationTools.evaluateGate(
            for: call.tool,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard decision.allowed else {
            return deniedDeviceAutomationResult(call: call, projectRoot: projectRoot, decision: decision)
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        guard let capture = await MainActor.run(resultType: (data: Data, width: Int, height: Int)?.self, body: {
            DeviceAutomationTools.captureMainDisplayPNG()
        }) else {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.screenCaptureFailed.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "screen_capture_failed")
            )
        }

        let defaultPath = "build/reports/xt_device_screen_capture_\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let rawPath = optStrArg(call, "path") ?? defaultPath
        let target = FileTool.resolvePath(rawPath, projectRoot: projectRoot)
        do {
            try PathGuard.requireInside(root: projectRoot, target: target)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try capture.data.write(to: target)
        } catch {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.screenCaptureEncodeFailed.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: error.localizedDescription)
            )
        }

        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: true
        )
        summary["path"] = .string(target.path)
        summary["bytes"] = .number(Double(capture.data.count))
        summary["width"] = .number(Double(capture.width))
        summary["height"] = .number(Double(capture.height))
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: true,
            output: structuredOutput(summary: summary, body: target.path)
        )
    }

    private static func executeDeviceBrowserControl(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let decision = DeviceAutomationTools.evaluateGate(
            for: call.tool,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard decision.allowed else {
            return deniedDeviceAutomationResult(call: call, projectRoot: projectRoot, decision: decision)
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        let rawAction = (optStrArg(call, "action") ?? "open_url")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let requestedAction = XTBrowserRuntimeRequestedAction.parse(rawAction) else {
            return deviceBrowserControlFailure(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                rejectCode: .browserActionUnsupported,
                action: rawAction,
                url: optStrArg(call, "url"),
                body: "unsupported_browser_action"
            )
        }

        let requestedSessionID = (optStrArg(call, "session_id") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let projectID = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let auditRef = browserRuntimeAuditRef(action: requestedAction, projectID: projectID, now: now)
        let existingSession = XTBrowserRuntimeStore.resolvedSession(
            for: ctx,
            requestedSessionID: requestedSessionID
        )

        if !requestedSessionID.isEmpty, existingSession == nil {
            return deviceBrowserControlFailure(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                rejectCode: .browserSessionMissing,
                action: requestedAction.rawValue,
                url: optStrArg(call, "url"),
                body: "browser_session_missing"
            )
        }

        switch requestedAction {
        case .open, .navigate:
            guard let rawURL = optStrArg(call, "url") else {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserURLMissing,
                    action: requestedAction.rawValue,
                    url: nil,
                    body: "missing_url"
                )
            }
            guard let url = validatedBrowserURL(rawURL) else {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserURLInvalid,
                    action: requestedAction.rawValue,
                    url: rawURL,
                    body: "invalid_url"
                )
            }

            let opened = await MainActor.run {
                DeviceAutomationTools.openURLInDefaultBrowser(url)
            }
            guard opened else {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserOpenFailed,
                    action: requestedAction.rawValue,
                    url: url.absoluteString,
                    body: "browser_open_failed"
                )
            }

            var session = existingSession ?? XTBrowserRuntimeStore.bootstrapSession(
                for: ctx,
                projectID: projectID,
                actionMode: browserRuntimeActionMode(for: requestedAction),
                now: now
            )
            session = session.setting(
                currentURL: url.absoluteString,
                actionMode: browserRuntimeActionMode(for: requestedAction),
                updatedAt: now,
                auditRef: auditRef
            )

            do {
                let snapshotRef = try XTBrowserRuntimeStore.writeSnapshot(
                    session: session,
                    action: requestedAction,
                    snapshotKind: "runtime_state",
                    excerpt: "",
                    detail: "browser action routed through system_default_browser_bridge",
                    auditRef: auditRef,
                    for: ctx,
                    now: now
                )
                session = session.setting(snapshotRef: snapshotRef, updatedAt: now, auditRef: auditRef)
                try XTBrowserRuntimeStore.saveSession(session, for: ctx)
                recordBrowserRuntimeAction(
                    session: session,
                    action: requestedAction,
                    ok: true,
                    url: url.absoluteString,
                    snapshotRef: snapshotRef,
                    detail: "browser runtime \(requestedAction.rawValue) succeeded",
                    rejectCode: nil,
                    auditRef: auditRef,
                    ctx: ctx,
                    now: now
                )

                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: true
                )
                summary["action"] = .string(requestedAction.rawValue)
                summary["url"] = .string(url.absoluteString)
                summary.merge(browserRuntimeSummary(session: session, ctx: ctx), uniquingKeysWith: { _, new in new })

                let body = """
session_id=\(session.sessionID)
profile_id=\(session.profileID)
transport=\(session.transport)
snapshot_ref=\(session.snapshotRef)
url=\(url.absoluteString)
"""
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: structuredOutput(summary: summary, body: body)
                )
            } catch {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserSnapshotFailed,
                    action: requestedAction.rawValue,
                    url: url.absoluteString,
                    body: "browser_snapshot_failed"
                )
            }

        case .snapshot:
            var session = existingSession ?? XTBrowserRuntimeStore.bootstrapSession(
                for: ctx,
                projectID: projectID,
                actionMode: browserRuntimeActionMode(for: requestedAction),
                now: now
            )
            let targetURL = (optStrArg(call, "url") ?? session.currentURL).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetURL.isEmpty else {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserSessionNoActiveURL,
                    action: requestedAction.rawValue,
                    url: nil,
                    body: "browser_session_no_active_url"
                )
            }

            session = session.setting(
                currentURL: targetURL,
                actionMode: browserRuntimeActionMode(for: requestedAction),
                updatedAt: now,
                auditRef: auditRef
            )
            do {
                let snapshotRef = try XTBrowserRuntimeStore.writeSnapshot(
                    session: session,
                    action: requestedAction,
                    snapshotKind: "runtime_state",
                    excerpt: "",
                    detail: "runtime state snapshot without browser-side mutation",
                    auditRef: auditRef,
                    for: ctx,
                    now: now
                )
                session = session.setting(snapshotRef: snapshotRef, updatedAt: now, auditRef: auditRef)
                try XTBrowserRuntimeStore.saveSession(session, for: ctx)
                recordBrowserRuntimeAction(
                    session: session,
                    action: requestedAction,
                    ok: true,
                    url: targetURL,
                    snapshotRef: snapshotRef,
                    detail: "browser runtime snapshot captured",
                    rejectCode: nil,
                    auditRef: auditRef,
                    ctx: ctx,
                    now: now
                )

                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: true
                )
                summary["action"] = .string(requestedAction.rawValue)
                summary["url"] = .string(targetURL)
                summary.merge(browserRuntimeSummary(session: session, ctx: ctx), uniquingKeysWith: { _, new in new })
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: structuredOutput(summary: summary, body: snapshotRef)
                )
            } catch {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserSnapshotFailed,
                    action: requestedAction.rawValue,
                    url: targetURL,
                    body: "browser_snapshot_failed"
                )
            }

        case .extract:
            var session = existingSession ?? XTBrowserRuntimeStore.bootstrapSession(
                for: ctx,
                projectID: projectID,
                actionMode: browserRuntimeActionMode(for: requestedAction),
                now: now
            )
            let targetURL = (optStrArg(call, "url") ?? session.currentURL).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetURL.isEmpty else {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserSessionNoActiveURL,
                    action: requestedAction.rawValue,
                    url: nil,
                    body: "browser_session_no_active_url"
                )
            }

            let extractCall = ToolCall(
                id: "\(call.id)_browser_read",
                tool: .browser_read,
                args: [
                    "url": .string(targetURL),
                    "grant_id": call.args["grant_id"] ?? .null,
                    "timeout_sec": call.args["timeout_sec"] ?? .number(15),
                    "max_bytes": call.args["max_bytes"] ?? .number(900_000),
                ]
            )
            let extracted: ToolResult
            do {
                extracted = try await execute(call: extractCall, projectRoot: projectRoot)
            } catch {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserExtractFailed,
                    action: requestedAction.rawValue,
                    url: targetURL,
                    body: "browser_extract_failed"
                )
            }
            guard extracted.ok else {
                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: false
                )
                summary["action"] = .string(requestedAction.rawValue)
                summary["url"] = .string(targetURL)
                summary["deny_code"] = .string(XTDeviceAutomationRejectCode.browserExtractFailed.rawValue)
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: extracted.output,
                        extra: summary
                    )
                )
            }

            let parsed = parseStructuredToolOutput(extracted.output)
            session = session.setting(
                currentURL: targetURL,
                actionMode: browserRuntimeActionMode(for: requestedAction),
                updatedAt: now,
                auditRef: auditRef
            )
            do {
                let snapshotRef = try XTBrowserRuntimeStore.writeSnapshot(
                    session: session,
                    action: requestedAction,
                    snapshotKind: "extracted_text",
                    excerpt: parsed.body,
                    detail: "extract delegated to browser_read",
                    auditRef: auditRef,
                    for: ctx,
                    now: now
                )
                session = session.setting(snapshotRef: snapshotRef, updatedAt: now, auditRef: auditRef)
                try XTBrowserRuntimeStore.saveSession(session, for: ctx)
                recordBrowserRuntimeAction(
                    session: session,
                    action: requestedAction,
                    ok: true,
                    url: targetURL,
                    snapshotRef: snapshotRef,
                    detail: "browser runtime extract succeeded",
                    rejectCode: nil,
                    auditRef: auditRef,
                    ctx: ctx,
                    now: now
                )

                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: true
                )
                summary["action"] = .string(requestedAction.rawValue)
                summary["url"] = .string(targetURL)
                summary["text_chars"] = .number(Double(parsed.body.count))
                if case .object(let extractedSummary)? = parsed.summary {
                    if let finalURL = extractedSummary["final_url"] {
                        summary["browser_read_final_url"] = finalURL
                    }
                    if let contentType = extractedSummary["content_type"] {
                        summary["browser_read_content_type"] = contentType
                    }
                }
                summary.merge(browserRuntimeSummary(session: session, ctx: ctx), uniquingKeysWith: { _, new in new })
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: structuredOutput(summary: summary, body: parsed.body)
                )
            } catch {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserSnapshotFailed,
                    action: requestedAction.rawValue,
                    url: targetURL,
                    body: "browser_snapshot_failed"
                )
            }

        case .click, .typeText, .upload:
            guard let sessionForAction = existingSession else {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserSessionMissing,
                    action: requestedAction.rawValue,
                    url: optStrArg(call, "url"),
                    body: "browser_session_missing"
                )
            }

            let targetURL = (optStrArg(call, "url") ?? sessionForAction.currentURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetURL.isEmpty else {
                return deviceBrowserControlFailure(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    rejectCode: .browserSessionNoActiveURL,
                    action: requestedAction.rawValue,
                    url: nil,
                    body: "browser_session_no_active_url"
                )
            }

            let attemptedSession = sessionForAction.setting(
                currentURL: targetURL,
                actionMode: browserRuntimeActionMode(for: requestedAction),
                updatedAt: now,
                auditRef: auditRef
            )
            let managedDriverReject = XTDeviceAutomationRejectCode.browserManagedDriverUnavailable
            recordBrowserRuntimeAction(
                session: attemptedSession,
                action: requestedAction,
                ok: false,
                url: targetURL,
                snapshotRef: "",
                detail: "managed browser driver is not implemented for \(requestedAction.rawValue)",
                rejectCode: managedDriverReject.rawValue,
                auditRef: auditRef,
                ctx: ctx,
                now: now
            )

            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["action"] = .string(requestedAction.rawValue)
            summary["url"] = .string(targetURL)
            summary["deny_code"] = .string(managedDriverReject.rawValue)
            summary["browser_runtime_driver_state"] = .string("unavailable")
            if let selector = optStrArg(call, "selector")?.trimmingCharacters(in: .whitespacesAndNewlines),
               !selector.isEmpty {
                summary["selector"] = .string(selector)
            }
            if requestedAction == .typeText {
                let inputText = [
                    optStrArg(call, "text"),
                    optStrArg(call, "content"),
                    optStrArg(call, "value"),
                ]
                .compactMap { raw -> String? in
                    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? nil : trimmed
                }
                .first ?? ""
                summary["input_chars"] = .number(Double(inputText.count))
            }
            if requestedAction == .upload,
               let path = optStrArg(call, "path")?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                summary["path"] = .string(path)
            }
            summary.merge(browserRuntimeSummary(session: attemptedSession, ctx: ctx), uniquingKeysWith: { _, new in new })
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "managed_browser_driver_unavailable")
            )
        }
    }

    private static func validatedBrowserURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func browserRuntimeActionMode(
        for action: XTBrowserRuntimeRequestedAction
    ) -> XTBrowserRuntimeActionMode {
        switch action {
        case .open, .navigate, .click, .typeText:
            return .interactive
        case .upload:
            return .interactiveWithUpload
        case .snapshot, .extract:
            return .readOnly
        }
    }

    private static func browserRuntimeSummary(
        session: XTBrowserRuntimeSession,
        ctx: AXProjectContext
    ) -> [String: JSONValue] {
        [
            "browser_runtime_session_id": .string(session.sessionID),
            "browser_runtime_profile_id": .string(session.profileID),
            "browser_runtime_profile_path": .string(XTBrowserRuntimeStore.managedProfilePath(for: ctx, session: session)),
            "browser_runtime_snapshot_ref": .string(session.snapshotRef),
            "browser_runtime_action_mode": .string(session.actionMode.rawValue),
            "browser_runtime_transport": .string(session.transport),
            "browser_runtime_browser_engine": .string(session.browserEngine),
            "browser_runtime_current_url": .string(session.currentURL),
            "browser_runtime_open_tabs": .number(Double(session.openTabs)),
            "browser_runtime_grant_policy_ref": .string(session.grantPolicyRef),
        ]
    }

    private static func deviceBrowserControlFailure(
        call: ToolCall,
        projectRoot: URL,
        decision: XTDeviceAutomationGateDecision,
        rejectCode: XTDeviceAutomationRejectCode,
        action: String,
        url: String?,
        body: String
    ) -> ToolResult {
        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: false
        )
        summary["action"] = .string(action)
        if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary["url"] = .string(url)
        }
        summary["deny_code"] = .string(rejectCode.rawValue)
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: false,
            output: structuredOutput(summary: summary, body: body)
        )
    }

    private static func recordBrowserRuntimeAction(
        session: XTBrowserRuntimeSession,
        action: XTBrowserRuntimeRequestedAction,
        ok: Bool,
        url: String,
        snapshotRef: String,
        detail: String,
        rejectCode: String?,
        auditRef: String,
        ctx: AXProjectContext,
        now: Date
    ) {
        XTBrowserRuntimeStore.appendActionLog(
            session: session,
            action: action,
            ok: ok,
            url: url,
            snapshotRef: snapshotRef,
            detail: detail,
            rejectCode: rejectCode,
            auditRef: auditRef,
            for: ctx,
            now: now
        )
        var rawLogRow: [String: Any] = [
            "type": "browser_runtime_action",
            "created_at": now.timeIntervalSince1970,
            "project_id": session.projectID,
            "session_id": session.sessionID,
            "profile_id": session.profileID,
            "action": action.rawValue,
            "ok": ok,
            "url": url,
            "snapshot_ref": snapshotRef,
            "audit_ref": auditRef,
            "transport": session.transport
        ]
        if let rejectCode, !rejectCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rawLogRow["reject_code"] = rejectCode
        }
        AXProjectStore.appendRawLog(rawLogRow, for: ctx)
    }

    private static func browserRuntimeAuditRef(
        action: XTBrowserRuntimeRequestedAction,
        projectID: String,
        now: Date
    ) -> String {
        let token = projectID
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "audit-xt-browser-\(action.rawValue)-\(token)-\(Int(now.timeIntervalSince1970))"
    }

    private static func executeDeviceAppleScript(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let permissionReadiness = await MainActor.run {
            AXTrustedAutomationPermissionOwnerReadiness.current()
        }
        let decision = DeviceAutomationTools.evaluateGate(
            for: call.tool,
            projectRoot: projectRoot,
            config: config,
            permissionReadiness: permissionReadiness
        )
        guard decision.allowed else {
            return deniedDeviceAutomationResult(call: call, projectRoot: projectRoot, decision: decision)
        }
        let autonomyState = await xtResolveProjectAutonomyPolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            config: config,
            effectiveAutonomy: autonomyState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveAutonomy: autonomyState.effectivePolicy
            )
        }

        let source = (optStrArg(call, "source") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            var summary = deviceAutomationSummaryBase(
                call: call,
                projectRoot: projectRoot,
                decision: decision,
                ok: false
            )
            summary["source_length"] = .number(0)
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.appleScriptSourceMissing.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "missing_source")
            )
        }

        let result = await MainActor.run {
            DeviceAutomationTools.runAppleScript(source)
        }
        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: result.ok
        )
        summary["source_length"] = .number(Double(source.count))
        summary["output_length"] = .number(Double(result.output.count))
        if !result.ok {
            summary["deny_code"] = .string(XTDeviceAutomationRejectCode.appleScriptExecutionFailed.rawValue)
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: result.errorMessage.isEmpty ? "applescript_execution_failed" : result.errorMessage)
            )
        }

        let body = result.output.isEmpty ? "(no output)" : result.output
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: true,
            output: structuredOutput(summary: summary, body: body)
        )
    }

    private static func executeWebSearch(call: ToolCall, projectRoot: URL) async throws -> ToolResult {
        let query = (optStrArg(call, "query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string("missing_query"),
            ]
            return ToolResult(id: call.id, tool: call.tool, ok: false, output: structuredOutput(summary: summary, body: "missing_query"))
        }

        var components = URLComponents(string: "https://duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = components?.url?.absoluteString ?? "https://duckduckgo.com/html/?q=\(encodedQuery)"
        let fetchCall = ToolCall(
            id: "\(call.id)_web_fetch",
            tool: .web_fetch,
            args: [
                "url": .string(searchURL),
                "grant_id": call.args["grant_id"] ?? .null,
                "timeout_sec": call.args["timeout_sec"] ?? .number(12),
                "max_bytes": call.args["max_bytes"] ?? .number(600_000),
            ]
        )
        let fetched = try await execute(call: fetchCall, projectRoot: projectRoot)
        guard fetched.ok else {
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: wrappedFailureOutput(tool: call.tool, body: fetched.output, extra: [
                    "query": .string(query),
                    "grant_id": optStrArg(call, "grant_id").map(JSONValue.string) ?? .null,
                ])
            )
        }

        let parsed = parseWebFetchOutput(fetched.output)
        let limit = max(1, min(10, Int(optDoubleArg(call, "max_results") ?? 5)))
        let results = extractSearchResults(from: parsed.body, maxResults: limit)
        let resultValues = results.map { item -> JSONValue in
            .object([
                "title": .string(item.title),
                "url": .string(item.url),
                "snippet": .string(item.snippet),
            ])
        }
        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(true),
            "query": .string(query),
            "grant_id": optStrArg(call, "grant_id").map(JSONValue.string) ?? .null,
            "search_url": .string(searchURL),
            "results_count": .number(Double(results.count)),
            "results": .array(resultValues),
        ]
        let body: String
        if results.isEmpty {
            let fallback = htmlToReadableText(parsed.body)
            body = fallback.isEmpty ? "(no search results parsed)" : String(fallback.prefix(2_000))
        } else {
            body = results.enumerated().map { index, item in
                let snippet = item.snippet.isEmpty ? "" : "\n  \(item.snippet)"
                return "\(index + 1). \(item.title)\n   \(item.url)\(snippet)"
            }.joined(separator: "\n\n")
        }
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeBrowserRead(call: ToolCall, projectRoot: URL) async throws -> ToolResult {
        let url = (optStrArg(call, "url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string("missing_url"),
            ]
            return ToolResult(id: call.id, tool: call.tool, ok: false, output: structuredOutput(summary: summary, body: "missing_url"))
        }

        let fetchCall = ToolCall(
            id: "\(call.id)_web_fetch",
            tool: .web_fetch,
            args: [
                "url": .string(url),
                "grant_id": call.args["grant_id"] ?? .null,
                "timeout_sec": call.args["timeout_sec"] ?? .number(15),
                "max_bytes": call.args["max_bytes"] ?? .number(900_000),
            ]
        )
        let fetched = try await execute(call: fetchCall, projectRoot: projectRoot)
        guard fetched.ok else {
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: wrappedFailureOutput(tool: call.tool, body: fetched.output, extra: [
                    "url": .string(url),
                    "grant_id": optStrArg(call, "grant_id").map(JSONValue.string) ?? .null,
                ])
            )
        }

        let parsed = parseWebFetchOutput(fetched.output)
        let contentType = parsed.header["content_type"] ?? ""
        let bodyText: String
        if contentType.lowercased().contains("html") {
            bodyText = htmlToReadableText(parsed.body)
        } else {
            bodyText = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let excerpt = bodyText.isEmpty ? "(empty body)" : String(bodyText.prefix(12_000))
        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(true),
            "url": .string(url),
            "grant_id": optStrArg(call, "grant_id").map(JSONValue.string) ?? .null,
            "final_url": parsed.header["final_url"].map(JSONValue.string) ?? .null,
            "content_type": .string(contentType),
            "text_chars": .number(Double(bodyText.count)),
            "readability_applied": .bool(contentType.lowercased().contains("html")),
        ]
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: excerpt))
    }

    static func parseStructuredToolOutput(_ output: String) -> (summary: JSONValue?, body: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, "")
        }
        if let boundary = structuredHeaderBoundary(in: trimmed) {
            let header = String(trimmed[..<boundary])
            let body = String(trimmed[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = header.data(using: .utf8),
               let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
                return (value, body)
            }
        }
        return (nil, trimmed)
    }

    static func structuredOutput(summary: [String: JSONValue], body: String? = nil) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let header: String
        if let data = try? encoder.encode(JSONValue.object(summary)),
           let text = String(data: data, encoding: .utf8) {
            header = text
        } else {
            header = "{\"tool\":\"unknown\"}"
        }

        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedBody.isEmpty else { return header }
        return header + "\n\n" + trimmedBody
    }

    private static func wrappedFailureOutput(tool: ToolName, body: String, extra: [String: JSONValue]) -> String {
        var summary = extra
        summary["tool"] = .string(tool.rawValue)
        summary["ok"] = .bool(false)
        summary["reason"] = .string(firstFailureReason(in: body))
        return structuredOutput(summary: summary, body: body)
    }

    private static func firstFailureReason(in body: String) -> String {
        let firstLine = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return firstLine?.isEmpty == false ? firstLine! : "tool_failed"
    }

    private static func structuredHeaderBoundary(in text: String) -> String.Index? {
        guard let first = text.first, first == "{" || first == "[" else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaping = false

        for index in text.indices {
            let character = text[index]
            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{", "[":
                depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 {
                    return text.index(after: index)
                }
            default:
                break
            }
        }

        return nil
    }

    private static func parseWebFetchOutput(_ output: String) -> (header: [String: String], body: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "\n\n") else {
            return ([:], trimmed)
        }
        let headerText = String(trimmed[..<range.lowerBound])
        let body = String(trimmed[range.upperBound...])
        var header: [String: String] = [:]
        for rawLine in headerText.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            header[key] = value
        }
        return (header, body)
    }

    private static func extractSearchResults(from html: String, maxResults: Int) -> [SearchResultItem] {
        guard maxResults > 0 else { return [] }
        let pattern = #"<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        var results: [SearchResultItem] = []
        var seen = Set<String>()

        for match in matches {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            guard let normalizedURL = normalizedSearchResultURL(String(html[hrefRange])) else {
                continue
            }
            guard seen.insert(normalizedURL).inserted else {
                continue
            }

            let title = htmlToReadableText(String(html[titleRange]))
            guard !title.isEmpty else { continue }

            let snippetStart = match.range.location + match.range.length
            let available = max(0, html.utf16.count - snippetStart)
            let snippetRange = NSRange(location: snippetStart, length: min(320, available))
            let snippetRaw: String
            if let range = Range(snippetRange, in: html) {
                snippetRaw = String(html[range])
            } else {
                snippetRaw = ""
            }
            let snippet = String(htmlToReadableText(snippetRaw).prefix(180))
            results.append(SearchResultItem(title: title, url: normalizedURL, snippet: snippet))
            if results.count >= maxResults {
                break
            }
        }

        return results
    }

    private static func normalizedSearchResultURL(_ href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed),
           let encoded = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = encoded.removingPercentEncoding,
           let decodedURL = URL(string: decoded),
           let scheme = decodedURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return decodedURL.absoluteString
        }

        if let directURL = URL(string: trimmed),
           let scheme = directURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return directURL.absoluteString
        }

        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }

        return nil
    }

    static func htmlToReadableText(_ html: String) -> String {
        var text = html
        let patterns = [
            #"(?is)<script\b[^>]*>.*?</script>"#,
            #"(?is)<style\b[^>]*>.*?</style>"#,
            #"(?i)<br\s*/?>"#,
            #"(?i)</p>"#,
            #"(?i)</div>"#,
            #"(?i)</li>"#,
            #"(?i)</h[1-6]>"#,
            #"(?is)<[^>]+>"#,
        ]
        let replacements = [" ", " ", "\n", "\n", "\n", "\n", "\n", " "]
        for (pattern, replacement) in zip(patterns, replacements) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            text = regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: NSRange(text.startIndex..<text.endIndex, in: text),
                withTemplate: replacement
            )
        }
        text = decodeHTMLEntities(text)
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            }
            .joined(separator: "\n")
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var out = text
        let replacements = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " ",
        ]
        for (entity, value) in replacements {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out
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

    private static func normalizedToolTextArg(_ call: ToolCall, _ key: String) -> String {
        (optStrArg(call, key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uiObservationSelectorSignature(_ selector: XTDeviceUISelector) -> String {
        [
            selector.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selector.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selector.identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selector.elementDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            selector.valueContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ]
        .joined(separator: "\u{1F}")
    }

    private static func uiSelectorObserveArgs(from call: ToolCall) -> [String: JSONValue] {
        var args: [String: JSONValue] = [:]
        for key in ["target_role", "target_title", "target_identifier", "target_description", "target_value_contains", "max_results"] {
            if let value = call.args[key] {
                args[key] = value
            }
        }
        return args
    }

    private static func uiSelectorActArgs(from call: ToolCall, selectedIndex: Int) -> [String: JSONValue] {
        var args: [String: JSONValue] = [:]
        for key in ["action", "value", "text", "content", "target_role", "target_title", "target_identifier", "target_description", "target_value_contains"] {
            if let value = call.args[key] {
                args[key] = value
            }
        }
        args["target_index"] = .number(Double(selectedIndex))
        return args
    }

    private static func uiStepFailureResult(
        call: ToolCall,
        stage: String,
        inner: ToolResult,
        selectedIndex: Int?,
        autoSelected: Bool
    ) -> ToolResult {
        let parsed = parseStructuredToolOutput(inner.output)
        var summary: [String: JSONValue]
        if case .object(let object)? = parsed.summary {
            summary = object
        } else {
            summary = [:]
        }
        summary["tool"] = .string(call.tool.rawValue)
        summary["ok"] = .bool(false)
        summary["side_effect_class"] = .string("ui_step")
        summary["step_mode"] = .string("observe_act_reobserve")
        summary["step_stage"] = .string(stage)
        if let selectedIndex {
            summary["selected_target_index"] = .number(Double(selectedIndex))
            summary["selected_target_auto"] = .bool(autoSelected)
        }
        let body = """
UI step stage failed: \(stage)

\(parsed.body)
"""
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: false,
            output: structuredOutput(summary: summary, body: body)
        )
    }

    private static func uiStepSummaryBase(
        tool: ToolName,
        preSummary: [String: JSONValue],
        action: String,
        selectedIndex: Int?,
        autoSelected: Bool,
        ok: Bool,
        denyCode: String
    ) -> [String: JSONValue] {
        var summary = preSummary
        summary["tool"] = .string(tool.rawValue)
        summary["ok"] = .bool(ok)
        summary["side_effect_class"] = .string("ui_step")
        summary["step_mode"] = .string("observe_act_reobserve")
        summary["action"] = .string(action)
        summary["deny_code"] = .string(denyCode)
        if let selectedIndex {
            summary["selected_target_index"] = .number(Double(selectedIndex))
        }
        summary["selected_target_auto"] = .bool(autoSelected)
        return summary
    }

    private static func jsonArrayValue(_ value: JSONValue?) -> [JSONValue]? {
        guard case .array(let array)? = value else { return nil }
        return array
    }

    private static func shouldUseSandbox(_ call: ToolCall) -> Bool {
        if let explicit = optBoolArg(call, "sandbox") {
            return explicit
        }
        return sandboxMode() == .sandbox
    }

    private static func deniedDeviceAutomationResult(
        call: ToolCall,
        projectRoot: URL,
        decision: XTDeviceAutomationGateDecision,
        detailOverride: String? = nil
    ) -> ToolResult {
        var summary = deviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: false
        )
        summary["deny_code"] = .string(decision.rejectCode?.rawValue ?? XTDeviceAutomationRejectCode.toolNotSupported.rawValue)
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: false,
            output: structuredOutput(summary: summary, body: detailOverride ?? decision.detail)
        )
    }

    private static func deniedRuntimePolicyResult(
        call: ToolCall,
        projectRoot: URL,
        config: AXProjectConfig,
        decision: XTToolRuntimePolicyDecision,
        effectiveAutonomy: AXProjectAutonomyEffectivePolicy? = nil
    ) -> ToolResult {
        let summary = xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: projectRoot,
            config: config,
            decision: decision,
            effectiveAutonomy: effectiveAutonomy
        )
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: false,
            output: structuredOutput(summary: summary, body: decision.detail)
        )
    }

    static func deniedHighRiskMemoryRecheckResultIfNeeded(
        call: ToolCall,
        projectRoot: URL,
        config: AXProjectConfig,
        resolutionOverride: HubIPCClient.MemoryContextResolutionResult? = nil
    ) async -> ToolResult? {
        let decision = await highRiskMemoryRecheckDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            resolutionOverride: resolutionOverride
        )
        guard decision.required, !decision.ok else { return nil }

        var summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(false),
            "memory_mode": .string(decision.useMode.rawValue),
            "memory_source": .string(decision.source),
            "memory_freshness": .string(decision.freshness),
            "memory_cache_hit": .bool(decision.cacheHit),
            "deny_code": .string(decision.denyCode ?? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue),
        ]
        if let reasonCode = decision.reasonCode {
            summary["memory_reason_code"] = .string(reasonCode)
        }
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: false,
            output: structuredOutput(summary: summary, body: decision.detail)
        )
    }

    private static func highRiskMemoryRecheckDecision(
        call: ToolCall,
        projectRoot: URL,
        config: AXProjectConfig,
        resolutionOverride: HubIPCClient.MemoryContextResolutionResult? = nil
    ) async -> HighRiskMemoryRecheckDecision {
        guard XTProjectMemoryGovernance.prefersHubMemory(config) else {
            return HighRiskMemoryRecheckDecision(
                required: false,
                ok: true,
                useMode: .toolActLowRisk,
                source: "disabled",
                freshness: "not_required",
                cacheHit: false,
                denyCode: nil,
                reasonCode: nil,
                detail: "hub memory disabled for project"
            )
        }

        guard requiresFreshMemoryRecheck(call: call, projectRoot: projectRoot) else {
            return HighRiskMemoryRecheckDecision(
                required: false,
                ok: true,
                useMode: .toolActLowRisk,
                source: "not_required",
                freshness: "not_required",
                cacheHit: false,
                denyCode: nil,
                reasonCode: nil,
                detail: "fresh hub recheck not required"
            )
        }

        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let result = if let resolutionOverride {
            resolutionOverride
        } else {
            await HubIPCClient.requestMemoryContextDetailed(
                useMode: .toolActHighRisk,
                requesterRole: .tool,
                projectId: projectId,
                projectRoot: projectRoot.standardizedFileURL.path,
                displayName: projectRoot.lastPathComponent,
                latestUser: highRiskMemoryRecheckLatestUser(call: call),
                constitutionHint: nil,
                canonicalText: nil,
                observationsText: highRiskMemoryRecheckObservationSummary(projectRoot: projectRoot),
                workingSetText: highRiskMemoryRecheckWorkingSet(projectRoot: projectRoot),
                rawEvidenceText: highRiskMemoryRecheckEvidence(call: call),
                budgets: nil,
                timeoutSec: 1.6
            )
        }
        if result.response != nil {
            return HighRiskMemoryRecheckDecision(
                required: true,
                ok: true,
                useMode: .toolActHighRisk,
                source: result.source,
                freshness: result.freshness,
                cacheHit: result.cacheHit,
                denyCode: nil,
                reasonCode: nil,
                detail: "fresh hub recheck satisfied"
            )
        }

        let denyCode = result.denyCode ?? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
        let detail = "high_risk_fresh_recheck_required (\(denyCode))" +
            (result.reasonCode.map { " reason=\($0)" } ?? "")
        return HighRiskMemoryRecheckDecision(
            required: true,
            ok: false,
            useMode: .toolActHighRisk,
            source: result.source,
            freshness: result.freshness,
            cacheHit: result.cacheHit,
            denyCode: denyCode,
            reasonCode: result.reasonCode,
            detail: detail
        )
    }

    private static func requiresFreshMemoryRecheck(call: ToolCall, projectRoot: URL) -> Bool {
        switch call.tool {
        case .git_apply, .deviceUIAct, .deviceUIStep, .deviceBrowserControl, .deviceAppleScript:
            return true
        case .write_file:
            guard let path = optStrArg(call, "path") else { return false }
            let target = resolvedProjectPath(path, projectRoot: projectRoot)
            return FileManager.default.fileExists(atPath: target.path)
        case .run_command:
            return isHighRiskCommand(optStrArg(call, "command") ?? "")
        default:
            return false
        }
    }

    private static func highRiskMemoryRecheckLatestUser(call: ToolCall) -> String {
        switch call.tool {
        case .write_file:
            return "tool.write_file path=\(optStrArg(call, "path") ?? "(none)")"
        case .run_command:
            return "tool.run_command command=\(optStrArg(call, "command") ?? "(none)")"
        case .git_apply:
            return "tool.git_apply patch_mutation"
        default:
            return "tool.\(call.tool.rawValue)"
        }
    }

    private static func highRiskMemoryRecheckWorkingSet(projectRoot: URL) -> String? {
        let recent = AXRecentContextStore.load(for: AXProjectContext(root: projectRoot))
        let text = recent.messages
            .suffix(6)
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func highRiskMemoryRecheckObservationSummary(projectRoot: URL) -> String? {
        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let registry = AXProjectRegistryStore.load()
        guard let entry = registry.project(for: projectId) else { return nil }
        let digest = (entry.statusDigest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = Int(registry.updatedAt)
        return """
project_id: \(projectId)
status_digest: \(digest.isEmpty ? "(none)" : digest)
project_updated_at: \(updated)
"""
    }

    private static func highRiskMemoryRecheckEvidence(call: ToolCall) -> String? {
        switch call.tool {
        case .write_file:
            let path = optStrArg(call, "path") ?? "(none)"
            let content = strArg(call, "content")
            return "write_target=\(path)\ncontent_chars=\(content.count)"
        case .run_command:
            let command = optStrArg(call, "command") ?? "(none)"
            return "command=\(command)"
        case .git_apply:
            let patch = strArg(call, "patch")
            return "patch_chars=\(patch.count)\nmutation_scope=repo"
        case .deviceBrowserControl:
            return "browser_action=\(optStrArg(call, "action") ?? "open_url")\nurl=\(optStrArg(call, "url") ?? "(none)")"
        case .deviceAppleScript:
            return "applescript_source_chars=\((optStrArg(call, "source") ?? "").count)"
        default:
            return "tool=\(call.tool.rawValue)"
        }
    }

    private static func isHighRiskCommand(_ raw: String) -> Bool {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !command.isEmpty else { return false }
        let tokens = [
            "git push",
            "rm ",
            "mv ",
            "cp ",
            "sed -i",
            "perl -pi",
            "launchctl ",
            "defaults write",
            "sudo ",
            "ssh ",
            "scp ",
            "rsync ",
            "docker push",
            "npm publish",
            "cargo publish",
            "gh release create",
            "xcodebuild -exportarchive"
        ]
        if tokens.contains(where: { command.contains($0) }) {
            return true
        }
        if command.contains("curl ") && (command.contains(" -x post") || command.contains(" --data") || command.contains(" -d ")) {
            return true
        }
        return false
    }

    private static func resolvedProjectPath(_ rawPath: String, projectRoot: URL) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return projectRoot }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }
        return projectRoot.appendingPathComponent(trimmed).standardizedFileURL
    }

    private static func isDeviceAutomationTool(_ tool: ToolName) -> Bool {
        switch tool {
        case .deviceUIObserve,
             .deviceUIAct,
             .deviceUIStep,
             .deviceClipboardRead,
             .deviceClipboardWrite,
             .deviceScreenCapture,
             .deviceBrowserControl,
             .deviceAppleScript:
            return true
        default:
            return false
        }
    }

    private static func deviceAutomationSummaryBase(
        call: ToolCall,
        projectRoot: URL,
        decision: XTDeviceAutomationGateDecision,
        ok: Bool
    ) -> [String: JSONValue] {
        xtDeviceAutomationSummaryBase(
            call: call,
            projectRoot: projectRoot,
            decision: decision,
            ok: ok
        )
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

    private static func connectorIngressDenyHint(_ reason: String) -> String? {
        switch reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sender_not_allowlisted":
            return "sender is not in ingress allowlist for this scope"
        case "dm_pairing_scope_violation":
            return "dm pairing authorization does not grant group scope"
        case "webhook_not_allowlisted":
            return "webhook source is not in configured allowlist"
        case "audit_write_failed":
            return "hub audit sink failure triggered fail-closed deny"
        default:
            return nil
        }
    }

    static func scanHighRiskGrantBypass(
        ctx: AXProjectContext,
        maxBytes: Int = 320_000,
        maxFindings: Int = 20
    ) -> HighRiskGrantBypassScanReport {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else {
            return HighRiskGrantBypassScanReport(
                generatedAt: Date().timeIntervalSince1970,
                scannedToolEvents: 0,
                webFetchEvents: 0,
                deniedEvents: 0,
                bypassCount: 0,
                findings: []
            )
        }
        guard let data = readTailData(url: ctx.rawLogURL, maxBytes: maxBytes),
              let text = String(data: data, encoding: .utf8) else {
            return HighRiskGrantBypassScanReport(
                generatedAt: Date().timeIntervalSince1970,
                scannedToolEvents: 0,
                webFetchEvents: 0,
                deniedEvents: 0,
                bypassCount: 0,
                findings: []
            )
        }

        var scannedToolEvents = 0
        var webFetchEvents = 0
        var deniedEvents = 0
        var bypassCountTotal = 0
        var findings: [HighRiskGrantBypassFinding] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            guard (obj["type"] as? String) == "tool" else { continue }
            scannedToolEvents += 1

            let action = ((obj["action"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard action == ToolName.web_fetch.rawValue else { continue }
            webFetchEvents += 1

            let ok = (obj["ok"] as? Bool) ?? false
            let createdAt = (obj["created_at"] as? Double) ?? 0
            let output = (obj["output"] as? String) ?? ""
            if !ok, output.lowercased().contains("high_risk_denied") {
                deniedEvents += 1
                continue
            }
            guard ok else { continue }

            let input = obj["input"] as? [String: Any]
            let grantId = toolInputGrantId(input)
            if let grantId, !grantId.isEmpty {
                continue
            }

            bypassCountTotal += 1
            let detail = "bypass_grant_execution: web_fetch ok=true but input.grant_id is missing"
            if findings.count < maxFindings {
                findings.append(
                    HighRiskGrantBypassFinding(
                        id: "scan_\(Int(createdAt * 1000))_\(findings.count + 1)",
                        createdAt: createdAt,
                        action: action,
                        detail: detail
                    )
                )
            }
        }

        return HighRiskGrantBypassScanReport(
            generatedAt: Date().timeIntervalSince1970,
            scannedToolEvents: scannedToolEvents,
            webFetchEvents: webFetchEvents,
            deniedEvents: deniedEvents,
            bypassCount: bypassCountTotal,
            findings: findings
        )
    }

    static func formatHighRiskGrantBypassScanReport(_ report: HighRiskGrantBypassScanReport) -> String {
        let header = """
High-risk bypass scan \(report.ok ? "PASS" : "FAIL")
- scanned tool events: \(report.scannedToolEvents)
- web_fetch events: \(report.webFetchEvents)
- denied by grant gate: \(report.deniedEvents)
- bypass findings: \(report.bypassCount)
"""
        guard !report.findings.isEmpty else { return header }

        let lines = report.findings.prefix(6).map { finding in
            let ts: String
            if finding.createdAt > 0 {
                let date = Date(timeIntervalSince1970: finding.createdAt)
                let fmt = DateFormatter()
                fmt.dateFormat = "MM-dd HH:mm:ss"
                ts = fmt.string(from: date)
            } else {
                ts = "unknown_time"
            }
            return "- [\(ts)] \(finding.detail)"
        }
        return header + "\n" + lines.joined(separator: "\n")
    }

    static func highRiskGrantRuntimeStatus(projectRoot: URL) async -> String {
        let now = Date().timeIntervalSince1970
        let summary = await highRiskGrantLedger.describeActiveGrants(
            projectRootKey: normalizeRootKey(projectRoot),
            now: now
        )
        if summary.isEmpty {
            return "active grants: (none)"
        }
        return "active grants:\n" + summary
    }

    static func runHighRiskGrantSelfChecks(projectRoot: URL) async -> [HighRiskGrantSelfCheck] {
        let rootKey = normalizeRootKey(projectRoot)
        let now = Date().timeIntervalSince1970
        let synthetic = await highRiskGrantLedger.registerActiveGrant(
            projectRootKey: rootKey,
            capability: HighRiskCapability.webFetch.rawValue,
            grantRequestId: nil,
            fallbackTTLSeconds: 120,
            now: now
        )

        let validState = await highRiskGrantLedger.validateGrant(
            projectRootKey: rootKey,
            capability: HighRiskCapability.webFetch.rawValue,
            grantId: synthetic,
            bridgeEnabled: true,
            now: now + 1
        )
        let expiredState = await highRiskGrantLedger.validateGrant(
            projectRootKey: rootKey,
            capability: HighRiskCapability.webFetch.rawValue,
            grantId: synthetic,
            bridgeEnabled: true,
            now: now + 180
        )
        let missingState = await highRiskGrantLedger.validateGrant(
            projectRootKey: rootKey,
            capability: HighRiskCapability.webFetch.rawValue,
            grantId: "missing_grant_for_selftest",
            bridgeEnabled: true,
            now: now
        )

        return [
            HighRiskGrantSelfCheck(
                name: "registered grant is accepted",
                ok: validState == .valid,
                detail: "state=\(validState.rawValue)"
            ),
            HighRiskGrantSelfCheck(
                name: "expired grant is denied",
                ok: expiredState == .expired,
                detail: "state=\(expiredState.rawValue)"
            ),
            HighRiskGrantSelfCheck(
                name: "missing grant is denied",
                ok: missingState == .missing || missingState == .invalid,
                detail: "state=\(missingState.rawValue)"
            ),
        ]
    }

    static func activateHighRiskGrantForSupervisor(
        projectRoot: URL,
        capability: String,
        grantRequestId: String?,
        fallbackSeconds: Int
    ) async -> String? {
        let token = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard token == HighRiskCapability.webFetch.rawValue.lowercased() else {
            return nil
        }
        return await noteActiveHighRiskGrant(
            projectRoot: projectRoot,
            capability: .webFetch,
            grantRequestId: grantRequestId,
            fallbackSeconds: fallbackSeconds
        )
    }

    private static func gateHighRiskWebFetch(call: ToolCall, projectRoot: URL) async -> HighRiskGrantGateDecision {
        guard let providedGrant = toolCallGrantId(call) else {
            return HighRiskGrantGateDecision(
                ok: false,
                grantId: nil,
                rejectCode: .missing,
                detail: "missing grant_id (call need_network first, then pass args.grant_id)"
            )
        }

        let state = await highRiskGrantLedger.validateGrant(
            projectRootKey: normalizeRootKey(projectRoot),
            capability: HighRiskCapability.webFetch.rawValue,
            grantId: providedGrant,
            bridgeEnabled: HubBridgeClient.status().enabled,
            now: Date().timeIntervalSince1970
        )

        switch state {
        case .valid:
            return HighRiskGrantGateDecision(ok: true, grantId: providedGrant, rejectCode: nil, detail: "ok")
        case .bridgeDisabled:
            return HighRiskGrantGateDecision(
                ok: false,
                grantId: providedGrant,
                rejectCode: .bridgeDisabled,
                detail: "bridge is not enabled for grant \(providedGrant)"
            )
        case .expired:
            return HighRiskGrantGateDecision(
                ok: false,
                grantId: providedGrant,
                rejectCode: .expired,
                detail: "grant \(providedGrant) is expired (replay denied)"
            )
        case .invalid, .missing:
            return HighRiskGrantGateDecision(
                ok: false,
                grantId: providedGrant,
                rejectCode: .invalid,
                detail: "grant \(providedGrant) is not active for this project/capability"
            )
        }
    }

    private static func noteActiveHighRiskGrant(
        projectRoot: URL,
        capability: HighRiskCapability,
        grantRequestId: String?,
        fallbackSeconds: Int
    ) async -> String? {
        let ttl = max(60, fallbackSeconds)
        let grantId = await highRiskGrantLedger.registerActiveGrant(
            projectRootKey: normalizeRootKey(projectRoot),
            capability: capability.rawValue,
            grantRequestId: grantRequestId,
            fallbackTTLSeconds: ttl,
            now: Date().timeIntervalSince1970
        )
        return grantId.isEmpty ? nil : grantId
    }

    private static func toolCallGrantId(_ call: ToolCall) -> String? {
        if let grant = optStrArg(call, "grant_id") {
            let token = normalizeGrantToken(grant)
            if !token.isEmpty { return token }
        }
        if let grant = optStrArg(call, "grant_request_id") {
            let token = normalizeGrantToken(grant)
            if !token.isEmpty { return token }
        }
        return nil
    }

    private static func toolInputGrantId(_ input: [String: Any]?) -> String? {
        guard let input else { return nil }
        if let grant = input["grant_id"] as? String {
            let token = normalizeGrantToken(grant)
            if !token.isEmpty { return token }
        }
        if let grant = input["grant_request_id"] as? String {
            let token = normalizeGrantToken(grant)
            if !token.isEmpty { return token }
        }
        return nil
    }

    private static func normalizeRootKey(_ projectRoot: URL) -> String {
        projectRoot.standardizedFileURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeGrantToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readTailData(url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let bounded = max(8_192, maxBytes)
        let totalSize = (try? handle.seekToEnd()) ?? 0
        let start = totalSize > UInt64(bounded) ? totalSize - UInt64(bounded) : 0
        try? handle.seek(toOffset: start)
        return try? handle.readToEnd()
    }

    private static func searchInSandbox(
        pattern: String,
        glob: String?,
        sandbox: any SandboxProvider,
        maxResults: Int
    ) async throws -> [String] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return [] }

        let command = buildSandboxRGSearchCommand(
            pattern: trimmedPattern,
            glob: glob,
            maxResults: maxResults
        )
        let result = try await sandbox.execute(command: command, timeout: 20.0)

        switch result.exitCode {
        case 0:
            return parseSearchLines(result.stdout, maxResults: maxResults)
        case 1:
            return []
        default:
            if isCommandNotFound(result: result, command: "rg") {
                return try await searchInSandboxFallback(
                    pattern: trimmedPattern,
                    glob: glob,
                    sandbox: sandbox,
                    maxResults: maxResults
                )
            }

            let detail = [result.stdout, result.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let reason = detail.isEmpty ? "sandbox search failed (exit \(result.exitCode))" : detail
            throw SandboxError.commandExecutionFailed(reason)
        }
    }

    private static func buildSandboxRGSearchCommand(
        pattern: String,
        glob: String?,
        maxResults: Int
    ) -> String {
        var parts: [String] = [
            "rg",
            "--line-number",
            "--no-heading",
            "--smart-case",
            "--max-count",
            String(maxResults)
        ]

        if let rawGlob = glob?.trimmingCharacters(in: .whitespacesAndNewlines), !rawGlob.isEmpty {
            parts.append("--glob")
            parts.append(shellQuote(rawGlob))
        }

        parts.append("--")
        parts.append(shellQuote(pattern))
        parts.append(".")
        return parts.joined(separator: " ")
    }

    private static func searchInSandboxFallback(
        pattern: String,
        glob: String?,
        sandbox: any SandboxProvider,
        maxResults: Int
    ) async throws -> [String] {
        let regex = try makeSearchRegex(pattern: pattern)
        let root = await sandbox.workingDirectory
        let files = try await collectSandboxFiles(
            root: root,
            sandbox: sandbox,
            maxFiles: 5_000
        )

        var out: [String] = []
        for file in files {
            guard out.count < maxResults else { break }
            guard sandboxGlobMatches(filePath: file, root: root, glob: glob) else { continue }
            guard let content = try? await sandbox.readFile(path: file) else { continue }

            var lineNumber = 0
            content.enumerateLines { line, stop in
                lineNumber += 1
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    out.append("\(file):\(lineNumber):\(line)")
                    if out.count >= maxResults {
                        stop = true
                    }
                }
            }
        }

        return out
    }

    private static func collectSandboxFiles(
        root: String,
        sandbox: any SandboxProvider,
        maxFiles: Int
    ) async throws -> [String] {
        var queue: [String] = [normalizePathForSet(root)]
        var index = 0
        var seen = Set<String>()
        var files: [String] = []

        while index < queue.count {
            let dir = queue[index]
            index += 1
            guard !seen.contains(dir) else { continue }
            seen.insert(dir)

            let entries = try await sandbox.listFiles(path: dir)
            for entry in entries {
                if entry.isDirectory {
                    if !entry.isSymbolicLink {
                        queue.append(normalizePathForSet(entry.path))
                    }
                    continue
                }

                if !entry.isSymbolicLink {
                    files.append(entry.path)
                    if files.count >= maxFiles {
                        return files.sorted()
                    }
                }
            }
        }

        return files.sorted()
    }

    private static func makeSearchRegex(pattern: String) throws -> NSRegularExpression {
        let hasUppercase = pattern.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        let options: NSRegularExpression.Options = hasUppercase ? [] : [.caseInsensitive]
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw SandboxError.commandExecutionFailed("invalid search pattern: \(error.localizedDescription)")
        }
    }

    private static func parseSearchLines(_ text: String, maxResults: Int) -> [String] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        if lines.count <= maxResults {
            return lines
        }
        return Array(lines.prefix(maxResults))
    }

    private static func isCommandNotFound(result: ExecutionResult, command: String) -> Bool {
        if result.exitCode == 127 {
            return true
        }
        let joined = ([result.stdout, result.stderr].joined(separator: "\n")).lowercased()
        return joined.contains("command not found") && joined.contains(command.lowercased())
    }

    private static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private static func sandboxGlobMatches(filePath: String, root: String, glob: String?) -> Bool {
        guard let rawGlob = glob?.trimmingCharacters(in: .whitespacesAndNewlines), !rawGlob.isEmpty else {
            return true
        }

        let normalizedRoot = normalizePathForSet(root)
        let normalizedFile = normalizePathForSet(filePath)

        let relative: String
        if normalizedFile.hasPrefix(normalizedRoot + "/") {
            relative = String(normalizedFile.dropFirst(normalizedRoot.count + 1))
        } else {
            relative = (normalizedFile as NSString).lastPathComponent
        }

        let pattern = rawGlob.replacingOccurrences(of: "\\", with: "/")
        let predicate = NSPredicate(format: "SELF LIKE %@", pattern)
        let basename = (relative as NSString).lastPathComponent
        return predicate.evaluate(with: relative) || predicate.evaluate(with: basename)
    }

private static func normalizePathForSet(_ path: String) -> String {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.isEmpty ? "/" : normalized
    }
}

private enum HighRiskGrantValidationState: String, Equatable {
    case valid
    case missing
    case invalid
    case expired
    case bridgeDisabled
}

private actor HighRiskGrantLedger {
    private struct GrantRecord: Equatable {
        var projectRootKey: String
        var capability: String
        var grantId: String
        var issuedAt: TimeInterval
        var expiresAt: TimeInterval
    }

    private var records: [String: GrantRecord] = [:]
    private let maxRecords = 512

    func registerActiveGrant(
        projectRootKey: String,
        capability: String,
        grantRequestId: String?,
        fallbackTTLSeconds: Int,
        now: TimeInterval
    ) -> String {
        let root = projectRootKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty, !cap.isEmpty else { return "" }

        let grantToken = normalizedGrant(grantRequestId)
        let grantId: String
        if !grantToken.isEmpty {
            grantId = grantToken
        } else {
            grantId = "session_grant_\(Int(now * 1000))_\(UUID().uuidString.prefix(8))"
        }

        let ttl = max(60, fallbackTTLSeconds)
        let expiresAt = now + Double(ttl)
        let key = makeKey(root: root, capability: cap, grantId: grantId)

        let previous = records[key]
        let record = GrantRecord(
            projectRootKey: root,
            capability: cap,
            grantId: grantId,
            issuedAt: previous?.issuedAt ?? now,
            expiresAt: max(previous?.expiresAt ?? 0, expiresAt)
        )
        records[key] = record
        trimIfNeeded(now: now)
        return grantId
    }

    func validateGrant(
        projectRootKey: String,
        capability: String,
        grantId: String,
        bridgeEnabled: Bool,
        now: TimeInterval
    ) -> HighRiskGrantValidationState {
        let root = projectRootKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let gid = normalizedGrant(grantId)
        guard !root.isEmpty, !cap.isEmpty, !gid.isEmpty else { return .missing }

        let key = makeKey(root: root, capability: cap, grantId: gid)
        guard let record = records[key] else {
            return .invalid
        }
        guard now <= record.expiresAt else {
            return .expired
        }
        guard bridgeEnabled else {
            return .bridgeDisabled
        }
        return .valid
    }

    func describeActiveGrants(projectRootKey: String, now: TimeInterval) -> String {
        let root = projectRootKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return "" }
        let active = records.values
            .filter { $0.projectRootKey == root && now <= $0.expiresAt }
            .sorted { lhs, rhs in
                if lhs.expiresAt != rhs.expiresAt { return lhs.expiresAt < rhs.expiresAt }
                return lhs.grantId.localizedCaseInsensitiveCompare(rhs.grantId) == .orderedAscending
            }
        guard !active.isEmpty else { return "" }

        let lines = active.prefix(8).map { record in
            let remaining = Int(max(0, ceil(record.expiresAt - now)))
            return "- grant=\(record.grantId) capability=\(record.capability.lowercased()) remaining=\(remaining)s"
        }
        return lines.joined(separator: "\n")
    }

    private func trimIfNeeded(now: TimeInterval) {
        // Keep expired records for a while to return a deterministic "expired" code on replay.
        let expiredRetention: TimeInterval = 24 * 3600
        records = records.filter { _, record in
            if now <= record.expiresAt {
                return true
            }
            return (now - record.expiresAt) <= expiredRetention
        }

        guard records.count > maxRecords else { return }
        let sorted = records.values.sorted { lhs, rhs in
            if lhs.expiresAt != rhs.expiresAt { return lhs.expiresAt < rhs.expiresAt }
            if lhs.issuedAt != rhs.issuedAt { return lhs.issuedAt < rhs.issuedAt }
            return lhs.grantId.localizedCaseInsensitiveCompare(rhs.grantId) == .orderedAscending
        }
        let dropCount = records.count - maxRecords
        for record in sorted.prefix(dropCount) {
            records.removeValue(forKey: makeKey(root: record.projectRootKey, capability: record.capability, grantId: record.grantId))
        }
    }

    private func makeKey(root: String, capability: String, grantId: String) -> String {
        "\(root)|\(capability.lowercased())|\(grantId.lowercased())"
    }

    private func normalizedGrant(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
