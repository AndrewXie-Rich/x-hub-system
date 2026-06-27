import AppKit
import Foundation
import RELFlowHubCore

func compactNotificationBody(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return HubUIStrings.Notifications.Summary.noExtraDetail }
    let collapsed = trimmed
        .replacingOccurrences(of: "\n\n", with: "\n")
        .replacingOccurrences(of: "\n", with: "  ")
    if collapsed.count <= 160 {
        return collapsed
    }
    return String(collapsed.prefix(157)) + "..."
}

struct HubNotificationFATrackerSummary {
    var subline: String
    var detailFacts: [HubNotificationFact]
}

struct HubNotificationFATrackerPayload {
    var projectName: String?
    var projectId: Int?
    var radarIds: [Int]
    var radarTitles: [Int: String]
}

func hubNotificationBodyFacts(_ notification: HubNotification) -> [HubNotificationFact] {
    var facts: [HubNotificationFact] = []
    let source = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)

    if let count = hubNotificationUnreadCount(notification),
       ["mail", "messages", "slack"].contains(source.lowercased()) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.unread, value: "\(count)"))
    }

    if let appName = hubNotificationOpenedBundleName(notification) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.app, value: appName))
    } else if hubNotificationOpensLocalApp(notification) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.app, value: hubNotificationLocalAppName(notification)))
    }

    if title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) || body.contains(HubUIStrings.Notifications.MissingContext.bodyMarker) {
        if let projectName = hubNotificationMissingContextProjectName(notification) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.project, value: projectName))
        }
        if let question = hubNotificationMissingContextQuestion(body) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.missingContext, value: question))
        }
        if let gap = hubNotificationMissingContextGap(body) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.currentGap, value: gap))
        }
        if let suggestion = hubNotificationReplySuggestion(notification) {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.suggestedReply, value: suggestion))
        }
        return hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
    }

    let structuredFacts = hubNotificationStructuredFacts(from: body)
    if hubNotificationUsesTerminalDeepLink(notification),
       let incidentFacts = hubNotificationLaneIncidentFacts(
           title: title,
           body: body,
           structuredFacts: structuredFacts
       ) {
        facts.append(contentsOf: incidentFacts)
        return hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
    }

    facts.append(contentsOf: structuredFacts)

    if facts.isEmpty, !body.isEmpty {
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count == 1 {
            facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.detail, value: compactNotificationBody(body)))
        } else {
            for (index, line) in lines.prefix(4).enumerated() {
                facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.detail(index + 1), value: compactNotificationBody(line)))
            }
        }
    }

    return hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
}

