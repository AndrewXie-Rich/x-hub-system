import Foundation

enum SupervisorDoctorSeverity: String, Codable {
    case info
    case warning
    case blocking
}

enum SupervisorDoctorPriority: String, Codable {
    case p0
    case p1
    case p2
}

struct SupervisorDoctorFinding: Codable, Equatable, Identifiable {
    var id: String { code }
    var code: String
    var area: String
    var severity: SupervisorDoctorSeverity
    var priority: SupervisorDoctorPriority
    var title: String
    var detail: String
    var priorityReason: String
    var actions: [String]
    var verifyHint: String?
}

struct SupervisorDoctorSuggestionCard: Codable, Equatable, Identifiable {
    var id: String { findingCode }
    var findingCode: String
    var priority: SupervisorDoctorPriority
    var title: String
    var why: String
    var actions: [String]
    var verifyHint: String?
}

struct SupervisorDoctorSummary: Codable, Equatable {
    var doctorReportPresent: Int
    var releaseBlockedByDoctorWithoutReport: Int
    var blockingCount: Int
    var warningCount: Int
    var dmAllowlistRiskCount: Int
    var wsAuthRiskCount: Int
    var preAuthFloodBreakerRiskCount: Int
    var secretsPathOutOfScopeCount: Int
    var secretsMissingVariableCount: Int
    var secretsPermissionBoundaryCount: Int
}

struct SupervisorDoctorReport: Codable, Equatable {
    var schemaVersion: String
    var generatedAtMs: Int64
    var workspaceRoot: String
    var configSource: String
    var secretsPlanSource: String
    var ok: Bool
    var findings: [SupervisorDoctorFinding]
    var suggestions: [SupervisorDoctorSuggestionCard]
    var summary: SupervisorDoctorSummary
}

private struct SupervisorSecretsDryRunCompatItem: Codable, Equatable {
    var code: String
    var title: String
    var detail: String
    var targetPath: String
    var missingVars: [String]
    var permissionBoundary: String

    enum CodingKeys: String, CodingKey {
        case code
        case title
        case detail
        case targetPath
        case missingVars
        case permissionBoundary = "permission_boundary"
    }
}

private struct SupervisorSecretsDryRunCompatReport: Codable, Equatable {
    var schemaVersion: String
    var generatedAtMs: Int64
    var dryRun: Bool
    var sourceReport: String
    var blockingCount: Int
    var targetPathOutOfScopeCount: Int
    var missingVariablesCount: Int
    var permissionBoundaryErrorCount: Int
    var items: [SupervisorSecretsDryRunCompatItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case dryRun = "dry_run"
        case sourceReport = "source_report"
        case blockingCount = "blocking_count"
        case targetPathOutOfScopeCount = "target_path_out_of_scope_count"
        case missingVariablesCount = "missing_variables_count"
        case permissionBoundaryErrorCount = "permission_boundary_error_count"
        case items
    }
}

private struct SupervisorDoctorCompatPayload: Codable, Equatable {
    var dmPolicy: String
    var allowFrom: [String]
    var wsOrigin: String
    var sharedTokenAuth: Bool
    var authzParityForAllIngress: Bool
    var nonMessageIngressPolicyCoverage: Int
    var unauthorizedFloodDropCount: Int

    enum CodingKeys: String, CodingKey {
        case dmPolicy
        case allowFrom
        case wsOrigin = "ws_origin"
        case sharedTokenAuth = "shared_token_auth"
        case authzParityForAllIngress = "authz_parity_for_all_ingress"
        case nonMessageIngressPolicyCoverage = "non_message_ingress_policy_coverage"
        case unauthorizedFloodDropCount = "unauthorized_flood_drop_count"
    }
}

private struct SupervisorDoctorCompatReport: Codable, Equatable {
    var schemaVersion: String
    var generatedAtMs: Int64
    var status: String
    var doctor: SupervisorDoctorCompatPayload

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case status
        case doctor
    }
}

struct SupervisorDoctorConfig: Codable, Equatable {
    struct WebSocketConfig: Codable, Equatable {
        var allowedOrigins: [String]
        var sharedTokenAuthEnabled: Bool
        var sharedTokenRef: String?
    }

