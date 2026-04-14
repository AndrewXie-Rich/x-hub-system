import Foundation

struct ProjectSkillActivityItem: Identifiable, Equatable, Sendable {
    var requestID: String
    var skillID: String
    var requestedSkillID: String = ""
    var intentFamilies: [String] = []
    var capabilityFamilies: [String] = []
    var capabilityProfiles: [String] = []
    var requiredRuntimeSurfaces: [String] = []
    var unblockActions: [String] = []
    var toolName: String
    var status: String
    var createdAt: Double
    var resolutionSource: String
    var toolArgs: [String: JSONValue]
    var routingReasonCode: String = ""
    var routingExplanation: String = ""
    var hubStateDirPath: String = ""
    var executionReadiness: String = ""
    var approvalSummary: String = ""
    var currentRunnableProfiles: [String] = []
    var requestedProfiles: [String] = []
    var deltaProfiles: [String] = []
    var currentRunnableCapabilityFamilies: [String] = []
    var requestedCapabilityFamilies: [String] = []
    var deltaCapabilityFamilies: [String] = []
    var grantFloor: String = ""
    var approvalFloor: String = ""
    var requiredCapability: String = ""
    var resultSummary: String
    var detail: String
    var denyCode: String
    var authorizationDisposition: String
    var policySource: String = ""
    var policyReason: String = ""
    var governanceTruth: String = ""
    var governanceReason: String = ""
    var blockedSummary: String = ""
    var repairAction: String = ""

    var id: String { requestID }
}

struct AXProjectSkillActivityEvent: Equatable, Sendable {
    var item: ProjectSkillActivityItem
    var rawObject: [String: JSONValue]
    var lineIndex: Int
}

enum AXProjectSkillActivityStore {
    private static let cacheQueue = DispatchQueue(label: "xterminal.project_skill_activity_store")
    private static let recentTailMaxBytes = 256 * 1024

    private struct CachedTailSnapshot {
        var path: String
        var modifiedAt: TimeInterval
        var fileSize: UInt64
        var events: [AXProjectSkillActivityEvent]
        var latestByRequestID: [String: AXProjectSkillActivityEvent]
    }

    private struct FileSignature: Equatable {
        var modifiedAt: TimeInterval
        var fileSize: UInt64
    }

    private static var recentTailCacheByPath: [String: CachedTailSnapshot] = [:]