func hubNotificationFriendlySubline(
    _ notification: HubNotification,
    facts: [HubNotificationFact],
    fallback: String? = nil
) -> String {
    let source = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)

    if let count = hubNotificationUnreadCount(notification) {
        switch source.lowercased() {
        case "mail":
            return HubUIStrings.Notifications.Unread.mail(count)
        case "messages":
            return HubUIStrings.Notifications.Unread.messages(count)
        case "slack":
            return HubUIStrings.Notifications.Unread.slack(count)
        default:
            break
        }
    }

    if title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) || body.contains(HubUIStrings.Notifications.MissingContext.bodyMarker) {
        if let question = hubNotificationMissingContextQuestion(body) {
            return HubUIStrings.Notifications.MissingContext.subline(question)
        }
    }

    if title.contains(HubUIStrings.Notifications.Presentation.Terminal.heartbeatKeyword) {
        let factMap = hubNotificationFactMap(facts)
        let reason = factMap[HubUIStrings.Notifications.Facts.reason] ?? factMap["Reason"]
        let blocked = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.blockedProjects] ?? factMap["Blocked Projects"])
        let queue = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.queuedProjects] ?? factMap["Queued Projects"])
        let pendingGrant = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.pendingGrants] ?? factMap["Pending Grants"])
        let repair = hubNotificationIntFact(factMap[HubUIStrings.Notifications.Facts.governanceRepairs] ?? factMap["Governance Repairs"])

        var parts: [String] = []
        if let reason, !reason.isEmpty {
            parts.append(reason)
        }
        if let blocked {
            parts.append(HubUIStrings.Notifications.Lane.blockedProjects(blocked))
        }
        if let queue, queue > 0 {
            parts.append(HubUIStrings.Notifications.Lane.queuedProjects(queue))
        }
        if let pendingGrant, pendingGrant > 0 {
            parts.append(HubUIStrings.Notifications.Lane.pendingGrants(pendingGrant))
        }
        if let repair, repair > 0 {
            parts.append(HubUIStrings.Notifications.Lane.governanceRepairs(repair))
        }
        if !parts.isEmpty {
            return HubUIStrings.Notifications.Lane.summary(parts)
        }
    }

    if hubNotificationUsesTerminalDeepLink(notification),
       let incidentSummary = hubNotificationLaneIncidentSummary(title: title, facts: facts) {
        return incidentSummary
    }

    if let primaryFact = hubNotificationPrimaryFactSummary(facts) {
        return primaryFact
    }

    if hubNotificationSourceIsTerminal(notification)
        && hubNotificationLooksLikeMachineReadableBody(body) {
        return fallback ?? HubUIStrings.Notifications.Presentation.Terminal.genericFallback
    }

    if !body.isEmpty {
        return compactNotificationBody(body)
    }

    return fallback ?? HubUIStrings.Notifications.Summary.noExtraDetail
}

func hubNotificationShouldOfferSummaryCopy(_ notification: HubNotification) -> Bool {
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = notification.body.trimmingCharacters(in: .whitespacesAndNewlines)

    if title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) || body.contains(HubUIStrings.Notifications.MissingContext.bodyMarker) {
        return false
    }

    guard hubNotificationSourceIsTerminal(notification) || hubNotificationUsesTerminalDeepLink(notification) else {
        return false
    }

    if title.contains(HubUIStrings.Notifications.Presentation.Terminal.silentKeyword)
        || title.contains(HubUIStrings.Notifications.Presentation.Terminal.heartbeatKeyword) {
        return false
    }

    let facts = hubNotificationBodyFacts(notification)
    if hubNotificationLaneIncidentSummary(title: title, facts: facts) != nil {
        return true
    }

    return false
}

func hubNotificationLocalAppName(_ notification: HubNotification) -> String {
    if let actionURL = notification.actionURL,
       let url = URL(string: actionURL),
       (url.scheme ?? "").lowercased() == "rdar" {
        return HubUIStrings.Notifications.Source.radar
    }

    if let openedBundleName = hubNotificationOpenedBundleName(notification) {
        return openedBundleName
    }

    let source = notification.source.trimmingCharacters(in: .whitespacesAndNewlines)
    if !source.isEmpty {
        return source
    }

    return HubUIStrings.Notifications.Source.genericApp
}

func hubNotificationLocalAppPrimaryLabel(_ notification: HubNotification) -> String {
    "\(HubUIStrings.Notifications.Presentation.Generic.open)\(hubNotificationLocalAppName(notification))"
}

