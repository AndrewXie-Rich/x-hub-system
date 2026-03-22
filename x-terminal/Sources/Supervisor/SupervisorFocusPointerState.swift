import Foundation

struct SupervisorFocusPointerState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_focus_pointer_state.v1"
    static let pointerTTLSeconds: TimeInterval = 2 * 60 * 60

    var schemaVersion: String
    var updatedAtMs: Int64
    var currentProjectId: String?
    var currentProjectAliases: [String]
    var currentProjectUpdatedAtMs: Int64?
    var currentPersonName: String?
    var currentPersonUpdatedAtMs: Int64?
    var currentCommitmentId: String?
    var currentCommitmentUpdatedAtMs: Int64?
    var currentTopicDigest: String?
    var lastTurnMode: SupervisorTurnMode?
    var lastSeenDeltaCursor: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case currentProjectId = "current_project_id"
        case currentProjectAliases = "current_project_aliases"
        case currentProjectUpdatedAtMs = "current_project_updated_at_ms"
        case currentPersonName = "current_person_name"
        case currentPersonUpdatedAtMs = "current_person_updated_at_ms"
        case currentCommitmentId = "current_commitment_id"
        case currentCommitmentUpdatedAtMs = "current_commitment_updated_at_ms"
        case currentTopicDigest = "current_topic_digest"
        case lastTurnMode = "last_turn_mode"
        case lastSeenDeltaCursor = "last_seen_delta_cursor"
    }

    static let empty = SupervisorFocusPointerState(
        schemaVersion: currentSchemaVersion,
        updatedAtMs: 0,
        currentProjectId: nil,
        currentProjectAliases: [],
        currentProjectUpdatedAtMs: nil,
        currentPersonName: nil,
        currentPersonUpdatedAtMs: nil,
        currentCommitmentId: nil,
        currentCommitmentUpdatedAtMs: nil,
        currentTopicDigest: nil,
        lastTurnMode: nil,
        lastSeenDeltaCursor: nil
    )

    struct ActivePointers: Equatable, Sendable {
        var currentProjectId: String?
        var currentPersonName: String?
        var currentCommitmentId: String?
        var lastTurnMode: SupervisorTurnMode?
    }

    func normalized() -> SupervisorFocusPointerState {
        let normalizedProjectId = normalizedFocusPointerScalar(currentProjectId)
        let normalizedPersonName = normalizedFocusPointerScalar(currentPersonName)
        let normalizedCommitmentId = normalizedFocusPointerScalar(currentCommitmentId)
        let normalizedProjectUpdatedAtMs = normalizedProjectId == nil ? nil : normalizedOptionalFocusPointerTime(currentProjectUpdatedAtMs)
        let normalizedPersonUpdatedAtMs = normalizedPersonName == nil ? nil : normalizedOptionalFocusPointerTime(currentPersonUpdatedAtMs)
        let normalizedCommitmentUpdatedAtMs = normalizedCommitmentId == nil ? nil : normalizedOptionalFocusPointerTime(currentCommitmentUpdatedAtMs)
        let normalizedUpdatedAtMs = max(
            max(0, updatedAtMs),
            normalizedProjectUpdatedAtMs ?? 0,
            normalizedPersonUpdatedAtMs ?? 0,
            normalizedCommitmentUpdatedAtMs ?? 0
        )
        return SupervisorFocusPointerState(
            schemaVersion: Self.currentSchemaVersion,
            updatedAtMs: normalizedUpdatedAtMs,
            currentProjectId: normalizedProjectId,
            currentProjectAliases: orderedUniqueFocusPointerScalars(currentProjectAliases),
            currentProjectUpdatedAtMs: normalizedProjectUpdatedAtMs,
            currentPersonName: normalizedPersonName,
            currentPersonUpdatedAtMs: normalizedPersonUpdatedAtMs,
            currentCommitmentId: normalizedCommitmentId,
            currentCommitmentUpdatedAtMs: normalizedCommitmentUpdatedAtMs,
            currentTopicDigest: normalizedFocusPointerTopic(currentTopicDigest),
            lastTurnMode: lastTurnMode,
            lastSeenDeltaCursor: normalizedFocusPointerScalar(lastSeenDeltaCursor)
        )
    }

    func activePointers(
        now: Date = Date(),
        ttlSeconds: TimeInterval = Self.pointerTTLSeconds
    ) -> ActivePointers {
        let normalized = normalized()
        return ActivePointers(
            currentProjectId: normalized.activeProjectId(now: now, ttlSeconds: ttlSeconds),
            currentPersonName: normalized.activePersonName(now: now, ttlSeconds: ttlSeconds),
            currentCommitmentId: normalized.activeCommitmentId(now: now, ttlSeconds: ttlSeconds),
            lastTurnMode: normalized.lastTurnMode
        )
    }

    func activeProjectId(
        now: Date = Date(),
        ttlSeconds: TimeInterval = Self.pointerTTLSeconds
    ) -> String? {
        guard isFresh(currentProjectUpdatedAtMs, now: now, ttlSeconds: ttlSeconds) else {
            return nil
        }
        return normalized().currentProjectId
    }

    func activePersonName(
        now: Date = Date(),
        ttlSeconds: TimeInterval = Self.pointerTTLSeconds
    ) -> String? {
        guard isFresh(currentPersonUpdatedAtMs, now: now, ttlSeconds: ttlSeconds) else {
            return nil
        }
        return normalized().currentPersonName
    }

    func activeCommitmentId(
        now: Date = Date(),
        ttlSeconds: TimeInterval = Self.pointerTTLSeconds
    ) -> String? {
        guard isFresh(currentCommitmentUpdatedAtMs, now: now, ttlSeconds: ttlSeconds) else {
            return nil
        }
        return normalized().currentCommitmentId
    }

    private func isFresh(
        _ updatedAtMs: Int64?,
        now: Date,
        ttlSeconds: TimeInterval
    ) -> Bool {
        guard let updatedAtMs, updatedAtMs > 0 else { return false }
        let ageSeconds = max(0, now.timeIntervalSince1970 - (Double(updatedAtMs) / 1000.0))
        return ageSeconds <= max(1, ttlSeconds)
    }
}

