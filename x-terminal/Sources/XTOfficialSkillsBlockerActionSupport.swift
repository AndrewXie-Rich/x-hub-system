import Foundation

struct XTOfficialSkillsBlockerAction: Equatable, Sendable {
    var label: String
    var title: String
    var detail: String
    var url: String
}

enum XTOfficialSkillsBlockerRouteKind: Equatable, Sendable {
    case troubleshootGrant
    case reviewBlocked
    case reviewDegraded
    case diagnosticsInstall
    case diagnosticsSupport
    case diagnosticsRevocation
    case reviewFallback
}

enum XTOfficialSkillsBlockerActionSupport {
    static func rankedBlockers(
        _ blockers: [AXOfficialSkillBlockerSummaryItem]
    ) -> [AXOfficialSkillBlockerSummaryItem] {
        blockers.sorted { lhs, rhs in
            let left = sortDescriptor(for: lhs)
            let right = sortDescriptor(for: rhs)

            if left.routePriority != right.routePriority {
                return left.routePriority < right.routePriority
            }
            if left.failureCount != right.failureCount {
                return left.failureCount > right.failureCount
            }
            if left.riskPriority != right.riskPriority {
                return left.riskPriority > right.riskPriority
            }
            if left.recency != right.recency {
                return left.recency > right.recency
            }
            if left.displayKey != right.displayKey {
                return left.displayKey < right.displayKey
            }
            return lhs.packageSHA256 < rhs.packageSHA256
        }
    }

    static func action(for item: AXOfficialSkillBlockerSummaryItem) -> XTOfficialSkillsBlockerAction? {
        let detail = actionDetail(for: item)
        let route = routeDescriptor(for: routeKind(for: item))

        guard let url = route.urlBuilder(
            route.sectionId,
            route.title,
            detail,
            .recheckOfficialSkills,
            "official_skill_blocker"
        ) else {
            return nil
        }

        return XTOfficialSkillsBlockerAction(
            label: route.label,
            title: route.title,
            detail: detail,
            url: url.absoluteString
        )
    }

    static func routeKind(for item: AXOfficialSkillBlockerSummaryItem) -> XTOfficialSkillsBlockerRouteKind {
        let state = normalizedStateLabel(item.stateLabel)
        if ["blocked", "degraded"].contains(state),
           summaryIndicatesGrantRequired(item.summaryLine) {
            return .troubleshootGrant
        }

        switch state {
        case "blocked":
            return .reviewBlocked
        case "degraded":
            return .reviewDegraded
        case "not installed":
            return .diagnosticsInstall
        case "not supported":
            return .diagnosticsSupport
        case "revoked":
            return .diagnosticsRevocation
        default:
            return .reviewFallback
        }
    }

    private static func sortDescriptor(
        for item: AXOfficialSkillBlockerSummaryItem
    ) -> (
        routePriority: Int,
        failureCount: Int,
        riskPriority: Int,
        recency: Int64,
        displayKey: String
    ) {
        let route = routeKind(for: item)
        let summaryFields = scalarFields(from: item.summaryLine)
        let timelineFields = scalarFields(from: item.timelineLine)

        return (
            routePriority: routePriority(for: route),
            failureCount: max(0, Int(summaryFields["failures"] ?? "") ?? 0),
            riskPriority: riskPriority(summaryFields["risk"]),
            recency: recencyPriority(from: timelineFields),
            displayKey: displayKey(for: item)
        )
    }

    private static func routePriority(for kind: XTOfficialSkillsBlockerRouteKind) -> Int {
        switch kind {
        case .troubleshootGrant:
            return 0
        case .diagnosticsRevocation:
            return 1
        case .reviewBlocked:
            return 2
        case .diagnosticsSupport:
            return 3
        case .diagnosticsInstall:
            return 4
        case .reviewDegraded:
            return 5
        case .reviewFallback:
            return 6
        }
    }

    private static func riskPriority(_ raw: String?) -> Int {
        switch normalizedScalar(raw).lowercased() {
        case "critical":
            return 4
        case "high":
            return 3
        case "medium":
            return 2
        case "low":
            return 1
        default:
            return 0
        }
    }

    private static func recencyPriority(from fields: [String: String]) -> Int64 {
        ["last_blocked", "last_transition", "updated"]
            .compactMap { fields[$0] }
            .compactMap(timestampMs(from:))
            .max() ?? 0
    }