func hubNotificationFATrackerSummary(_ notification: HubNotification) -> HubNotificationFATrackerSummary {
    let payload = hubNotificationParseFATrackerPayload(notification)
    let projectName = payload.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectLabel = (projectName?.isEmpty == false) ? projectName! : HubUIStrings.Notifications.FATracker.defaultProjectLabel
    let radarCount = payload.radarIds.count

    let subline: String
    if radarCount == 0 {
        subline = HubUIStrings.Notifications.FATracker.openInProject(projectLabel)
    } else if radarCount == 1, let radarId = payload.radarIds.first {
        if let title = payload.radarTitles[radarId], !title.isEmpty {
            subline = HubUIStrings.Notifications.FATracker.radarTitleLine(projectLabel: projectLabel, radarId: radarId, title: title)
        } else {
            subline = HubUIStrings.Notifications.FATracker.singleRadarLine(projectLabel)
        }
    } else {
        subline = HubUIStrings.Notifications.FATracker.radarCountLine(projectLabel: projectLabel, count: radarCount)
    }

    var detailFacts: [HubNotificationFact] = []
    if let projectName, !projectName.isEmpty {
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.project, value: projectName))
    }
    if !payload.radarIds.isEmpty {
        let preview = HubUIStrings.Formatting.commaSeparated(payload.radarIds.prefix(8).map(String.init))
        let suffix = payload.radarIds.count > 8 ? HubUIStrings.Notifications.FATracker.additionalRadar(payload.radarIds.count - 8) : ""
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.radarList, value: preview + suffix))
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.count, value: String(payload.radarIds.count)))
    }

    for (radarId, radarTitle) in payload.radarTitles
        .sorted(by: { $0.key < $1.key })
        .prefix(3) {
        detailFacts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.radar(radarId), value: radarTitle))
    }

    if detailFacts.isEmpty {
        detailFacts = hubNotificationBodyFacts(notification)
    }

    return HubNotificationFATrackerSummary(
        subline: subline,
        detailFacts: hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(detailFacts))
    )
}

func hubNotificationUnreadCount(_ notification: HubNotification) -> Int? {
    hubNotificationFirstInteger(in: notification.body) ?? hubNotificationFirstInteger(in: notification.title)
}

func hubNotificationFirstInteger(in text: String) -> Int? {
    var digits = ""
    for character in text {
        if character.isNumber {
            digits.append(character)
        } else if !digits.isEmpty {
            break
        }
    }
    return digits.isEmpty ? nil : Int(digits)
}

func hubNotificationStructuredFacts(from body: String) -> [HubNotificationFact] {
    let lines = body
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard !lines.isEmpty else { return [] }

    var facts: [HubNotificationFact] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        defer { index += 1 }

        guard !line.isEmpty else { continue }

        if let fact = hubNotificationInlineFact(from: line) {
            facts.append(fact)
            continue
        }

        guard hubNotificationLooksLikeStandaloneLabel(line) else { continue }
        let label = hubNotificationDisplayLabel(String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines))
        guard !label.isEmpty else { continue }

        var values: [String] = []
        var scanIndex = index + 1
        while scanIndex < lines.count {
            let candidate = lines[scanIndex]
            if candidate.isEmpty {
                if !values.isEmpty { break }
                scanIndex += 1
                continue
            }
            if hubNotificationInlineFact(from: candidate) != nil || hubNotificationLooksLikeStandaloneLabel(candidate) {
                break
            }
            values.append(candidate)
            scanIndex += 1
            if values.count >= 2 { break }
        }

        if !values.isEmpty {
            facts.append(HubNotificationFact(label: label, value: compactNotificationBody(values.joined(separator: " "))))
            index = max(index, scanIndex - 1)
        }
    }

    return hubNotificationDedupedFacts(facts)
}

func hubNotificationInlineFact(from line: String) -> HubNotificationFact? {
    let separators: [Character] = ["：", ":", "="]
    guard let separatorIndex = line.firstIndex(where: { separators.contains($0) }) else {
        return nil
    }

    let rawLabel = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    let label = hubNotificationDisplayLabel(String(rawLabel))
    let valueStart = line.index(after: separatorIndex)
    let rawValue = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
    let value = hubNotificationDisplayValue(rawLabel: String(rawLabel), rawValue: String(rawValue))

    guard !label.isEmpty, !value.isEmpty else { return nil }
    guard label.count <= 40 else { return nil }

    return HubNotificationFact(label: label, value: compactNotificationBody(value))
}

func hubNotificationLooksLikeStandaloneLabel(_ line: String) -> Bool {
    guard let last = line.last else { return false }
    guard last == "：" || last == ":" else { return false }
    let label = String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    return !label.isEmpty && label.count <= 40
}

func hubNotificationDisplayLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let mapped: [String: String] = [
        "time": HubUIStrings.Notifications.Facts.time,
        "reason": HubUIStrings.Notifications.Facts.reason,
        "project_count": HubUIStrings.Notifications.Facts.projectCount,
        "blocked_projects": HubUIStrings.Notifications.Facts.blockedProjects,
        "queued_projects": HubUIStrings.Notifications.Facts.queuedProjects,
        "pending_grants": HubUIStrings.Notifications.Facts.pendingGrants,
        "governance_repairs": HubUIStrings.Notifications.Facts.governanceRepairs,
        "device_id": HubUIStrings.Notifications.Facts.deviceID,
        "project_id": HubUIStrings.Notifications.Facts.projectID,
        "capability": HubUIStrings.Notifications.Facts.capability,
        "required_capability": HubUIStrings.Notifications.Facts.capability,
        "grant_capability": HubUIStrings.Notifications.Facts.capability,
        "radars": HubUIStrings.Notifications.Facts.radarList,
        "bundle_id": HubUIStrings.Notifications.Facts.bundleID,
        "lane": HubUIStrings.Notifications.Facts.lane,
        "action": HubUIStrings.Notifications.Facts.action,
        "deny": HubUIStrings.Notifications.Facts.denyReason,
        "latency": HubUIStrings.Notifications.Facts.latency,
        "audit": HubUIStrings.Notifications.Facts.audit,
    ]

    let normalized = hubNotificationSemanticLabel(trimmed)

    if let mapped = mapped[normalized] {
        return mapped
    }

    return trimmed
}

func hubNotificationDisplayValue(rawLabel: String, rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let normalizedLabel = hubNotificationSemanticLabel(rawLabel)

    switch normalizedLabel {
    case "action":
        switch trimmed.lowercased() {
        case "notify_user":
            return HubUIStrings.Notifications.Lane.continueInSupervisor
        case "open_hub_grants":
            return HubUIStrings.Notifications.Lane.openHubGrants
        case "open_grant_pending_board":
            return HubUIStrings.Notifications.Lane.viewGrantPendingBoard
        case "replan_next_safe_point":
            return HubUIStrings.Notifications.Lane.replanNextSafePoint
        case "stop_immediately":
            return HubUIStrings.Notifications.Lane.stopImmediately
        default:
            return trimmed
        }
    case "deny", "reason":
        if let mapped = hubNotificationHumanizedReasonCode(trimmed) {
            return mapped
        }
        if trimmed.lowercased().hasPrefix("event") {
            return HubUIStrings.Notifications.Lane.backgroundEvent
        }
        return trimmed
    case "capability":
        return hubNotificationHumanizedCapabilityCode(trimmed) ?? trimmed
    case "latency":
        return trimmed == "-1ms" ? HubUIStrings.Notifications.Lane.notRecorded : trimmed
    default:
        if normalizedLabel.hasSuffix("reason"),
           let mapped = hubNotificationHumanizedReasonCode(trimmed) {
            return mapped
        }
        return trimmed
    }
}

func hubNotificationSemanticLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    let normalized = trimmed
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")

    let aliases: [String: String] = [
        HubUIStrings.Notifications.Facts.time: "time",
        HubUIStrings.Notifications.Facts.reason: "reason",
        HubUIStrings.Notifications.Facts.projectCount: "project_count",
        HubUIStrings.Notifications.Facts.blockedProjects: "blocked_projects",
        HubUIStrings.Notifications.Facts.queuedProjects: "queued_projects",
        HubUIStrings.Notifications.Facts.pendingGrants: "pending_grants",
        HubUIStrings.Notifications.Facts.governanceRepairs: "governance_repairs",
        HubUIStrings.Notifications.Facts.deviceID: "device_id",
        HubUIStrings.Notifications.Facts.projectID: "project_id",
        HubUIStrings.Notifications.Facts.projectIDLegacyAlias: "project_id",
        HubUIStrings.Notifications.Facts.capability: "capability",
        HubUIStrings.Notifications.Facts.lane: "lane",
        HubUIStrings.Notifications.Facts.action: "action",
        HubUIStrings.Notifications.Facts.suggestedAction: "action",
        HubUIStrings.Notifications.Facts.denyReason: "deny",
        HubUIStrings.Notifications.Facts.latency: "latency",
        HubUIStrings.Notifications.Facts.audit: "audit",
        "capability": "capability",
        "required_capability": "capability",
        "grant_capability": "capability",
    ]

    return aliases[trimmed] ?? normalized
}

