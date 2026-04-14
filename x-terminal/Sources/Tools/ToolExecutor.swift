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

    private struct LocalSkillCatalogIndexSnapshot: Decodable {
        struct Skill: Decodable {
            var skillID: String
            var name: String
            var version: String
            var description: String
            var publisherID: String
            var capabilitiesRequired: [String]
            var sourceID: String
            var packageSHA256: String
            var installHint: String
            var riskLevel: String
            var requiresGrant: Bool
            var sideEffectClass: String

            enum CodingKeys: String, CodingKey {
                case skillID = "skill_id"
                case name
                case version
                case description
                case publisherID = "publisher_id"
                case capabilitiesRequired = "capabilities_required"
                case sourceID = "source_id"
                case packageSHA256 = "package_sha256"
                case installHint = "install_hint"
                case riskLevel = "risk_level"
                case requiresGrant = "requires_grant"
                case sideEffectClass = "side_effect_class"
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                skillID = try container.decode(String.self, forKey: .skillID)
                name = try container.decode(String.self, forKey: .name)
                version = try container.decode(String.self, forKey: .version)
                description = try container.decode(String.self, forKey: .description)
                publisherID = try container.decode(String.self, forKey: .publisherID)
                capabilitiesRequired = try container.decodeIfPresent([String].self, forKey: .capabilitiesRequired) ?? []
                sourceID = try container.decode(String.self, forKey: .sourceID)
                packageSHA256 = try container.decodeIfPresent(String.self, forKey: .packageSHA256) ?? ""
                installHint = try container.decodeIfPresent(String.self, forKey: .installHint) ?? ""
                riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel) ?? "low"
                requiresGrant = try container.decodeIfPresent(Bool.self, forKey: .requiresGrant) ?? false
                sideEffectClass = try container.decodeIfPresent(String.self, forKey: .sideEffectClass) ?? ""
            }
        }

        var updatedAtMs: Int64
        var skills: [Skill]

        enum CodingKeys: String, CodingKey {
            case updatedAtMs = "updated_at_ms"
            case skills
        }
    }

    private enum SummarizeSourceKind: String {
        case url
        case path
        case text
    }

    private struct SummarizeLoadedSource {
        var kind: SummarizeSourceKind
        var title: String
        var text: String
        var summary: [String: JSONValue]
    }

    private struct SelfImprovementIncidentPayload: Decodable {
        var events: [XTReadyIncidentEvent]
    }

    private struct UIObservationProof: Equatable {
        var selectorSignature: String
        var observedAt: TimeInterval
        var matchCount: Int
    }

    private struct BrowserSecretFillRequest: Equatable {
        var secretReferenceRequested: Bool
        var plaintextInput: String?
        var inputChars: Int
        var selector: String?
        var fieldRole: String?
        var secretItemId: String?
        var secretScope: String?
        var secretName: String?
        var secretProjectId: String?

        var hasSecretReference: Bool {
            secretReferenceRequested || hasValidSecretReference
        }

        var hasValidSecretReference: Bool {
            secretItemId != nil || (secretScope != nil && secretName != nil)
        }

        var requiresSecretRefOnly: Bool {
            guard plaintextInput != nil else { return false }
            if let fieldRole, Self.sensitiveFieldRoles.contains(fieldRole) {
                return true
            }
            let selectorToken = selector?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return !selectorToken.isEmpty && Self.sensitiveSelectorTokens.contains(where: { selectorToken.contains($0) })
        }

        private static let sensitiveFieldRoles: Set<String> = [
            "password",
            "passcode",
            "otp",
            "mfa",
            "token",
            "secret",
            "credential",
            "auth_code",
            "verification_code",
            "payment",
            "cvv",
            "card_number"
        ]

        private static let sensitiveSelectorTokens: [String] = [
            "password",
            "passcode",
            "otp",
            "token",
            "secret",
            "auth",
            "verification",
            "cvv",
            "cardnumber",
            "card-number"
        ]
    }

    private struct BrowserSecretResolvedValue {
        var source: String
        var leaseId: String?
        var itemId: String?
        var plaintext: String
    }

    private struct BrowserSecretResolutionFailure: Error {
        var rejectCode: XTDeviceAutomationRejectCode
        var detail: String
        var body: String
        var source: String?
        var reasonCode: String?
        var resolutionDetail: String?
        var itemId: String?
        var leaseId: String?
    }

    private struct BrowserSecretFillExecutionFailure: Error {
        var rejectCode: XTDeviceAutomationRejectCode
        var detail: String
        var body: String
        var reasonCode: String?
    }

    private struct BrowserSecretFillOutput {
        var excerpt: String
        var tagName: String?
    }

    private struct BrowserSecretDriverResponse: Decodable {
        var ok: Bool?
        var reason: String?
        var selector: String?
        var tagName: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case reason
            case selector
            case tagName = "tag_name"
        }
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

    static func execute(
        call: ToolCall,
        projectRoot: URL,
        extraReadableRoots: [URL] = [],
        stream: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> ToolResult {
        let ctx = AXProjectContext(root: projectRoot)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: projectRoot)
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        if !isDeviceAutomationTool(call.tool) {
            let runtimePolicyDecision = xtToolRuntimePolicyDecision(
                call: call,
                projectRoot: projectRoot,
                config: config,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
            )
            if !runtimePolicyDecision.allowed {
                return deniedRuntimePolicyResult(
                    call: call,
                    projectRoot: projectRoot,
                    config: config,
                    decision: runtimePolicyDecision,
                    effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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
            let useSandbox = shouldUseSandbox(call) && extraReadableRoots.isEmpty
            if useSandbox {
                let sandboxManager = await MainActor.run { SandboxManager.shared }
                let sandbox = try await sandboxManager.createSandbox(forProjectRoot: projectRoot)
                let s = try await sandbox.readFile(path: path)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "sandbox: true\n" + s)
            }
            let allowedRoots = governedReadableRoots(
                projectRoot: projectRoot,
                config: config,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy,
                extraReadableRoots: extraReadableRoots
            )
            do {
                let s = try FileTool.readText(
                    path: path,
                    projectRoot: projectRoot,
                    allowedRoots: allowedRoots
                )
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: s)
            } catch let violation as XTPathScopeViolation {
                return deniedPathScopeResult(
                    call: call,
                    projectRoot: projectRoot,
                    violation: violation
                )
            }

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
            do {
                try FileTool.writeText(path: path, content: content, projectRoot: projectRoot)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
            } catch let violation as XTPathScopeViolation {
                return deniedPathScopeResult(
                    call: call,
                    projectRoot: projectRoot,
                    violation: violation
                )
            }

        case .delete_path:
            if shouldUseSandbox(call) {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: "sandbox_not_supported_for_delete_path",
                        extra: [:]
                    )
                )
            }
            let path = strArg(call, "path")
            let recursive = optBoolArg(call, "recursive") ?? false
            let force = optBoolArg(call, "force") ?? false
            do {
                let deleted = try FileTool.deletePath(
                    path: path,
                    projectRoot: projectRoot,
                    recursive: recursive,
                    force: force
                )
                let relativePath = relativeDisplayPath(deleted.path, projectRoot: projectRoot)
                let summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(true),
                    "path": .string(relativePath),
                    "deleted": .bool(deleted.deleted),
                    "target_type": .string(deleted.targetType),
                    "recursive": .bool(recursive),
                    "force": .bool(force),
                ]
                let body = deleted.deleted
                    ? "delete_path completed: \(relativePath)"
                    : "delete_path no-op: \(relativePath) already missing"
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
            } catch let violation as XTPathScopeViolation {
                return deniedPathScopeResult(
                    call: call,
                    projectRoot: projectRoot,
                    violation: violation
                )
            } catch {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: error.localizedDescription,
                        extra: ["path": .string(path)]
                    )
                )
            }

        case .move_path:
            if shouldUseSandbox(call) {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: "sandbox_not_supported_for_move_path",
                        extra: [:]
                    )
                )
            }
            let fromPath = strArg(call, "from")
            let toPath = strArg(call, "to")
            let overwrite = optBoolArg(call, "overwrite") ?? false
            let createDirs = optBoolArg(call, "create_dirs") ?? true
            do {
                let moved = try FileTool.movePath(
                    from: fromPath,
                    to: toPath,
                    projectRoot: projectRoot,
                    createDirs: createDirs,
                    overwrite: overwrite
                )
                let relativeFrom = relativeDisplayPath(moved.fromPath, projectRoot: projectRoot)
                let relativeTo = relativeDisplayPath(moved.toPath, projectRoot: projectRoot)
                let summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(true),
                    "from": .string(relativeFrom),
                    "to": .string(relativeTo),
                    "target_type": .string(moved.targetType),
                    "overwrite": .bool(overwrite),
                    "create_dirs": .bool(createDirs),
                ]
                let body = "move_path completed: \(relativeFrom) -> \(relativeTo)"
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
            } catch let violation as XTPathScopeViolation {
                return deniedPathScopeResult(
                    call: call,
                    projectRoot: projectRoot,
                    violation: violation
                )
            } catch {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: error.localizedDescription,
                        extra: [
                            "from": .string(fromPath),
                            "to": .string(toPath),
                        ]
                    )
                )
            }

        case .list_dir:
            let path = strArg(call, "path")
            let useSandbox = shouldUseSandbox(call) && extraReadableRoots.isEmpty
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
            let allowedRoots = governedReadableRoots(
                projectRoot: projectRoot,
                config: config,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy,
                extraReadableRoots: extraReadableRoots
            )
            do {
                let items = try FileTool.listDir(
                    path: path,
                    projectRoot: projectRoot,
                    allowedRoots: allowedRoots
                )
                let output = items.isEmpty ? "(empty)" : items.joined(separator: "\n")
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: output)
            } catch let violation as XTPathScopeViolation {
                return deniedPathScopeResult(
                    call: call,
                    projectRoot: projectRoot,
                    violation: violation
                )
            }

        case .search:
            let pattern = strArg(call, "pattern")
            let path = optStrArg(call, "path") ?? "."
            let glob = optStrArg(call, "glob")
            let useSandbox = shouldUseSandbox(call) && extraReadableRoots.isEmpty
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
            let allowedRoots = governedReadableRoots(
                projectRoot: projectRoot,
                config: config,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy,
                extraReadableRoots: extraReadableRoots
            )
            do {
                let lines = try FileTool.search(
                    pattern: pattern,
                    path: path,
                    projectRoot: projectRoot,
                    allowedRoots: allowedRoots,
                    glob: glob
                )
                let out = lines.isEmpty ? "(no matches)" : lines.joined(separator: "\n")
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: out)
            } catch let violation as XTPathScopeViolation {
                return deniedPathScopeResult(
                    call: call,
                    projectRoot: projectRoot,
                    violation: violation
                )
            }

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

        case .process_start:
            let command = strArg(call, "command")
            let processId = optStrArg(call, "process_id")
            let name = optStrArg(call, "name")
            let cwd = optStrArg(call, "cwd")
            let restartOnExit = optBoolArg(call, "restart_on_exit") ?? false
            let env = managedProcessEnv(call)
            do {
                let record = try await XTManagedProcessStore.shared.start(
                    projectRoot: projectRoot,
                    processId: processId,
                    name: name,
                    command: command,
                    cwd: cwd,
                    env: env,
                    restartOnExit: restartOnExit
                )
                let summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(true),
                    "process": .object(managedProcessSummaryObject(record, projectRoot: projectRoot)),
                ]
                let body = "process_start completed: \(record.processId) pid=\(record.pid ?? 0) cwd=\(record.cwd)"
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
            } catch {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: error.localizedDescription,
                        extra: [
                            "command": .string(command),
                            "process_id": processId.map(JSONValue.string) ?? .null,
                        ]
                    )
                )
            }

        case .process_status:
            let processId = optStrArg(call, "process_id")
            let includeExited = optBoolArg(call, "include_exited") ?? false
            let records = await XTManagedProcessStore.shared.status(
                projectRoot: projectRoot,
                processId: processId,
                includeExited: includeExited
            )
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(true),
                "process_count": .number(Double(records.count)),
                "running_count": .number(Double(records.filter { $0.status == .running || $0.status == .restarting || $0.status == .starting }.count)),
                "processes": .array(records.map { .object(managedProcessSummaryObject($0, projectRoot: projectRoot)) }),
            ]
            let body = records.isEmpty
                ? "(no managed processes)"
                : records.map { managedProcessStatusLine($0) }.joined(separator: "\n")
            return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))

        case .process_logs:
            let processId = strArg(call, "process_id")
            let tailLines = max(1, min(400, Int(optDoubleArg(call, "tail_lines") ?? 80)))
            let maxBytes = max(1_024, min(512_000, Int(optDoubleArg(call, "max_bytes") ?? 64_000)))
            do {
                let response = try await XTManagedProcessStore.shared.logs(
                    projectRoot: projectRoot,
                    processId: processId,
                    tailLines: tailLines,
                    maxBytes: maxBytes
                )
                let summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(true),
                    "process": .object(managedProcessSummaryObject(response.record, projectRoot: projectRoot)),
                    "tail_lines": .number(Double(tailLines)),
                    "max_bytes": .number(Double(maxBytes)),
                    "truncated": .bool(response.truncated),
                ]
                let body = response.text.isEmpty ? "(empty log)" : response.text
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
            } catch {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: error.localizedDescription,
                        extra: ["process_id": .string(processId)]
                    )
                )
            }

        case .process_stop:
            let processId = strArg(call, "process_id")
            let force = optBoolArg(call, "force") ?? false
            do {
                let record = try await XTManagedProcessStore.shared.stop(
                    projectRoot: projectRoot,
                    processId: processId,
                    force: force
                )
                let summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(true),
                    "process": .object(managedProcessSummaryObject(record, projectRoot: projectRoot)),
                    "force": .bool(force),
                ]
                let body = "process_stop completed: \(record.processId) status=\(record.status.rawValue)"
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
            } catch {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: error.localizedDescription,
                        extra: ["process_id": .string(processId)]
                    )
                )
            }

        case .git_status:
            let res = try GitTool.status(root: projectRoot)
            return ToolResult(id: call.id, tool: call.tool, ok: res.exitCode == 0, output: res.combined.isEmpty ? "(clean)" : res.combined)

        case .git_diff:
            let cached = optBoolArg(call, "cached") ?? false
            let res = try GitTool.diff(root: projectRoot, cached: cached)
            return ToolResult(id: call.id, tool: call.tool, ok: res.exitCode == 0, output: res.combined.isEmpty ? "(empty diff)" : res.combined)

        case .git_commit:
            let message = strArg(call, "message")
            let all = optBoolArg(call, "all") ?? false
            let allowEmpty = optBoolArg(call, "allow_empty") ?? false
            let paths = stringArrayArg(call, "paths")
            do {
                let commit = try GitTool.commit(
                    root: projectRoot,
                    message: message,
                    all: all,
                    allowEmpty: allowEmpty,
                    paths: paths
                )
                var summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(commit.result.exitCode == 0),
                    "message": .string(message),
                    "all": .bool(all),
                    "allow_empty": .bool(allowEmpty),
                    "paths": .array(paths.map(JSONValue.string)),
                ]
                if let failure = commit.inferredFailure {
                    summary["reason_code"] = .string(failure.reasonCode)
                    summary["failure_stage"] = .string(failure.failureStage)
                    if let diagnostic = failure.diagnostic, !diagnostic.isEmpty {
                        summary["diagnostic"] = .string(diagnostic)
                    }
                }
                let body = "exit: \(commit.result.exitCode)\n" + (commit.result.combined.isEmpty ? "(no output)" : commit.result.combined)
                return ToolResult(id: call.id, tool: call.tool, ok: commit.result.exitCode == 0, output: structuredOutput(summary: summary, body: body))
            } catch let failure as GitToolFailure {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(
                        summary: [
                            "tool": .string(call.tool.rawValue),
                            "ok": .bool(false),
                            "message": .string(message),
                            "all": .bool(all),
                            "allow_empty": .bool(allowEmpty),
                            "paths": .array(paths.map(JSONValue.string)),
                            "reason_code": .string(failure.reasonCode),
                            "failure_stage": .string(failure.failureStage),
                        ],
                        body: failure.diagnostic.map { failure.detail + "\n" + $0 } ?? failure.detail
                    )
                )
            } catch let violation as XTPathScopeViolation {
                return deniedPathScopeResult(
                    call: call,
                    projectRoot: projectRoot,
                    violation: violation
                )
            }

        case .git_push:
            let remote = optStrArg(call, "remote")
            let branch = optStrArg(call, "branch")
            let setUpstream = optBoolArg(call, "set_upstream") ?? false
            do {
                let push = try GitTool.push(
                    root: projectRoot,
                    remote: remote,
                    branch: branch,
                    setUpstream: setUpstream
                )
                var summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(push.result.exitCode == 0),
                    "remote": .string(push.remote),
                    "branch": .string(push.branch),
                    "set_upstream": .bool(setUpstream),
                ]
                if let failure = push.inferredFailure {
                    summary["reason_code"] = .string(failure.reasonCode)
                    summary["failure_stage"] = .string(failure.failureStage)
                    if let diagnostic = failure.diagnostic, !diagnostic.isEmpty {
                        summary["diagnostic"] = .string(diagnostic)
                    }
                }
                let body = "exit: \(push.result.exitCode)\n" + (push.result.combined.isEmpty ? "(no output)" : push.result.combined)
                return ToolResult(id: call.id, tool: call.tool, ok: push.result.exitCode == 0, output: structuredOutput(summary: summary, body: body))
            } catch let failure as GitToolFailure {
                var summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(false),
                    "set_upstream": .bool(setUpstream),
                    "reason_code": .string(failure.reasonCode),
                    "failure_stage": .string(failure.failureStage),
                ]
                if let remote, !remote.isEmpty {
                    summary["remote"] = .string(remote)
                }
                if let branch, !branch.isEmpty {
                    summary["branch"] = .string(branch)
                }
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(
                        summary: summary,
                        body: failure.diagnostic.map { failure.detail + "\n" + $0 } ?? failure.detail
                    )
                )
            } catch {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: error.localizedDescription,
                        extra: [:]
                    )
                )
            }

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

        case .pr_create:
            let title = optStrArg(call, "title")
            let body = optStrArg(call, "body")
            let base = optStrArg(call, "base")
            let head = optStrArg(call, "head")
            let draft = optBoolArg(call, "draft") ?? false
            let fill = optBoolArg(call, "fill") ?? false
            let labels = stringArrayArg(call, "labels")
            let reviewers = stringArrayArg(call, "reviewers")
            let result = try GitHubTool.prCreate(
                root: projectRoot,
                title: title,
                body: body,
                base: base,
                head: head,
                draft: draft,
                fill: fill,
                labels: labels,
                reviewers: reviewers
            )
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: jsonBoolValue(result.structuredSummary["ok"]) ?? false,
                output: structuredOutput(summary: result.structuredSummary, body: result.output)
            )

        case .ci_read:
            let provider = (optStrArg(call, "provider") ?? "github").lowercased()
            guard provider == "github" else {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: "unsupported_ci_provider",
                        extra: ["provider": .string(provider)]
                    )
                )
            }
            let result = try GitHubTool.ciRead(
                root: projectRoot,
                workflow: optStrArg(call, "workflow"),
                branch: optStrArg(call, "branch"),
                commit: optStrArg(call, "commit"),
                limit: Int(optDoubleArg(call, "limit") ?? 10)
            )
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: jsonBoolValue(result.structuredSummary["ok"]) ?? false,
                output: structuredOutput(summary: result.structuredSummary, body: result.output)
            )

        case .ci_trigger:
            let provider = (optStrArg(call, "provider") ?? "github").lowercased()
            guard provider == "github" else {
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: wrappedFailureOutput(
                        tool: call.tool,
                        body: "unsupported_ci_provider",
                        extra: ["provider": .string(provider)]
                    )
                )
            }
            let inputs = jsonObject(call.args["inputs"]) ?? [:]
            let result = try GitHubTool.ciTrigger(
                root: projectRoot,
                workflow: strArg(call, "workflow"),
                ref: optStrArg(call, "ref"),
                inputs: inputs
            )
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: jsonBoolValue(result.structuredSummary["ok"]) ?? false,
                output: structuredOutput(summary: result.structuredSummary, body: result.output)
            )

        case .session_list:
            return await executeSessionList(call: call, projectRoot: projectRoot)

        case .session_resume:
            return await executeSessionResume(call: call, projectRoot: projectRoot)

        case .session_compact:
            return await executeSessionCompact(call: call, projectRoot: projectRoot)

        case .agentImportRecord:
            return await executeAgentImportRecord(call: call, projectRoot: projectRoot)

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

        case .skills_search:
            return await executeSkillsSearch(call: call, projectRoot: projectRoot)

        case .skills_pin:
            return await executeSkillsPin(call: call, projectRoot: projectRoot)

        case .summarize:
            return try await executeSummarize(call: call, projectRoot: projectRoot)

        case .supervisorVoicePlayback:
            return await executeSupervisorVoicePlayback(call: call)

        case .run_local_task:
            return await executeRunLocalTask(call: call)

        case .need_network:
            let seconds = max(60, Int(optDoubleArg(call, "seconds") ?? 900))
            let reason = optStrArg(call, "reason")
            let reasonText = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = reasonText.isEmpty ? "" : " reason=\(reasonText)"
            let access = await HubIPCClient.requestNetworkAccess(root: projectRoot, seconds: seconds, reason: reason)
            let route = access.source.lowercased()
            let accessDetail = (access.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let accessDetailSuffix = accessDetail.isEmpty ? "" : " detail=\(accessDetail)"
            var activeGrantId: String?
            switch access.state {
            case .enabled, .autoApproved:
                activeGrantId = await noteActiveHighRiskGrant(
                    projectRoot: projectRoot,
                    capability: .webFetch,
                    grantRequestId: access.grantRequestId,
                    approvedGrantId: nil,
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
                let out = why == "denied"
                    ? "network_denied\(accessDetailSuffix)"
                    : "network_denied (\(why))\(accessDetailSuffix)"
                return ToolResult(id: call.id, tool: call.tool, ok: false, output: out)

            case .failed:
                let why = HubIPCClient.normalizedReasonCode(access.reasonCode, fallback: "grant_failed") ?? "grant_failed"
                if why == "hub_not_connected" {
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: false,
                        output: "hub_not_connected (cannot request network)\(accessDetailSuffix)"
                    )
                }
                if route == "grpc" {
                    let out = why == "grant_failed"
                        ? "network_grpc_grant_failed\(accessDetailSuffix)"
                        : "network_grpc_grant_failed (\(why))\(accessDetailSuffix)"
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: out)
                }
                let out = why == "grant_failed"
                    ? "network_request_failed\(accessDetailSuffix)"
                    : "network_request_failed (\(why))\(accessDetailSuffix)"
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

        @unknown default:
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: "unsupported_tool (\(call.tool.rawValue))"
            )
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
            title: AXProjectRegistryStore.displayName(forRoot: projectRoot),
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
        let retrospective = optBoolArg(call, "retrospective") ?? false
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
            displayName: AXProjectRegistryStore.displayName(forRoot: projectRoot),
            latestUser: "(memory_snapshot_tool)",
            constitutionHint: nil,
            canonicalText: nil,
            observationsText: nil,
            workingSetText: nil,
            rawEvidenceText: nil,
            progressiveDisclosure: useMode == .projectChat || useMode == .supervisorOrchestration,
            budgets: nil,
            timeoutSec: 2.0
        )

        if retrospective {
            let focus = optStrArg(call, "focus") ?? ""
            let limit = max(1, min(8, Int(optDoubleArg(call, "limit") ?? 5)))
            let includeDoctor = optBoolArg(call, "include_doctor") ?? true
            let includeIncidents = optBoolArg(call, "include_incidents") ?? true
            let includeSkillCalls = optBoolArg(call, "include_skill_calls") ?? true
            let includePlan = optBoolArg(call, "include_plan") ?? true
            let includeMemory = optBoolArg(call, "include_memory") ?? true
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: renderSelfImprovementMemorySnapshotOutput(
                    response: response,
                    projectRoot: projectRoot,
                    projectId: projectId,
                    mode: useMode.rawValue,
                    focus: focus,
                    limit: limit,
                    includeDoctor: includeDoctor,
                    includeIncidents: includeIncidents,
                    includeSkillCalls: includeSkillCalls,
                    includePlan: includePlan,
                    includeMemory: includeMemory
                )
            )
        }

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
            "requested_profile": response.requestedProfile.map(JSONValue.string) ?? .null,
            "resolved_profile": response.resolvedProfile.map(JSONValue.string) ?? .null,
            "attempted_profiles": .array((response.attemptedProfiles ?? []).map(JSONValue.string)),
            "progressive_upgrade_count": response.progressiveUpgradeCount.map { .number(Double($0)) } ?? .null,
            "longterm_mode": response.longtermMode.map(JSONValue.string) ?? .null,
            "retrieval_available": response.retrievalAvailable.map(JSONValue.bool) ?? .null,
            "fulltext_not_loaded": response.fulltextNotLoaded.map(JSONValue.bool) ?? .null,
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

    private static func renderSelfImprovementMemorySnapshotOutput(
        response: HubIPCClient.MemoryContextResponsePayload?,
        projectRoot: URL,
        projectId: String,
        mode: String,
        focus: String,
        limit: Int,
        includeDoctor: Bool,
        includeIncidents: Bool,
        includeSkillCalls: Bool,
        includePlan: Bool,
        includeMemory: Bool
    ) -> String {
        let ctx = AXProjectContext(root: projectRoot)
        let localMemory = includeMemory ? (try? AXProjectStore.loadOrCreateMemory(for: ctx)) : nil

        let jobsSnapshot = includePlan ? SupervisorProjectJobStore.load(for: ctx) : SupervisorProjectJobSnapshot(
            schemaVersion: SupervisorProjectJobSnapshot.currentSchemaVersion,
            updatedAtMs: 0,
            jobs: []
        )
        let plansSnapshot = includePlan ? SupervisorProjectPlanStore.load(for: ctx) : SupervisorProjectPlanSnapshot(
            schemaVersion: SupervisorProjectPlanSnapshot.currentSchemaVersion,
            updatedAtMs: 0,
            plans: []
        )
        let skillCallsSnapshot = includeSkillCalls ? SupervisorProjectSkillCallStore.load(for: ctx) : SupervisorProjectSkillCallSnapshot(
            schemaVersion: SupervisorProjectSkillCallSnapshot.currentSchemaVersion,
            updatedAtMs: 0,
            calls: []
        )

        let activeJob = jobsSnapshot.jobs.first
        let activePlan = activeJob.flatMap { job in
            plansSnapshot.plans.first(where: { $0.planId == job.activePlanId && $0.jobId == job.jobId })
        } ?? plansSnapshot.plans.first

        let interestingSkillCalls = skillCallsSnapshot.calls.filter { call in
            switch call.status {
            case .awaitingAuthorization, .failed, .blocked, .running:
                return true
            case .queued, .completed, .canceled:
                return false
            }
        }
        let sampledSkillCalls = Array(interestingSkillCalls.prefix(limit))
        let failedSkillCallCount = skillCallsSnapshot.calls.filter { $0.status == .failed || $0.status == .blocked }.count
        let awaitingAuthorizationSkillCallCount = skillCallsSnapshot.calls.filter { $0.status == .awaitingAuthorization }.count

        let interestingPlanSteps = (activePlan?.steps ?? []).filter { step in
            switch step.status {
            case .running, .blocked, .awaitingAuthorization, .failed:
                return true
            case .pending, .completed, .canceled:
                return false
            }
        }
        let sampledPlanSteps = Array(interestingPlanSteps.prefix(limit))
        let blockedPlanStepCount = (activePlan?.steps ?? []).filter { $0.status == .blocked || $0.status == .failed }.count

        let doctorReport = includeDoctor ? loadSelfImprovementDoctorReport(projectRoot: projectRoot) : nil
        let incidentEvents = includeIncidents ? loadSelfImprovementIncidentEvents(projectRoot: projectRoot) : []
        let requiredIncidentCodes = ["grant_pending", "awaiting_instruction", "runtime_error"]
        let incidentCodesPresent = Set(incidentEvents.map(\.incidentCode))
        let missingIncidentCodes = includeIncidents
            ? requiredIncidentCodes.filter { !incidentCodesPresent.contains($0) }
            : []

        var signalLines: [String] = []
        for call in sampledSkillCalls {
            var fragments: [String] = [
                "skill \(call.skillId) [\(call.status.rawValue)]"
            ]
            if let capability = call.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines),
               !capability.isEmpty {
                fragments.append("capability=\(capability)")
            }
            let summary = call.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                fragments.append(capped(summary, maxChars: 140))
            }
            signalLines.append(fragments.joined(separator: " | "))
        }
        for step in sampledPlanSteps {
            let detail = step.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = detail.isEmpty ? "" : " | \(capped(detail, maxChars: 140))"
            signalLines.append("plan_step \(step.stepId) [\(step.status.rawValue)] \(step.title)\(suffix)")
        }
        if let report = doctorReport {
            for finding in report.findings.filter({ $0.severity == .blocking || $0.severity == .warning }).prefix(limit) {
                signalLines.append("doctor \(finding.code) [\(finding.severity.rawValue)] \(capped(finding.title, maxChars: 140))")
            }
        } else if includeDoctor {
            signalLines.append("doctor report missing at .axcoder/reports/supervisor_doctor_report.json")
        }
        if includeIncidents {
            if incidentEvents.isEmpty {
                signalLines.append("incident export missing or empty at .axcoder/reports/xt_ready_incident_events.runtime.json")
            } else if !missingIncidentCodes.isEmpty {
                signalLines.append("incident readiness missing codes: \(missingIncidentCodes.joined(separator: ", "))")
            }
        }
        signalLines = Array(signalLines.prefix(limit))

        var recommendations: [String] = []
        if awaitingAuthorizationSkillCallCount > 0 {
            let capabilities = sampledSkillCalls
                .compactMap { $0.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let capabilityText = capabilities.isEmpty ? "required capabilities" : Array(Set(capabilities)).sorted().joined(separator: ", ")
            recommendations.append("Preflight or pre-approve \(capabilityText) before long-running skill calls so the supervisor does not stall on authorization.")
        }
        if failedSkillCallCount > 0 {
            let failingSkills = skillCallsSnapshot.calls
                .filter { $0.status == .failed || $0.status == .blocked }
                .map(\.skillId)
            let skillText = Array(Set(failingSkills)).sorted().joined(separator: ", ")
            recommendations.append("Add contract tests and payload validation for failing skills\(skillText.isEmpty ? "" : " (\(skillText))") before dispatch reaches runtime.")
        }
        if blockedPlanStepCount > 0 {
            recommendations.append("Update the active plan so blocked steps carry explicit retry or fallback owners instead of remaining in an ambiguous blocked state.")
        }
        if let report = doctorReport,
           report.summary.blockingCount > 0,
           let finding = report.findings.first(where: { $0.severity == .blocking }) {
            let action = finding.actions.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "resolve the top blocking doctor finding"
            recommendations.append("Fix doctor finding \(finding.code) first: \(capped(action, maxChars: 180)).")
        }
        if includeIncidents, !missingIncidentCodes.isEmpty {
            recommendations.append("Restore XT-ready incident coverage for \(missingIncidentCodes.joined(separator: ", ")) so automated takeover remains observable and auditable.")
        }
        if recommendations.isEmpty {
            recommendations.append("No active blocking signals were found. Capture this working recipe as a pinned Agent baseline and keep the same governance defaults.")
        }
        recommendations = Array(recommendations.prefix(limit))

        let memoryCueLines = buildSelfImprovementMemoryCueLines(
            localMemory: localMemory,
            response: response,
            limit: min(3, limit)
        )

        let memorySource = response?.source ?? (localMemory == nil ? "unavailable" : "local_overlay_only")
        let memorySourceLabel = XTMemorySourceTruthPresentation.label(memorySource)
        let memorySourceClass = XTMemorySourceTruthPresentation.sourceClass(memorySource)
        var summary: [String: JSONValue] = [
            "tool": .string(ToolName.memory_snapshot.rawValue),
            "ok": .bool(true),
            "project_id": .string(projectId),
            "mode": .string(mode),
            "analysis_profile": .string("self_improvement"),
            "focus": .string(focus),
            "source": .string(memorySource),
            "source_label": .string(memorySourceLabel),
            "source_class": .string(memorySourceClass),
            "resolved_mode": response?.resolvedMode.map(JSONValue.string) ?? .null,
            "resolved_profile": response?.resolvedProfile.map(JSONValue.string) ?? .null,
            "longterm_mode": response?.longtermMode.map(JSONValue.string) ?? .null,
            "retrieval_available": response?.retrievalAvailable.map(JSONValue.bool) ?? .null,
            "fulltext_not_loaded": response?.fulltextNotLoaded.map(JSONValue.bool) ?? .null,
            "freshness": response?.freshness.map(JSONValue.string) ?? .null,
            "cache_hit": response?.cacheHit.map(JSONValue.bool) ?? .null,
            "skill_signal_count": .number(Double(sampledSkillCalls.count)),
            "failed_skill_call_count": .number(Double(failedSkillCallCount)),
            "awaiting_authorization_skill_call_count": .number(Double(awaitingAuthorizationSkillCallCount)),
            "blocked_plan_step_count": .number(Double(blockedPlanStepCount)),
            "doctor_blocking_count": .number(Double(doctorReport?.summary.blockingCount ?? 0)),
            "doctor_warning_count": .number(Double(doctorReport?.summary.warningCount ?? 0)),
            "incident_event_count": .number(Double(incidentEvents.count)),
            "incident_missing_codes": .array(missingIncidentCodes.map(JSONValue.string)),
            "recommendation_count": .number(Double(recommendations.count)),
            "memory_available": .bool(response != nil || localMemory != nil),
        ]
        if let activeJob {
            summary["active_job_status"] = .string(activeJob.status.rawValue)
            summary["active_job_goal"] = .string(capped(activeJob.goal, maxChars: 180))
        }
        if let activePlan {
            summary["active_plan_status"] = .string(activePlan.status.rawValue)
            summary["active_plan_id"] = .string(activePlan.planId)
        }

        let projectDisplayName = AXProjectRegistryStore.displayName(forRoot: projectRoot)
        var lines: [String] = ["Self Improvement Report", "project: \(projectDisplayName)"]
        if !focus.isEmpty {
            lines.append("focus: \(focus)")
        }
        var memoryLine = "memory: \(memorySourceLabel)"
        if let freshness = response?.freshness?.trimmingCharacters(in: .whitespacesAndNewlines),
           !freshness.isEmpty {
            memoryLine += " (freshness=\(freshness))"
        }
        lines.append(memoryLine)
        if let goal = localMemory?.goal.trimmingCharacters(in: .whitespacesAndNewlines),
           !goal.isEmpty {
            lines.append("goal: \(capped(goal, maxChars: 180))")
        }
        if let activeJob {
            lines.append("active_job: [\(activeJob.status.rawValue)] \(capped(activeJob.goal, maxChars: 180))")
        }
        if let activePlan {
            lines.append("active_plan: \(activePlan.planId) [\(activePlan.status.rawValue)]")
        }

        lines.append("")
        lines.append("Signals:")
        if signalLines.isEmpty {
            lines.append("- No blocking signals found in the sampled local artifacts.")
        } else {
            lines.append(contentsOf: signalLines.map { "- \($0)" })
        }

        lines.append("")
        lines.append("Recommendations:")
        for (index, item) in recommendations.enumerated() {
            lines.append("\(index + 1). \(item)")
        }

        if !memoryCueLines.isEmpty {
            lines.append("")
            lines.append("Memory Cues:")
            lines.append(contentsOf: memoryCueLines.map { "- \($0)" })
        }

        return structuredOutput(summary: summary, body: lines.joined(separator: "\n"))
    }

    private static func buildSelfImprovementMemoryCueLines(
        localMemory: AXMemory?,
        response: HubIPCClient.MemoryContextResponsePayload?,
        limit: Int
    ) -> [String] {
        var lines: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard seen.insert(trimmed).inserted else { return }
            lines.append(trimmed)
        }

        if let localMemory {
            let goal = localMemory.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !goal.isEmpty {
                append("local_goal: \(capped(goal, maxChars: 160))")
            }
            if let next = localMemory.nextSteps.first {
                let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    append("local_next: \(capped(trimmed, maxChars: 160))")
                }
            }
            if let risk = localMemory.risks.first ?? localMemory.openQuestions.first {
                let trimmed = risk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    append("local_risk: \(capped(trimmed, maxChars: 160))")
                }
            }
        }

        if let text = response?.text {
            let extracted = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { !$0.hasPrefix("[") && !$0.hasPrefix("/") }
            for item in extracted.prefix(limit) {
                append("hub_memory: \(capped(item, maxChars: 160))")
            }
        }

        return Array(lines.prefix(limit))
    }

    private static func loadSelfImprovementDoctorReport(projectRoot: URL) -> SupervisorDoctorReport? {
        let reportURL = projectRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent("supervisor_doctor_report.json")
        guard let data = try? Data(contentsOf: reportURL) else {
            return nil
        }
        return try? JSONDecoder().decode(SupervisorDoctorReport.self, from: data)
    }

    private static func loadSelfImprovementIncidentEvents(projectRoot: URL) -> [XTReadyIncidentEvent] {
        let reportURL = projectRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent("xt_ready_incident_events.runtime.json")
        guard let data = try? Data(contentsOf: reportURL),
              let payload = try? JSONDecoder().decode(SelfImprovementIncidentPayload.self, from: data) else {
            return []
        }
        return payload.events
    }

    private static func executeProjectSnapshot(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let projectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let ctx = AXProjectContext(root: projectRoot)
        let registry = AXProjectRegistryStore.load()
        let entry = registry.project(for: projectId)
        let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
        let resolvedConfig = config ?? .default(forProjectRoot: projectRoot)
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: resolvedConfig
        )
        let effectiveRuntimeSurface = runtimeSurfaceState.effectivePolicy
        let resolvedGovernance = xtResolveProjectGovernance(
            projectRoot: projectRoot,
            config: resolvedConfig,
            effectiveRuntimeSurface: effectiveRuntimeSurface
        )
        let configuredRuntimeSurfaces = resolvedConfig.configuredRuntimeSurfaceLabels
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
        let runtimeSurfaceObject: JSONValue = .object([
            "configured_surface": .string(resolvedConfig.runtimeSurfaceMode.rawValue),
            "effective_surface": .string(effectiveRuntimeSurface.effectiveMode.rawValue),
            "hub_override_surface": .string(effectiveRuntimeSurface.hubOverrideMode.rawValue),
            "local_override_surface": .string(effectiveRuntimeSurface.localOverrideMode.rawValue),
            "remote_override_surface": .string(effectiveRuntimeSurface.remoteOverrideMode.rawValue),
            "remote_override_source": .string(effectiveRuntimeSurface.remoteOverrideSource),
            "remote_override_updated_at_ms": .number(Double(effectiveRuntimeSurface.remoteOverrideUpdatedAtMs)),
            "ttl_sec": .number(Double(resolvedConfig.runtimeSurfaceTTLSeconds)),
            "remaining_sec": .number(Double(effectiveRuntimeSurface.remainingSeconds)),
            "expired": .bool(effectiveRuntimeSurface.expired),
            "kill_switch_engaged": .bool(effectiveRuntimeSurface.killSwitchEngaged),
            "configured_surfaces": .array(configuredRuntimeSurfaces.map(JSONValue.string)),
            "effective_surfaces": .array(effectiveRuntimeSurface.allowedSurfaceLabels.map(JSONValue.string)),
            "updated_at_ms": .number(Double(resolvedConfig.runtimeSurfaceUpdatedAtMs)),
        ])
        let autonomyPolicyObject: JSONValue = .object([
            "configured_mode": .string(resolvedConfig.runtimeSurfaceMode.rawValue),
            "effective_mode": .string(effectiveRuntimeSurface.effectiveMode.rawValue),
            "hub_override_mode": .string(effectiveRuntimeSurface.hubOverrideMode.rawValue),
            "local_override_mode": .string(effectiveRuntimeSurface.localOverrideMode.rawValue),
            "remote_override_mode": .string(effectiveRuntimeSurface.remoteOverrideMode.rawValue),
            "remote_override_source": .string(effectiveRuntimeSurface.remoteOverrideSource),
            "remote_override_updated_at_ms": .number(Double(effectiveRuntimeSurface.remoteOverrideUpdatedAtMs)),
            "ttl_sec": .number(Double(resolvedConfig.runtimeSurfaceTTLSeconds)),
            "remaining_sec": .number(Double(effectiveRuntimeSurface.remainingSeconds)),
            "expired": .bool(effectiveRuntimeSurface.expired),
            "kill_switch_engaged": .bool(effectiveRuntimeSurface.killSwitchEngaged),
            "configured_surfaces": .array(configuredRuntimeSurfaces.map(JSONValue.string)),
            "effective_surfaces": .array(effectiveRuntimeSurface.allowedSurfaceLabels.map(JSONValue.string)),
            "updated_at_ms": .number(Double(resolvedConfig.runtimeSurfaceUpdatedAtMs)),
        ])
        let governanceObject: JSONValue = .object([
            "configured_execution_tier": .string(resolvedGovernance.configuredBundle.executionTier.rawValue),
            "effective_execution_tier": .string(resolvedGovernance.effectiveBundle.executionTier.rawValue),
            "configured_supervisor_tier": .string(resolvedGovernance.configuredBundle.supervisorInterventionTier.rawValue),
            "effective_supervisor_tier": .string(resolvedGovernance.effectiveBundle.supervisorInterventionTier.rawValue),
            "review_policy_mode": .string(resolvedGovernance.effectiveBundle.reviewPolicyMode.rawValue),
            "progress_heartbeat_sec": .number(Double(resolvedGovernance.effectiveBundle.schedule.progressHeartbeatSeconds)),
            "review_pulse_sec": .number(Double(resolvedGovernance.effectiveBundle.schedule.reviewPulseSeconds)),
            "brainstorm_review_sec": .number(Double(resolvedGovernance.effectiveBundle.schedule.brainstormReviewSeconds)),
            "event_driven_review_enabled": .bool(resolvedGovernance.effectiveBundle.schedule.eventDrivenReviewEnabled),
            "event_review_triggers": .array(resolvedGovernance.effectiveBundle.schedule.eventReviewTriggers.map { .string($0.rawValue) }),
            "compat_source": .string(resolvedGovernance.compatSource.rawValue),
            "project_memory_ceiling": .string(resolvedGovernance.projectMemoryCeiling.rawValue),
            "supervisor_review_memory_ceiling": .string(resolvedGovernance.supervisorReviewMemoryCeiling.rawValue),
            "allowed_capabilities": .array(resolvedGovernance.capabilityBundle.allowedCapabilityLabels.map(JSONValue.string)),
        ])
        let browserRuntimeSession = XTBrowserRuntimeStore.loadSession(for: ctx)
        let latestUIObservation = XTUIObservationStore.loadLatestBrowserPageReference(for: ctx)
        let latestUIReview = XTUIReviewStore.loadLatestBrowserPageReference(for: ctx)
        let browserRuntimeObject: JSONValue = {
            guard let browserRuntimeSession else { return .null }
            var object: [String: JSONValue] = [
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
            ]
            if let latestUIObservation {
                object["ui_observation_ref"] = .string(latestUIObservation.bundleRef)
                object["ui_observation_status"] = .string(latestUIObservation.captureStatus.rawValue)
                object["ui_observation_probe_depth"] = .string(latestUIObservation.probeDepth.rawValue)
                object["ui_observation_updated_at_ms"] = .number(Double(latestUIObservation.updatedAtMs))
            }
            if let latestUIReview {
                object["ui_review_ref"] = .string(latestUIReview.reviewRef)
                object["ui_review_agent_evidence_ref"] = .string(
                    XTUIReviewAgentEvidenceStore.reviewRef(reviewID: latestUIReview.reviewID)
                )
                object["ui_review_verdict"] = .string(latestUIReview.verdict.rawValue)
                object["ui_review_confidence"] = .string(latestUIReview.confidence.rawValue)
                object["ui_review_sufficient_evidence"] = .bool(latestUIReview.sufficientEvidence)
                object["ui_review_objective_ready"] = .bool(latestUIReview.objectiveReady)
                object["ui_review_issue_codes"] = .array(latestUIReview.issueCodes.map(JSONValue.string))
                object["ui_review_summary"] = .string(latestUIReview.summary)
                object["ui_review_updated_at_ms"] = .number(Double(latestUIReview.updatedAtMs))
            }
            return .object(object)
        }()
        let uiReviewObject: JSONValue = {
            guard let latestUIReview else { return .null }
            return .object([
                "review_id": .string(latestUIReview.reviewID),
                "review_ref": .string(latestUIReview.reviewRef),
                "agent_evidence_ref": .string(
                    XTUIReviewAgentEvidenceStore.reviewRef(reviewID: latestUIReview.reviewID)
                ),
                "bundle_id": .string(latestUIReview.bundleID),
                "bundle_ref": .string(latestUIReview.bundleRef),
                "verdict": .string(latestUIReview.verdict.rawValue),
                "confidence": .string(latestUIReview.confidence.rawValue),
                "sufficient_evidence": .bool(latestUIReview.sufficientEvidence),
                "objective_ready": .bool(latestUIReview.objectiveReady),
                "issue_codes": .array(latestUIReview.issueCodes.map(JSONValue.string)),
                "summary": .string(latestUIReview.summary),
                "updated_at_ms": .number(Double(latestUIReview.updatedAtMs)),
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
        let projectDisplayName = AXProjectRegistryStore.displayName(
            forRoot: projectRoot,
            registry: registry,
            preferredDisplayName: entry?.displayName
        )
        var summary: [String: JSONValue] = [:]
        summary["tool"] = .string(call.tool.rawValue)
        summary["ok"] = .bool(true)
        summary["project_id"] = .string(projectId)
        summary["display_name"] = .string(projectDisplayName)
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
        summary["governance"] = governanceObject
        summary["execution_tier"] = .string(resolvedGovernance.configuredBundle.executionTier.rawValue)
        summary["effective_execution_tier"] = .string(resolvedGovernance.effectiveBundle.executionTier.rawValue)
        summary["supervisor_intervention_tier"] = .string(resolvedGovernance.configuredBundle.supervisorInterventionTier.rawValue)
        summary["effective_supervisor_intervention_tier"] = .string(resolvedGovernance.effectiveBundle.supervisorInterventionTier.rawValue)
        summary["review_policy_mode"] = .string(resolvedGovernance.effectiveBundle.reviewPolicyMode.rawValue)
        summary["progress_heartbeat_sec"] = .number(Double(resolvedGovernance.effectiveBundle.schedule.progressHeartbeatSeconds))
        summary["review_pulse_sec"] = .number(Double(resolvedGovernance.effectiveBundle.schedule.reviewPulseSeconds))
        summary["brainstorm_review_sec"] = .number(Double(resolvedGovernance.effectiveBundle.schedule.brainstormReviewSeconds))
        summary["event_driven_review_enabled"] = .bool(resolvedGovernance.effectiveBundle.schedule.eventDrivenReviewEnabled)
        summary["event_review_triggers"] = .array(resolvedGovernance.effectiveBundle.schedule.eventReviewTriggers.map { .string($0.rawValue) })
        summary["governance_compat_source"] = .string(resolvedGovernance.compatSource.rawValue)
        summary["runtime_surface"] = runtimeSurfaceObject
        summary["autonomy_policy"] = autonomyPolicyObject
        summary["browser_runtime"] = browserRuntimeObject
        summary["ui_review"] = uiReviewObject
        summary["is_git_repo"] = .bool(isGitRepo)
        summary["git_dirty"] = .bool(isGitRepo && !gitSummary.isEmpty)
        summary["session"] = .object(sessionSummary)

        let verifyText = resolvedConfig.verifyCommands.isEmpty ? "(none)" : resolvedConfig.verifyCommands.joined(separator: " | ")
        let browserRuntimeText: String = {
            guard let browserRuntimeSession else { return "(none)" }
            let currentURL = browserRuntimeSession.currentURL.isEmpty ? "(none)" : browserRuntimeSession.currentURL
            let snapshotRef = browserRuntimeSession.snapshotRef.isEmpty ? "(none)" : browserRuntimeSession.snapshotRef
            let observationRef = latestUIObservation?.bundleRef ?? "(none)"
            let reviewRef = latestUIReview?.reviewRef ?? "(none)"
            return "session=\(browserRuntimeSession.sessionID) mode=\(browserRuntimeSession.actionMode.rawValue) url=\(currentURL) snapshot=\(snapshotRef) ui_observation=\(observationRef) ui_review=\(reviewRef)"
        }()
        let uiReviewText: String = {
            guard let latestUIReview else { return "(none)" }
            return "ref=\(latestUIReview.reviewRef) verdict=\(latestUIReview.verdict.rawValue) confidence=\(latestUIReview.confidence.rawValue) sufficient_evidence=\(latestUIReview.sufficientEvidence) summary=\(latestUIReview.summary)"
        }()
        let configuredRuntimeSurfaceText = configuredRuntimeSurfaces.isEmpty ? "(none)" : configuredRuntimeSurfaces.joined(separator: ",")
        let effectiveRuntimeSurfaceText = effectiveRuntimeSurface.allowedSurfaceLabels.isEmpty ? "(none)" : effectiveRuntimeSurface.allowedSurfaceLabels.joined(separator: ",")
        let governanceTriggerText = resolvedGovernance.effectiveBundle.schedule.eventReviewTriggers.isEmpty
            ? "(none)"
            : resolvedGovernance.effectiveBundle.schedule.eventReviewTriggers.map(\.rawValue).joined(separator: ",")
        let runtimeSurfaceRemainingText: String = {
            if effectiveRuntimeSurface.killSwitchEngaged {
                return "kill_switch"
            }
            if effectiveRuntimeSurface.expired {
                return "expired"
            }
            if resolvedConfig.runtimeSurfaceMode == .manual {
                return "n/a"
            }
            return String(effectiveRuntimeSurface.remainingSeconds)
        }()
        let body = """
project=\(projectDisplayName)
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
execution_tier=\(resolvedGovernance.configuredBundle.executionTier.rawValue)
effective_execution_tier=\(resolvedGovernance.effectiveBundle.executionTier.rawValue)
supervisor_intervention_tier=\(resolvedGovernance.configuredBundle.supervisorInterventionTier.rawValue)
effective_supervisor_intervention_tier=\(resolvedGovernance.effectiveBundle.supervisorInterventionTier.rawValue)
review_policy_mode=\(resolvedGovernance.effectiveBundle.reviewPolicyMode.rawValue)
progress_heartbeat_sec=\(resolvedGovernance.effectiveBundle.schedule.progressHeartbeatSeconds)
review_pulse_sec=\(resolvedGovernance.effectiveBundle.schedule.reviewPulseSeconds)
brainstorm_review_sec=\(resolvedGovernance.effectiveBundle.schedule.brainstormReviewSeconds)
event_driven_review_enabled=\(resolvedGovernance.effectiveBundle.schedule.eventDrivenReviewEnabled)
event_review_triggers=\(governanceTriggerText)
governance_compat_source=\(resolvedGovernance.compatSource.rawValue)
runtime_surface_configured=\(resolvedConfig.runtimeSurfaceMode.rawValue)
runtime_surface_effective=\(effectiveRuntimeSurface.effectiveMode.rawValue)
runtime_surface_hub_override=\(effectiveRuntimeSurface.hubOverrideMode.rawValue)
runtime_surface_local_override=\(effectiveRuntimeSurface.localOverrideMode.rawValue)
runtime_surface_remote_override=\(effectiveRuntimeSurface.remoteOverrideMode.rawValue)
runtime_surface_remote_override_source=\(effectiveRuntimeSurface.remoteOverrideSource.isEmpty ? "(none)" : effectiveRuntimeSurface.remoteOverrideSource)
runtime_surface_configured_surfaces=\(configuredRuntimeSurfaceText)
runtime_surface_effective_surfaces=\(effectiveRuntimeSurfaceText)
runtime_surface_ttl_remaining=\(runtimeSurfaceRemainingText)
browser_runtime=\(browserRuntimeText)
ui_review=\(uiReviewText)
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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

                let probeDepth = XTUIObservationProbeDepth.parse(optStrArg(call, "probe_depth")) ?? .standard
                var uiObservationRef = ""
                var uiObservationStatus = "failed"
                var uiObservationCapturedLayers = 0
                var uiObservationError = ""
                var uiReviewRef = ""
                var uiReviewVerdict = ""
                var uiReviewConfidence = ""
                var uiReviewSummaryText = ""
                var uiReviewSufficientEvidence = false
                var uiReviewObjectiveReady = false
                var uiReviewIssueCodes: [String] = []
                var uiReviewAgentEvidenceRef = ""
                var uiReviewError = ""
                do {
                    let stored = try await XTBrowserUIObservationProbe.capture(
                        session: session,
                        ctx: ctx,
                        permissionReadiness: permissionReadiness,
                        probeDepth: probeDepth,
                        triggerSource: "browser_snapshot_action",
                        auditRef: auditRef,
                        now: now
                    )
                    uiObservationRef = stored.bundleRef
                    uiObservationStatus = stored.bundle.captureStatus.rawValue
                    uiObservationCapturedLayers = stored.capturedLayers
                    do {
                        let review = try XTBrowserUIReviewEngine.review(
                            storedBundle: stored,
                            ctx: ctx
                        )
                        uiReviewRef = review.reviewRef
                        uiReviewVerdict = review.review.verdict.rawValue
                        uiReviewConfidence = review.review.confidence.rawValue
                        uiReviewSummaryText = review.review.summary
                        uiReviewSufficientEvidence = review.review.sufficientEvidence
                        uiReviewObjectiveReady = review.review.objectiveReady
                        uiReviewIssueCodes = review.review.issueCodes
                        uiReviewAgentEvidenceRef = XTUIReviewAgentEvidenceStore.reviewRef(
                            reviewID: review.review.reviewID
                        )
                    } catch {
                        uiReviewError = String(error.localizedDescription)
                    }
                } catch {
                    uiObservationError = String(error.localizedDescription)
                }

                var summary = deviceAutomationSummaryBase(
                    call: call,
                    projectRoot: projectRoot,
                    decision: decision,
                    ok: true
                )
                summary["action"] = .string(requestedAction.rawValue)
                summary["url"] = .string(targetURL)
                summary["ui_observation_probe_depth"] = .string(probeDepth.rawValue)
                summary["ui_observation_status"] = .string(uiObservationStatus)
                summary["ui_observation_bundle_ref"] = uiObservationRef.isEmpty ? .null : .string(uiObservationRef)
                summary["ui_observation_captured_layers"] = .number(Double(uiObservationCapturedLayers))
                if !uiObservationError.isEmpty {
                    summary["ui_observation_error"] = .string(uiObservationError)
                }
                summary["ui_review_ref"] = uiReviewRef.isEmpty ? .null : .string(uiReviewRef)
                if !uiReviewVerdict.isEmpty {
                    summary["ui_review_verdict"] = .string(uiReviewVerdict)
                }
                if !uiReviewConfidence.isEmpty {
                    summary["ui_review_confidence"] = .string(uiReviewConfidence)
                }
                if !uiReviewSummaryText.isEmpty {
                    summary["ui_review_summary"] = .string(uiReviewSummaryText)
                }
                summary["ui_review_sufficient_evidence"] = .bool(uiReviewSufficientEvidence)
                summary["ui_review_objective_ready"] = .bool(uiReviewObjectiveReady)
                summary["ui_review_issue_codes"] = .array(uiReviewIssueCodes.map(JSONValue.string))
                if !uiReviewAgentEvidenceRef.isEmpty {
                    summary["ui_review_agent_evidence_ref"] = .string(uiReviewAgentEvidenceRef)
                }
                if !uiReviewError.isEmpty {
                    summary["ui_review_error"] = .string(uiReviewError)
                }
                AXProjectStore.appendRawLog(
                    [
                        "type": "ui_review",
                        "surface": "browser_page",
                        "action": requestedAction.rawValue,
                        "project_id": projectID,
                        "session_id": session.sessionID,
                        "bundle_ref": uiObservationRef,
                        "bundle_status": uiObservationStatus,
                        "review_ref": uiReviewRef,
                        "verdict": uiReviewVerdict,
                        "confidence": uiReviewConfidence,
                        "sufficient_evidence": uiReviewSufficientEvidence,
                        "objective_ready": uiReviewObjectiveReady,
                        "issue_codes": uiReviewIssueCodes,
                        "agent_evidence_ref": uiReviewAgentEvidenceRef,
                        "summary": uiReviewSummaryText,
                        "review_error": uiReviewError,
                        "created_at": now.timeIntervalSince1970,
                        "audit_ref": auditRef
                    ],
                    for: ctx
                )
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
            let browserSecretRequest = requestedAction == .typeText
                ? browserSecretFillRequest(for: call, defaultProjectID: projectID)
                : BrowserSecretFillRequest(
                    secretReferenceRequested: false,
                    plaintextInput: nil,
                    inputChars: 0,
                    selector: optStrArg(call, "selector"),
                    fieldRole: nil,
                    secretItemId: nil,
                    secretScope: nil,
                    secretName: nil,
                    secretProjectId: nil
                )

            if requestedAction == .typeText, browserSecretRequest.hasSecretReference {
                guard browserSecretRequest.hasValidSecretReference else {
                    let rejectCode = XTDeviceAutomationRejectCode.browserSecretReferenceInvalid
                    recordBrowserRuntimeAction(
                        session: attemptedSession,
                        action: requestedAction,
                        ok: false,
                        url: targetURL,
                        snapshotRef: "",
                        detail: "secret reference requires secret_item_id or secret_scope + secret_name",
                        rejectCode: rejectCode.rawValue,
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
                    summary["deny_code"] = .string(rejectCode.rawValue)
                    summary["browser_runtime_driver_state"] = .string("secret_vault_resolution_invalid")
                    if let selector = optStrArg(call, "selector")?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !selector.isEmpty {
                        summary["selector"] = .string(selector)
                    }
                    appendBrowserSecretSummary(browserSecretRequest, into: &summary)
                    summary.merge(browserRuntimeSummary(session: attemptedSession, ctx: ctx), uniquingKeysWith: { _, new in new })
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: false,
                        output: structuredOutput(summary: summary, body: "browser_secret_reference_invalid")
                    )
                }

                let selector = (optStrArg(call, "selector") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !selector.isEmpty else {
                    let rejectCode = XTDeviceAutomationRejectCode.browserSecretSelectorMissing
                    recordBrowserRuntimeAction(
                        session: attemptedSession,
                        action: requestedAction,
                        ok: false,
                        url: targetURL,
                        snapshotRef: "",
                        detail: "secret-backed browser fill requires a non-empty selector",
                        rejectCode: rejectCode.rawValue,
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
                    summary["deny_code"] = .string(rejectCode.rawValue)
                    summary["browser_runtime_driver_state"] = .string("secret_vault_selector_required")
                    appendBrowserSecretSummary(browserSecretRequest, into: &summary)
                    summary.merge(browserRuntimeSummary(session: attemptedSession, ctx: ctx), uniquingKeysWith: { _, new in new })
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: false,
                        output: structuredOutput(summary: summary, body: "browser_secret_selector_missing")
                    )
                }

                let secretResolution = await resolveBrowserSecretValue(
                    request: browserSecretRequest,
                    projectID: projectID,
                    targetURL: targetURL
                )
                switch secretResolution {
                case .failure(let failure):
                    recordBrowserRuntimeAction(
                        session: attemptedSession,
                        action: requestedAction,
                        ok: false,
                        url: targetURL,
                        snapshotRef: "",
                        detail: failure.detail,
                        rejectCode: failure.rejectCode.rawValue,
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
                    summary["deny_code"] = .string(failure.rejectCode.rawValue)
                    summary["browser_runtime_driver_state"] = .string("secret_vault_resolution_failed")
                    summary["selector"] = .string(selector)
                    appendBrowserSecretSummary(browserSecretRequest, into: &summary)
                    appendBrowserSecretResolvedSummary(
                        leaseId: failure.leaseId,
                        itemId: failure.itemId,
                        source: failure.source,
                        reasonCode: failure.reasonCode,
                        detail: failure.resolutionDetail,
                        into: &summary
                    )
                    summary.merge(browserRuntimeSummary(session: attemptedSession, ctx: ctx), uniquingKeysWith: { _, new in new })
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: false,
                        output: structuredOutput(summary: summary, body: failure.body)
                    )
                case .success(let resolved):
                    let fill = await performBrowserSecretFill(
                        selector: selector,
                        plaintext: resolved.plaintext
                    )
                    switch fill {
                    case .failure(let failure):
                        recordBrowserRuntimeAction(
                            session: attemptedSession,
                            action: requestedAction,
                            ok: false,
                            url: targetURL,
                            snapshotRef: "",
                            detail: failure.detail,
                            rejectCode: failure.rejectCode.rawValue,
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
                        summary["deny_code"] = .string(failure.rejectCode.rawValue)
                        summary["browser_runtime_driver_state"] = .string("secret_vault_applescript_fill_failed")
                        summary["selector"] = .string(selector)
                        summary["input_chars"] = .number(Double(resolved.plaintext.count))
                        appendBrowserSecretSummary(browserSecretRequest, into: &summary)
                        appendBrowserSecretResolvedSummary(
                            leaseId: resolved.leaseId,
                            itemId: resolved.itemId,
                            source: resolved.source,
                            reasonCode: failure.reasonCode,
                            detail: nil,
                            into: &summary
                        )
                        summary.merge(browserRuntimeSummary(session: attemptedSession, ctx: ctx), uniquingKeysWith: { _, new in new })
                        return ToolResult(
                            id: call.id,
                            tool: call.tool,
                            ok: false,
                            output: structuredOutput(summary: summary, body: failure.body)
                        )
                    case .success(let fillOutput):
                        var session = attemptedSession
                        do {
                            let snapshotRef = try XTBrowserRuntimeStore.writeSnapshot(
                                session: session,
                                action: requestedAction,
                                snapshotKind: "secret_fill_result",
                                excerpt: fillOutput.excerpt,
                                detail: "secret-backed browser fill succeeded via applescript_dom_bridge",
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
                                detail: "secret-backed browser fill succeeded",
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
                            summary["selector"] = .string(selector)
                            summary["input_chars"] = .number(Double(resolved.plaintext.count))
                            summary["browser_runtime_driver_state"] = .string("secret_vault_applescript_fill")
                            appendBrowserSecretSummary(browserSecretRequest, into: &summary)
                            appendBrowserSecretResolvedSummary(
                                leaseId: resolved.leaseId,
                                itemId: resolved.itemId,
                                source: resolved.source,
                                reasonCode: nil,
                                detail: nil,
                                into: &summary
                            )
                            if let tagName = fillOutput.tagName {
                                summary["browser_fill_tag_name"] = .string(tagName)
                            }
                            summary.merge(browserRuntimeSummary(session: session, ctx: ctx), uniquingKeysWith: { _, new in new })
                            let body = """
session_id=\(session.sessionID)
profile_id=\(session.profileID)
transport=\(session.transport)
snapshot_ref=\(session.snapshotRef)
selector=\(selector)
secret_item_id=\(resolved.itemId ?? "")
lease_id=\(resolved.leaseId ?? "")
"""
                            return ToolResult(
                                id: call.id,
                                tool: call.tool,
                                ok: true,
                                output: structuredOutput(summary: summary, body: body)
                            )
                        } catch {
                            let rejectCode = XTDeviceAutomationRejectCode.browserSnapshotFailed
                            recordBrowserRuntimeAction(
                                session: attemptedSession,
                                action: requestedAction,
                                ok: false,
                                url: targetURL,
                                snapshotRef: "",
                                detail: "browser secret fill snapshot persistence failed",
                                rejectCode: rejectCode.rawValue,
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
                            summary["selector"] = .string(selector)
                            summary["deny_code"] = .string(rejectCode.rawValue)
                            summary["browser_runtime_driver_state"] = .string("secret_vault_applescript_fill")
                            summary["input_chars"] = .number(Double(resolved.plaintext.count))
                            appendBrowserSecretSummary(browserSecretRequest, into: &summary)
                            appendBrowserSecretResolvedSummary(
                                leaseId: resolved.leaseId,
                                itemId: resolved.itemId,
                                source: resolved.source,
                                reasonCode: nil,
                                detail: nil,
                                into: &summary
                            )
                            summary.merge(browserRuntimeSummary(session: attemptedSession, ctx: ctx), uniquingKeysWith: { _, new in new })
                            return ToolResult(
                                id: call.id,
                                tool: call.tool,
                                ok: false,
                                output: structuredOutput(summary: summary, body: "browser_snapshot_failed")
                            )
                        }
                    }
                }
            }

            if requestedAction == .typeText, browserSecretRequest.requiresSecretRefOnly {
                let rejectCode = XTDeviceAutomationRejectCode.browserSecretPlaintextForbidden
                recordBrowserRuntimeAction(
                    session: attemptedSession,
                    action: requestedAction,
                    ok: false,
                    url: targetURL,
                    snapshotRef: "",
                    detail: "sensitive browser field requires Secret Vault reference instead of plaintext input",
                    rejectCode: rejectCode.rawValue,
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
                summary["deny_code"] = .string(rejectCode.rawValue)
                summary["browser_runtime_driver_state"] = .string("unavailable")
                if let selector = optStrArg(call, "selector")?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !selector.isEmpty {
                    summary["selector"] = .string(selector)
                }
                appendBrowserSecretSummary(browserSecretRequest, into: &summary)
                summary["input_chars"] = .number(Double(browserSecretRequest.inputChars))
                summary.merge(browserRuntimeSummary(session: attemptedSession, ctx: ctx), uniquingKeysWith: { _, new in new })
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(summary: summary, body: "browser_secret_plaintext_forbidden")
                )
            }

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
                summary["input_chars"] = .number(Double(browserSecretRequest.inputChars))
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

    private static func browserSecretFillRequest(
        for call: ToolCall,
        defaultProjectID: String
    ) -> BrowserSecretFillRequest {
        let rawSecretItemId = optStrArg(call, "secret_item_id")
        let rawSecretScope = optStrArg(call, "secret_scope")
        let rawSecretName = optStrArg(call, "secret_name")
        let secretReferenceRequested = [rawSecretItemId, rawSecretScope, rawSecretName]
            .contains { raw in
                let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !trimmed.isEmpty
            }
        let secretItemId = normalizedBrowserSecretReference(rawSecretItemId)
        let secretScope = normalizedBrowserSecretScope(rawSecretScope)
        let secretName = normalizedBrowserSecretReference(rawSecretName)
        let plaintextInput = [
            optStrArg(call, "text"),
            optStrArg(call, "content"),
            optStrArg(call, "value"),
        ]
        .compactMap { raw -> String? in
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        .first

        let fieldRole = normalizeBrowserFieldRole(
            optStrArg(call, "field_role") ?? optStrArg(call, "secret_field_role")
        )
        let secretProjectId = secretReferenceRequested
            ? normalizedBrowserSecretProjectID(
                optStrArg(call, "secret_project_id"),
                defaultProjectID: defaultProjectID
            )
            : nil

        return BrowserSecretFillRequest(
            secretReferenceRequested: secretReferenceRequested,
            plaintextInput: plaintextInput,
            inputChars: plaintextInput?.count ?? 0,
            selector: optStrArg(call, "selector"),
            fieldRole: fieldRole,
            secretItemId: secretItemId,
            secretScope: secretScope,
            secretName: secretName,
            secretProjectId: secretProjectId
        )
    }

    private static func normalizedBrowserSecretReference(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedBrowserSecretScope(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch trimmed {
        case "device", "user", "app", "project":
            return trimmed
        default:
            return nil
        }
    }

    private static func normalizedBrowserSecretProjectID(
        _ raw: String?,
        defaultProjectID: String
    ) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        let fallback = defaultProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    private static func normalizeBrowserFieldRole(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func appendBrowserSecretSummary(
        _ request: BrowserSecretFillRequest,
        into summary: inout [String: JSONValue]
    ) {
        summary["secret_ref_only"] = .bool(request.hasSecretReference || request.requiresSecretRefOnly)
        if let fieldRole = request.fieldRole {
            summary["secret_field_role"] = .string(fieldRole)
        }
        if let secretItemId = request.secretItemId {
            summary["secret_item_id"] = .string(secretItemId)
        }
        if let secretScope = request.secretScope {
            summary["secret_scope"] = .string(secretScope)
        }
        if let secretName = request.secretName {
            summary["secret_name"] = .string(secretName)
        }
        if let secretProjectId = request.secretProjectId {
            summary["secret_project_id"] = .string(secretProjectId)
        }
    }

    private static func appendBrowserSecretResolvedSummary(
        leaseId: String?,
        itemId: String?,
        source: String?,
        reasonCode: String?,
        detail: String?,
        into summary: inout [String: JSONValue]
    ) {
        if let leaseId = normalized(leaseId) {
            summary["secret_lease_id"] = .string(leaseId)
        }
        if summary["secret_item_id"] == nil, let itemId = normalized(itemId) {
            summary["secret_item_id"] = .string(itemId)
        }
        if let source = normalized(source) {
            summary["secret_use_source"] = .string(source)
        }
        if let reasonCode = normalized(reasonCode) {
            summary["secret_reason_code"] = .string(reasonCode)
        }
        if let detail = normalized(detail) {
            summary["secret_detail"] = .string(detail)
        }
    }

    private static func browserSecretFailureDetail(
        stage: String,
        reasonCode: String?,
        detail: String?
    ) -> String {
        let normalizedReason = normalized(reasonCode) ?? "browser_secret_\(stage)_failed"
        if let normalizedDetail = normalized(detail) {
            return "secret vault \(stage) failed: \(normalizedReason); \(normalizedDetail)"
        }
        return "secret vault \(stage) failed: \(normalizedReason)"
    }

    private static func resolveBrowserSecretValue(
        request: BrowserSecretFillRequest,
        projectID: String,
        targetURL: String
    ) async -> Result<BrowserSecretResolvedValue, BrowserSecretResolutionFailure> {
        let effectiveProjectID = normalized(request.secretProjectId) ?? normalized(projectID)
        let begin = await HubIPCClient.beginSecretUse(
            HubIPCClient.SecretUseRequestPayload(
                itemId: request.secretItemId,
                scope: request.secretScope,
                name: request.secretName,
                projectId: effectiveProjectID,
                purpose: "browser_secret_fill",
                target: targetURL,
                ttlMs: 60_000
            )
        )
        guard begin.ok, let useToken = normalized(begin.useToken) else {
            return .failure(
                BrowserSecretResolutionFailure(
                    rejectCode: .browserSecretBeginUseFailed,
                    detail: browserSecretFailureDetail(
                        stage: "begin_use",
                        reasonCode: begin.reasonCode,
                        detail: begin.detail
                    ),
                    body: "browser_secret_begin_use_failed",
                    source: begin.source,
                    reasonCode: begin.reasonCode,
                    resolutionDetail: begin.detail,
                    itemId: begin.itemId,
                    leaseId: begin.leaseId
                )
            )
        }

        let redeem = await HubIPCClient.redeemSecretUse(
            HubIPCClient.SecretRedeemRequestPayload(
                useToken: useToken,
                projectId: effectiveProjectID
            )
        )
        guard redeem.ok, let plaintext = normalized(redeem.plaintext) else {
            return .failure(
                BrowserSecretResolutionFailure(
                    rejectCode: .browserSecretRedeemFailed,
                    detail: browserSecretFailureDetail(
                        stage: "redeem",
                        reasonCode: redeem.reasonCode,
                        detail: redeem.detail
                    ),
                    body: "browser_secret_redeem_failed",
                    source: redeem.source,
                    reasonCode: redeem.reasonCode,
                    resolutionDetail: redeem.detail,
                    itemId: redeem.itemId ?? begin.itemId,
                    leaseId: redeem.leaseId ?? begin.leaseId
                )
            )
        }

        let source = firstNonEmptyString(redeem.source, begin.source)
        return .success(
            BrowserSecretResolvedValue(
                source: source,
                leaseId: redeem.leaseId ?? begin.leaseId,
                itemId: redeem.itemId ?? begin.itemId,
                plaintext: plaintext
            )
        )
    }

    private static func performBrowserSecretFill(
        selector: String,
        plaintext: String
    ) async -> Result<BrowserSecretFillOutput, BrowserSecretFillExecutionFailure> {
        guard let source = browserSecretFillAppleScriptSource(selector: selector, plaintext: plaintext) else {
            return .failure(
                BrowserSecretFillExecutionFailure(
                    rejectCode: .browserSecretFillUnavailable,
                    detail: "browser secret fill script generation failed",
                    body: "browser_secret_fill_unavailable",
                    reasonCode: "browser_secret_fill_script_invalid"
                )
            )
        }

        let result = await MainActor.run {
            DeviceAutomationTools.runAppleScript(source)
        }
        if !result.ok {
            let reason = normalized(result.errorMessage) ?? "browser_secret_fill_failed"
            let lower = reason.lowercased()
            let unavailable = lower.contains("unsupported_frontmost_browser")
                || lower.contains("browser_window_missing")
                || lower.contains("front_browser_missing")
            return .failure(
                BrowserSecretFillExecutionFailure(
                    rejectCode: unavailable ? .browserSecretFillUnavailable : .browserSecretFillFailed,
                    detail: reason,
                    body: unavailable ? "browser_secret_fill_unavailable" : "browser_secret_fill_failed",
                    reasonCode: sanitizeReasonToken(reason)
                )
            )
        }

        if let decoded = parseBrowserSecretDriverResponse(result.output),
           decoded.ok == false {
            let reason = normalized(decoded.reason) ?? "browser_secret_fill_failed"
            let lower = reason.lowercased()
            let unavailable = lower.contains("unsupported_frontmost_browser")
                || lower.contains("browser_window_missing")
                || lower.contains("front_browser_missing")
            return .failure(
                BrowserSecretFillExecutionFailure(
                    rejectCode: unavailable ? .browserSecretFillUnavailable : .browserSecretFillFailed,
                    detail: reason,
                    body: unavailable ? "browser_secret_fill_unavailable" : "browser_secret_fill_failed",
                    reasonCode: sanitizeReasonToken(reason)
                )
            )
        }

        return .success(
            BrowserSecretFillOutput(
                excerpt: browserSecretFillExcerpt(from: result.output),
                tagName: parseBrowserSecretDriverResponse(result.output)?.tagName
            )
        )
    }

    private static func parseBrowserSecretDriverResponse(_ output: String) -> BrowserSecretDriverResponse? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(BrowserSecretDriverResponse.self, from: data)
    }

    private static func browserSecretFillExcerpt(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "browser_secret_fill_ok" }
        return capped(trimmed, maxChars: 240)
    }

    private static func browserSecretFillAppleScriptSource(
        selector: String,
        plaintext: String
    ) -> String? {
        guard let jsSource = browserSecretFillJavaScriptSource(selector: selector, plaintext: plaintext) else {
            return nil
        }
        let jsLiteral = appleScriptStringLiteral(jsSource)
        return """
set jsSource to \(jsLiteral)
tell application "System Events"
    set frontAppName to name of first application process whose frontmost is true
end tell
if frontAppName is "Safari" then
    tell application "Safari"
        if (count of windows) is 0 then error "browser_window_missing"
        set jsResult to do JavaScript jsSource in current tab of front window
    end tell
else if frontAppName is "Google Chrome" then
    tell application "Google Chrome"
        if (count of windows) is 0 then error "browser_window_missing"
        set jsResult to execute active tab of front window javascript jsSource
    end tell
else if frontAppName is "Chromium" then
    tell application "Chromium"
        if (count of windows) is 0 then error "browser_window_missing"
        set jsResult to execute active tab of front window javascript jsSource
    end tell
else if frontAppName is "Microsoft Edge" then
    tell application "Microsoft Edge"
        if (count of windows) is 0 then error "browser_window_missing"
        set jsResult to execute active tab of front window javascript jsSource
    end tell
else if frontAppName is "Brave Browser" then
    tell application "Brave Browser"
        if (count of windows) is 0 then error "browser_window_missing"
        set jsResult to execute active tab of front window javascript jsSource
    end tell
else if frontAppName is "Arc" then
    tell application "Arc"
        if (count of windows) is 0 then error "browser_window_missing"
        set jsResult to execute active tab of front window javascript jsSource
    end tell
else
    error "unsupported_frontmost_browser:" & frontAppName
end if
return jsResult
"""
    }

    private static func browserSecretFillJavaScriptSource(
        selector: String,
        plaintext: String
    ) -> String? {
        guard let selectorLiteral = jsonStringLiteral(selector),
              let valueLiteral = jsonStringLiteral(Data(plaintext.utf8).base64EncodedString()) else {
            return nil
        }
        return [
            "(() => {",
            "const selector = \(selectorLiteral);",
            "const encoded = \(valueLiteral);",
            "const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));",
            "const value = new TextDecoder().decode(bytes);",
            "const node = document.querySelector(selector);",
            "if (!node) return JSON.stringify({ok:false,reason:'selector_not_found',selector});",
            "if (node instanceof HTMLInputElement || node instanceof HTMLTextAreaElement) {",
            "const proto = node instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;",
            "const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;",
            "node.focus();",
            "if (setter) setter.call(node, value); else node.value = value;",
            "} else if (node instanceof HTMLSelectElement) {",
            "node.value = value;",
            "} else if (node.isContentEditable) {",
            "node.focus(); node.textContent = value;",
            "} else {",
            "if ('value' in node) node.value = value; else node.textContent = value;",
            "}",
            "node.dispatchEvent(new Event('input', { bubbles: true }));",
            "node.dispatchEvent(new Event('change', { bubbles: true }));",
            "return JSON.stringify({ok:true,selector,tag_name:(node.tagName||'').toLowerCase()});",
            "})();"
        ].joined(separator: "")
    }

    private static func jsonStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let text = String(data: data, encoding: .utf8),
              text.count >= 2 else {
            return nil
        }
        return String(text.dropFirst().dropLast())
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizeReasonToken(_ raw: String) -> String {
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
        var summary: [String: JSONValue] = [
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
        if let latest = XTUIObservationStore.loadLatestBrowserPageReference(for: ctx) {
            summary["browser_runtime_ui_observation_ref"] = .string(latest.bundleRef)
            summary["browser_runtime_ui_observation_status"] = .string(latest.captureStatus.rawValue)
            summary["browser_runtime_ui_observation_probe_depth"] = .string(latest.probeDepth.rawValue)
            summary["browser_runtime_ui_observation_updated_at_ms"] = .number(Double(latest.updatedAtMs))
        }
        if let latest = XTUIReviewStore.loadLatestBrowserPageReference(for: ctx) {
            summary["browser_runtime_ui_review_ref"] = .string(latest.reviewRef)
            summary["browser_runtime_ui_review_agent_evidence_ref"] = .string(
                XTUIReviewAgentEvidenceStore.reviewRef(reviewID: latest.reviewID)
            )
            summary["browser_runtime_ui_review_verdict"] = .string(latest.verdict.rawValue)
            summary["browser_runtime_ui_review_confidence"] = .string(latest.confidence.rawValue)
            summary["browser_runtime_ui_review_sufficient_evidence"] = .bool(latest.sufficientEvidence)
            summary["browser_runtime_ui_review_objective_ready"] = .bool(latest.objectiveReady)
            summary["browser_runtime_ui_review_issue_codes"] = .array(latest.issueCodes.map(JSONValue.string))
            summary["browser_runtime_ui_review_summary"] = .string(latest.summary)
            summary["browser_runtime_ui_review_updated_at_ms"] = .number(Double(latest.updatedAtMs))
        }
        return summary
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
        let runtimeSurfaceState = await xtResolveProjectRuntimeSurfacePolicy(
            projectRoot: projectRoot,
            config: config
        )
        let runtimePolicyDecision = xtToolRuntimePolicyDecision(
            call: call,
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
        )
        guard runtimePolicyDecision.allowed else {
            return deniedRuntimePolicyResult(
                call: call,
                projectRoot: projectRoot,
                config: config,
                decision: runtimePolicyDecision,
                effectiveRuntimeSurface: runtimeSurfaceState.effectivePolicy
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

    private static func executeSkillsSearch(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let query = (optStrArg(call, "query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string("missing_query"),
            ]
            return ToolResult(id: call.id, tool: call.tool, ok: false, output: structuredOutput(summary: summary, body: "missing_query"))
        }

        let sourceFilter = (optStrArg(call, "source_filter") ?? optStrArg(call, "source") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = (optStrArg(call, "project_id") ?? AXProjectRegistryStore.projectId(forRoot: projectRoot))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(25, Int(optDoubleArg(call, "limit") ?? optDoubleArg(call, "max_results") ?? 8)))

        let remote = await HubIPCClient.searchSkills(
            query: query,
            sourceFilter: sourceFilter.isEmpty ? nil : sourceFilter,
            projectId: projectID.isEmpty ? nil : projectID,
            limit: limit
        )
        let resolved: HubIPCClient.SkillsSearchResult
        if remote.ok {
            resolved = remote
        } else if let local = searchLocalSkillCatalog(
            query: query,
            sourceFilter: sourceFilter.isEmpty ? nil : sourceFilter,
            limit: limit,
            hubBaseDir: HubPaths.baseDir()
        ) {
            resolved = local
        } else {
            let reason = (remote.reasonCode ?? "skills_search_unavailable").trimmingCharacters(in: .whitespacesAndNewlines)
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "query": .string(query),
                "source_filter": sourceFilter.isEmpty ? .null : .string(sourceFilter),
                "project_id": projectID.isEmpty ? .null : .string(projectID),
                "reason": .string(reason.isEmpty ? "skills_search_unavailable" : reason),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: reason.isEmpty ? "skills_search_unavailable" : reason)
            )
        }

        let rows = resolved.results.prefix(limit).map { item -> JSONValue in
            .object([
                "skill_id": .string(item.skillID),
                "name": .string(item.name),
                "version": .string(item.version),
                "publisher_id": .string(item.publisherID),
                "source_id": .string(item.sourceID),
                "package_sha256": .string(item.packageSHA256),
                "install_hint": .string(item.installHint),
                "risk_level": .string(item.riskLevel),
                "requires_grant": .bool(item.requiresGrant),
                "side_effect_class": .string(item.sideEffectClass),
                "capabilities_required": .array(item.capabilitiesRequired.map(JSONValue.string)),
            ])
        }
        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(resolved.ok),
            "query": .string(query),
            "source_filter": sourceFilter.isEmpty ? .null : .string(sourceFilter),
            "project_id": projectID.isEmpty ? .null : .string(projectID),
            "source": .string(resolved.source),
            "updated_at_ms": .number(Double(resolved.updatedAtMs)),
            "results_count": .number(Double(resolved.results.count)),
            "results": .array(rows),
        ]
        let body: String
        if resolved.results.isEmpty {
            body = "(no matching skills)"
        } else {
            body = resolved.results.prefix(limit).enumerated().map { index, item in
                let caps = item.capabilitiesRequired.isEmpty ? "caps: (none)" : "caps: " + item.capabilitiesRequired.joined(separator: ", ")
                let governance = "risk=\(item.riskLevel) grant=\(item.requiresGrant ? "yes" : "no") side_effect=\(item.sideEffectClass.isEmpty ? "unspecified" : item.sideEffectClass)"
                let install = item.installHint.trimmingCharacters(in: .whitespacesAndNewlines)
                let installLine = install.isEmpty ? "" : "\n   install: \(install)"
                return "\(index + 1). \(item.name) [\(item.skillID)] v\(item.version)\n   publisher=\(item.publisherID) source=\(item.sourceID)\n   \(governance)\n   \(caps)\(installLine)"
            }.joined(separator: "\n\n")
        }
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeSkillsPin(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let skillId = firstNonEmptyString(
            optStrArg(call, "skill_id"),
            optStrArg(call, "id")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let packageSHA256 = firstNonEmptyString(
            optStrArg(call, "package_sha256"),
            optStrArg(call, "sha256")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        let explicitProjectId = (optStrArg(call, "project_id") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let registryProjectId = AXProjectRegistryStore.projectId(forRoot: projectRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitScope = (optStrArg(call, "scope") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scope: String = {
            if explicitScope == "global" || explicitScope == "project" {
                return explicitScope
            }
            return explicitProjectId.isEmpty ? "global" : "project"
        }()
        let derivedProjectId = firstNonEmptyString(
            explicitProjectId,
            scope == "project" ? registryProjectId : ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (optStrArg(call, "note") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !skillId.isEmpty else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string("missing_skill_id"),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: skillsPinFailureBody(reasonCode: "missing_skill_id"))
            )
        }

        guard !packageSHA256.isEmpty else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "skill_id": .string(skillId),
                "reason": .string("missing_package_sha256"),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: skillsPinFailureBody(reasonCode: "missing_package_sha256"))
            )
        }

        guard scope == "global" || scope == "project" else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "skill_id": .string(skillId),
                "package_sha256": .string(packageSHA256),
                "scope": .string(scope),
                "reason": .string("unsupported_skill_pin_scope"),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: skillsPinFailureBody(reasonCode: "unsupported_skill_pin_scope"))
            )
        }

        guard scope == "global" || !derivedProjectId.isEmpty else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "skill_id": .string(skillId),
                "package_sha256": .string(packageSHA256),
                "scope": .string(scope),
                "reason": .string("missing_project_id"),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: skillsPinFailureBody(reasonCode: "missing_project_id"))
            )
        }

        let result = await HubIPCClient.setSkillPin(
            scope: scope,
            skillId: skillId,
            packageSHA256: packageSHA256,
            projectId: derivedProjectId.isEmpty ? nil : derivedProjectId,
            note: note.isEmpty ? nil : note,
            requestId: call.id
        )
        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(result.ok),
            "source": .string(result.source),
            "scope": .string(result.scope),
            "project_id": result.projectId.isEmpty ? .null : .string(result.projectId),
            "skill_id": .string(result.skillId),
            "package_sha256": .string(result.packageSHA256),
            "previous_package_sha256": result.previousPackageSHA256.isEmpty ? .null : .string(result.previousPackageSHA256),
            "updated_at_ms": .number(Double(result.updatedAtMs)),
            "reason": result.reasonCode.map(JSONValue.string) ?? .null,
        ]
        let shortSHA = String(result.packageSHA256.prefix(12))
        if result.ok {
            let refreshProjectId = firstNonEmptyString(
                scope == "project" ? result.projectId : "",
                registryProjectId
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !refreshProjectId.isEmpty {
                _ = await XTResolvedSkillsCacheStore.refreshFromHubIfPossible(
                    projectId: refreshProjectId,
                    projectName: nil,
                    context: AXProjectContext(root: projectRoot),
                    hubBaseDir: HubPaths.baseDir(),
                    force: true
                )
            }
            let body = skillsPinSuccessBody(
                skillId: result.skillId,
                shortSHA: shortSHA,
                scope: result.scope,
                projectId: result.projectId
            )
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: true,
                output: structuredOutput(summary: summary, body: body)
            )
        }

        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: false,
            output: structuredOutput(
                summary: summary,
                body: skillsPinFailureBody(reasonCode: (result.reasonCode ?? "skills_pin_failed"))
            )
        )
    }

    private static func skillsPinSuccessBody(
        skillId: String,
        shortSHA: String,
        scope: String,
        projectId: String
    ) -> String {
        if scope == "project", !projectId.isEmpty {
            return "Hub 已通过审查并启用技能：\(skillId)@\(shortSHA)（project: \(projectId)）"
        }
        return "Hub 已通过审查并启用技能：\(skillId)@\(shortSHA)（global）"
    }

    private static func skillsPinFailureBody(reasonCode rawReasonCode: String) -> String {
        let reasonCode = rawReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        switch reasonCode {
        case "missing_skill_id":
            return "技能启用请求必须带上 skill_id。"
        case "missing_package_sha256":
            return "技能启用请求必须带上 package_sha256。"
        case "unsupported_skill_pin_scope":
            return "技能启用请求的 scope 只支持 global 或 project。"
        case "missing_project_id":
            return "project scope 的技能启用请求必须带上 project_id。"
        case "package_not_found":
            return "Hub 还没有这个技能包，不能直接启用；需要先让包进入受治理技能仓库。"
        case "skill_package_mismatch":
            return "这次技能启用请求里的 skill_id 和 package_sha256 对不上。"
        case "trusted_automation_project_not_bound", "trusted_automation_workspace_mismatch":
            return "当前 Hub 侧 trusted automation 绑定不满足这次技能启用请求。"
        case "official_skill_review_blocked":
            return "Hub 已自动审查该官方技能包，但当前 official_skills doctor 结果还不是 ready，暂不能启用。"
        default:
            return reasonCode.isEmpty ? "skills_pin_failed" : reasonCode
        }
    }

    private static func executeAgentImportRecord(call: ToolCall, projectRoot: URL) async -> ToolResult {
        let stagingId = firstNonEmptyString(
            optStrArg(call, "staging_id"),
            optStrArg(call, "id"),
            optStrArg(call, "import_id")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let selector = firstNonEmptyString(
            optStrArg(call, "selector"),
            optStrArg(call, "locator"),
            optStrArg(call, "mode")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let skillId = firstNonEmptyString(
            optStrArg(call, "skill_id"),
            optStrArg(call, "skill")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let currentProjectID = AXProjectRegistryStore.projectId(forRoot: projectRoot)
        let projectID = firstNonEmptyString(
            optStrArg(call, "project_id"),
            optStrArg(call, "project"),
            currentProjectID
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSelector: String? = {
            guard stagingId.isEmpty else { return nil }
            if !selector.isEmpty { return selector }
            if !skillId.isEmpty { return "latest_for_skill" }
            if !projectID.isEmpty { return "latest_for_project" }
            return "last_import"
        }()

        let record = await HubIPCClient.getAgentImportRecord(
            stagingId: stagingId.isEmpty ? nil : stagingId,
            selector: resolvedSelector,
            skillId: skillId.isEmpty ? nil : skillId,
            projectId: stagingId.isEmpty ? (projectID.isEmpty ? nil : projectID) : nil
        )
        guard record.ok else {
            var summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "source": .string(record.source),
                "staging_id": .string(record.stagingId ?? stagingId),
                "reason": .string(record.reasonCode ?? "agent_import_record_failed"),
            ]
            if let selector = record.selector ?? resolvedSelector, !selector.isEmpty {
                summary["selector"] = .string(selector)
            }
            if let project = record.projectId ?? (projectID.isEmpty ? nil : projectID), !project.isEmpty {
                summary["project_id"] = .string(project)
            }
            if let skill = record.skillId ?? (skillId.isEmpty ? nil : skillId), !skill.isEmpty {
                summary["skill_id"] = .string(skill)
            }
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: record.reasonCode ?? "agent_import_record_failed")
            )
        }

        var summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(true),
            "source": .string(record.source),
            "staging_id": .string(record.stagingId ?? stagingId),
        ]
        let summarySelector = firstNonEmptyString(record.selector, resolvedSelector)
        if !summarySelector.isEmpty {
            summary["selector"] = .string(summarySelector)
        }
        let status = firstNonEmptyString(record.status)
        if !status.isEmpty {
            summary["status"] = .string(status)
        }
        let auditRef = firstNonEmptyString(record.auditRef)
        if !auditRef.isEmpty {
            summary["audit_ref"] = .string(auditRef)
        }
        let schemaVersion = firstNonEmptyString(record.schemaVersion)
        if !schemaVersion.isEmpty {
            summary["schema_version"] = .string(schemaVersion)
        }
        let resolvedSkillID = firstNonEmptyString(record.skillId)
        if !resolvedSkillID.isEmpty {
            summary["skill_id"] = .string(resolvedSkillID)
        }
        let projectIDSummary = firstNonEmptyString(record.projectId, projectID)
        if !projectIDSummary.isEmpty {
            summary["project_id"] = .string(projectIDSummary)
        }
        if let recordRoot = jsonObject(from: record.recordJSON) {
            if let vetterStatus = jsonStringValue(recordRoot["vetter_status"]) {
                summary["vetter_status"] = .string(vetterStatus)
            }
            if let criticalCount = jsonNumberValue(recordRoot["vetter_critical_count"]) {
                summary["vetter_critical_count"] = .number(criticalCount)
            }
            if let warnCount = jsonNumberValue(recordRoot["vetter_warn_count"]) {
                summary["vetter_warn_count"] = .number(warnCount)
            }
            if let blockedReason = jsonStringValue(recordRoot["promotion_blocked_reason"]) {
                summary["blocked_reason"] = .string(blockedReason)
            }
            if let reportRef = jsonStringValue(recordRoot["vetter_report_ref"]) {
                summary["vetter_report_ref"] = .string(reportRef)
            }
            if let findings = recordRoot["findings"] as? [Any] {
                summary["findings_count"] = .number(Double(findings.count))
            }
        }

        let body = XTAgentSkillImportReviewFormatter.formatHubRecordReview(
            recordJSON: record.recordJSON,
            fallbackStagingId: record.stagingId ?? stagingId,
            fallbackSkillId: record.skillId ?? (skillId.isEmpty ? "skill" : skillId)
        )
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: body))
    }

    private static func executeSummarize(call: ToolCall, projectRoot: URL) async throws -> ToolResult {
        let focus = (optStrArg(call, "focus") ?? optStrArg(call, "question") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let format = normalizedSummarizeFormat(optStrArg(call, "format"))
        let maxChars = max(220, min(2_400, Int(optDoubleArg(call, "max_chars") ?? 900)))

        let loaded: SummarizeLoadedSource
        do {
            loaded = try await loadSummarizeSource(call: call, projectRoot: projectRoot)
        } catch let error as SummarizeLoadError {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string(error.reasonCode),
            ]
            return ToolResult(id: call.id, tool: call.tool, ok: false, output: structuredOutput(summary: summary, body: error.reasonCode))
        }

        let normalizedSource = normalizedSummarySourceText(loaded.text)
        guard !normalizedSource.isEmpty else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "source_kind": .string(loaded.kind.rawValue),
                "reason": .string("empty_source_text"),
            ]
            return ToolResult(id: call.id, tool: call.tool, ok: false, output: structuredOutput(summary: summary, body: "empty_source_text"))
        }

        let processingLimit = max(6_000, min(40_000, Int(optDoubleArg(call, "max_source_chars") ?? 20_000)))
        let processedText = String(normalizedSource.prefix(processingLimit))
        let summaryBody = governedSummaryBody(
            sourceText: processedText,
            title: loaded.title,
            focus: focus,
            format: format,
            maxChars: maxChars
        )
        let sourceTruncated = normalizedSource.count > processedText.count
        var summary = loaded.summary
        summary["tool"] = .string(call.tool.rawValue)
        summary["ok"] = .bool(true)
        summary["source_kind"] = .string(loaded.kind.rawValue)
        summary["source_title"] = .string(loaded.title)
        summary["focus"] = focus.isEmpty ? .null : .string(focus)
        summary["format"] = .string(format)
        summary["input_chars"] = .number(Double(normalizedSource.count))
        summary["processed_chars"] = .number(Double(processedText.count))
        summary["summary_chars"] = .number(Double(summaryBody.count))
        summary["source_truncated"] = .bool(sourceTruncated)
        return ToolResult(id: call.id, tool: call.tool, ok: true, output: structuredOutput(summary: summary, body: summaryBody))
    }

    private static let supportedLocalTaskKinds: Set<String> = [
        "text_generate",
        "embedding",
        "speech_to_text",
        "text_to_speech",
        "vision_understand",
        "ocr",
    ]

    private static let localTaskReservedArgTokens: Set<String> = [
        "task_kind",
        "taskkind",
        "model_id",
        "model",
        "preferred_model_id",
        "preferredmodelid",
        "device_id",
        "deviceid",
        "timeout_sec",
        "timeoutsec",
        "parameters",
    ]

    private enum LocalTaskParameterParsingError: String, Error {
        case invalidParametersObject = "invalid_parameters_object"
    }

    private struct LocalTaskModelInvocationResolution {
        var requestedModelID: String?
        var preferredModelID: String?
        var resolvedModelID: String?
        var reasonCode: String
    }

    private static func executeSupervisorVoicePlayback(call: ToolCall) async -> ToolResult {
        let rawAction = firstNonEmptyString(
            optStrArg(call, "action"),
            optStrArg(call, "mode"),
            optStrArg(call, "operation")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = firstNonEmptyString(
            optStrArg(call, "text"),
            optStrArg(call, "content"),
            optStrArg(call, "value")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let action = rawAction.isEmpty ? (text.isEmpty ? "status" : "speak") : rawAction.lowercased()
        let supportedActions = Set(["status", "preview", "speak", "stop"])

        guard supportedActions.contains(action) else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "action": .string(action),
                "reason": .string("unsupported_action"),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "unsupported_action")
            )
        }

        if action == "speak" {
            guard !text.isEmpty else {
                let summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(false),
                    "action": .string(action),
                    "reason": .string("missing_text"),
                ]
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(summary: summary, body: "missing_text")
                )
            }
            if text.count > 320 {
                let summary: [String: JSONValue] = [
                    "tool": .string(call.tool.rawValue),
                    "ok": .bool(false),
                    "action": .string(action),
                    "reason": .string("text_too_long"),
                    "input_chars": .number(Double(text.count)),
                ]
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: false,
                    output: structuredOutput(summary: summary, body: "text_too_long")
                )
            }
        }

        let result = await MainActor.run {
            SupervisorManager.shared.executeSupervisorVoiceSkillAction(
                action: action,
                text: action == "speak" ? text : nil
            )
        }

        var summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(result.ok),
            "action": .string(action),
            "reason": .string(result.reasonCode),
            "requested_playback_preference": .string(result.playbackPreference),
            "persona": .string(result.persona),
            "voice_timbre": .string(result.timbre),
            "speech_rate_multiplier": .number(result.speechRateMultiplier),
            "locale_identifier": .string(result.localeIdentifier),
            "resolved_source": .string(result.resolution.resolvedSource.rawValue),
            "resolution_reason": .string(result.resolution.reasonCode),
            "activity_state": .string(result.activity.state.rawValue),
            "activity_reason": .string(result.activity.reasonCode),
            "provider": .string(result.activity.provider),
            "model_id": .string(result.activity.modelID),
            "engine_name": .string(result.activity.engineName),
            "speaker_id": .string(result.activity.speakerId),
            "device_backend": .string(result.activity.deviceBackend),
            "native_tts_used": result.activity.nativeTTSUsed.map(JSONValue.bool) ?? .null,
            "fallback_mode": .string(result.activity.fallbackMode),
            "fallback_reason_code": .string(result.activity.fallbackReasonCode),
            "audio_format": .string(result.activity.audioFormat),
            "voice_name": .string(result.activity.voiceName),
            "updated_at": .number(result.activity.updatedAt),
        ]
        summary["preferred_hub_voice_pack_id"] = result.resolution.preferredHubVoicePackID.isEmpty
            ? .null
            : .string(result.resolution.preferredHubVoicePackID)
        summary["resolved_hub_voice_pack_id"] = result.resolution.resolvedHubVoicePackID.isEmpty
            ? .null
            : .string(result.resolution.resolvedHubVoicePackID)
        summary["fallback_from"] = result.resolution.fallbackFrom.map { .string($0.rawValue) } ?? .null
        summary["actual_source"] = result.activity.actualSource.map { .string($0.rawValue) } ?? .null
        if action == "speak" {
            summary["input_chars"] = .number(Double(text.count))
        }

        let body = supervisorVoicePlaybackBody(action: action, inputText: action == "speak" ? text : "", result: result)
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: result.ok,
            output: structuredOutput(summary: summary, body: body)
        )
    }

    private static func executeRunLocalTask(call: ToolCall) async -> ToolResult {
        let taskKind = normalized(
            firstNonEmptyString(
                optStrArg(call, "task_kind"),
                optStrArg(call, "taskKind")
            )
        )?
        .lowercased() ?? ""
        guard supportedLocalTaskKinds.contains(taskKind) else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string("unsupported_task_kind"),
                "task_kind": taskKind.isEmpty ? .null : .string(taskKind),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: "unsupported_task_kind")
            )
        }

        let explicitModelID = normalized(
            firstNonEmptyString(
                optStrArg(call, "model_id"),
                optStrArg(call, "model")
            )
        )
        let preferredModelID = normalized(optStrArg(call, "preferred_model_id"))
        let modelResolution = resolveLocalTaskInvocationModel(
            taskKind: taskKind,
            explicitModelID: explicitModelID,
            preferredModelID: preferredModelID
        )
        guard let resolvedModelID = modelResolution.resolvedModelID else {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string(modelResolution.reasonCode),
                "task_kind": .string(taskKind),
                "requested_model_id": modelResolution.requestedModelID.map(JSONValue.string) ?? .null,
                "preferred_model_id": modelResolution.preferredModelID.map(JSONValue.string) ?? .null,
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: modelResolution.reasonCode)
            )
        }

        let parametersResult = localTaskParameters(from: call)
        guard case .success(let parameters) = parametersResult else {
            let reason: String
            switch parametersResult {
            case .failure(let failure):
                reason = failure.rawValue
            case .success:
                reason = "invalid_parameters_object"
            }
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string(reason),
                "task_kind": .string(taskKind),
                "model_id": .string(resolvedModelID),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: reason)
            )
        }

        if let validationFailure = validateLocalTaskParameters(
            taskKind: taskKind,
            parameters: parameters
        ) {
            let summary: [String: JSONValue] = [
                "tool": .string(call.tool.rawValue),
                "ok": .bool(false),
                "reason": .string(validationFailure),
                "task_kind": .string(taskKind),
                "model_id": .string(resolvedModelID),
                "parameter_keys": .array(parameters.keys.sorted().map(JSONValue.string)),
            ]
            return ToolResult(
                id: call.id,
                tool: call.tool,
                ok: false,
                output: structuredOutput(summary: summary, body: validationFailure)
            )
        }

        let deviceID = normalized(
            firstNonEmptyString(
                optStrArg(call, "device_id"),
                optStrArg(call, "deviceId")
            )
        )
        let timeoutSec = min(
            180.0,
            max(
                1.0,
                optDoubleArg(call, "timeout_sec")
                    ?? optDoubleArg(call, "timeoutSec")
                    ?? defaultLocalTaskTimeoutSec(for: taskKind)
            )
        )
        let result = HubIPCClient.executeLocalTaskViaLocalHub(
            taskKind: taskKind,
            modelID: resolvedModelID,
            parameters: parameters,
            deviceID: deviceID,
            timeoutSec: timeoutSec
        )

        var summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(result.ok),
            "task_kind": .string(normalized(result.taskKind) ?? taskKind),
            "model_id": .string(normalized(result.modelId) ?? resolvedModelID),
            "provider": normalized(result.provider).map(JSONValue.string) ?? .null,
            "source": .string(result.source),
            "runtime_source": normalized(result.runtimeSource).map(JSONValue.string) ?? .null,
            "reason": normalized(result.reasonCode).map(JSONValue.string) ?? .null,
            "runtime_reason": normalized(result.runtimeReasonCode).map(JSONValue.string) ?? .null,
            "parameter_keys": .array(parameters.keys.sorted().map(JSONValue.string)),
            "timeout_sec": .number(timeoutSec),
            "requested_model_id": modelResolution.requestedModelID.map(JSONValue.string) ?? .null,
            "preferred_model_id": modelResolution.preferredModelID.map(JSONValue.string) ?? .null,
            "model_resolution": .string(modelResolution.reasonCode),
        ]
        summary["device_id"] = deviceID.map(JSONValue.string) ?? .null

        if let text = localTaskPrimaryText(from: result.payload) {
            summary["text_chars"] = .number(Double(text.count))
        }
        if let vectorCount = localTaskNumericValue(result.payload["vectorCount"] ?? result.payload["vector_count"]) {
            summary["vector_count"] = .number(vectorCount)
        }
        if let dims = localTaskNumericValue(result.payload["dims"]) {
            summary["dims"] = .number(dims)
        }
        if let audioPath = normalized(
            result.payload["audioPath"]?.stringValue
                ?? result.payload["audio_path"]?.stringValue
        ) {
            summary["audio_path"] = .string(audioPath)
        }
        if let routeTrace = result.payload["routeTrace"]?.objectValue ?? result.payload["route_trace"]?.objectValue,
           let executionPath = normalized(
            routeTrace["executionPath"]?.stringValue
                ?? routeTrace["execution_path"]?.stringValue
           ) {
            summary["execution_path"] = .string(executionPath)
        }

        let body = result.ok
            ? localTaskSuccessBody(result: result, requestedTaskKind: taskKind, requestedModelID: resolvedModelID)
            : localTaskFailureBody(result: result, requestedTaskKind: taskKind, requestedModelID: resolvedModelID)
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: result.ok,
            output: structuredOutput(summary: summary, body: body)
        )
    }

    private static func localTaskParameters(
        from call: ToolCall
    ) -> Result<[String: JSONValue], LocalTaskParameterParsingError> {
        var parameters: [String: JSONValue] = [:]
        if let raw = call.args["parameters"] {
            guard let object = raw.objectValue else {
                return .failure(.invalidParametersObject)
            }
            parameters = object
        }

        for (key, value) in call.args {
            let token = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !localTaskReservedArgTokens.contains(token) else { continue }
            parameters[key] = value
        }
        return .success(parameters)
    }

    private static func validateLocalTaskParameters(
        taskKind: String,
        parameters: [String: JSONValue]
    ) -> String? {
        switch taskKind {
        case "text_generate":
            return localTaskHasAnyParameterValue(
                parameters,
                keys: ["prompt", "text", "content", "value", "messages", "multimodal_messages"]
            ) ? nil : "missing_prompt"
        case "embedding":
            return localTaskHasAnyParameterValue(
                parameters,
                keys: ["texts", "text", "content", "value", "query", "documents"]
            ) ? nil : "missing_embedding_input"
        case "speech_to_text":
            return localTaskHasAnyParameterValue(
                parameters,
                keys: ["audio_path"]
            ) ? nil : "missing_audio_path"
        case "text_to_speech":
            return localTaskHasAnyParameterValue(
                parameters,
                keys: ["text", "content", "value", "prompt"]
            ) ? nil : "missing_text"
        case "vision_understand", "ocr":
            return localTaskHasAnyParameterValue(
                parameters,
                keys: ["image_path", "image_paths", "multimodal_messages", "image"]
            ) ? nil : "missing_image_input"
        default:
            return "unsupported_task_kind"
        }
    }

    private static func defaultLocalTaskTimeoutSec(for taskKind: String) -> Double {
        switch taskKind {
        case "embedding":
            return 15.0
        case "speech_to_text", "vision_understand", "ocr":
            return 45.0
        default:
            return 30.0
        }
    }

    private static func localTaskHasAnyParameterValue(
        _ parameters: [String: JSONValue],
        keys: [String]
    ) -> Bool {
        for key in keys {
            if localTaskParameterValue(parameters, key: key) != nil {
                return true
            }
        }
        return false
    }

    private static func localTaskParameterValue(
        _ parameters: [String: JSONValue],
        key: String
    ) -> JSONValue? {
        if let value = parameters[key], localTaskParameterHasValue(value) {
            return value
        }
        if let input = parameters["input"]?.objectValue,
           let value = input[key],
           localTaskParameterHasValue(value) {
            return value
        }
        return nil
    }

    private static func localTaskParameterHasValue(_ value: JSONValue) -> Bool {
        switch value {
        case .null:
            return false
        case .string(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let rows):
            return !rows.isEmpty
        case .object(let object):
            return !object.isEmpty
        case .bool, .number:
            return true
        }
    }

    private static func localTaskPrimaryText(
        from payload: [String: JSONValue]
    ) -> String? {
        normalized(
            payload["text"]?.stringValue
                ?? payload["generated_text"]?.stringValue
                ?? payload["transcript"]?.stringValue
        )
    }

    private static func localTaskNumericValue(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number):
            return number
        case .string(let text):
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func resolveLocalTaskInvocationModel(
        taskKind: String,
        explicitModelID: String?,
        preferredModelID: String?
    ) -> LocalTaskModelInvocationResolution {
        if let explicitModelID {
            if let snapshot = localTaskModelStateSnapshot() {
                let resolution = HubModelSelectionAdvisor.resolveLocalTaskModel(
                    taskKind: taskKind,
                    explicitModelId: explicitModelID,
                    snapshot: snapshot
                )
                if let resolvedModel = resolution.resolvedModel {
                    return LocalTaskModelInvocationResolution(
                        requestedModelID: explicitModelID,
                        preferredModelID: preferredModelID,
                        resolvedModelID: resolvedModel.id,
                        reasonCode: resolution.reasonCode
                    )
                }
            }
            return LocalTaskModelInvocationResolution(
                requestedModelID: explicitModelID,
                preferredModelID: preferredModelID,
                resolvedModelID: explicitModelID,
                reasonCode: "explicit_model_passthrough"
            )
        }

        if let preferredModelID {
            if let snapshot = localTaskModelStateSnapshot() {
                let resolution = HubModelSelectionAdvisor.resolveLocalTaskModel(
                    taskKind: taskKind,
                    preferredModelId: preferredModelID,
                    snapshot: snapshot
                )
                return LocalTaskModelInvocationResolution(
                    requestedModelID: preferredModelID,
                    preferredModelID: preferredModelID,
                    resolvedModelID: resolution.resolvedModel?.id,
                    reasonCode: resolution.reasonCode
                )
            }
            return LocalTaskModelInvocationResolution(
                requestedModelID: preferredModelID,
                preferredModelID: preferredModelID,
                resolvedModelID: preferredModelID,
                reasonCode: "preferred_model_passthrough"
            )
        }

        guard let snapshot = localTaskModelStateSnapshot() else {
            return LocalTaskModelInvocationResolution(
                requestedModelID: nil,
                preferredModelID: nil,
                resolvedModelID: nil,
                reasonCode: "missing_model_id"
            )
        }

        let resolution = HubModelSelectionAdvisor.resolveLocalTaskModel(
            taskKind: taskKind,
            snapshot: snapshot
        )
        return LocalTaskModelInvocationResolution(
            requestedModelID: nil,
            preferredModelID: nil,
            resolvedModelID: resolution.resolvedModel?.id,
            reasonCode: resolution.reasonCode
        )
    }

    private static func localTaskModelStateSnapshot() -> ModelStateSnapshot? {
        let url = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private static func localTaskSuccessBody(
        result: HubIPCClient.LocalTaskResult,
        requestedTaskKind: String,
        requestedModelID: String
    ) -> String {
        var lines = [
            "本地模型任务已完成：task_kind=\(normalized(result.taskKind) ?? requestedTaskKind) model_id=\(normalized(result.modelId) ?? requestedModelID)"
        ]
        if let provider = normalized(result.provider) {
            lines.append("provider=\(provider)")
        }
        if let runtimeSource = normalized(result.runtimeSource) {
            lines.append("runtime_source=\(runtimeSource)")
        }
        if let text = localTaskPrimaryText(from: result.payload) {
            let excerpt = text.count > 1_200 ? String(text.prefix(1_200)) + "..." : text
            lines.append(excerpt)
        } else if let audioPath = normalized(
            result.payload["audioPath"]?.stringValue
                ?? result.payload["audio_path"]?.stringValue
        ) {
            lines.append("audio_path=\(audioPath)")
        } else if let vectorCount = localTaskNumericValue(result.payload["vectorCount"] ?? result.payload["vector_count"]) {
            var vectorLine = "vector_count=\(Int(vectorCount.rounded()))"
            if let dims = localTaskNumericValue(result.payload["dims"]) {
                vectorLine += " dims=\(Int(dims.rounded()))"
            }
            lines.append(vectorLine)
        }
        return lines.joined(separator: "\n")
    }

    private static func localTaskFailureBody(
        result: HubIPCClient.LocalTaskResult,
        requestedTaskKind: String,
        requestedModelID: String
    ) -> String {
        var lines = [
            "本地模型任务未完成：task_kind=\(normalized(result.taskKind) ?? requestedTaskKind) model_id=\(normalized(result.modelId) ?? requestedModelID)"
        ]
        if let reason = normalized(result.reasonCode) {
            lines.append("reason=\(reason)")
        }
        if let detail = normalized(result.detail), detail != normalized(result.reasonCode) {
            lines.append(detail)
        } else if let error = normalized(result.error), error != normalized(result.reasonCode) {
            lines.append(error)
        }
        return lines.joined(separator: "\n")
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

    private struct SummarizeLoadError: Error {
        var reasonCode: String
    }

    private static func loadSummarizeSource(
        call: ToolCall,
        projectRoot: URL
    ) async throws -> SummarizeLoadedSource {
        let url = (optStrArg(call, "url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let path = (optStrArg(call, "path") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let inlineText = firstNonEmptyString(
            optStrArg(call, "text"),
            optStrArg(call, "content"),
            optStrArg(call, "value")
        )
        let sourceCount = [!url.isEmpty, !path.isEmpty, !inlineText.isEmpty].filter { $0 }.count
        guard sourceCount > 0 else {
            throw SummarizeLoadError(reasonCode: "missing_source")
        }
        guard sourceCount == 1 else {
            throw SummarizeLoadError(reasonCode: "multiple_sources_provided")
        }

        if !url.isEmpty {
            let nested = ToolCall(
                id: "\(call.id)_browser_read",
                tool: .browser_read,
                args: [
                    "url": .string(url),
                    "grant_id": call.args["grant_id"] ?? .null,
                    "timeout_sec": call.args["timeout_sec"] ?? .number(15),
                    "max_bytes": call.args["max_bytes"] ?? .number(900_000),
                ]
            )
            let result = try await execute(call: nested, projectRoot: projectRoot)
            guard result.ok else {
                throw SummarizeLoadError(reasonCode: firstFailureReason(in: result.output))
            }
            let parsed = parseStructuredToolOutput(result.output)
            let header = jsonObject(parsed.summary) ?? [:]
            return SummarizeLoadedSource(
                kind: .url,
                title: summarizeSourceTitle(
                    url: jsonStringValue(header["final_url"]) ?? url,
                    fallback: url
                ),
                text: parsed.body,
                summary: [
                    "url": .string(url),
                    "final_url": header["final_url"] ?? .null,
                    "content_type": header["content_type"] ?? .null,
                    "grant_id": call.args["grant_id"] ?? .null,
                ]
            )
        }

        if !path.isEmpty {
            let nested = ToolCall(
                id: "\(call.id)_read_file",
                tool: .read_file,
                args: [
                    "path": .string(path),
                ]
            )
            let result = try await execute(call: nested, projectRoot: projectRoot)
            guard result.ok else {
                throw SummarizeLoadError(reasonCode: firstFailureReason(in: result.output))
            }
            return SummarizeLoadedSource(
                kind: .path,
                title: URL(fileURLWithPath: path).lastPathComponent,
                text: result.output,
                summary: [
                    "path": .string(path),
                ]
            )
        }

        return SummarizeLoadedSource(
            kind: .text,
            title: "inline_text",
            text: inlineText,
            summary: [:]
        )
    }

    private static func searchLocalSkillCatalog(
        query: String,
        sourceFilter: String?,
        limit: Int,
        hubBaseDir: URL
    ) -> HubIPCClient.SkillsSearchResult? {
        let indexURL = hubBaseDir
            .appendingPathComponent("skills_store", isDirectory: true)
            .appendingPathComponent("skills_store_index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let snapshot = try? JSONDecoder().decode(LocalSkillCatalogIndexSnapshot.self, from: data) else {
            return nil
        }

        let normalizedSourceFilter = (sourceFilter ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tokens = searchableTokens(query)
        let entries = snapshot.skills
            .compactMap { row -> (score: Int, skill: LocalSkillCatalogIndexSnapshot.Skill)? in
                if !normalizedSourceFilter.isEmpty,
                   !row.sourceID.lowercased().contains(normalizedSourceFilter) {
                    return nil
                }
                let score = localSkillCatalogScore(skill: row, tokens: tokens, rawQuery: query)
                guard score > 0 else { return nil }
                return (score, row)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                let nameOrder = lhs.skill.name.localizedCaseInsensitiveCompare(rhs.skill.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.skill.skillID < rhs.skill.skillID
            }
            .prefix(limit)
            .map { row in
                HubIPCClient.SkillCatalogEntry(
                    skillID: row.skill.skillID,
                    name: row.skill.name,
                    version: row.skill.version,
                    description: row.skill.description,
                    publisherID: row.skill.publisherID,
                    capabilitiesRequired: row.skill.capabilitiesRequired,
                    sourceID: row.skill.sourceID,
                    packageSHA256: row.skill.packageSHA256,
                    installHint: row.skill.installHint,
                    riskLevel: row.skill.riskLevel,
                    requiresGrant: row.skill.requiresGrant,
                    sideEffectClass: row.skill.sideEffectClass
                )
            }

        return HubIPCClient.SkillsSearchResult(
            ok: true,
            source: "local_hub_index",
            updatedAtMs: snapshot.updatedAtMs,
            results: entries,
            reasonCode: nil,
            officialChannelStatus: nil
        )
    }

    private static func localSkillCatalogScore(
        skill: LocalSkillCatalogIndexSnapshot.Skill,
        tokens: [String],
        rawQuery: String
    ) -> Int {
        let normalizedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedQuery.isEmpty {
            return 1
        }
        var score = 0
        if skill.skillID.lowercased() == normalizedQuery {
            score += 200
        }
        if skill.name.lowercased() == normalizedQuery {
            score += 180
        }
        if skill.skillID.lowercased().contains(normalizedQuery) {
            score += 120
        }
        if skill.name.lowercased().contains(normalizedQuery) {
            score += 100
        }
        for token in tokens {
            if skill.skillID.lowercased().contains(token) {
                score += 40
            }
            if skill.name.lowercased().contains(token) {
                score += 32
            }
            if skill.capabilitiesRequired.contains(where: { $0.lowercased().contains(token) }) {
                score += 24
            }
            if skill.description.lowercased().contains(token) {
                score += 12
            }
            if skill.installHint.lowercased().contains(token) {
                score += 6
            }
        }
        if skill.publisherID == "xhub.official" {
            score += 4
        }
        return score
    }

    private static func searchableTokens(_ query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" && $0 != "." })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalizedSummarizeFormat(_ raw: String?) -> String {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bullets", "bullet", "list":
            return "bullets"
        default:
            return "paragraph"
        }
    }

    private static func governedSummaryBody(
        sourceText: String,
        title: String,
        focus: String,
        format: String,
        maxChars: Int
    ) -> String {
        let focusTokens = searchableTokens(focus)
        let candidates = summaryCandidates(from: sourceText)
        let ranked = rankSummaryCandidates(candidates, focusTokens: focusTokens)
        let selected = selectSummarySegments(
            ranked,
            maxChars: maxChars,
            maxItems: format == "bullets" ? 5 : 3
        )
        if selected.isEmpty {
            return String(sourceText.prefix(maxChars))
        }

        if format == "bullets" {
            let titleLine = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : ["Title: \(title)"]
            let bodyLines = selected.map { "- \($0)" }
            return (titleLine + bodyLines).joined(separator: "\n")
        }

        let prefix = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\(title): "
        let joined = selected.joined(separator: " ")
        let focused = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if focused.isEmpty {
            return capped(prefix + joined, maxChars: maxChars)
        }
        return capped(prefix + joined + " Focus: " + focused, maxChars: maxChars)
    }

    private static func summaryCandidates(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        for line in lines {
            if line.count <= 240 {
                out.append(line)
            }
            for segment in sentenceSegments(from: line) where segment.count > 24 {
                out.append(segment)
            }
        }
        return out
    }

    private static func sentenceSegments(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ".!?。！？;；")
        let parts = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count <= 1 {
            return parts
        }
        return parts.map { segment in
            let collapsed = segment.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func rankSummaryCandidates(
        _ candidates: [String],
        focusTokens: [String]
    ) -> [String] {
        var seen = Set<String>()
        let ranked = candidates.enumerated().compactMap { index, candidate -> (Int, String)? in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            let dedupeKey = normalized.lowercased()
            guard seen.insert(dedupeKey).inserted else { return nil }

            var score = max(0, 120 - index)
            if normalized.count >= 40 && normalized.count <= 220 {
                score += 24
            }
            if normalized.hasPrefix("-") || normalized.hasPrefix("*") {
                score += 14
            }
            if normalized.contains(":") {
                score += 8
            }
            let lowered = normalized.lowercased()
            for token in focusTokens where lowered.contains(token) {
                score += 40
            }
            return (score, normalized)
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 > rhs.0 }
                if lhs.1.count != rhs.1.count { return lhs.1.count < rhs.1.count }
                return lhs.1 < rhs.1
            }
            .map(\.1)
    }

    private static func selectSummarySegments(
        _ ranked: [String],
        maxChars: Int,
        maxItems: Int
    ) -> [String] {
        var selected: [String] = []
        var usedChars = 0
        for segment in ranked {
            guard selected.count < maxItems else { break }
            let cost = segment.count + (selected.isEmpty ? 0 : 1)
            if !selected.isEmpty && usedChars + cost > maxChars {
                continue
            }
            selected.append(segment)
            usedChars += cost
            if usedChars >= maxChars { break }
        }
        return selected
    }

    private static func normalizedSummarySourceText(_ raw: String) -> String {
        let candidate: String
        if raw.lowercased().contains("<html") || raw.lowercased().contains("<body") {
            candidate = htmlToReadableText(raw)
        } else {
            candidate = raw
        }
        return candidate
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func summarizeSourceTitle(url: String, fallback: String) -> String {
        if let parsed = URL(string: url), let host = parsed.host, !host.isEmpty {
            let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.isEmpty {
                return host
            }
            let tail = path.components(separatedBy: "/").last ?? path
            return "\(host)/\(tail)"
        }
        return fallback
    }

    private static func supervisorVoicePlaybackBody(
        action: String,
        inputText: String,
        result: SupervisorManager.SupervisorVoiceSkillExecutionResult
    ) -> String {
        var lines: [String] = []
        switch action {
        case "status":
            lines.append("Supervisor 语音状态已就绪。")
        case "preview":
            lines.append(result.ok ? "Supervisor 语音试听已完成。" : "Supervisor 语音试听未能开始。")
        case "speak":
            lines.append(result.ok ? "Supervisor 语音播放已完成。" : "Supervisor 语音播放未能开始。")
            if !inputText.isEmpty {
                lines.append("文本：\(capped(inputText, maxChars: 120))")
            }
        case "stop":
            lines.append(result.ok ? "Supervisor 语音播放已停止。" : "当前没有正在播放的 Supervisor 语音。")
        default:
            lines.append("Supervisor 语音动作已完成。")
        }

        lines.append("请求输出：\(VoicePlaybackPreference(rawValue: result.playbackPreference)?.displayName ?? result.playbackPreference)")
        lines.append("实际输出：\(result.resolution.resolvedSource.displayName)")
        if !result.resolution.resolvedHubVoicePackID.isEmpty {
            lines.append("实际语音包：\(result.resolution.resolvedHubVoicePackID)")
        } else if !result.resolution.preferredHubVoicePackID.isEmpty {
            lines.append("首选语音包：\(result.resolution.preferredHubVoicePackID)")
        }
        lines.append("最近一次播放：\(result.activity.headline)")
        lines.append(result.activity.summaryLine)
        lines.append("人格：\(result.persona)  音色：\(result.timbre)  语速：\(String(format: "%.2fx", result.speechRateMultiplier))")
        lines.append("语言：\(result.localeIdentifier)")
        lines.append("原因：\(result.reasonCode)")
        if !result.activity.engineDisplayName.isEmpty {
            lines.append("引擎：\(result.activity.engineDisplayName)")
        }
        if !result.activity.speakerId.isEmpty {
            lines.append("说话人：\(result.activity.speakerDisplayName)")
        }
        if result.activity.shouldDisplayExecutionMode {
            lines.append("执行模式：\(result.activity.executionModeDisplayName)")
        }
        if !result.activity.fallbackReasonCode.isEmpty {
            lines.append("回退原因：\(result.activity.fallbackReasonDisplayName)")
        }
        if !result.activity.voiceName.isEmpty {
            lines.append("声音：\(result.activity.voiceName)")
        }
        if !result.activity.modelID.isEmpty {
            lines.append("模型：\(result.activity.modelID)")
        }
        return lines.joined(separator: "\n")
    }

    private static func capped(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max(0, maxChars))
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNonEmptyString(_ values: String?...) -> String {
        for value in values {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return value ?? ""
            }
        }
        return ""
    }

    private static func jsonObject(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private static func jsonStringValue(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        return text
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

    private static func jsonObject(from text: String?) -> [String: Any]? {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func jsonStringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func jsonNumberValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
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

    private static func managedProcessEnv(_ call: ToolCall) -> [String: String] {
        guard case .object(let object)? = call.args["env"] else { return [:] }
        var env: [String: String] = [:]
        for key in object.keys.sorted() {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { continue }
            switch object[key] {
            case .string(let value):
                env[normalizedKey] = value
            case .number(let value):
                env[normalizedKey] = String(value)
            case .bool(let value):
                env[normalizedKey] = value ? "true" : "false"
            default:
                continue
            }
        }
        return env
    }

    private static func stringArrayArg(_ call: ToolCall, _ key: String) -> [String] {
        guard case .array(let values)? = call.args[key] else { return [] }
        return values.compactMap { value in
            guard case .string(let text) = value else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func jsonBoolValue(_ value: JSONValue?) -> Bool? {
        guard case .bool(let flag)? = value else { return nil }
        return flag
    }

    private static func managedProcessSummaryObject(
        _ record: XTManagedProcessRecord,
        projectRoot: URL
    ) -> [String: JSONValue] {
        [
            "process_id": .string(record.processId),
            "name": .string(record.name),
            "command": .string(record.command),
            "cwd": .string(record.cwd),
            "status": .string(record.status.rawValue),
            "pid": record.pid.map { .number(Double($0)) } ?? .null,
            "restart_on_exit": .bool(record.restartOnExit),
            "restart_count": .number(Double(record.restartCount)),
            "created_at_ms": .number(Double(record.createdAtMs)),
            "started_at_ms": record.startedAtMs.map { .number(Double($0)) } ?? .null,
            "updated_at_ms": .number(Double(record.updatedAtMs)),
            "exit_code": record.exitCode.map { .number(Double($0)) } ?? .null,
            "termination_reason": record.terminationReason.map(JSONValue.string) ?? .null,
            "last_error": record.lastError.map(JSONValue.string) ?? .null,
            "log_path": .string(relativeDisplayPath(record.logPath, projectRoot: projectRoot)),
        ]
    }

    private static func managedProcessStatusLine(_ record: XTManagedProcessRecord) -> String {
        var parts = [
            "- \(record.processId)",
            "name=\(record.name)",
            "status=\(record.status.rawValue)",
            "cwd=\(record.cwd)",
        ]
        if let pid = record.pid {
            parts.append("pid=\(pid)")
        }
        if record.restartOnExit {
            parts.append("restart=\(record.restartCount)")
        }
        if let exitCode = record.exitCode {
            parts.append("exit=\(exitCode)")
        }
        return parts.joined(separator: " | ")
    }

    private static func relativeDisplayPath(_ rawPath: String, projectRoot: URL) -> String {
        guard rawPath.hasPrefix("/") else { return rawPath }
        let target = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let root = projectRoot.standardizedFileURL.path
        if target == root {
            return "."
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if target.hasPrefix(prefix) {
            return String(target.dropFirst(prefix.count))
        }
        return target
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

    private static func governedReadableRoots(
        projectRoot: URL,
        config: AXProjectConfig,
        effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy,
        extraReadableRoots: [URL] = []
    ) -> [URL] {
        var roots: [URL] = [projectRoot]
        guard xtProjectGovernedDeviceAuthorityEnabled(
            projectRoot: projectRoot,
            config: config,
            effectiveRuntimeSurface: effectiveRuntimeSurface
        ) else {
            for root in extraReadableRoots {
                roots.append(root)
            }
            return deduplicatedReadableRoots(roots)
        }

        for raw in config.governedReadableRoots {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            roots.append(URL(fileURLWithPath: trimmed))
        }
        roots.append(contentsOf: extraReadableRoots)

        return deduplicatedReadableRoots(roots)
    }

    private static func deduplicatedReadableRoots(_ roots: [URL]) -> [URL] {
        var ordered: [URL] = []
        var seen = Set<String>()
        for root in roots {
            let resolved = PathGuard.resolve(root).path
            guard seen.insert(resolved).inserted else { continue }
            ordered.append(URL(fileURLWithPath: resolved, isDirectory: true))
        }
        return ordered
    }

    private static func deniedPathScopeResult(
        call: ToolCall,
        projectRoot: URL,
        violation: XTPathScopeViolation
    ) -> ToolResult {
        let summary: [String: JSONValue] = [
            "tool": .string(call.tool.rawValue),
            "ok": .bool(false),
            "project_id": .string(AXProjectRegistryStore.projectId(forRoot: projectRoot)),
            "deny_code": .string(violation.denyCode),
            "policy_source": .string("governed_path_scope"),
            "policy_reason": .string(violation.policyReason),
            "target_path": .string(violation.targetPath),
            "allowed_roots": .array(violation.allowedRoots.map(JSONValue.string)),
        ]
        return ToolResult(
            id: call.id,
            tool: call.tool,
            ok: false,
            output: structuredOutput(summary: summary, body: violation.detail)
        )
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
        effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy? = nil
    ) -> ToolResult {
        let summary = xtToolRuntimePolicyDeniedSummary(
            call: call,
            projectRoot: projectRoot,
            config: config,
            decision: decision,
            effectiveRuntimeSurface: effectiveRuntimeSurface
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
                displayName: AXProjectRegistryStore.displayName(forRoot: projectRoot),
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
        case .delete_path, .move_path, .git_commit, .git_push, .git_apply, .pr_create, .ci_trigger, .process_start, .deviceUIAct, .deviceUIStep, .deviceBrowserControl, .deviceAppleScript:
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
        case .delete_path:
            return "tool.delete_path path=\(optStrArg(call, "path") ?? "(none)")"
        case .move_path:
            return "tool.move_path from=\(optStrArg(call, "from") ?? "(none)") to=\(optStrArg(call, "to") ?? "(none)")"
        case .git_commit:
            return "tool.git_commit message=\(optStrArg(call, "message") ?? "(none)")"
        case .git_push:
            return "tool.git_push remote=\(optStrArg(call, "remote") ?? "(default)") branch=\(optStrArg(call, "branch") ?? "(default)")"
        case .run_command:
            return "tool.run_command command=\(optStrArg(call, "command") ?? "(none)")"
        case .pr_create:
            return "tool.pr_create title=\(optStrArg(call, "title") ?? "(none)")"
        case .ci_trigger:
            return "tool.ci_trigger workflow=\(optStrArg(call, "workflow") ?? "(none)")"
        case .process_start:
            return "tool.process_start command=\(optStrArg(call, "command") ?? "(none)")"
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
        case .delete_path:
            return "delete_target=\(optStrArg(call, "path") ?? "(none)")\nrecursive=\(optBoolArg(call, "recursive") ?? false)"
        case .move_path:
            return "move_from=\(optStrArg(call, "from") ?? "(none)")\nmove_to=\(optStrArg(call, "to") ?? "(none)")"
        case .git_commit:
            return "message=\(optStrArg(call, "message") ?? "(none)")\nall=\(optBoolArg(call, "all") ?? false)\npaths=\(stringArrayArg(call, "paths").joined(separator: ","))"
        case .git_push:
            return "remote=\(optStrArg(call, "remote") ?? "(default)")\nbranch=\(optStrArg(call, "branch") ?? "(default)")\nset_upstream=\(optBoolArg(call, "set_upstream") ?? false)"
        case .run_command:
            let command = optStrArg(call, "command") ?? "(none)"
            return "command=\(command)"
        case .pr_create:
            return "title=\(optStrArg(call, "title") ?? "(none)")\nbase=\(optStrArg(call, "base") ?? "(default)")\nhead=\(optStrArg(call, "head") ?? "(default)")"
        case .ci_trigger:
            return "workflow=\(optStrArg(call, "workflow") ?? "(none)")\nref=\(optStrArg(call, "ref") ?? "(default)")"
        case .process_start:
            return "command=\(optStrArg(call, "command") ?? "(none)")\ncwd=\(optStrArg(call, "cwd") ?? ".")\nrestart_on_exit=\(optBoolArg(call, "restart_on_exit") ?? false)"
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
            approvedGrantId: nil,
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
        approvedGrantId: String? = nil,
        fallbackSeconds: Int
    ) async -> String? {
        guard highRiskCapabilityMatches(capability, target: .webFetch) else {
            return nil
        }
        return await noteActiveHighRiskGrant(
            projectRoot: projectRoot,
            capability: .webFetch,
            grantRequestId: grantRequestId,
            approvedGrantId: approvedGrantId,
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
        approvedGrantId: String?,
        fallbackSeconds: Int
    ) async -> String? {
        let ttl = max(60, fallbackSeconds)
        let grantId = await highRiskGrantLedger.registerActiveGrant(
            projectRootKey: normalizeRootKey(projectRoot),
            capability: capability.rawValue,
            grantRequestId: grantRequestId,
            approvedGrantId: approvedGrantId,
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
        return nil
    }

    private static func toolInputGrantId(_ input: [String: Any]?) -> String? {
        guard let input else { return nil }
        if let grant = input["grant_id"] as? String {
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

    private static func highRiskCapabilityMatches(
        _ raw: String,
        target: HighRiskCapability
    ) -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch target {
        case .webFetch:
            return token == HighRiskCapability.webFetch.rawValue.lowercased()
                || token == "web.fetch"
        }
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
        var grantRequestId: String
        var issuedAt: TimeInterval
        var expiresAt: TimeInterval
    }

    private var records: [String: GrantRecord] = [:]
    private let maxRecords = 512

    func registerActiveGrant(
        projectRootKey: String,
        capability: String,
        grantRequestId: String?,
        approvedGrantId: String?,
        fallbackTTLSeconds: Int,
        now: TimeInterval
    ) -> String {
        let root = projectRootKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty, !cap.isEmpty else { return "" }

        let requestToken = normalizedGrant(grantRequestId)
        let approvedToken = normalizedGrant(approvedGrantId)
        let grantId: String
        if !approvedToken.isEmpty {
            grantId = approvedToken
        } else if !requestToken.isEmpty,
                  let existing = records.values.first(where: {
                      $0.projectRootKey == root
                          && $0.capability == cap
                          && $0.grantRequestId == requestToken
                  }) {
            grantId = existing.grantId
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
            grantRequestId: requestToken,
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