    struct PreAuthFloodBreaker: Codable, Equatable {
        var enabled: Bool
        var maxUnauthorizedPerMinute: Int
        var banSeconds: Int
    }

    struct PreAuthConfig: Codable, Equatable {
        var bodyBytesCap: Int
        var keyCountCap: Int
        var floodBreaker: PreAuthFloodBreaker
    }

    var dmPolicy: String
    var allowFrom: [String]
    var webSocket: WebSocketConfig
    var preAuth: PreAuthConfig

    static func conservativeDefault() -> SupervisorDoctorConfig {
        SupervisorDoctorConfig(
            dmPolicy: "allowlist",
            allowFrom: ["group:release_ops"],
            webSocket: .init(
                allowedOrigins: ["https://localhost"],
                sharedTokenAuthEnabled: true,
                sharedTokenRef: "secrets://x-terminal/ws_shared_token"
            ),
            preAuth: .init(
                bodyBytesCap: 128 * 1024,
                keyCountCap: 64,
                floodBreaker: .init(
                    enabled: true,
                    maxUnauthorizedPerMinute: 45,
                    banSeconds: 90
                )
            )
        )
    }
}

struct SupervisorSecretsDryRunPlan: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String { targetPath }
        var name: String?
        var targetPath: String
        var requiredVariables: [String]
        var providedVariables: [String]
        var mode: String
    }

    var allowedRoots: [String]
    var allowedModes: [String]
    var items: [Item]

    static func conservativeDefault(workspaceRoot: URL) -> SupervisorSecretsDryRunPlan {
        SupervisorSecretsDryRunPlan(
            allowedRoots: [
                workspaceRoot.appendingPathComponent(".axcoder/secrets").path
            ],
            allowedModes: ["0600", "0640"],
            items: []
        )
    }
}

struct SupervisorDoctorInputBundle {
    var workspaceRoot: URL
    var config: SupervisorDoctorConfig
    var configSource: String
    var secretsPlan: SupervisorSecretsDryRunPlan?
    var secretsPlanSource: String
    var reportURL: URL
}

struct SupervisorDoctorGateDecision {
    var pass: Bool
    var releaseBlockedByDoctorWithoutReport: Int
    var reason: String
}

enum SupervisorDoctorGateEvaluator {
    static func evaluate(report: SupervisorDoctorReport?) -> SupervisorDoctorGateDecision {
        guard let report else {
            return SupervisorDoctorGateDecision(
                pass: false,
                releaseBlockedByDoctorWithoutReport: 1,
                reason: "missing_supervisor_doctor_report"
            )
        }

        if report.summary.releaseBlockedByDoctorWithoutReport != 0 {
            return SupervisorDoctorGateDecision(
                pass: false,
                releaseBlockedByDoctorWithoutReport: report.summary.releaseBlockedByDoctorWithoutReport,
                reason: "invalid_release_blocked_by_doctor_without_report_metric"
            )
        }

        if report.summary.blockingCount > 0 || !report.ok {
            return SupervisorDoctorGateDecision(
                pass: false,
                releaseBlockedByDoctorWithoutReport: 0,
                reason: "doctor_blocking_findings_present"
            )
        }

        return SupervisorDoctorGateDecision(
            pass: true,
            releaseBlockedByDoctorWithoutReport: 0,
            reason: "ok"
        )
    }
}

enum SupervisorDoctorChecker {
    static let schemaVersion = "supervisor_doctor.v1"

