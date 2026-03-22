import Foundation

struct SupervisorBackgroundPreferenceDomain: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    static let techStack = SupervisorBackgroundPreferenceDomain(rawValue: "tech_stack")
    static let uxStyle = SupervisorBackgroundPreferenceDomain(rawValue: "ux_style")

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = SupervisorBackgroundPreferenceDomain.normalize(rawValue)
    }

    init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func normalize(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let pieces = trimmed.split(separator: "_").map(String.init).filter { !$0.isEmpty }
        return pieces.joined(separator: "_")
    }
}

enum SupervisorBackgroundPreferenceStrength: String, Codable, Sendable {
    case weak
    case medium
    case strong

    var rank: Int {
        switch self {
        case .strong:
            return 3
        case .medium:
            return 2
        case .weak:
            return 1
        }
    }
}

enum SupervisorBackgroundPreferenceTrackMergeError: Error, Equatable {
    case schemaVersionMismatch
    case noteIdentityMismatch
}

struct SupervisorBackgroundPreferenceNote: Identifiable, Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_background_preference_note.v1"

    var schemaVersion: String
    var noteId: String
    var projectId: String
    var domain: SupervisorBackgroundPreferenceDomain
    var strength: SupervisorBackgroundPreferenceStrength
    var statement: String
    var mustNotPromoteWithoutDecision: Bool
    var createdAtMs: Int64

    var id: String { noteId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case noteId = "note_id"
        case projectId = "project_id"
        case domain
        case strength
        case statement
        case mustNotPromoteWithoutDecision = "must_not_promote_without_decision"
        case createdAtMs = "created_at_ms"
    }

    var sanitizedForStorage: SupervisorBackgroundPreferenceNote {
        SupervisorBackgroundPreferenceNote(
            schemaVersion: Self.schemaVersion,
            noteId: normalizedBackgroundToken(noteId),
            projectId: normalizedBackgroundToken(projectId),
            domain: domain,
            strength: strength,
            statement: normalizedBackgroundScalar(statement),
            mustNotPromoteWithoutDecision: mustNotPromoteWithoutDecision,
            createdAtMs: max(0, createdAtMs)
        )
    }

    func merged(with incoming: SupervisorBackgroundPreferenceNote) throws -> SupervisorBackgroundPreferenceNote {
        guard schemaVersion == Self.schemaVersion, incoming.schemaVersion == Self.schemaVersion else {
            throw SupervisorBackgroundPreferenceTrackMergeError.schemaVersionMismatch
        }

        let base = sanitizedForStorage
        let other = incoming.sanitizedForStorage
        guard base.noteId == other.noteId,
              base.projectId == other.projectId,
              base.domain == other.domain else {
            throw SupervisorBackgroundPreferenceTrackMergeError.noteIdentityMismatch
        }

        let incomingWins = other.createdAtMs >= base.createdAtMs
        let primary = incomingWins ? other : base
        let secondary = incomingWins ? base : other

        return SupervisorBackgroundPreferenceNote(
            schemaVersion: Self.schemaVersion,
            noteId: base.noteId,
            projectId: base.projectId,
            domain: base.domain,
            strength: preferredStrength(primary.strength, secondary.strength, incomingWins: incomingWins),
            statement: preferredBackgroundScalar(primary.statement, secondary.statement),
            mustNotPromoteWithoutDecision: base.mustNotPromoteWithoutDecision || other.mustNotPromoteWithoutDecision,
            createdAtMs: max(base.createdAtMs, other.createdAtMs)
        )
    }
}

struct SupervisorBackgroundPreferenceTrackSnapshot: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_background_preference_track.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var notes: [SupervisorBackgroundPreferenceNote]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case notes
    }
}

