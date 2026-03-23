import Foundation

struct AXModelRouteDiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = "xt.model_route_diagnostic_event.v1"

    var schemaVersion: String
    var createdAt: Double
    var projectId: String
    var projectDisplayName: String
    var role: String
    var stage: String
    var requestedModelId: String
    var actualModelId: String
    var runtimeProvider: String
    var executionPath: String
    var fallbackReasonCode: String
    var remoteRetryAttempted: Bool
    var remoteRetryFromModelId: String
    var remoteRetryToModelId: String
    var remoteRetryReasonCode: String

    var id: String {
        [
            projectId,
            role,
            String(Int((createdAt * 1000).rounded())),
            executionPath,
            requestedModelId,
            actualModelId
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ":")
    }

    var isFailureIncident: Bool {
        switch executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "remote_error":
            return true
        default:
            return false
        }
    }

    var isRemoteRetryRecovery: Bool {
        executionPath == "remote_model"
            && remoteRetryAttempted
            && !remoteRetryToModelId.isEmpty
    }

    var isNotable: Bool {
        isFailureIncident || remoteRetryAttempted
    }

    func diagnosticLine(includeProject: Bool) -> String {
        var parts: [String] = []
        if includeProject {
            let display = projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("project=\(display.isEmpty ? projectId : display)")
        }
        if !role.isEmpty {
            parts.append("role=\(role)")
        }
        if !executionPath.isEmpty {
            parts.append("path=\(executionPath)")
        }
        if remoteRetryAttempted {
            let retryFrom = remoteRetryFromModelId.isEmpty ? requestedModelId : remoteRetryFromModelId
            if !retryFrom.isEmpty || !remoteRetryToModelId.isEmpty {
                let fromText = retryFrom.isEmpty ? "remote" : retryFrom
                let toText = remoteRetryToModelId.isEmpty ? "backup_remote" : remoteRetryToModelId
                parts.append("remote_retry=\(fromText)->\(toText)")
            } else {
                parts.append("remote_retry=true")
            }
            if !remoteRetryReasonCode.isEmpty {
                parts.append("retry_reason=\(remoteRetryReasonCode)")
            }
        }
        if !requestedModelId.isEmpty {
            parts.append("requested=\(requestedModelId)")
        }
        if !actualModelId.isEmpty {
            parts.append("actual=\(actualModelId)")
        }
        if !fallbackReasonCode.isEmpty {
            parts.append("reason=\(fallbackReasonCode)")
        }
        if !runtimeProvider.isEmpty {
            parts.append("provider=\(runtimeProvider)")
        }
        return parts.joined(separator: " ")
    }
}

struct AXModelRouteDiagnosticsSummary: Equatable, Sendable {
    static let empty = AXModelRouteDiagnosticsSummary(
        recentEventCount: 0,
        recentFailureCount: 0,
        recentRemoteRetryRecoveryCount: 0,
        latestEvent: nil,
        detailLines: []
    )

    var recentEventCount: Int
    var recentFailureCount: Int
    var recentRemoteRetryRecoveryCount: Int
    var latestEvent: AXModelRouteDiagnosticEvent?
    var detailLines: [String]
}

struct AXModelRouteTruthProjection: Codable, Equatable, Sendable {
    var projectionSource: String
    var completeness: String
    var requestSnapshot: AXModelRouteTruthRequestSnapshot
    var resolutionChain: [AXModelRouteTruthResolutionNode]
    var winningProfile: AXModelRouteTruthWinningProfile
    var winningBinding: AXModelRouteTruthWinningBinding
    var routeResult: AXModelRouteTruthRouteResult
    var constraintSnapshot: AXModelRouteTruthConstraintSnapshot
}

struct AXModelRouteTruthRequestSnapshot: Codable, Equatable, Sendable {
    var jobType: String
    var mode: String
    var projectIDPresent: String
    var sensitivity: String
    var trustLevel: String
    var budgetClass: String
    var remoteAllowedByPolicy: String
    var killSwitchState: String
}

