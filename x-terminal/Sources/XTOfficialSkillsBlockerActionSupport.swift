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

    static func topActionLabel(for blockers: [AXOfficialSkillBlockerSummaryItem]) -> String? {
        let ranked = rankedBlockers(blockers)
        guard !ranked.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for item in ranked {
            guard let label = action(for: item)?.label else { continue }
            counts[label, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .first?
            .key
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

    static func headline(for item: AXOfficialSkillBlockerSummaryItem) -> String {
        let state = normalizedStateLabel(item.stateLabel)
        if ["blocked", "degraded"].contains(state),
           summaryIndicatesGrantRequired(item.summaryLine) {
            return "当前卡在 Hub Grant，官方包还没进入真正可执行态。"
        }

        switch state {
        case "blocked":
            return "当前包处于阻塞态，先处理治理或分发异常，再恢复官方技能链。"
        case "degraded":
            return "当前包还能被看见，但链路已降级，建议先把真相和执行面拉齐。"
        case "not installed":
            return "catalog 已经知道这个包，但当前设备 / 项目上还没真正安装到可执行面。"
        case "not supported":
            return "当前环境或项目治理不支持这个官方技能包，需要先回到治理或兼容面处理。"
        case "revoked":
            return "这个包已经进入撤销 / 失效态，应该优先确认信任链和替代路径。"
        default:
            return "这个官方技能包需要人工看一下治理状态，再决定下一步修复动作。"
        }
    }

    static func actionExplanation(for item: AXOfficialSkillBlockerSummaryItem) -> String {
        switch routeKind(for: item) {
        case .troubleshootGrant:
            return "优先补齐 Hub grant / capability chain，让官方包重新进入可请求、可执行的治理态。"
        case .reviewBlocked:
            return "先回到 readiness / blocker 面确认卡在哪一层，再决定是刷新真相还是改治理。"
        case .reviewDegraded:
            return "先确认是分发、缓存还是执行面降级，避免模型看到包却命不中真实执行链。"
        case .diagnosticsInstall:
            return "先排查安装与 pinning，确认官方包是否真的落到了项目或全局执行面。"
        case .diagnosticsSupport:
            return "先核对当前运行环境、项目设置和兼容面，确认为什么这个包被判定为不支持。"
        case .diagnosticsRevocation:
            return "先确认信任根、撤销原因和替代包，避免继续依赖一个已失效的官方技能。"
        case .reviewFallback:
            return "先打开 readiness 面看最新真相，避免只根据旧缓存或单次报错继续修。"
        }
    }

    static func unblockActionLabels(for item: AXOfficialSkillBlockerSummaryItem) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for action in item.unblockActions.map(unblockActionLabel) {
            let normalized = normalizedScalar(action).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(action)
        }
        return ordered
    }

    static func unblockActionLabel(_ action: String) -> String {
        switch normalizedScalar(action).lowercased() {
        case "request_hub_grant":
            return "处理 Hub Grant"
        case "request_local_approval":
            return "处理本地审批"
        case "open_project_settings":
            return "项目治理"
        case "open_trusted_automation_doctor":
            return "可信自动化诊断"
        case "reconnect_hub":
            return "重连 Hub"
        case "open_skill_governance_surface":
            return "打开治理面"
        case "refresh_resolved_cache":
            return "刷新真相"
        case "install_baseline":
            return "安装 Baseline"
        case "pin_package_project":
            return "固定到项目"
        case "pin_package_global":
            return "固定到全局"
        case "retry_dispatch":
            return "重试调度"
        default:
            return normalizedScalar(action)
        }
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
        let whyNotRunnable = normalizedScalar(item.whyNotRunnable)
        let unblock = item.unblockActions.isEmpty ? "" : "unblock_actions=\(item.unblockActions.joined(separator: ","))"
        let parts = [display, summary, timeline, whyNotRunnable, unblock].filter { !$0.isEmpty }
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