enum SupervisorBackgroundPreferenceTrack {
    static func merged(
        existing: [SupervisorBackgroundPreferenceNote],
        incoming: [SupervisorBackgroundPreferenceNote]
    ) throws -> [SupervisorBackgroundPreferenceNote] {
        var mergedByID: [String: SupervisorBackgroundPreferenceNote] = [:]

        for note in existing + incoming {
            let normalized = note.sanitizedForStorage
            guard !normalized.noteId.isEmpty else { continue }
            if let current = mergedByID[normalized.noteId] {
                mergedByID[normalized.noteId] = try current.merged(with: normalized)
            } else {
                mergedByID[normalized.noteId] = normalized
            }
        }

        return mergedByID.values.sorted(by: backgroundNoteSort)
    }

    static func preferredBackgroundNotes(
        from notes: [SupervisorBackgroundPreferenceNote]
    ) -> [SupervisorBackgroundPreferenceDomain: SupervisorBackgroundPreferenceNote] {
        var selected: [SupervisorBackgroundPreferenceDomain: SupervisorBackgroundPreferenceNote] = [:]

        for note in notes.map(\.sanitizedForStorage).sorted(by: backgroundNotePreferenceSort) {
            if selected[note.domain] == nil {
                selected[note.domain] = note
            }
        }

        return selected
    }
}

struct SupervisorDecisionRailResolution: Equatable, Codable, Sendable {
    var domain: SupervisorBackgroundPreferenceDomain
    var hardDecision: SupervisorDecisionTrackEvent?
    var preferredBackgroundNote: SupervisorBackgroundPreferenceNote?
    var shadowedBackgroundNotes: [SupervisorBackgroundPreferenceNote]

    var effectiveStatement: String? {
        hardDecision?.statement ?? preferredBackgroundNote?.statement
    }

    var usesDecisionTrack: Bool {
        hardDecision != nil
    }
}

struct SupervisorProjectDecisionRails: Equatable, Codable, Sendable {
    var projectId: String
    var decisionTrack: [SupervisorDecisionTrackEvent]
    var backgroundPreferenceTrack: [SupervisorBackgroundPreferenceNote]
    var resolutions: [SupervisorDecisionRailResolution]

    func hardDecision(for category: SupervisorDecisionCategory) -> SupervisorDecisionTrackEvent? {
        resolutions.first { $0.domain.rawValue == category.rawValue }?.hardDecision
    }

    func resolution(for domain: SupervisorBackgroundPreferenceDomain) -> SupervisorDecisionRailResolution? {
        resolutions.first { $0.domain == domain }
    }
}

enum SupervisorDecisionRailResolver {
    static func resolve(
        projectId: String,
        decisions: [SupervisorDecisionTrackEvent],
        backgroundNotes: [SupervisorBackgroundPreferenceNote]
    ) -> SupervisorProjectDecisionRails {
        let hardDecisions = SupervisorDecisionTrack.hardConstraints(from: decisions)
        let sortedBackgroundNotes = backgroundNotes.map(\.sanitizedForStorage).sorted(by: backgroundNotePreferenceSort)
        let preferredBackground = SupervisorBackgroundPreferenceTrack.preferredBackgroundNotes(from: sortedBackgroundNotes)

        let domains = Set(hardDecisions.keys.map { SupervisorBackgroundPreferenceDomain(rawValue: $0.rawValue) })
            .union(sortedBackgroundNotes.map(\.domain))

        let resolutions = domains.sorted { $0.rawValue < $1.rawValue }.map { domain in
            let hardDecision = hardDecisions[SupervisorDecisionCategory(rawValue: domain.rawValue)]
            let domainNotes = sortedBackgroundNotes.filter { $0.domain == domain }
            let preferredNote = hardDecision == nil ? preferredBackground[domain] : nil
            let shadowedNotes = hardDecision == nil ? [] : domainNotes

            return SupervisorDecisionRailResolution(
                domain: domain,
                hardDecision: hardDecision,
                preferredBackgroundNote: preferredNote,
                shadowedBackgroundNotes: shadowedNotes
            )
        }

        return SupervisorProjectDecisionRails(
            projectId: normalizedBackgroundToken(projectId),
            decisionTrack: hardDecisions.values.sorted { lhs, rhs in
                if lhs.updatedAtMs != rhs.updatedAtMs {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                return lhs.decisionId > rhs.decisionId
            },
            backgroundPreferenceTrack: sortedBackgroundNotes,
            resolutions: resolutions
        )
    }
}

enum SupervisorBackgroundPreferenceTrackBuilder {
    static func build(
        noteId: String,
        projectId: String,
        domain: SupervisorBackgroundPreferenceDomain,
        strength: SupervisorBackgroundPreferenceStrength,
        statement: String,
        mustNotPromoteWithoutDecision: Bool = true,
        createdAtMs: Int64
    ) -> SupervisorBackgroundPreferenceNote {
        SupervisorBackgroundPreferenceNote(
            schemaVersion: SupervisorBackgroundPreferenceNote.schemaVersion,
            noteId: noteId,
            projectId: projectId,
            domain: domain,
            strength: strength,
            statement: statement,
            mustNotPromoteWithoutDecision: mustNotPromoteWithoutDecision,
            createdAtMs: createdAtMs
        ).sanitizedForStorage
    }
}

enum SupervisorBackgroundPreferenceTrackStore {
    private static let fileName = "supervisor_background_preference_track.json"

