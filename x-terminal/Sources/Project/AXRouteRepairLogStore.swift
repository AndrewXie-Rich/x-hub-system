import Foundation

struct AXRouteRepairLogDigest: Equatable, Sendable {
    var totalEvents: Int
    var failureCount: Int
    var topRouteReason: String?
    var topRouteReasonCount: Int
    var topRepairReason: String?
    var topRepairReasonCount: Int
    var latestFailure: AXRouteRepairLogEvent?
    var latestSuccess: AXRouteRepairLogEvent?

    static let empty = AXRouteRepairLogDigest(
        totalEvents: 0,
        failureCount: 0,
        topRouteReason: nil,
        topRouteReasonCount: 0,
        topRepairReason: nil,
        topRepairReasonCount: 0,
        latestFailure: nil,
        latestSuccess: nil
    )

    var headline: String {
        guard totalEvents > 0 else {
            return "最近还没有路由修复记录。"
        }

        var parts: [String] = [
            "最近 \(totalEvents) 次路由修复"
        ]
        if let topRouteReason, topRouteReasonCount > 0 {
            parts.append(
                "最常见的路由问题是 \(AXRouteRepairLogStore.userFacingRouteReason(topRouteReason, includeCode: true))（\(topRouteReasonCount) 次）"
            )
        }
        if let latestFailure {
            parts.append(
                "最近一次失败停在 \(AXRouteRepairLogStore.userFacingActionLabel(latestFailure.actionId))"
            )
        } else if let latestSuccess {
            parts.append(
                "最近一次结果是 \(AXRouteRepairLogStore.userFacingActionLabel(latestSuccess.actionId))（\(AXRouteRepairLogStore.userFacingOutcomeLabel(latestSuccess.outcome))）"
            )
        }
        return parts.joined(separator: "；")
    }

    var detailLines: [String] {
        guard totalEvents > 0 else { return [] }

        var lines: [String] = [
            "recent_route_repairs=\(totalEvents)",
            "recent_route_repair_failures=\(failureCount)"
        ]
        if let topRouteReason, topRouteReasonCount > 0 {
            lines.append("top_route_reason=\(topRouteReason) count=\(topRouteReasonCount)")
        }
        if let topRepairReason, topRepairReasonCount > 0 {
            lines.append("top_repair_reason=\(topRepairReason) count=\(topRepairReasonCount)")
        }
        if let latestFailure {
            lines.append("latest_failure=\(latestFailure.summaryLine(includeProject: false))")
        }
        if let latestSuccess {
            lines.append("latest_success=\(latestSuccess.summaryLine(includeProject: false))")
        }
        return lines
    }
}

struct AXRouteRepairProjectWatchItem: Identifiable, Equatable, Sendable {
    var projectId: String
    var projectDisplayName: String
    var digest: AXRouteRepairLogDigest
    var latestEventAt: Double?

    var id: String { projectId }

    var summary: String {
        digest.headline
    }
}

struct AXRouteRepairLogEvent: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = "xt.route_repair_log_event.v1"

    var schemaVersion: String
    var createdAt: Double
    var projectId: String
    var projectDisplayName: String
    var actionId: String
    var outcome: String
    var requestedModelId: String
    var actualModelId: String
    var fallbackReasonCode: String
    var repairReasonCode: String
    var note: String

    var id: String {
        [
            projectId,
            actionId,
            outcome,
            String(Int((createdAt * 1000).rounded()))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ":")
    }

    func summaryLine(includeProject: Bool = false) -> String {
        var parts: [String] = []
        if includeProject {
            let display = projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("project=\(display.isEmpty ? projectId : display)")
        }
        parts.append("action=\(actionId)")
        parts.append("outcome=\(outcome)")
        if !requestedModelId.isEmpty {
            parts.append("requested=\(requestedModelId)")
        }
        if !actualModelId.isEmpty {
            parts.append("actual=\(actualModelId)")
        }
        if !fallbackReasonCode.isEmpty {
            parts.append("route_reason=\(fallbackReasonCode)")
        }
        if !repairReasonCode.isEmpty {
            parts.append("repair_reason=\(repairReasonCode)")
        }
        if !note.isEmpty {
            parts.append("note=\(note)")
        }
        return parts.joined(separator: " ")
    }

    func userFacingSummaryLine(includeProject: Bool = false) -> String {
        var parts: [String] = []
        if includeProject {
            let display = projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(display.isEmpty ? projectId : display)
        }

        let action = AXRouteRepairLogStore.userFacingActionLabel(actionId)
        let outcome = AXRouteRepairLogStore.userFacingOutcomeLabel(outcome)
        if !action.isEmpty, !outcome.isEmpty {
            parts.append("\(action)（\(outcome)）")
        } else if !action.isEmpty {
            parts.append(action)
        } else if !outcome.isEmpty {
            parts.append(outcome)
        }

        if !requestedModelId.isEmpty {
            parts.append("请求 \(requestedModelId)")
        }
        if !actualModelId.isEmpty {
            parts.append("实际 \(actualModelId)")
        }
        if !fallbackReasonCode.isEmpty {
            parts.append(
                "路由问题 \(AXRouteRepairLogStore.userFacingRouteReason(fallbackReasonCode, includeCode: true))"
            )
        }
        if !repairReasonCode.isEmpty {
            parts.append(
                "修复原因 \(AXRouteRepairLogStore.userFacingRouteReason(repairReasonCode, includeCode: true))"
            )
        }
        if let note = AXRouteRepairLogStore.userFacingNoteLabel(note) {
            parts.append(note)
        }

        return parts.joined(separator: " · ")
    }
}