    static func run(input: SupervisorDoctorInputBundle, now: Date = Date()) -> SupervisorDoctorReport {
        var findings: [SupervisorDoctorFinding] = []
        findings.append(contentsOf: checkDirectMessageAllowlist(config: input.config))
        findings.append(contentsOf: checkWebSocketSecurity(config: input.config))
        findings.append(contentsOf: checkPreAuthFloodBreaker(config: input.config))
        findings.append(contentsOf: checkSecretsDryRun(plan: input.secretsPlan, workspaceRoot: input.workspaceRoot))

        let blockingCount = findings.filter { $0.severity == .blocking }.count
        let warningCount = findings.filter { $0.severity == .warning }.count
        let suggestions = findings
            .filter { $0.severity == .blocking || $0.severity == .warning }
            .map { finding in
                SupervisorDoctorSuggestionCard(
                    findingCode: finding.code,
                    priority: finding.priority,
                    title: finding.title,
                    why: finding.priorityReason,
                    actions: finding.actions,
                    verifyHint: finding.verifyHint
                )
            }

        let summary = SupervisorDoctorSummary(
            doctorReportPresent: 1,
            releaseBlockedByDoctorWithoutReport: 0,
            blockingCount: blockingCount,
            warningCount: warningCount,
            dmAllowlistRiskCount: findings.filter { $0.area == "dm_allowlist" }.count,
            wsAuthRiskCount: findings.filter { $0.area == "ws_auth" }.count,
            preAuthFloodBreakerRiskCount: findings.filter { $0.area == "pre_auth_flood_breaker" }.count,
            secretsPathOutOfScopeCount: findings.filter { $0.code == "secrets_target_path_out_of_scope" }.count,
            secretsMissingVariableCount: findings.filter { $0.code == "secrets_missing_required_variables" }.count,
            secretsPermissionBoundaryCount: findings.filter { $0.code == "secrets_permission_boundary_error" }.count
        )

        return SupervisorDoctorReport(
            schemaVersion: schemaVersion,
            generatedAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded()),
            workspaceRoot: input.workspaceRoot.path,
            configSource: input.configSource,
            secretsPlanSource: input.secretsPlanSource,
            ok: blockingCount == 0,
            findings: findings,
            suggestions: suggestions,
            summary: summary
        )
    }

    static func runAndPersist(input: SupervisorDoctorInputBundle, now: Date = Date()) -> SupervisorDoctorReport {
        let report = run(input: input, now: now)
        writeReport(report, to: input.reportURL)
        writeDoctorCompatReport(
            report,
            config: input.config,
            sourceReportURL: input.reportURL,
            workspaceRoot: input.workspaceRoot
        )
        writeSecretsDryRunCompatReport(
            report,
            sourceReportURL: input.reportURL,
            workspaceRoot: input.workspaceRoot
        )
        return report
    }

    static func loadDefaultInputBundle(
        workspaceRoot: URL = defaultWorkspaceRoot(),
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> SupervisorDoctorInputBundle {
        let configURL = URL(fileURLWithPath: env["XTERMINAL_SUPERVISOR_DOCTOR_CONFIG"] ?? "")
        let hasCustomConfigURL = !(env["XTERMINAL_SUPERVISOR_DOCTOR_CONFIG"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let resolvedConfigURL = hasCustomConfigURL
            ? configURL
            : workspaceRoot.appendingPathComponent(".axcoder/supervisor/doctor_config.json")

        let secretsURL = URL(fileURLWithPath: env["XTERMINAL_SUPERVISOR_SECRETS_DRY_RUN_PLAN"] ?? "")
        let hasCustomSecretsURL = !(env["XTERMINAL_SUPERVISOR_SECRETS_DRY_RUN_PLAN"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let resolvedSecretsURL = hasCustomSecretsURL
            ? secretsURL
            : workspaceRoot.appendingPathComponent(".axcoder/secrets/secrets_apply_dry_run.json")

        let reportURL = URL(fileURLWithPath: env["XTERMINAL_SUPERVISOR_DOCTOR_REPORT_PATH"] ?? "")
        let hasCustomReportURL = !(env["XTERMINAL_SUPERVISOR_DOCTOR_REPORT_PATH"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let resolvedReportURL = hasCustomReportURL
            ? reportURL
            : workspaceRoot.appendingPathComponent(".axcoder/reports/supervisor_doctor_report.json")

        let config: SupervisorDoctorConfig
        let configSource: String
        if let loaded: SupervisorDoctorConfig = loadJSON(at: resolvedConfigURL) {
            config = loaded
            configSource = resolvedConfigURL.path
        } else {
            config = SupervisorDoctorConfig.conservativeDefault()
            configSource = "defaults(conservative)"
        }

        let secretsPlan: SupervisorSecretsDryRunPlan?
        let secretsSource: String
        if let loaded: SupervisorSecretsDryRunPlan = loadJSON(at: resolvedSecretsURL) {
            secretsPlan = loaded
            secretsSource = resolvedSecretsURL.path
        } else {
            secretsPlan = nil
            secretsSource = "missing"
        }

        return SupervisorDoctorInputBundle(
            workspaceRoot: workspaceRoot,
            config: config,
            configSource: configSource,
            secretsPlan: secretsPlan,
            secretsPlanSource: secretsSource,
            reportURL: resolvedReportURL
        )
    }

    static func defaultWorkspaceRoot() -> URL {
        let env = (ProcessInfo.processInfo.environment["XTERMINAL_WORKSPACE_ROOT"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            return URL(fileURLWithPath: NSString(string: env).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    static func writeReport(_ report: SupervisorDoctorReport, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // Keep doctor check pure fail-closed: report write failure should not crash app loop.
            print("SupervisorDoctor write report failed: \(error)")
        }
    }

    static func writeDoctorCompatReport(
        _ report: SupervisorDoctorReport,
        config: SupervisorDoctorConfig,
        sourceReportURL: URL,
        workspaceRoot: URL
    ) {
        let destinationURL = resolvedDoctorCompatReportURL(
            sourceReportURL: sourceReportURL,
            workspaceRoot: workspaceRoot
        )
        let wsOrigin = config.webSocket.allowedOrigins
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let hasAuthBoundaryRisk = report.findings.contains { finding in
            finding.area == "dm_allowlist" || finding.area == "ws_auth"
        }
        let hasIngressCoverageRisk = report.findings.contains { finding in
            finding.area == "pre_auth_flood_breaker"
        }
        let compat = SupervisorDoctorCompatReport(
            schemaVersion: "doctor_report.v1",
            generatedAtMs: report.generatedAtMs,
            status: report.ok ? "pass" : "fail",
            doctor: SupervisorDoctorCompatPayload(
                dmPolicy: config.dmPolicy,
                allowFrom: config.allowFrom,
                wsOrigin: wsOrigin,
                sharedTokenAuth: config.webSocket.sharedTokenAuthEnabled,
                authzParityForAllIngress: !hasAuthBoundaryRisk,
                nonMessageIngressPolicyCoverage: hasIngressCoverageRisk ? 0 : 1,
                unauthorizedFloodDropCount: max(0, config.preAuth.floodBreaker.maxUnauthorizedPerMinute)
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(compat) else { return }
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            // Keep doctor check pure fail-closed: sidecar write failure should not crash app loop.
            print("SupervisorDoctor write doctor compat report failed: \(error)")
        }
    }

    static func writeSecretsDryRunCompatReport(
        _ report: SupervisorDoctorReport,
        sourceReportURL: URL,
        workspaceRoot: URL
    ) {
        let destinationURL = resolvedSecretsDryRunCompatReportURL(
            sourceReportURL: sourceReportURL,
            workspaceRoot: workspaceRoot
        )
        let payload = SupervisorSecretsDryRunCompatReport(
            schemaVersion: "secrets_dry_run.v1",
            generatedAtMs: report.generatedAtMs,
            dryRun: true,
            sourceReport: sourceReportURL.path,
            blockingCount: report.summary.blockingCount,
            targetPathOutOfScopeCount: report.summary.secretsPathOutOfScopeCount,
            missingVariablesCount: report.summary.secretsMissingVariableCount,
            permissionBoundaryErrorCount: report.summary.secretsPermissionBoundaryCount,
            items: report.findings
                .filter { $0.area == "secrets_dry_run" }
                .map { finding in
                    SupervisorSecretsDryRunCompatItem(
                        code: finding.code,
                        title: finding.title,
                        detail: finding.detail,
                        targetPath: targetPathHint(from: finding.detail),
                        missingVars: missingVariablesHint(from: finding.detail),
                        permissionBoundary: permissionBoundaryHint(for: finding.code)
                    )
                }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            // Keep doctor check pure fail-closed: sidecar write failure should not crash app loop.
            print("SupervisorDoctor write secrets dry-run compat report failed: \(error)")
        }
    }

    // MARK: - Private

    private static func checkDirectMessageAllowlist(config: SupervisorDoctorConfig) -> [SupervisorDoctorFinding] {
        let policy = config.dmPolicy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowFrom = config.allowFrom.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var findings: [SupervisorDoctorFinding] = []

        if policy == "allowlist" && allowFrom.isEmpty {
            findings.append(
                finding(
                    code: "dm_allowlist_empty",
                    area: "dm_allowlist",
                    severity: .blocking,
                    priority: .p0,
                    title: "dm/group allowlist 为空，发布阻断",
                    detail: "当前配置为 dmPolicy=allowlist，但 allowFrom=[]，会导致来源边界不可判定。",
                    reason: "这是基础信任边界，空 allowlist 可能让上线后行为依赖隐式默认值，属于高风险漂移。",
                    actions: [
                        "在 .axcoder/supervisor/doctor_config.json 明确至少一个 allowFrom，例如 group:release_ops。",
                        "确保每个 allowFrom 条目使用显式前缀（group: 或 dm:）。",
                        "重新运行 doctor，确认 dm_allowlist_risk_count 归零。"
                    ],
                    verifyHint: "supervisor doctor -> dm_allowlist_empty 消失"
                )
            )
            return findings
        }

        if policy == "allowlist" {
            let invalidTokens = allowFrom.filter { token in
                !(token.hasPrefix("group:") || token.hasPrefix("dm:"))
            }
            if !invalidTokens.isEmpty {
                findings.append(
                    finding(
                        code: "dm_allowlist_token_invalid",
                        area: "dm_allowlist",
                        severity: .warning,
                        priority: .p1,
                        title: "allowlist 存在未标准化条目",
                        detail: "检测到非 group:/dm: 前缀条目：\(invalidTokens.joined(separator: ", "))",
                        reason: "条目语义不明确会影响审计一致性，建议上线前收敛格式。",
                        actions: [
                            "将 allowFrom 条目规范为 group:<name> 或 dm:<id>。",
                            "删除无法映射到权限域的历史别名。"
                        ],
                        verifyHint: "supervisor doctor -> dm_allowlist_token_invalid 消失"
                    )
                )
            }
        }
        return findings
    }

    private static func checkWebSocketSecurity(config: SupervisorDoctorConfig) -> [SupervisorDoctorFinding] {
        var findings: [SupervisorDoctorFinding] = []
        let origins = config.webSocket.allowedOrigins
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if origins.isEmpty {
            findings.append(
                finding(
                    code: "ws_origin_missing",
                    area: "ws_auth",
                    severity: .blocking,
                    priority: .p0,
                    title: "WS origin allowlist 为空，发布阻断",
                    detail: "未配置 ws allowedOrigins，无法在握手阶段做来源约束。",
                    reason: "origin 边界缺失会放大跨来源劫持风险，属于关键门禁项。",
                    actions: [
                        "在 doctor_config.json -> webSocket.allowedOrigins 配置可信域名。",
                        "禁止使用 * 或全局通配 origin。",
                        "与网关实际入口域名保持一一对应。"
                    ],
                    verifyHint: "supervisor doctor -> ws_origin_missing 消失"
                )
            )
        } else if origins.contains("*") {
            findings.append(
                finding(
                    code: "ws_origin_wildcard",
                    area: "ws_auth",
                    severity: .blocking,
                    priority: .p0,
                    title: "WS origin 使用通配符，发布阻断",
                    detail: "allowedOrigins 包含 '*'，等价于禁用 origin 防护。",
                    reason: "高风险入口不能依赖后置检测，必须前置在握手阶段阻断。",
                    actions: [
                        "移除 '*'，改为精确 origin 列表。",
                        "按环境拆分配置（dev/staging/prod）避免误带测试域。"
                    ],
                    verifyHint: "supervisor doctor -> ws_origin_wildcard 消失"
                )
            )
        }

        if !config.webSocket.sharedTokenAuthEnabled {
            findings.append(
                finding(
                    code: "ws_shared_token_auth_disabled",
                    area: "ws_auth",
                    severity: .blocking,
                    priority: .p0,
                    title: "WS shared-token 鉴权关闭，发布阻断",
                    detail: "webSocket.sharedTokenAuthEnabled=false。",
                    reason: "高风险操作链路需要双门禁（origin + token）；缺 token 等于单点失效。",
                    actions: [
                        "启用 webSocket.sharedTokenAuthEnabled=true。",
                        "配置 sharedTokenRef 指向受控 secrets（非硬编码）。",
                        "在发布前做一次 token 轮换演练。"
                    ],
                    verifyHint: "supervisor doctor -> ws_shared_token_auth_disabled 消失"
                )
            )
        } else {
            let tokenRef = (config.webSocket.sharedTokenRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if tokenRef.isEmpty {
                findings.append(
                    finding(
                        code: "ws_shared_token_ref_missing",
                        area: "ws_auth",
                        severity: .warning,
                        priority: .p1,
                        title: "shared-token 已启用但缺少引用路径",
                        detail: "sharedTokenAuthEnabled=true，但 sharedTokenRef 为空。",
                        reason: "缺少引用路径会让轮换流程不可审计，建议在上线前补齐。",
                        actions: [
                            "将 sharedTokenRef 指向统一 secrets 管理路径。",
                            "确保 token 注入流程仅在运行时可见。"
                        ],
                        verifyHint: "supervisor doctor -> ws_shared_token_ref_missing 消失"
                    )
                )
            }
        }

        return findings
    }

    private static func checkPreAuthFloodBreaker(config: SupervisorDoctorConfig) -> [SupervisorDoctorFinding] {
        var findings: [SupervisorDoctorFinding] = []
        let pre = config.preAuth
        let breaker = pre.floodBreaker

        if pre.bodyBytesCap <= 0 {
            findings.append(
                finding(
                    code: "preauth_body_cap_invalid",
                    area: "pre_auth_flood_breaker",
                    severity: .blocking,
                    priority: .p0,
                    title: "pre-auth body cap 非法，发布阻断",
                    detail: "preAuth.bodyBytesCap=\(pre.bodyBytesCap)，必须 > 0。",
                    reason: "缺少 body cap 会扩大预鉴权资源消耗面，影响可用性与成本。",
                    actions: [
                        "设置 preAuth.bodyBytesCap（建议 64KB~256KB）。",
                        "对超过上限的请求在 pre-auth 阶段直接拒绝。"
                    ],
                    verifyHint: "supervisor doctor -> preauth_body_cap_invalid 消失"
                )
            )
        }

        if pre.keyCountCap <= 0 {
            findings.append(
                finding(
                    code: "preauth_key_cap_invalid",
                    area: "pre_auth_flood_breaker",
                    severity: .blocking,
                    priority: .p0,
                    title: "pre-auth key cap 非法，发布阻断",
                    detail: "preAuth.keyCountCap=\(pre.keyCountCap)，必须 > 0。",
                    reason: "缺少 key cap 时，恶意请求可放大解析开销并触发队列拥塞。",
                    actions: [
                        "设置 preAuth.keyCountCap（建议 32~128）。",
                        "将超限请求归类为 invalid_request 并计入审计。"
                    ],
                    verifyHint: "supervisor doctor -> preauth_key_cap_invalid 消失"
                )
            )
        }

        if !breaker.enabled {
            findings.append(
                finding(
                    code: "preauth_flood_breaker_disabled",
                    area: "pre_auth_flood_breaker",
                    severity: .blocking,
                    priority: .p0,
                    title: "pre-auth flood breaker 关闭，发布阻断",
                    detail: "preAuth.floodBreaker.enabled=false。",
                    reason: "未授权洪泛必须在前置阶段限流，否则高风险接口会被打穿。",
                    actions: [
                        "启用 preAuth.floodBreaker.enabled=true。",
                        "配置 maxUnauthorizedPerMinute 与 banSeconds。"
                    ],
                    verifyHint: "supervisor doctor -> preauth_flood_breaker_disabled 消失"
                )
            )
            return findings
        }

        if breaker.maxUnauthorizedPerMinute <= 0 || breaker.banSeconds <= 0 {
            findings.append(
                finding(
                    code: "preauth_flood_breaker_invalid_threshold",
                    area: "pre_auth_flood_breaker",
                    severity: .blocking,
                    priority: .p0,
                    title: "flood breaker 阈值非法，发布阻断",
                    detail: "maxUnauthorizedPerMinute=\(breaker.maxUnauthorizedPerMinute), banSeconds=\(breaker.banSeconds)。",
                    reason: "阈值无效会使 breaker 形同虚设，无法形成有效防护。",
                    actions: [
                        "将 maxUnauthorizedPerMinute 设置为 > 0（建议 30~120）。",
                        "将 banSeconds 设置为 > 0（建议 30~300）。"
                    ],
                    verifyHint: "supervisor doctor -> preauth_flood_breaker_invalid_threshold 消失"
                )
            )
        } else if breaker.maxUnauthorizedPerMinute > 600 {
            findings.append(
                finding(
                    code: "preauth_flood_breaker_too_loose",
                    area: "pre_auth_flood_breaker",
                    severity: .warning,
                    priority: .p1,
                    title: "flood breaker 阈值偏宽松",
                    detail: "maxUnauthorizedPerMinute=\(breaker.maxUnauthorizedPerMinute) 过高，防护收益有限。",
                    reason: "宽松阈值会降低未授权洪泛检测灵敏度。",
                    actions: [
                        "将 maxUnauthorizedPerMinute 调整到与真实业务峰值匹配的区间。",
                        "回看最近 7 天未授权请求分位数后再定阈值。"
                    ],
                    verifyHint: "supervisor doctor -> preauth_flood_breaker_too_loose 消失"
                )
            )
        }

        return findings
    }

    private static func checkSecretsDryRun(
        plan: SupervisorSecretsDryRunPlan?,
        workspaceRoot: URL
    ) -> [SupervisorDoctorFinding] {
        guard let plan else {
            return [
                finding(
                    code: "secrets_dry_run_missing",
                    area: "secrets_dry_run",
                    severity: .blocking,
                    priority: .p0,
                    title: "缺少 secrets apply --dry-run 摘要，发布阻断",
                    detail: "未发现 secrets dry-run 计划文件，无法验证目标路径/变量/权限边界。",
                    reason: "发布前缺少 dry-run 结果会导致 secrets 风险后移到运行时。",
                    actions: [
                        "生成 .axcoder/secrets/secrets_apply_dry_run.json。",
                        "至少包含目标路径、required/provided variables、mode。"
                    ],
                    verifyHint: "supervisor doctor -> secrets_dry_run_missing 消失"
                )
            ]
        }

        let roots = plan.allowedRoots
            .map { resolvePath($0, workspaceRoot: workspaceRoot) }
            .map { $0.standardizedFileURL }
        let allowedModes = Set(plan.allowedModes.map { normalizeMode($0) }.filter { !$0.isEmpty })
        var findings: [SupervisorDoctorFinding] = []

        for item in plan.items {
            let targetURL = resolvePath(item.targetPath, workspaceRoot: workspaceRoot).standardizedFileURL
            if !isTarget(targetURL, within: roots) {
                findings.append(
                    finding(
                        code: "secrets_target_path_out_of_scope",
                        area: "secrets_dry_run",
                        severity: .blocking,
                        priority: .p0,
                        title: "secrets 目标路径越界，发布阻断",
                        detail: "目标路径 \(targetURL.path) 不在 allowedRoots 内。",
                        reason: "越界写入会突破 secrets 边界，必须在 dry-run 阶段拦截。",
                        actions: [
                            "将 targetPath 收敛到 allowedRoots 目录内。",
                            "必要时显式扩展 allowedRoots 并做安全评审。"
                        ],
                        verifyHint: "supervisor doctor -> secrets_target_path_out_of_scope 消失"
                    )
                )
            }

            let required = Set(item.requiredVariables.map(normalizeVarToken))
            let provided = Set(item.providedVariables.map(normalizeVarToken))
            let missing = required.subtracting(provided).filter { !$0.isEmpty }.sorted()
            if !missing.isEmpty {
                findings.append(
                    finding(
                        code: "secrets_missing_required_variables",
                        area: "secrets_dry_run",
                        severity: .blocking,
                        priority: .p0,
                        title: "secrets 缺少必需变量，发布阻断",
                        detail: "目标 \(item.targetPath) 缺少变量：\(missing.joined(separator: ", "))。",
                        reason: "变量缺失会导致发布后注入失败或退回不安全默认值。",
                        actions: [
                            "补齐缺失变量并重新生成 dry-run 摘要。",
                            "为关键变量设置 non-empty 校验。"
                        ],
                        verifyHint: "supervisor doctor -> secrets_missing_required_variables 消失"
                    )
                )
            }

            let normalizedMode = normalizeMode(item.mode)
            if normalizedMode.isEmpty || (!allowedModes.isEmpty && !allowedModes.contains(normalizedMode)) {
                findings.append(
                    finding(
                        code: "secrets_permission_boundary_error",
                        area: "secrets_dry_run",
                        severity: .blocking,
                        priority: .p0,
                        title: "secrets 权限边界错误，发布阻断",
                        detail: "目标 \(item.targetPath) 使用 mode=\(item.mode)（允许：\(allowedModes.sorted().joined(separator: ", "))）。",
                        reason: "权限模式越界会导致 secrets 过度暴露，必须在发布前修复。",
                        actions: [
                            "将 mode 调整到允许范围（建议 0600/0640）。",
                            "统一由 secrets 模板定义权限，避免手工漂移。"
                        ],
                        verifyHint: "supervisor doctor -> secrets_permission_boundary_error 消失"
                    )
                )
            }
        }
        return findings
    }

    private static func finding(
        code: String,
        area: String,
        severity: SupervisorDoctorSeverity,
        priority: SupervisorDoctorPriority,
        title: String,
        detail: String,
        reason: String,
        actions: [String],
        verifyHint: String?
    ) -> SupervisorDoctorFinding {
        SupervisorDoctorFinding(
            code: code,
            area: area,
            severity: severity,
            priority: priority,
            title: title,
            detail: detail,
            priorityReason: reason,
            actions: actions,
            verifyHint: verifyHint
        )
    }

    private static func resolvePath(_ raw: String, workspaceRoot: URL) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return workspaceRoot.appendingPathComponent(trimmed)
    }

    private static func isTarget(_ target: URL, within roots: [URL]) -> Bool {
        let targetPath = target.path
        for root in roots {
            let rootPath = root.path
            if targetPath == rootPath { return true }
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if targetPath.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    private static func normalizeVarToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizeMode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let digits = trimmed.filter { ("0"..."7").contains($0) }
        guard digits.count >= 3 else { return "" }
        if digits.count == 3 { return "0" + digits }
        return String(digits.suffix(4))
    }

    private static func resolvedDoctorCompatReportURL(
        sourceReportURL: URL,
        workspaceRoot: URL
    ) -> URL {
        let envPath = (ProcessInfo.processInfo.environment["XTERMINAL_DOCTOR_COMPAT_REPORT_PATH"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !envPath.isEmpty {
            if envPath.hasPrefix("/") {
                return URL(fileURLWithPath: envPath)
            }
            return workspaceRoot.appendingPathComponent(envPath)
        }
        return sourceReportURL.deletingLastPathComponent().appendingPathComponent("doctor-report.json")
    }

    private static func resolvedSecretsDryRunCompatReportURL(
        sourceReportURL: URL,
        workspaceRoot: URL
    ) -> URL {
        let envPath = (ProcessInfo.processInfo.environment["XTERMINAL_SECRETS_DRY_RUN_REPORT_PATH"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !envPath.isEmpty {
            if envPath.hasPrefix("/") {
                return URL(fileURLWithPath: envPath)
            }
            return workspaceRoot.appendingPathComponent(envPath)
        }
        return sourceReportURL.deletingLastPathComponent().appendingPathComponent("secrets-dry-run-report.json")
    }

    private static func targetPathHint(from detail: String) -> String {
        if let range = detail.range(of: "目标路径 ") {
            let suffix = detail[range.upperBound...]
            if let end = suffix.range(of: " ") {
                return String(suffix[..<end.lowerBound])
            }
            return String(suffix)
        }
        if let range = detail.range(of: "目标 ") {
            let suffix = detail[range.upperBound...]
            if let end = suffix.range(of: " ") {
                return String(suffix[..<end.lowerBound])
            }
            return String(suffix)
        }
        return ""
    }

    private static func missingVariablesHint(from detail: String) -> [String] {
        let markers = ["缺少变量：", "缺少变量:"]
        for marker in markers {
            guard let range = detail.range(of: marker) else { continue }
            let value = detail[range.upperBound...]
            return value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func permissionBoundaryHint(for code: String) -> String {
        switch code {
        case "secrets_target_path_out_of_scope":
            return "out_of_scope"
        case "secrets_permission_boundary_error":
            return "permission_boundary_error"
        default:
            return ""
        }
    }

    private static func loadJSON<T: Decodable>(at url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