    static func load(for ctx: AXProjectContext) -> SupervisorBackgroundPreferenceTrackSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: url(for: ctx)),
              let snapshot = try? JSONDecoder().decode(SupervisorBackgroundPreferenceTrackSnapshot.self, from: data) else {
            return SupervisorBackgroundPreferenceTrackSnapshot(
                schemaVersion: SupervisorBackgroundPreferenceTrackSnapshot.schemaVersion,
                updatedAtMs: 0,
                notes: []
            )
        }
        return snapshot
    }

    @discardableResult
    static func upsert(_ note: SupervisorBackgroundPreferenceNote, for ctx: AXProjectContext) throws -> SupervisorBackgroundPreferenceTrackSnapshot {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorBackgroundPreferenceTrackSnapshot.schemaVersion
        snapshot.notes = try SupervisorBackgroundPreferenceTrack.merged(existing: snapshot.notes, incoming: [note])
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, note.sanitizedForStorage.createdAtMs)
        try save(snapshot, for: ctx)
        return snapshot
    }

    static func save(_ snapshot: SupervisorBackgroundPreferenceTrackSnapshot, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let target = url(for: ctx)
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: target)
    }

    private static func url(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent(fileName)
    }
}

private func backgroundNoteSort(_ lhs: SupervisorBackgroundPreferenceNote, _ rhs: SupervisorBackgroundPreferenceNote) -> Bool {
    if lhs.createdAtMs != rhs.createdAtMs {
        return lhs.createdAtMs > rhs.createdAtMs
    }
    return lhs.noteId > rhs.noteId
}

private func backgroundNotePreferenceSort(_ lhs: SupervisorBackgroundPreferenceNote, _ rhs: SupervisorBackgroundPreferenceNote) -> Bool {
    if lhs.domain.rawValue != rhs.domain.rawValue {
        return lhs.domain.rawValue < rhs.domain.rawValue
    }
    if lhs.strength.rank != rhs.strength.rank {
        return lhs.strength.rank > rhs.strength.rank
    }
    return backgroundNoteSort(lhs, rhs)
}

private func preferredStrength(
    _ primary: SupervisorBackgroundPreferenceStrength,
    _ fallback: SupervisorBackgroundPreferenceStrength,
    incomingWins: Bool
) -> SupervisorBackgroundPreferenceStrength {
    if primary.rank != fallback.rank {
        return primary.rank > fallback.rank ? primary : fallback
    }
    return incomingWins ? primary : fallback
}

private func preferredBackgroundScalar(_ primary: String, _ fallback: String) -> String {
    let normalizedPrimary = normalizedBackgroundScalar(primary)
    if !normalizedPrimary.isEmpty {
        return normalizedPrimary
    }
    return normalizedBackgroundScalar(fallback)
}

private func normalizedBackgroundToken(_ raw: String) -> String {
    normalizedBackgroundScalar(raw)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
}

private func normalizedBackgroundScalar(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