struct AXModelRouteTruthResolutionNode: Codable, Equatable, Sendable {
    var scopeKind: String
    var scopeRefRedacted: String
    var matched: String
    var profileID: String
    var selectionStrategy: String
    var skipReason: String
}

struct AXModelRouteTruthWinningProfile: Codable, Equatable, Sendable {
    var resolvedProfileID: String
    var scopeKind: String
    var scopeRefRedacted: String
    var selectionStrategy: String
    var policyVersion: String
    var disabled: String
}

struct AXModelRouteTruthWinningBinding: Codable, Equatable, Sendable {
    var bindingKind: String
    var bindingKey: String
    var provider: String
    var modelID: String
    var selectedByUser: String
}

struct AXModelRouteTruthRouteResult: Codable, Equatable, Sendable {
    var routeSource: String
    var routeReasonCode: String
    var fallbackApplied: String
    var fallbackReason: String
    var remoteAllowed: String
    var auditRef: String
    var denyCode: String
}

struct AXModelRouteTruthConstraintSnapshot: Codable, Equatable, Sendable {
    var remoteAllowedAfterUserPref: String
    var remoteAllowedAfterPolicy: String
    var budgetClass: String
    var budgetBlocked: String
    var policyBlockedRemote: String
}

private struct AXModelRouteObservedDiagnosticLine {
    var auditRef: String
    var projectPresent: Bool
    var executionPath: String
    var requestedModelID: String
    var actualModelID: String
    var provider: String
    var fallbackReasonCode: String
    var remoteRetryTargetModelID: String
    var remoteRetryReasonCode: String
}

extension AXModelRouteDiagnosticsSummary {
    var truthProjection: AXModelRouteTruthProjection? {
        AXModelRouteTruthProjection(summary: self)
    }
}

extension AXModelRouteTruthProjection {
    init?(summary: AXModelRouteDiagnosticsSummary) {
        guard summary.recentEventCount > 0 || summary.recentFailureCount > 0 || summary.recentRemoteRetryRecoveryCount > 0 else {
            return nil
        }

        let latestObservedEvent = summary.latestEvent.map { event in
            AXModelRouteObservedDiagnosticLine(
                auditRef: event.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "latest_event" : event.id,
                projectPresent: !event.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !event.projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                executionPath: event.executionPath,
                requestedModelID: event.requestedModelId,
                actualModelID: event.actualModelId,
                provider: event.runtimeProvider,
                fallbackReasonCode: event.fallbackReasonCode,
                remoteRetryTargetModelID: event.remoteRetryToModelId,
                remoteRetryReasonCode: event.remoteRetryReasonCode
            )
        }
        self = AXModelRouteTruthProjection.make(latestObservedEvent: latestObservedEvent, projectionSource: "xt_model_route_diagnostics_summary")
    }

    init?(doctorDetailLines: [String]) {
        let detailMap = axModelRouteDetailLineMap(from: doctorDetailLines)
        let routeEventEntries = axModelRouteOrderedRouteEventEntries(detailMap)
        guard !routeEventEntries.isEmpty
                || detailMap["recent_route_events_24h"] != nil
                || detailMap["recent_route_failures_24h"] != nil
                || detailMap["recent_remote_retry_recoveries_24h"] != nil else {
            return nil
        }

        let latestObservedEvent = routeEventEntries.first.map { entry in
            AXModelRouteObservedDiagnosticLine(
                auditRef: entry.key,
                projectPresent: entry.value.contains("project="),
                executionPath: axModelRouteTokenValue("path", in: entry.value) ?? "",
                requestedModelID: axModelRouteTokenValue("requested", in: entry.value) ?? "",
                actualModelID: axModelRouteTokenValue("actual", in: entry.value) ?? "",
                provider: axModelRouteTokenValue("provider", in: entry.value) ?? "",
                fallbackReasonCode: axModelRouteTokenValue("reason", in: entry.value) ?? "",
                remoteRetryTargetModelID: axModelRouteRemoteRetryTarget(from: entry.value) ?? "",
                remoteRetryReasonCode: axModelRouteTokenValue("retry_reason", in: entry.value) ?? ""
            )
        }
        self = AXModelRouteTruthProjection.make(
            latestObservedEvent: latestObservedEvent,
            projectionSource: "xt_model_route_diagnostics_detail_lines"
        )
    }