func hubNotificationMissingContextQuestion(_ body: String) -> String? {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let range = trimmed.range(of: HubUIStrings.Notifications.MissingContext.bodyLead) {
        let candidate = String(trimmed[range.upperBound...])
        let stopTokens = [" \(HubUIStrings.Notifications.MissingContext.currentGapMarker)", HubUIStrings.Notifications.MissingContext.directSayStop, "。"]
        return hubNotificationPrefix(beforeAnyOf: stopTokens, in: candidate)
    }

    return hubNotificationPrefix(beforeAnyOf: [" \(HubUIStrings.Notifications.MissingContext.currentGapMarker)", HubUIStrings.Notifications.MissingContext.directSayStop], in: trimmed)
}

func hubNotificationMissingContextProjectName(_ notification: HubNotification) -> String? {
    let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard title.hasPrefix(HubUIStrings.Notifications.MissingContext.titlePrefix) else { return nil }
    let projectName = String(title.dropFirst(HubUIStrings.Notifications.MissingContext.titlePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return projectName.isEmpty ? nil : projectName
}

func hubNotificationMissingContextGap(_ body: String) -> String? {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let range = trimmed.range(of: HubUIStrings.Notifications.MissingContext.currentGapMarker) else { return nil }
    let candidate = String(trimmed[range.upperBound...])
    return hubNotificationPrefix(beforeAnyOf: [HubUIStrings.Notifications.MissingContext.directSayStop, HubUIStrings.Notifications.MissingContext.enoughSuffix], in: candidate)
}

func hubNotificationMissingContextDisplayTitle(_ notification: HubNotification) -> String {
    HubUIStrings.Notifications.MissingContext.displayTitle(projectName: hubNotificationMissingContextProjectName(notification))
}

func hubNotificationLaneIncidentFacts(
    title: String,
    body: String,
    structuredFacts: [HubNotificationFact]
) -> [HubNotificationFact]? {
    guard title.contains(HubUIStrings.Notifications.Lane.titleMarker) || body.contains("action=") || body.contains("deny=") else {
        return nil
    }

    let factMap = hubNotificationFactMap(structuredFacts)
    var facts: [HubNotificationFact] = []

    if let incident = hubNotificationTerminalIncidentCode(from: title),
       let mapped = hubNotificationHumanizedReasonCode(incident) {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.issueType, value: mapped))
    }
    if let capability = factMap[HubUIStrings.Notifications.Facts.capability], !capability.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.capability, value: capability))
    }
    if let deviceID = factMap[HubUIStrings.Notifications.Facts.deviceID], !deviceID.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.deviceID, value: deviceID))
    }
    if let deny = factMap[HubUIStrings.Notifications.Facts.denyReason], !deny.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.denyReason, value: deny))
    }
    if let action = factMap[HubUIStrings.Notifications.Facts.action], !action.isEmpty {
        facts.append(HubNotificationFact(label: HubUIStrings.Notifications.Facts.suggestedAction, value: action))
    }

    return facts.isEmpty ? nil : hubNotificationUserVisibleFacts(hubNotificationDedupedFacts(facts))
}