enum SupervisorFocusPointerUpdater {
    static func update(
        previous: SupervisorFocusPointerState,
        decision: SupervisorTurnRoutingDecision,
        userMessage: String,
        projects: [AXProjectEntry],
        personalMemory: SupervisorPersonalMemorySnapshot,
        now: Date = Date(),
        deltaCursor: String? = nil
    ) -> SupervisorFocusPointerState {
        let normalizedPrevious = previous.normalized()
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())

        var next = normalizedPrevious
        next.schemaVersion = SupervisorFocusPointerState.currentSchemaVersion
        next.updatedAtMs = max(normalizedPrevious.updatedAtMs, nowMs)
        next.lastTurnMode = decision.mode
        next.currentTopicDigest = focusTopicDigest(for: userMessage, mode: decision.mode)

        if let deltaCursor = normalizedFocusPointerScalar(deltaCursor) {
            next.lastSeenDeltaCursor = deltaCursor
        }

        if let projectId = normalizedFocusPointerScalar(decision.focusedProjectId) {
            next.currentProjectId = projectId
            next.currentProjectAliases = focusProjectAliases(
                projectId: projectId,
                decision: decision,
                projects: projects
            )
            next.currentProjectUpdatedAtMs = nowMs
        }

        if let personName = normalizedFocusPointerScalar(decision.focusedPersonName) {
            next.currentPersonName = personName
            next.currentPersonUpdatedAtMs = nowMs
        }

        if let commitmentId = normalizedFocusPointerScalar(decision.focusedCommitmentId),
           personalMemory.item(for: commitmentId)?.isActiveLike == true {
            next.currentCommitmentId = commitmentId
            next.currentCommitmentUpdatedAtMs = nowMs
        }

        return next.normalized()
    }

    private static func focusProjectAliases(
        projectId: String,
        decision: SupervisorTurnRoutingDecision,
        projects: [AXProjectEntry]
    ) -> [String] {
        if let project = projects.first(where: { $0.projectId == projectId }) {
            return orderedUniqueFocusPointerScalars([
                project.displayName,
                project.projectId
            ])
        }
        return orderedUniqueFocusPointerScalars([
            decision.focusedProjectName ?? "",
            projectId
        ])
    }

    private static func focusTopicDigest(
        for userMessage: String,
        mode: SupervisorTurnMode
    ) -> String? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let singleLine = trimmed
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
            .joined(separator: " ")
        return normalizedFocusPointerTopic("\(mode.rawValue): \(singleLine)")
    }
}

private func normalizedFocusPointerScalar(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedOptionalFocusPointerTime(_ value: Int64?) -> Int64? {
    guard let value, value > 0 else { return nil }
    return value
}

private func normalizedFocusPointerTopic(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value
        .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(160))
}

private func orderedUniqueFocusPointerScalars(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values {
        guard let normalized = normalizedFocusPointerScalar(value) else { continue }
        let key = normalized.lowercased()
        guard seen.insert(key).inserted else { continue }
        output.append(normalized)
    }
    return output
}
