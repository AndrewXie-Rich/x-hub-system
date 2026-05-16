import Foundation

struct RustHubReadinessPresentation: Equatable {
    enum Tone: Equatable {
        case ready
        case warning
        case unavailable
    }

    var title: String
    var badgeText: String
    var tone: Tone
    var lines: [String]

    static func loading(language: XTInterfaceLanguage = .defaultPreference) -> RustHubReadinessPresentation {
        RustHubReadinessPresentation(
            title: XTL10n.text(language, zhHans: "Hub 内核状态", en: "Hub Kernel Status"),
            badgeText: XTL10n.text(language, zhHans: "读取中", en: "Loading"),
            tone: .unavailable,
            lines: [
                XTL10n.text(language, zhHans: "正在读取 Hub 内核 `/ready`。", en: "Reading Hub kernel `/ready`.")
            ]
        )
    }

    static func unavailable(
        message: String,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> RustHubReadinessPresentation {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return RustHubReadinessPresentation(
            title: XTL10n.text(language, zhHans: "Hub 内核状态", en: "Hub Kernel Status"),
            badgeText: XTL10n.text(language, zhHans: "未连接", en: "Offline"),
            tone: .unavailable,
            lines: [
                XTL10n.text(
                    language,
                    zhHans: "XT 暂时读不到 Hub 内核 HTTP 诊断；已配对 Hub 连接状态不受这个诊断影响。",
                    en: "XT cannot read Hub kernel HTTP diagnostics right now; paired Hub connectivity is unaffected by this diagnostic."
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
        snapshot: RustHubReadinessSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> RustHubReadinessPresentation {
        let boundaryOK = snapshot.mode == "shadow_http"
            && snapshot.runtime.mlExecutionInRust != true
            && snapshot.memory.canonicalWriterInRust != true
            && snapshot.skills.executionAuthorityInRust != true
            && snapshot.skills.hubExecutesThirdPartyCode != true

        let tone: Tone
        let badge: String
        if snapshot.ok && snapshot.ready && boundaryOK {
            tone = .ready
            badge = XTL10n.text(language, zhHans: "内核就绪", en: "Kernel Ready")
        } else if snapshot.ok || snapshot.ready {
            tone = .warning
            badge = XTL10n.text(language, zhHans: "需核对", en: "Review")
        } else {
            tone = .unavailable
            badge = XTL10n.text(language, zhHans: "未就绪", en: "Not Ready")
        }

        let failingBlockingChecks = snapshot.checks
            .filter { $0.blocking == true && !$0.ok }
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var lines = [
            headline(snapshot: snapshot, boundaryOK: boundaryOK, language: language),
            XTL10n.text(
                language,
                zhHans: "地址：\(displayToken(snapshot.httpAddr)) · mode=\(displayToken(snapshot.mode)) · daemon=\(displayToken(snapshot.daemon))",
                en: "Address: \(displayToken(snapshot.httpAddr)) · mode=\(displayToken(snapshot.mode)) · daemon=\(displayToken(snapshot.daemon))"
            ),
            XTL10n.text(
                language,
                zhHans: "边界：model_exec_rust=\(boolOptionalToken(snapshot.runtime.mlExecutionInRust)) · memory_writer_rust=\(boolOptionalToken(snapshot.memory.canonicalWriterInRust)) · skills_exec_rust=\(boolOptionalToken(snapshot.skills.executionAuthorityInRust))",
                en: "Boundary: model_exec_rust=\(boolOptionalToken(snapshot.runtime.mlExecutionInRust)) · memory_writer_rust=\(boolOptionalToken(snapshot.memory.canonicalWriterInRust)) · skills_exec_rust=\(boolOptionalToken(snapshot.skills.executionAuthorityInRust))"
            ),
            XTL10n.text(
                language,
                zhHans: "Hub 连接：这只是内核诊断，不会单独把 XT 的 Hub pairing/gRPC 标记为已连接；生产模型、授权、memory 写入和 skill 执行仍以已配对 Hub 入口为准。",
                en: "Hub connection: this is only a kernel diagnostic and does not independently mark XT Hub pairing/gRPC as connected; production model, grant, memory write, and skill execution still follow the paired Hub entrypoint."
            )
        ]

        if !failingBlockingChecks.isEmpty {
            lines.append(XTL10n.text(
                language,
                zhHans: "Rust blocking checks：\(failingBlockingChecks.joined(separator: ", "))",
                en: "Rust blocking checks: \(failingBlockingChecks.joined(separator: ", "))"
            ))
        }

        lines.append(capabilityLine(snapshot: snapshot, language: language))

        return RustHubReadinessPresentation(
            title: XTL10n.text(language, zhHans: "Hub 内核状态", en: "Hub Kernel Status"),
            badgeText: badge,
            tone: tone,
            lines: lines
        )
    }

    private static func headline(
        snapshot: RustHubReadinessSnapshot,
        boundaryOK: Bool,
        language: XTInterfaceLanguage
    ) -> String {
        if snapshot.ok && snapshot.ready && boundaryOK {
            return XTL10n.text(
                language,
                zhHans: "Hub 内核 HTTP 已就绪；当前是诊断/只读后端，生产连接仍以已配对 Hub 入口为准。",
                en: "Hub kernel HTTP is ready; this is a diagnostics/read-only backend, and production connectivity still follows the paired Hub entrypoint."
            )
        }
        if !boundaryOK {
            return XTL10n.text(
                language,
                zhHans: "Hub 内核返回的 authority 边界需要核对；XT 不会把它提升为生产 Hub 入口。",
                en: "Hub kernel returned authority boundaries that need review; XT will not promote it to the production Hub entrypoint."
            )
        }
        return XTL10n.text(
            language,
            zhHans: "Hub 内核 HTTP 尚未 ready；XT 继续按已配对 Hub 链路状态处理。",
            en: "Hub kernel HTTP is not ready; XT continues using the paired Hub link state."
        )
    }

    private static func capabilityLine(
        snapshot: RustHubReadinessSnapshot,
        language: XTInterfaceLanguage
    ) -> String {
        let interesting = [
            "model_inventory_http",
            "model_route_diagnostics_http",
            "provider_route_http",
            "skills_catalog_http",
            "memory_retrieval_http"
        ]
        let enabled = interesting.filter { snapshot.capabilities[$0] == true }
        return XTL10n.text(
            language,
            zhHans: "Hub 内核 HTTP 能力：\(enabled.isEmpty ? "none" : enabled.joined(separator: ", "))",
            en: "Hub kernel HTTP capabilities: \(enabled.isEmpty ? "none" : enabled.joined(separator: ", "))"
        )
    }

    private static func displayToken(_ raw: String?) -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "unknown" : value
    }

    private static func boolOptionalToken(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "true" : "false"
    }
}