    private static func make(
        latestObservedEvent: AXModelRouteObservedDiagnosticLine?,
        projectionSource: String
    ) -> AXModelRouteTruthProjection {
        let fallbackApplied = axModelRouteFallbackAppliedState(for: latestObservedEvent?.executionPath)
        let fallbackReason = axModelRouteFallbackReason(
            fallbackApplied: fallbackApplied,
            event: latestObservedEvent
        )
        let routeReasonCode = axModelRouteFirstNonEmpty(
            latestObservedEvent?.fallbackReasonCode,
            latestObservedEvent?.remoteRetryReasonCode
        ) ?? "unknown"
        let bindingModelID = axModelRouteFirstNonEmpty(
            latestObservedEvent?.actualModelID,
            latestObservedEvent?.requestedModelID,
            latestObservedEvent?.remoteRetryTargetModelID
        ) ?? "unknown"

        return AXModelRouteTruthProjection(
            projectionSource: projectionSource,
            completeness: latestObservedEvent == nil ? "partial_counts_only" : "partial_xt_projection",
            requestSnapshot: AXModelRouteTruthRequestSnapshot(
                jobType: "unknown",
                mode: "unknown",
                projectIDPresent: axModelRouteProjectPresenceState(for: latestObservedEvent),
                sensitivity: "unknown",
                trustLevel: "unknown",
                budgetClass: "unknown",
                remoteAllowedByPolicy: "unknown",
                killSwitchState: "unknown"
            ),
            resolutionChain: axModelRoutePartialResolutionChain(),
            winningProfile: AXModelRouteTruthWinningProfile(
                resolvedProfileID: "unknown",
                scopeKind: "unknown",
                scopeRefRedacted: "unknown",
                selectionStrategy: "unknown",
                policyVersion: "unknown",
                disabled: "unknown"
            ),
            winningBinding: AXModelRouteTruthWinningBinding(
                bindingKind: "unknown",
                bindingKey: "unknown",
                provider: axModelRouteFallbackString(latestObservedEvent?.provider),
                modelID: bindingModelID,
                selectedByUser: "unknown"
            ),
            routeResult: AXModelRouteTruthRouteResult(
                routeSource: axModelRouteFallbackString(latestObservedEvent?.executionPath),
                routeReasonCode: routeReasonCode,
                fallbackApplied: fallbackApplied,
                fallbackReason: fallbackReason,
                remoteAllowed: "unknown",
                auditRef: latestObservedEvent?.auditRef ?? "unknown",
                denyCode: "unknown"
            ),
            constraintSnapshot: AXModelRouteTruthConstraintSnapshot(
                remoteAllowedAfterUserPref: "unknown",
                remoteAllowedAfterPolicy: "unknown",
                budgetClass: "unknown",
                budgetBlocked: "unknown",
                policyBlockedRemote: "unknown"
            )
        )
    }
}

enum AXModelRouteDiagnosticsStore {
    static func appendUsageIfNeeded(_ entry: [String: Any], for ctx: AXProjectContext) {
        guard let event = event(from: entry, ctx: ctx) else { return }
        guard let data = try? JSONEncoder().encode(event) else { return }
        appendJSONLLine(data, to: ctx.modelRouteDiagnosticsLogURL)
    }

    static func recentEvents(for ctx: AXProjectContext, limit: Int = 20) -> [AXModelRouteDiagnosticEvent] {
        let logEvents = loadEvents(from: ctx.modelRouteDiagnosticsLogURL)
        if !logEvents.isEmpty {
            return Array(logEvents.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id > rhs.id
            }.prefix(limit))
        }