    private static func timestampMs(from raw: String) -> Int64? {
        let value = normalizedScalar(raw)
        guard !value.isEmpty else { return nil }

        if let milliseconds = Int64(value) {
            return milliseconds
        }

        guard let date = ISO8601DateFormatter().date(from: value) else {
            return nil
        }
        return Int64(date.timeIntervalSince1970 * 1000.0)
    }

    private static func scalarFields(from raw: String?) -> [String: String] {
        normalizedScalar(raw)
            .split(separator: " ")
            .reduce(into: [String: String]()) { result, token in
                let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return }
                result[key] = value
            }
    }

    private static func displayKey(for item: AXOfficialSkillBlockerSummaryItem) -> String {
        firstMeaningfulScalar([
            normalizedScalar(item.title).lowercased(),
            normalizedScalar(item.subtitle).lowercased(),
            item.packageSHA256.lowercased()
        ])
    }

    private static func firstMeaningfulScalar(_ values: [String]) -> String {
        values.first(where: { !normalizedScalar($0).isEmpty }) ?? ""
    }

    private static func routeDescriptor(
        for kind: XTOfficialSkillsBlockerRouteKind
    ) -> (
        label: String,
        title: String,
        sectionId: String,
        urlBuilder: (
            _ sectionId: String?,
            _ title: String?,
            _ detail: String?,
            _ refreshAction: XTSectionRefreshAction?,
            _ refreshReason: String?
        ) -> URL?
    ) {
        switch kind {
        case .troubleshootGrant:
            return (
                label: "处理授权阻塞",
                title: "处理官方技能授权阻塞",
                sectionId: "troubleshoot",
                urlBuilder: XTDeepLinkURLBuilder.hubSetupURL
            )
        case .reviewBlocked:
            return (
                label: "查看阻塞状态",
                title: "查看受阻的官方技能",
                sectionId: "verify_readiness",
                urlBuilder: XTDeepLinkURLBuilder.hubSetupURL
            )
        case .reviewDegraded:
            return (
                label: "查看降级状态",
                title: "查看已降级的官方技能",
                sectionId: "verify_readiness",
                urlBuilder: XTDeepLinkURLBuilder.hubSetupURL
            )
        case .diagnosticsInstall:
            return (
                label: "打开诊断",
                title: "查看官方技能安装状态",
                sectionId: "diagnostics",
                urlBuilder: XTDeepLinkURLBuilder.settingsURL
            )
        case .diagnosticsSupport:
            return (
                label: "打开诊断",
                title: "查看官方技能支持状态",
                sectionId: "diagnostics",
                urlBuilder: XTDeepLinkURLBuilder.settingsURL
            )
        case .diagnosticsRevocation:
            return (
                label: "打开诊断",
                title: "查看官方技能撤销状态",
                sectionId: "diagnostics",
                urlBuilder: XTDeepLinkURLBuilder.settingsURL
            )
        case .reviewFallback:
            return (
                label: "打开就绪检查",
                title: "查看官方技能阻塞项",
                sectionId: "verify_readiness",
                urlBuilder: XTDeepLinkURLBuilder.hubSetupURL
            )
        }
    }

    private static func actionDetail(for item: AXOfficialSkillBlockerSummaryItem) -> String {
        let display = displayLabel(for: item)
        let summary = normalizedScalar(item.summaryLine)
        let timeline = normalizedScalar(item.timelineLine)
        let parts = [display, summary, timeline].filter { !$0.isEmpty }
        return parts.joined(separator: " | ")
    }

    private static func displayLabel(for item: AXOfficialSkillBlockerSummaryItem) -> String {
        let title = normalizedScalar(item.title)
        let subtitle = normalizedScalar(item.subtitle)
        let state = normalizedStateLabel(item.stateLabel)

        let subject: String
        if !title.isEmpty, !subtitle.isEmpty {
            subject = "\(title) (\(subtitle))"
        } else if !title.isEmpty {
            subject = title
        } else if !subtitle.isEmpty {
            subject = subtitle
        } else {
            subject = item.packageSHA256
        }

        guard !state.isEmpty else { return subject }
        return "\(subject) [\(state)]"
    }

    private static func normalizedStateLabel(_ raw: String) -> String {
        normalizedScalar(raw)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func summaryIndicatesGrantRequired(_ raw: String) -> Bool {
        normalizedScalar(raw)
            .lowercased()
            .contains("grant=required")
    }

    private static func normalizedScalar(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
