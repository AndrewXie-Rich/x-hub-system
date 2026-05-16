import Foundation

struct RustHubModelRouteDiagnosticsPresentation: Equatable {
    enum Tone: Equatable {
        case ready
        case warning
        case blocked
        case unavailable
    }

    var title: String
    var badgeText: String
    var tone: Tone
    var lines: [String]

    static func loading(language: XTInterfaceLanguage = .defaultPreference) -> RustHubModelRouteDiagnosticsPresentation {
        RustHubModelRouteDiagnosticsPresentation(
            title: XTL10n.text(
                language,
                zhHans: "Hub 内核模型路由诊断",
                en: "Hub Kernel Model Route Diagnostics"
            ),
            badgeText: XTL10n.text(language, zhHans: "读取中", en: "Loading"),
            tone: .unavailable,
            lines: [
                XTL10n.text(
                    language,
                    zhHans: "正在读取 Hub 内核只读诊断状态。",
                    en: "Reading Hub kernel read-only diagnostics status."
                )
            ]
        )
    }

    static func unavailable(
        message: String,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> RustHubModelRouteDiagnosticsPresentation {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return RustHubModelRouteDiagnosticsPresentation(
            title: XTL10n.text(
                language,
                zhHans: "Hub 内核模型路由诊断",
                en: "Hub Kernel Model Route Diagnostics"
            ),
            badgeText: XTL10n.text(language, zhHans: "未连接", en: "Offline"),
            tone: .unavailable,
            lines: [
                XTL10n.text(
                    language,
                    zhHans: "暂时读不到 Hub 内核诊断端点；XT 继续使用现有模型设置和 Hub 路由。",
                    en: "Hub kernel diagnostics is not reachable right now; XT keeps using the existing model settings and Hub route."
                ),
                XTL10n.text(
                    language,
                    zhHans: "原因：\(trimmed.isEmpty ? "unknown" : trimmed)",
                    en: "Reason: \(trimmed.isEmpty ? "unknown" : trimmed)"
                )
            ]
        )
    }

    static func build(
        snapshot: RustHubModelRouteDiagnosticsSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> RustHubModelRouteDiagnosticsPresentation {
        let observed = snapshot.observedAuthority
        let boundaryOK = snapshot.readOnly
            && snapshot.diagnosticsOnly
            && !snapshot.productionAuthorityChange
            && !snapshot.selectedModelAuthorityEnabled
            && (observed?.productionAuthorityChanges ?? 0) == 0
            && (observed?.selectedModelAuthorityEnabledReports ?? 0) == 0
            && (observed?.nodeAuthorityFailures ?? 0) == 0
            && snapshot.nodeRemainsModelSelectionAuthority != false

        let tone: Tone
        let badge: String
        if !snapshot.ok {
            tone = .blocked
            badge = XTL10n.text(language, zhHans: "返回异常", en: "Not OK")
        } else if !boundaryOK {
            tone = .blocked
            badge = XTL10n.text(language, zhHans: "边界异常", en: "Boundary")
        } else if snapshot.ready {
            tone = .ready
            badge = XTL10n.text(language, zhHans: "Ready", en: "Ready")
        } else {
            tone = .warning
            badge = XTL10n.text(language, zhHans: "Not Ready", en: "Not Ready")
        }

        var lines = [
            headline(snapshot: snapshot, boundaryOK: boundaryOK, language: language),
            boundaryLine(snapshot: snapshot, language: language),
            observedAuthorityLine(snapshot.observedAuthority, language: language)
        ]

        if let authorityPlan = snapshot.latest?.authorityPlan {
            lines.append(authorityPlanLine(authorityPlan, language: language))
        }
        if let prepTrial = snapshot.latest?.prepTrial {
            lines.append(prepTrialLine(prepTrial, language: language))
        }
        if let prepSustained = snapshot.latest?.prepSustained {
            lines.append(prepSustainedLine(prepSustained, language: language))
        }
        if let candidateEvidence = snapshot.latest?.candidateEvidence {
            lines.append(candidateEvidenceLine(candidateEvidence, language: language))
        }

        let failingChecks = snapshot.checks
            .filter { !$0.ok }
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !failingChecks.isEmpty {
            lines.append(XTL10n.text(
                language,
                zhHans: "阻塞检查：\(failingChecks.joined(separator: ", "))",
                en: "Blocking checks: \(failingChecks.joined(separator: ", "))"
            ))
        }

        lines.append(sourceLine(snapshot: snapshot, language: language))

        return RustHubModelRouteDiagnosticsPresentation(
            title: XTL10n.text(
                language,
                zhHans: "Hub 内核模型路由诊断",
                en: "Hub Kernel Model Route Diagnostics"
            ),
            badgeText: badge,
            tone: tone,
            lines: lines
        )
    }

    private static func headline(
        snapshot: RustHubModelRouteDiagnosticsSnapshot,
        boundaryOK: Bool,
        language: XTInterfaceLanguage
    ) -> String {
        guard snapshot.ok else {
            return XTL10n.text(
                language,
                zhHans: "Hub 内核返回 ok=false；XT 不会采用这份诊断作为路由依据。",
                en: "Hub kernel returned ok=false; XT will not use this diagnostics result as routing input."
            )
        }
        guard boundaryOK else {
            return XTL10n.text(
                language,
                zhHans: "诊断报告显示 authority 边界异常；XT 保持现有 Hub/Node 选模权威。",
                en: "Diagnostics reports an authority boundary issue; XT keeps the existing Hub/Node model-selection authority."
            )
        }
        if snapshot.ready {
            return XTL10n.text(
                language,
                zhHans: "dry-run、prep trial 和 sustained 证据已通过；当前仍只是只读诊断。",
                en: "Dry-run, prep trial, and sustained evidence passed; this is still diagnostics only."
            )
        }
        return XTL10n.text(
            language,
            zhHans: "诊断证据还没 ready；XT 当前选模和生成链路不受影响。",
            en: "Diagnostics evidence is not ready yet; XT model selection and generation are unchanged."
        )
    }

    private static func boundaryLine(
        snapshot: RustHubModelRouteDiagnosticsSnapshot,
        language: XTInterfaceLanguage
    ) -> String {
        XTL10n.text(
            language,
            zhHans: "边界：read_only=\(boolToken(snapshot.readOnly)) · diagnostics_only=\(boolToken(snapshot.diagnosticsOnly)) · production_authority_change=\(boolToken(snapshot.productionAuthorityChange)) · selected_model_authority_enabled=\(boolToken(snapshot.selectedModelAuthorityEnabled))",
            en: "Boundary: read_only=\(boolToken(snapshot.readOnly)) · diagnostics_only=\(boolToken(snapshot.diagnosticsOnly)) · production_authority_change=\(boolToken(snapshot.productionAuthorityChange)) · selected_model_authority_enabled=\(boolToken(snapshot.selectedModelAuthorityEnabled))"
        )
    }

    private static func observedAuthorityLine(
        _ observed: RustHubModelRouteDiagnosticsSnapshot.ObservedAuthority?,
        language: XTInterfaceLanguage
    ) -> String {
        let productionChanges = observed?.productionAuthorityChanges ?? 0
        let selectedEnabled = observed?.selectedModelAuthorityEnabledReports ?? 0
        let nodeFailures = observed?.nodeAuthorityFailures ?? 0
        return XTL10n.text(
            language,
            zhHans: "Authority 观测：production_changes=\(productionChanges) · selected_model_enabled_reports=\(selectedEnabled) · node_authority_failures=\(nodeFailures)",
            en: "Authority observed: production_changes=\(productionChanges) · selected_model_enabled_reports=\(selectedEnabled) · node_authority_failures=\(nodeFailures)"
        )
    }

    private static func authorityPlanLine(
        _ report: RustHubModelRouteDiagnosticsSnapshot.Report,
        language: XTInterfaceLanguage
    ) -> String {
        let metrics = report.metrics
        let remoteModel = displayToken(metrics?.remoteModelID)
        let localModel = displayToken(metrics?.localModelID)
        let provider = displayToken(metrics?.provider)
        let rustPrep = boolOptionalToken(metrics?.rustCanPrepareModelRouteDecision)
        return XTL10n.text(
            language,
            zhHans: "Authority plan：\(reportStatus(report)) · mode=\(displayToken(report.authorityMode)) · provider=\(provider) · remote=\(remoteModel) · local=\(localModel) · rust_prepare=\(rustPrep)",
            en: "Authority plan: \(reportStatus(report)) · mode=\(displayToken(report.authorityMode)) · provider=\(provider) · remote=\(remoteModel) · local=\(localModel) · rust_prepare=\(rustPrep)"
        )
    }

    private static func prepTrialLine(
        _ report: RustHubModelRouteDiagnosticsSnapshot.Report,
        language: XTInterfaceLanguage
    ) -> String {
        let remote = report.metrics?.remote
        let local = report.metrics?.local
        return XTL10n.text(
            language,
            zhHans: "Prep trial：\(reportStatus(report)) · remote_matches=\(intToken(remote?.prepMatchCount)) · local_matches=\(intToken(local?.prepMatchCount)) · warnings=\(intToken((remote?.prepWarningCount ?? 0) + (local?.prepWarningCount ?? 0)))",
            en: "Prep trial: \(reportStatus(report)) · remote_matches=\(intToken(remote?.prepMatchCount)) · local_matches=\(intToken(local?.prepMatchCount)) · warnings=\(intToken((remote?.prepWarningCount ?? 0) + (local?.prepWarningCount ?? 0)))"
        )
    }

    private static func prepSustainedLine(
        _ report: RustHubModelRouteDiagnosticsSnapshot.Report,
        language: XTInterfaceLanguage
    ) -> String {
        let aggregate = report.metrics?.aggregate
        return XTL10n.text(
            language,
            zhHans: "Prep sustained：\(reportStatus(report)) · ready_cycles=\(intToken(aggregate?.readyCycles)) · failed_cycles=\(intToken(aggregate?.failedCycles)) · remote_matches=\(intToken(aggregate?.totalRemotePrepMatches)) · local_matches=\(intToken(aggregate?.totalLocalPrepMatches)) · warnings=\(intToken(aggregate?.totalPrepWarnings))",
            en: "Prep sustained: \(reportStatus(report)) · ready_cycles=\(intToken(aggregate?.readyCycles)) · failed_cycles=\(intToken(aggregate?.failedCycles)) · remote_matches=\(intToken(aggregate?.totalRemotePrepMatches)) · local_matches=\(intToken(aggregate?.totalLocalPrepMatches)) · warnings=\(intToken(aggregate?.totalPrepWarnings))"
        )
    }

    private static func candidateEvidenceLine(
        _ report: RustHubModelRouteDiagnosticsSnapshot.Report,
        language: XTInterfaceLanguage
    ) -> String {
        let remote = report.metrics?.remote
        let local = report.metrics?.local
        return XTL10n.text(
            language,
            zhHans: "Candidate evidence：\(reportStatus(report)) · remote_total=\(intToken(remote?.total)) · local_total=\(intToken(local?.total)) · remote_secret_leak=\(intToken(remote?.secretLeak)) · local_secret_leak=\(intToken(local?.secretLeak))",
            en: "Candidate evidence: \(reportStatus(report)) · remote_total=\(intToken(remote?.total)) · local_total=\(intToken(local?.total)) · remote_secret_leak=\(intToken(remote?.secretLeak)) · local_secret_leak=\(intToken(local?.secretLeak))"
        )
    }

    private static func sourceLine(
        snapshot: RustHubModelRouteDiagnosticsSnapshot,
        language: XTInterfaceLanguage
    ) -> String {
        XTL10n.text(
            language,
            zhHans: "来源：schema=\(snapshot.schemaVersion) · command=\(displayToken(snapshot.command)) · decision=\(displayToken(snapshot.decision))",
            en: "Source: schema=\(snapshot.schemaVersion) · command=\(displayToken(snapshot.command)) · decision=\(displayToken(snapshot.decision))"
        )
    }

    private static func reportStatus(_ report: RustHubModelRouteDiagnosticsSnapshot.Report) -> String {
        let readyText = boolOptionalToken(report.ready)
        let decision = displayToken(report.decision)
        let path = sanitizedReportPath(report.reportPath) ?? sanitizedReportPath(report.fileName) ?? "unknown"
        return "ready=\(readyText) decision=\(decision) report=\(path)"
    }

    private static func displayToken(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func sanitizedReportPath(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "/").suffix(2)
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    private static func boolToken(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func boolOptionalToken(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return boolToken(value)
    }

    private static func intToken(_ value: Int?) -> String {
        guard let value else { return "unknown" }
        return String(value)
    }
}