func hubNotificationUserVisibleFacts(_ facts: [HubNotificationFact]) -> [HubNotificationFact] {
    let hiddenLabels: Set<String> = [
        HubUIStrings.Notifications.Facts.audit,
        HubUIStrings.Notifications.Facts.lane,
        HubUIStrings.Notifications.Facts.latency,
        HubUIStrings.Notifications.Facts.projectID,
        HubUIStrings.Notifications.Facts.bundleID,
    ]

    return hubNotificationDedupedFacts(
        facts.filter { fact in
            let label = fact.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return !label.isEmpty
                && !hiddenLabels.contains(label)
                && !hubNotificationFactLabelLooksMachineGenerated(label)
        }
    )
}

func hubNotificationFactLabelLooksMachineGenerated(_ label: String) -> Bool {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return trimmed.range(of: #"^[a-z0-9_./-]+$"#, options: .regularExpression) != nil
}

func hubNotificationLooksLikeMachineReadableBody(_ body: String) -> Bool {
    let lines = body
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !lines.isEmpty else { return false }

    let machineReadableLines = lines.filter { line in
        line.contains("=") || line.range(of: #"^[a-z0-9_./-]+:[^\s].*$"#, options: .regularExpression) != nil
    }

    return machineReadableLines.count == lines.count
}

func hubNotificationLaneIncidentSummary(title: String, facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)
    let incidentLabel = incidentCode.flatMap(hubNotificationHumanizedReasonCode)
    let action = factMap[HubUIStrings.Notifications.Facts.suggestedAction] ?? factMap[HubUIStrings.Notifications.Facts.action]
    let capability = hubNotificationGrantPendingCapabilityName(facts)

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingSummary(
            hubNotificationLaneCount(from: title),
            capability: capability
        )
    }

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionSummary
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorSummary
    }

    if let incidentLabel {
        return HubUIStrings.Notifications.Lane.incidentSummary(incidentLabel: incidentLabel, action: action)
    }
    if let action, !action.isEmpty {
        return HubUIStrings.Notifications.Lane.actionOnlySummary(action)
    }
    return nil
}

func hubNotificationLaneIncidentDisplayTitle(title: String, facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)
    let capability = hubNotificationGrantPendingCapabilityName(facts)

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingDisplayTitle(
            hubNotificationLaneCount(from: title),
            capability: capability
        )
    }

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionDisplayTitle
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorDisplayTitle
    }

    if let incidentLabel = incidentCode.flatMap(hubNotificationHumanizedReasonCode) {
        return HubUIStrings.Notifications.Lane.incidentDisplayTitle(incidentLabel)
    }

    return nil
}

func hubNotificationLaneIncidentNextStep(title: String, facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)
    let action = factMap[HubUIStrings.Notifications.Facts.suggestedAction] ?? factMap[HubUIStrings.Notifications.Facts.action]
    let capability = hubNotificationGrantPendingCapabilityName(facts)

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingNextStep(capability)
    }

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionNextStep
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorNextStep
    }

    if let action, !action.isEmpty {
        return HubUIStrings.Notifications.Lane.actionNextStep(action)
    }

    return nil
}

func hubNotificationLaneIncidentPrimaryLabel(title: String, facts: [HubNotificationFact]) -> String {
    let factMap = hubNotificationFactMap(facts)
    let incidentCode = hubNotificationTerminalIncidentCode(from: title)

    if incidentCode == "awaiting_instruction" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingNextInstruction {
        return HubUIStrings.Notifications.Lane.awaitingInstructionPrimaryLabel
    }

    if incidentCode == "runtime_error" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.runtimeError {
        return HubUIStrings.Notifications.Lane.runtimeErrorPrimaryLabel
    }

    if incidentCode == "grant_pending" || factMap[HubUIStrings.Notifications.Facts.denyReason] == HubUIStrings.Notifications.Lane.waitingGrant {
        return HubUIStrings.Notifications.Lane.grantPendingPrimaryLabel
    }

    return HubUIStrings.Notifications.Lane.genericPrimaryLabel
}