enum AXRouteRepairLogStore {
    static func userFacingActionLabel(_ raw: String) -> String {
        let normalized = normalizedText(raw)
        guard !normalized.isEmpty else { return "" }

        switch normalized.lowercased() {
        case "open_model_picker":
            return "打开模型候选"
        case "apply_recommended_model":
            return "改用推荐模型"
        case "connect_hub_and_diagnose":
            return "连接 Hub 并重诊断"
        case "reconnect_hub_and_diagnose":
            return "重连并重诊断"
        case "open_choose_model":
            return "打开 Choose Model"
        case "open_model_settings":
            return "打开模型设置"
        case "open_xt_diagnostics":
            return "打开 XT Diagnostics"
        case "open_hub_recovery":
            return "打开 Hub Recovery"
        case "open_hub_connection_log":
            return "打开 Hub 日志"
        default:
            return normalized
        }
    }

    static func userFacingOutcomeLabel(_ raw: String) -> String {
        let normalized = normalizedText(raw)
        guard !normalized.isEmpty else { return "" }

        switch normalized.lowercased() {
        case "opened":
            return "已打开"
        case "auto_opened":
            return "已自动打开"
        case "selected":
            return "已选择"
        case "started":
            return "已开始"
        case "succeeded":
            return "已成功"
        case "failed":
            return "失败"
        default:
            return normalized
        }
    }

    static func userFacingRouteReason(
        _ raw: String,
        includeCode: Bool = false
    ) -> String {
        let normalized = normalizedText(raw)
        guard !normalized.isEmpty else { return "" }

        let label: String
        switch normalized.lowercased() {
        case "model_not_found", "remote_model_not_found":
            label = "目标模型未加载"
        case "grpc_route_unavailable":
            label = "远端链路不可用"
        case "runtime_not_running":
            label = "Hub runtime 未启动"
        case "response_timeout":
            label = "远端响应超时"
        case "request_write_failed":
            label = "请求发送失败"
        case "remote_export_blocked":
            label = "远端导出被拦截"
        case "downgrade_to_local":
            label = "Hub 降级到本地"
        default:
            label = normalized
        }

        guard includeCode,
              label.caseInsensitiveCompare(normalized) != .orderedSame else {
            return label
        }
        return "\(label)（\(normalized)）"
    }