    static func loadRecentActivities(
        ctx: AXProjectContext,
        limit: Int = 8
    ) -> [ProjectSkillActivityItem] {
        guard let snapshot = recentTailSnapshot(ctx: ctx) else {
            return []
        }
        guard limit > 0 else { return [] }
        return snapshot.latestByRequestID.values
            .map(\.item)
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.requestID > rhs.requestID
            }
            .prefix(limit)
            .map { $0 }
    }

    static func loadRawLogText(ctx: AXProjectContext) -> String? {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path),
              let data = try? Data(contentsOf: ctx.rawLogURL),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        return raw
    }

    static func loadTailRawLogText(
        ctx: AXProjectContext,
        maxBytes: Int = recentTailMaxBytes
    ) -> String? {
        loadTailRawLogText(url: ctx.rawLogURL, maxBytes: maxBytes)
    }

    static func parseRecentActivities(
        from raw: String,
        limit: Int = 8
    ) -> [ProjectSkillActivityItem] {
        guard limit > 0 else { return [] }

        let latest = latestEventsByRequestID(from: raw)
        return latest.values
            .map(\.item)
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.requestID > rhs.requestID
            }
            .prefix(limit)
            .map { $0 }
    }

    static func loadEvents(
        ctx: AXProjectContext,
        requestID: String
    ) -> [AXProjectSkillActivityEvent] {
        guard let raw = loadRawLogText(ctx: ctx) else {
            return []
        }
        return events(from: raw, requestID: requestID)
    }

    static func events(
        from raw: String,
        requestID: String
    ) -> [AXProjectSkillActivityEvent] {
        let normalizedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestID.isEmpty else { return [] }

        return parsedEvents(from: raw)
            .filter { $0.item.requestID == normalizedRequestID }
            .sorted { lhs, rhs in
                if lhs.item.createdAt != rhs.item.createdAt {
                    return lhs.item.createdAt < rhs.item.createdAt
                }
                return lhs.lineIndex < rhs.lineIndex
            }
    }

    static func dispatchesByRequestID(
        ctx: AXProjectContext,
        toolCalls: [ToolCall]
    ) -> [String: XTProjectMappedSkillDispatch] {
        guard let snapshot = recentTailSnapshot(ctx: ctx) else {
            return [:]
        }
        return dispatchesByRequestID(
            latestItemsByRequestID: snapshot.latestByRequestID.mapValues(\.item),
            toolCalls: toolCalls
        )
    }

    static func dispatchesByRequestID(
        from raw: String,
        toolCalls: [ToolCall]
    ) -> [String: XTProjectMappedSkillDispatch] {
        guard !toolCalls.isEmpty else { return [:] }
        let latestItems = latestEventsByRequestID(from: raw).mapValues(\.item)
        return dispatchesByRequestID(
            latestItemsByRequestID: latestItems,
            toolCalls: toolCalls
        )
    }

    private static func dispatchesByRequestID(
        latestItemsByRequestID latestItems: [String: ProjectSkillActivityItem],
        toolCalls: [ToolCall]
    ) -> [String: XTProjectMappedSkillDispatch] {
        var out: [String: XTProjectMappedSkillDispatch] = [:]
        for call in toolCalls {
            guard let item = latestItems[call.id] else { continue }
            guard let dispatch = dispatch(for: item, toolCall: call) else { continue }
            out[call.id] = dispatch
        }
        return out
    }

    static func dispatch(
        for item: ProjectSkillActivityItem,
        requestID: String? = nil
    ) -> XTProjectMappedSkillDispatch? {
        guard let call = toolCall(for: item, requestID: requestID) else {
            return nil
        }
        return dispatch(for: item, toolCall: call)
    }

    static func toolCall(
        for item: ProjectSkillActivityItem,
        requestID: String? = nil
    ) -> ToolCall? {
        let toolToken = item.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tool = ToolName(rawValue: toolToken) else {
            return nil
        }
        let preferredID = requestID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedID = preferredID.isEmpty
            ? item.requestID.trimmingCharacters(in: .whitespacesAndNewlines)
            : preferredID
        return ToolCall(
            id: resolvedID.isEmpty ? UUID().uuidString : resolvedID,
            tool: tool,
            args: item.toolArgs
        )
    }

    private static func dispatch(
        for item: ProjectSkillActivityItem,
        toolCall: ToolCall
    ) -> XTProjectMappedSkillDispatch? {
        let skillID = item.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skillID.isEmpty else { return nil }

        let requestedSkillID = item.requestedSkillID.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolName = item.toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let routingReasonCode = item.routingReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let routingExplanation = item.routingExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let grantFloor = item.grantFloor.trimmingCharacters(in: .whitespacesAndNewlines)
        let approvalFloor = item.approvalFloor.trimmingCharacters(in: .whitespacesAndNewlines)

        return XTProjectMappedSkillDispatch(
            requestedSkillId: requestedSkillID.isEmpty ? nil : requestedSkillID,
            skillId: skillID,
            intentFamilies: item.intentFamilies,
            capabilityFamilies: item.capabilityFamilies,
            capabilityProfiles: item.capabilityProfiles,
            grantFloor: grantFloor.isEmpty ? XTSkillGrantFloor.none.rawValue : grantFloor,
            approvalFloor: approvalFloor.isEmpty ? XTSkillApprovalFloor.none.rawValue : approvalFloor,
            routingReasonCode: routingReasonCode.isEmpty ? nil : routingReasonCode,
            routingExplanation: routingExplanation.isEmpty ? nil : routingExplanation,
            hubStateDirPath: normalizedHubStateDirPath(item.hubStateDirPath),
            toolCall: toolCall,
            toolName: toolName.isEmpty ? toolCall.tool.rawValue : toolName
        )
    }

    static func prettyJSONString(
        for rawObject: [String: JSONValue]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(JSONValue.object(rawObject)),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func latestEventsByRequestID(
        from raw: String
    ) -> [String: AXProjectSkillActivityEvent] {
        var latestByRequestID: [String: AXProjectSkillActivityEvent] = [:]
        for event in parsedEvents(from: raw) {
            if let existing = latestByRequestID[event.item.requestID] {
                if event.item.createdAt > existing.item.createdAt
                    || (event.item.createdAt == existing.item.createdAt && event.lineIndex > existing.lineIndex) {
                    latestByRequestID[event.item.requestID] = event
                }
            } else {
                latestByRequestID[event.item.requestID] = event
            }
        }
        return latestByRequestID
    }

    private static func recentTailSnapshot(
        ctx: AXProjectContext
    ) -> CachedTailSnapshot? {
        let path = ctx.rawLogURL.path
        guard let signature = fileSignature(for: ctx.rawLogURL) else {
            _ = cacheQueue.sync {
                recentTailCacheByPath.removeValue(forKey: path)
            }
            return nil
        }

        return cacheQueue.sync {
            if let cached = recentTailCacheByPath[path],
               cached.modifiedAt == signature.modifiedAt,
               cached.fileSize == signature.fileSize {
                return cached
            }

            guard let text = loadTailRawLogText(
                url: ctx.rawLogURL,
                maxBytes: recentTailMaxBytes
            ) else {
                recentTailCacheByPath.removeValue(forKey: path)
                return nil
            }

            let events = parsedEvents(from: text)
            let snapshot = CachedTailSnapshot(
                path: path,
                modifiedAt: signature.modifiedAt,
                fileSize: signature.fileSize,
                events: events,
                latestByRequestID: latestEventsByRequestID(from: events)
            )
            recentTailCacheByPath[path] = snapshot
            return snapshot
        }
    }

    private static func latestEventsByRequestID(
        from events: [AXProjectSkillActivityEvent]
    ) -> [String: AXProjectSkillActivityEvent] {
        var latestByRequestID: [String: AXProjectSkillActivityEvent] = [:]
        for event in events {
            if let existing = latestByRequestID[event.item.requestID] {
                if event.item.createdAt > existing.item.createdAt
                    || (event.item.createdAt == existing.item.createdAt && event.lineIndex > existing.lineIndex) {
                    latestByRequestID[event.item.requestID] = event
                }
            } else {
                latestByRequestID[event.item.requestID] = event
            }
        }
        return latestByRequestID
    }

    private static func fileSignature(
        for url: URL
    ) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return FileSignature(
            modifiedAt: modifiedAt,
            fileSize: fileSize
        )
    }

    private static func loadTailRawLogText(
        url: URL,
        maxBytes: Int
    ) -> String? {
        guard let data = readTailData(url: url, maxBytes: maxBytes),
              var text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let totalSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .uint64Value ?? 0
        if totalSize > UInt64(max(8_192, maxBytes)),
           let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        return text
    }

    private static func readTailData(
        url: URL,
        maxBytes: Int
    ) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let bounded = max(8_192, maxBytes)
        let totalSize = (try? handle.seekToEnd()) ?? 0
        let start = totalSize > UInt64(bounded) ? totalSize - UInt64(bounded) : 0
        try? handle.seek(toOffset: start)
        return try? handle.readToEnd()
    }

    private static func parsedEvents(
        from raw: String
    ) -> [AXProjectSkillActivityEvent] {
        raw.split(separator: "\n", omittingEmptySubsequences: true)
            .enumerated()
            .compactMap { lineIndex, line in
                guard let data = line.data(using: .utf8),
                      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                      case .object(let object) = value,
                      let item = parsedActivityItem(object) else {
                    return nil
                }
                return AXProjectSkillActivityEvent(
                    item: item,
                    rawObject: object,
                    lineIndex: lineIndex
                )
            }
    }

    private static func parsedActivityItem(
        _ object: [String: JSONValue]
    ) -> ProjectSkillActivityItem? {
        guard stringValue(object["type"]) == "project_skill_call" else { return nil }

        let requestID = stringValue(object["request_id"]) ?? ""
        guard !requestID.isEmpty else { return nil }

        return ProjectSkillActivityItem(
            requestID: requestID,
            skillID: stringValue(object["skill_id"]) ?? "",
            requestedSkillID: stringValue(object["requested_skill_id"]) ?? "",
            intentFamilies: stringArrayValue(object["intent_families"]),
            capabilityFamilies: stringArrayValue(object["capability_families"]),
            capabilityProfiles: stringArrayValue(object["capability_profiles"]),
            requiredRuntimeSurfaces: stringArrayValue(object["required_runtime_surfaces"]),
            unblockActions: stringArrayValue(object["unblock_actions"]),
            toolName: stringValue(object["tool_name"]) ?? "",
            status: stringValue(object["status"]) ?? "",
            createdAt: numberValue(object["created_at"]) ?? 0,
            resolutionSource: stringValue(object["resolution_source"]) ?? "",
            toolArgs: jsonObjectValue(object["tool_args"]),
            routingReasonCode: stringValue(object["routing_reason_code"]) ?? "",
            routingExplanation: stringValue(object["routing_explanation"]) ?? "",
            hubStateDirPath: stringValue(object["hub_state_dir_path"]) ?? "",
            executionReadiness: stringValue(object["execution_readiness"]) ?? "",
            approvalSummary: stringValue(object["approval_summary"]) ?? "",
            currentRunnableProfiles: stringArrayValue(object["current_runnable_profiles"]),
            requestedProfiles: stringArrayValue(object["requested_profiles"]),
            deltaProfiles: stringArrayValue(object["delta_profiles"]),
            currentRunnableCapabilityFamilies: stringArrayValue(object["current_runnable_capability_families"]),
            requestedCapabilityFamilies: stringArrayValue(object["requested_capability_families"]),
            deltaCapabilityFamilies: stringArrayValue(object["delta_capability_families"]),
            grantFloor: stringValue(object["grant_floor"]) ?? "",
            approvalFloor: stringValue(object["approval_floor"]) ?? "",
            requiredCapability: stringValue(object["required_capability"]) ?? "",
            resultSummary: stringValue(object["result_summary"]) ?? "",
            detail: stringValue(object["detail"]) ?? "",
            denyCode: stringValue(object["deny_code"]) ?? "",
            authorizationDisposition: stringValue(object["authorization_disposition"]) ?? "",
            policySource: stringValue(object["policy_source"]) ?? "",
            policyReason: resolvedPolicyReason(object),
            governanceTruth: stringValue(object["governance_truth"])
                ?? XTGuardrailMessagePresentation.governanceTruthLine(
                    from: object,
                    denyCode: stringValue(object["deny_code"]) ?? "",
                    policySource: stringValue(object["policy_source"]) ?? ""
                ) ?? "",
            governanceReason: stringValue(object["governance_reason"]) ?? "",
            blockedSummary: stringValue(object["blocked_summary"]) ?? "",
            repairAction: stringValue(object["repair_action"]) ?? ""
        )
    }

    private static func resolvedPolicyReason(
        _ object: [String: JSONValue]
    ) -> String {
        let policySource = stringValue(object["policy_source"]) ?? ""
        if policySource == "project_autonomy_policy",
           let runtimeSurfacePolicyReason = stringValue(object["runtime_surface_policy_reason"]) {
            return runtimeSurfacePolicyReason
        }
        return stringValue(object["policy_reason"]) ?? ""
    }

    private static func stringValue(
        _ raw: JSONValue?
    ) -> String? {
        guard let value = raw?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func numberValue(
        _ raw: JSONValue?
    ) -> Double? {
        switch raw {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }

    private static func jsonObjectValue(
        _ raw: JSONValue?
    ) -> [String: JSONValue] {
        guard case .object(let object)? = raw else {
            return [:]
        }
        return object
    }

    private static func stringArrayValue(
        _ raw: JSONValue?
    ) -> [String] {
        guard case .array(let array)? = raw else {
            return []
        }
        return array.compactMap {
            $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    private static func normalizedHubStateDirPath(
        _ raw: String
    ) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSString(string: trimmed).expandingTildeInPath
    }
}