func hubNotificationTerminalIncidentCode(from title: String) -> String? {
    guard let marker = title.lastIndex(of: "：") ?? title.lastIndex(of: ":") else { return nil }
    let code = title[title.index(after: marker)...].trimmingCharacters(in: .whitespacesAndNewlines)
    return code.isEmpty ? nil : String(code)
}

func hubNotificationLaneCount(from title: String) -> Int? {
    guard title.contains("Lane") else { return nil }
    return hubNotificationFirstInteger(in: title)
}

func hubNotificationHumanizedReasonCode(_ raw: String) -> String? {
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    guard !normalized.isEmpty else { return nil }

    switch normalized {
    case "grant_pending":
        return HubUIStrings.Notifications.Lane.waitingGrant
    case "grant_pending_connector_side_effect":
        return HubUIStrings.Notifications.Lane.waitingConnectorSideEffectGrant
    case "awaiting_instruction":
        return HubUIStrings.Notifications.Lane.waitingNextInstruction
    case "runtime_error":
        return HubUIStrings.Notifications.Lane.runtimeError
    case "allocation_blocked":
        return HubUIStrings.Notifications.Lane.allocationBlocked
    case "permission_denied":
        return HubUIStrings.Notifications.Lane.permissionDenied
    case "event", "event...", "event_update":
        return HubUIStrings.Notifications.Lane.backgroundEvent
    default:
        if normalized.hasPrefix("connector_event/") {
            let suffix = normalized.dropFirst("connector_event/".count)
            return HubUIStrings.Notifications.Lane.connectorEvent(String(suffix))
        }
        return nil
    }
}

func hubNotificationHumanizedCapabilityCode(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let normalized: String = {
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("capability_") {
            return String(lowered.dropFirst("capability_".count))
        }
        return lowered
    }()

    switch normalized {
    case "web.fetch", "web_fetch":
        return HubUIStrings.MainPanel.PairingScope.webFetch
    case "ai.generate.paid", "ai_generate_paid":
        return HubUIStrings.MainPanel.PairingScope.paidAI
    case "ai.generate.local", "ai_generate_local":
        return HubUIStrings.MainPanel.PairingScope.localAI
    default:
        return nil
    }
}

func hubNotificationGrantPendingCapabilityName(_ facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let capability = factMap[HubUIStrings.Notifications.Facts.capability]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return capability.isEmpty ? nil : capability
}

func hubNotificationGrantPendingDeviceID(_ facts: [HubNotificationFact]) -> String? {
    let factMap = hubNotificationFactMap(facts)
    let deviceID = factMap[HubUIStrings.Notifications.Facts.deviceID]?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return deviceID.isEmpty ? nil : deviceID
}

func hubNotificationFATrackerDisplayTitle(_ notification: HubNotification) -> String {
    let payload = hubNotificationParseFATrackerPayload(notification)
    let projectName = payload.projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectLabel = (projectName?.isEmpty == false) ? projectName! : HubUIStrings.Notifications.FATracker.defaultProjectLabel
    let count = payload.radarIds.count

    if count <= 0 {
        return HubUIStrings.Notifications.FATracker.displayTitleNoRadar(projectLabel)
    }
    if count == 1 {
        return HubUIStrings.Notifications.FATracker.displayTitleOneRadar(projectLabel)
    }
    return HubUIStrings.Notifications.FATracker.displayTitleManyRadar(projectLabel, count: count)
}