    static func userFacingNoteLabel(_ raw: String) -> String? {
        let normalized = normalizedText(raw)
        guard !normalized.isEmpty else { return nil }

        switch normalized.lowercased() {
        case "source=connect_hub_and_diagnose_failed":
            return "来源 连接 Hub 失败后自动打开"
        case "source=reconnect_hub_and_diagnose_failed":
            return "来源 重连失败后自动打开"
        default:
            break
        }

        if normalized.lowercased().hasPrefix("target_model=") {
            let modelId = String(normalized.dropFirst("target_model=".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !modelId.isEmpty {
                return "目标模型 \(modelId)"
            }
        }

        return "备注 \(normalized)"
    }

    static func record(
        actionId: String,
        outcome: String,
        latestEvent: AXModelRouteDiagnosticEvent?,
        repairReasonCode: String? = nil,
        note: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        for ctx: AXProjectContext
    ) {
        let normalizedActionId = normalizedText(actionId)
        let normalizedOutcome = normalizedText(outcome)
        guard !normalizedActionId.isEmpty, !normalizedOutcome.isEmpty else { return }
        try? ctx.ensureDirs()

        let event = AXRouteRepairLogEvent(
            schemaVersion: AXRouteRepairLogEvent.currentSchemaVersion,
            createdAt: createdAt,
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectDisplayName: AXProjectRegistryStore.displayName(
                forRoot: ctx.root,
                preferredDisplayName: ctx.projectName()
            ),
            actionId: normalizedActionId,
            outcome: normalizedOutcome,
            requestedModelId: normalizedText(latestEvent?.requestedModelId),
            actualModelId: normalizedText(latestEvent?.actualModelId),
            fallbackReasonCode: normalizedText(latestEvent?.fallbackReasonCode),
            repairReasonCode: normalizedText(repairReasonCode),
            note: normalizedText(note)
        )
        guard let data = try? JSONEncoder().encode(event) else { return }
        appendJSONLLine(data, to: ctx.routeRepairLogURL)
    }

    static func recentEvents(for ctx: AXProjectContext, limit: Int = 20) -> [AXRouteRepairLogEvent] {
        guard FileManager.default.fileExists(atPath: ctx.routeRepairLogURL.path),
              let data = try? Data(contentsOf: ctx.routeRepairLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let events = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> AXRouteRepairLogEvent? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(AXRouteRepairLogEvent.self, from: data)
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id > rhs.id
            }
        return Array(events.prefix(limit))
    }

    static func summaryLines(for ctx: AXProjectContext, limit: Int = 5) -> [String] {
        recentEvents(for: ctx, limit: limit).map { $0.summaryLine(includeProject: false) }
    }

    static func userFacingSummaryLines(for ctx: AXProjectContext, limit: Int = 5) -> [String] {
        recentEvents(for: ctx, limit: limit).map { $0.userFacingSummaryLine(includeProject: false) }
    }

    static func digest(for ctx: AXProjectContext, limit: Int = 50) -> AXRouteRepairLogDigest {
        let events = recentEvents(for: ctx, limit: limit)
        guard !events.isEmpty else { return .empty }

        let failureCount = events.filter { $0.outcome == "failed" }.count
        let latestFailure = events.first(where: { $0.outcome == "failed" })
        let latestSuccess = events.first(where: { $0.outcome != "failed" })
        let topRoute = topCountedValue(events.map(\.fallbackReasonCode))
        let topRepair = topCountedValue(events.map(\.repairReasonCode))

        return AXRouteRepairLogDigest(
            totalEvents: events.count,
            failureCount: failureCount,
            topRouteReason: topRoute.value,
            topRouteReasonCount: topRoute.count,
            topRepairReason: topRepair.value,
            topRepairReasonCount: topRepair.count,
            latestFailure: latestFailure,
            latestSuccess: latestSuccess
        )
    }

    static func watchItems(
        for projects: [AXProjectEntry],
        limit: Int = 3,
        digestLimit: Int = 50
    ) -> [AXRouteRepairProjectWatchItem] {
        let items = projects.compactMap { project -> AXRouteRepairProjectWatchItem? in
            let rootPath = project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rootPath.isEmpty else { return nil }
            let ctx = AXProjectContext(root: URL(fileURLWithPath: rootPath, isDirectory: true))
            let digest = digest(for: ctx, limit: digestLimit)
            guard digest.totalEvents > 0 else { return nil }
            let latestEventAt = recentEvents(for: ctx, limit: 1).first?.createdAt
            return AXRouteRepairProjectWatchItem(
                projectId: project.projectId,
                projectDisplayName: project.displayName,
                digest: digest,
                latestEventAt: latestEventAt
            )
        }

        return Array(
            items.sorted { lhs, rhs in
                let lhsNeedsAttention = lhs.digest.failureCount > 0
                let rhsNeedsAttention = rhs.digest.failureCount > 0
                if lhsNeedsAttention != rhsNeedsAttention {
                    return lhsNeedsAttention && !rhsNeedsAttention
                }
                if lhs.digest.failureCount != rhs.digest.failureCount {
                    return lhs.digest.failureCount > rhs.digest.failureCount
                }
                let lhsEventAt = lhs.latestEventAt ?? 0
                let rhsEventAt = rhs.latestEventAt ?? 0
                if lhsEventAt != rhsEventAt {
                    return lhsEventAt > rhsEventAt
                }
                if lhs.digest.totalEvents != rhs.digest.totalEvents {
                    return lhs.digest.totalEvents > rhs.digest.totalEvents
                }
                return lhs.projectDisplayName.localizedCaseInsensitiveCompare(rhs.projectDisplayName) == .orderedAscending
            }
            .prefix(limit)
        )
    }

    private static func normalizedText(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func topCountedValue(_ values: [String]) -> (value: String?, count: Int) {
        var counts: [String: Int] = [:]
        for raw in values {
            let value = normalizedText(raw)
            guard !value.isEmpty else { continue }
            counts[value, default: 0] += 1
        }
        guard let winner = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }) else {
            return (nil, 0)
        }
        return (winner.key, winner.value)
    }

    private static func appendJSONLLine(_ json: Data, to url: URL) {
        var line = json
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? XTStoreWriteSupport.writeSnapshotData(line, to: url)
            return
        }
        do {
            let fh = try FileHandle(forWritingTo: url)
            defer { try? fh.close() }
            try fh.seekToEnd()
            try fh.write(contentsOf: line)
        } catch {
            // Best-effort only.
        }
    }
}