        let usageEvents = loadEventsFromUsageLog(ctx: ctx)
        return Array(usageEvents.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id > rhs.id
        }.prefix(limit))
    }

    static func diagnosisSummary(
        for ctx: AXProjectContext,
        limit: Int = 3
    ) -> String {
        let events = recentEvents(for: ctx, limit: limit)
        guard !events.isEmpty else {
            return "无最近路由异常或远端重试记录。"
        }

        return events.map { "- \($0.diagnosticLine(includeProject: false))" }
            .joined(separator: "\n")
    }

    static func doctorSummary(
        for projects: [AXProjectEntry],
        now: Date = Date(),
        recentWindow: TimeInterval = 24 * 60 * 60,
        limit: Int = 3
    ) -> AXModelRouteDiagnosticsSummary {
        let cutoff = now.timeIntervalSince1970 - max(60, recentWindow)
        var collected: [AXModelRouteDiagnosticEvent] = []

        for project in projects {
            let rootPath = project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rootPath.isEmpty else { continue }
            let ctx = AXProjectContext(root: URL(fileURLWithPath: rootPath, isDirectory: true))
            for var event in recentEvents(for: ctx, limit: max(limit * 2, 8)) {
                if !project.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    event.projectDisplayName = project.displayName
                } else if event.projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    event.projectDisplayName = resolvedProjectDisplayName(for: ctx)
                }
                guard event.createdAt >= cutoff else { continue }
                collected.append(event)
            }
        }

        collected.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id > rhs.id
        }

        let recentFailures = collected.filter(\.isFailureIncident)
        let recentRecoveries = collected.filter(\.isRemoteRetryRecovery)
        var detailLines: [String] = [
            "recent_route_events_24h=\(collected.count)",
            "recent_route_failures_24h=\(recentFailures.count)",
            "recent_remote_retry_recoveries_24h=\(recentRecoveries.count)"
        ]
        for (index, event) in collected.prefix(limit).enumerated() {
            detailLines.append("route_event_\(index + 1)=\(event.diagnosticLine(includeProject: true))")
        }

        return AXModelRouteDiagnosticsSummary(
            recentEventCount: collected.count,
            recentFailureCount: recentFailures.count,
            recentRemoteRetryRecoveryCount: recentRecoveries.count,
            latestEvent: collected.first,
            detailLines: detailLines
        )
    }

    private static func loadEvents(from url: URL) -> [AXModelRouteDiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(AXModelRouteDiagnosticEvent.self, from: data)
            }
    }

    private static func loadEventsFromUsageLog(ctx: AXProjectContext) -> [AXModelRouteDiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: ctx.usageLogURL.path),
              let data = try? Data(contentsOf: ctx.usageLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return event(from: obj, ctx: ctx)
            }
    }

    private static func event(
        from obj: [String: Any],
        ctx: AXProjectContext
    ) -> AXModelRouteDiagnosticEvent? {
        guard text(obj["type"]) == "ai_usage" else { return nil }

        let executionPath = text(obj["execution_path"])
        let remoteRetryAttempted = bool(obj["remote_retry_attempted"]) ?? false
        guard isNotable(executionPath: executionPath, remoteRetryAttempted: remoteRetryAttempted) else {
            return nil
        }

        let createdAt = number(obj["created_at"])
        let projectDisplayName = resolvedProjectDisplayName(for: ctx)
        return AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: createdAt,
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectDisplayName: projectDisplayName,
            role: text(obj["role"]),
            stage: text(obj["stage"]),
            requestedModelId: text(obj["requested_model_id"]),
            actualModelId: text(obj["actual_model_id"]),
            runtimeProvider: text(obj["runtime_provider"]),
            executionPath: executionPath,
            fallbackReasonCode: text(obj["fallback_reason_code"]),
            remoteRetryAttempted: remoteRetryAttempted,
            remoteRetryFromModelId: text(obj["remote_retry_from_model_id"]),
            remoteRetryToModelId: text(obj["remote_retry_to_model_id"]),
            remoteRetryReasonCode: text(obj["remote_retry_reason_code"])
        )
    }

    private static func isNotable(
        executionPath: String,
        remoteRetryAttempted: Bool
    ) -> Bool {
        switch executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "remote_error":
            return true
        case "remote_model":
            return remoteRetryAttempted
        default:
            return remoteRetryAttempted
        }
    }

    private static func resolvedProjectDisplayName(for ctx: AXProjectContext) -> String {
        AXProjectRegistryStore.displayName(
            forRoot: ctx.root,
            preferredDisplayName: ctx.projectName()
        )
    }

    private static func text(_ raw: Any?) -> String {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func number(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? Int64 { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String, let parsed = Double(value) { return parsed }
        return 0
    }

    private static func bool(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        if let value = raw as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        }
        return nil
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

private func axModelRoutePartialResolutionChain() -> [AXModelRouteTruthResolutionNode] {
    [
        "project_mode",
        "project",
        "mode",
        "user_default",
        "system_fallback"
    ].map { scope in
        AXModelRouteTruthResolutionNode(
            scopeKind: scope,
            scopeRefRedacted: "unknown",
            matched: "unknown",
            profileID: "unknown",
            selectionStrategy: "unknown",
            skipReason: "upstream_route_truth_unavailable_in_xt_export"
        )
    }
}

private func axModelRouteDetailLineMap(from detailLines: [String]) -> [String: String] {
    detailLines.reduce(into: [String: String]()) { partial, line in
        guard let separator = line.firstIndex(of: "=") else { return }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        partial[key] = value
    }
}

private func axModelRouteOrderedRouteEventEntries(_ detailMap: [String: String]) -> [(key: String, value: String)] {
    detailMap
        .filter { $0.key.hasPrefix("route_event_") }
        .sorted { lhs, rhs in
            let lhsIndex = Int(lhs.key.replacingOccurrences(of: "route_event_", with: "")) ?? .max
            let rhsIndex = Int(rhs.key.replacingOccurrences(of: "route_event_", with: "")) ?? .max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.key < rhs.key
        }
}

private func axModelRouteTokenValue(_ key: String, in line: String) -> String? {
    line
        .split(separator: " ", omittingEmptySubsequences: true)
        .first { $0.hasPrefix("\(key)=") }
        .map { String($0.dropFirst(key.count + 1)) }
}

private func axModelRouteRemoteRetryTarget(from line: String) -> String? {
    guard let remoteRetry = axModelRouteTokenValue("remote_retry", in: line),
          let separator = remoteRetry.firstIndex(of: ">") else {
        return nil
    }
    let rawTarget = String(remoteRetry[remoteRetry.index(after: separator)...])
    let target = rawTarget.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
    return target.isEmpty ? nil : target
}

private func axModelRouteFallbackAppliedState(for executionPath: String?) -> String {
    switch executionPath {
    case "hub_downgraded_to_local", "local_fallback_after_remote_error":
        return "true"
    case "remote_model", "remote_error":
        return "false"
    case .none:
        return "unknown"
    case .some(let value) where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
        return "unknown"
    default:
        return "unknown"
    }
}

private func axModelRouteFallbackReason(
    fallbackApplied: String,
    event: AXModelRouteObservedDiagnosticLine?
) -> String {
    guard fallbackApplied == "true" else {
        return fallbackApplied == "false" ? "none" : "unknown"
    }
    return axModelRouteFirstNonEmpty(event?.fallbackReasonCode, event?.remoteRetryReasonCode) ?? "unknown"
}

private func axModelRouteProjectPresenceState(for event: AXModelRouteObservedDiagnosticLine?) -> String {
    guard let event else { return "unknown" }
    return event.projectPresent ? "true" : "false"
}

private func axModelRouteFirstNonEmpty(_ values: String?...) -> String? {
    for value in values {
        guard let value else { continue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

private func axModelRouteFallbackString(_ value: String?) -> String {
    axModelRouteFirstNonEmpty(value) ?? "unknown"
}