func hubNotificationPrefix(beforeAnyOf tokens: [String], in text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let endIndex = tokens.compactMap { token in
        trimmed.range(of: token).map(\.lowerBound)
    }.min() ?? trimmed.endIndex

    let result = trimmed[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : String(result)
}

func hubNotificationPrimaryFactSummary(_ facts: [HubNotificationFact]) -> String? {
    let summaryFacts = facts.filter { fact in
        let label = fact.label.lowercased()
        return label != "detail"
            && label != HubUIStrings.Notifications.Facts.detail
            && !label.hasPrefix("detail ")
            && !label.hasPrefix(HubUIStrings.Notifications.Facts.detail.lowercased() + " ")
            && label != HubUIStrings.Notifications.Facts.lane.lowercased()
            && label != HubUIStrings.Notifications.Facts.latency.lowercased()
            && label != HubUIStrings.Notifications.Facts.audit.lowercased()
    }

    let chosen = summaryFacts.isEmpty ? facts.prefix(2) : summaryFacts.prefix(2)
    let parts = chosen.compactMap { fact -> String? in
        let label = fact.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = fact.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if label.isEmpty
            || label == "Detail"
            || label == HubUIStrings.Notifications.Facts.detail
            || label.hasPrefix("Detail ")
            || label.hasPrefix(HubUIStrings.Notifications.Facts.detail + " ") {
            return value
        }
        return HubUIStrings.Notifications.Facts.labelValue(label, value: value)
    }

    guard !parts.isEmpty else { return nil }
    return HubUIStrings.Notifications.Lane.summary(parts)
}

func hubNotificationFactMap(_ facts: [HubNotificationFact]) -> [String: String] {
    var map: [String: String] = [:]
    for fact in facts {
        map[fact.label] = fact.value
    }
    return map
}

func hubNotificationIntFact(_ text: String?) -> Int? {
    guard let text else { return nil }
    return hubNotificationFirstInteger(in: text)
}

func hubNotificationDedupedFacts(_ facts: [HubNotificationFact]) -> [HubNotificationFact] {
    var seen: Set<String> = []
    var deduped: [HubNotificationFact] = []
    for fact in facts {
        let label = fact.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = fact.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { continue }
        let key = "\(label)|\(value)"
        guard seen.insert(key).inserted else { continue }
        deduped.append(HubNotificationFact(label: label, value: value))
    }
    return deduped
}

func hubNotificationOpenedBundleName(_ notification: HubNotification) -> String? {
    guard let actionURL = notification.actionURL,
          let url = URL(string: actionURL),
          (url.scheme ?? "").lowercased() == "relflowhub",
          (url.host ?? "").lowercased() == "openapp" else {
        return nil
    }

    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let bundleID = (items.first(where: { $0.name == "bundle_id" })?.value ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bundleID.isEmpty else { return nil }

    if let knownName = HubUIStrings.Notifications.Source.bundleDisplayName(bundleID) {
        return knownName
    }

    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
       let bundle = Bundle(url: appURL),
       let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
       !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return appName
    }

    let suffix = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    return suffix.isEmpty ? nil : suffix
}

func hubNotificationParseFATrackerPayload(_ notification: HubNotification) -> HubNotificationFATrackerPayload {
    guard notification.source == "FAtracker" else {
        return HubNotificationFATrackerPayload(projectName: nil, projectId: nil, radarIds: [], radarTitles: [:])
    }

    let lines = notification.body
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)

    let projectName = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    var projectId: Int?
    var radarIds: [Int] = []

    if let actionURL = notification.actionURL,
       let url = URL(string: actionURL),
       (url.scheme ?? "").lowercased() == "relflowhub" {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        projectId = Int(items.first(where: { $0.name == "project_id" })?.value ?? "")
        radarIds = (items.first(where: { $0.name == "radars" })?.value ?? "")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    if radarIds.isEmpty, lines.count >= 2 {
        radarIds = lines[1]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    var radarTitles: [Int: String] = [:]
    if lines.count >= 3 {
        for line in lines.dropFirst(2) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let dashRange = trimmed.range(of: " - ") else { continue }
            let idText = trimmed[..<dashRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed[dashRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let radarId = Int(idText), !title.isEmpty {
                radarTitles[radarId] = String(title)
            }
        }
    }

    return HubNotificationFATrackerPayload(
        projectName: projectName,
        projectId: projectId,
        radarIds: radarIds,
        radarTitles: radarTitles
    )
}
