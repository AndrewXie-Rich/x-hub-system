import Foundation

struct SupervisorSelectedEvidencePin: Identifiable, Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_selected_evidence_pin.v1"

    var schemaVersion: String
    var pinId: String
    var projectId: String
    var summary: String
    var sourceNote: String
    var whyItMatters: String
    var createdAtMs: Int64
    var auditRef: String

    var id: String { pinId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case pinId = "pin_id"
        case projectId = "project_id"
        case summary
        case sourceNote = "source_note"
        case whyItMatters = "why_it_matters"
        case createdAtMs = "created_at_ms"
        case auditRef = "audit_ref"
    }

    var sanitizedForStorage: SupervisorSelectedEvidencePin {
        SupervisorSelectedEvidencePin(
            schemaVersion: Self.schemaVersion,
            pinId: normalizedEvidencePinToken(pinId),
            projectId: normalizedEvidencePinToken(projectId),
            summary: normalizedEvidencePinScalar(summary),
            sourceNote: normalizedEvidencePinScalar(sourceNote),
            whyItMatters: normalizedEvidencePinScalar(whyItMatters),
            createdAtMs: max(0, createdAtMs),
            auditRef: normalizedEvidencePinScalar(auditRef)
        )
    }
}

struct SupervisorSelectedEvidenceSnapshot: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_selected_evidence_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var pins: [SupervisorSelectedEvidencePin]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case pins
    }
}

enum SupervisorSelectedEvidencePinBuilder {
    static func build(
        pinId: String,
        projectId: String,
        summary: String,
        sourceNote: String,
        whyItMatters: String,
        createdAtMs: Int64,
        auditRef: String
    ) -> SupervisorSelectedEvidencePin {
        SupervisorSelectedEvidencePin(
            schemaVersion: SupervisorSelectedEvidencePin.schemaVersion,
            pinId: pinId,
            projectId: projectId,
            summary: summary,
            sourceNote: sourceNote,
            whyItMatters: whyItMatters,
            createdAtMs: createdAtMs,
            auditRef: auditRef
        ).sanitizedForStorage
    }
}

enum SupervisorSelectedEvidencePinStore {
    private static let fileName = "supervisor_selected_evidence_pins.json"
    private static let maxPins = 32

    static func load(for ctx: AXProjectContext) -> SupervisorSelectedEvidenceSnapshot {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: url(for: ctx)),
              let snapshot = try? JSONDecoder().decode(SupervisorSelectedEvidenceSnapshot.self, from: data) else {
            return SupervisorSelectedEvidenceSnapshot(
                schemaVersion: SupervisorSelectedEvidenceSnapshot.schemaVersion,
                updatedAtMs: 0,
                pins: []
            )
        }
        return snapshot
    }

    @discardableResult
    static func upsert(
        _ pin: SupervisorSelectedEvidencePin,
        for ctx: AXProjectContext
    ) throws -> SupervisorSelectedEvidenceSnapshot {
        try ctx.ensureDirs()
        var snapshot = load(for: ctx)
        snapshot.schemaVersion = SupervisorSelectedEvidenceSnapshot.schemaVersion
        let normalized = pin.sanitizedForStorage
        if let index = snapshot.pins.firstIndex(where: { $0.pinId == normalized.pinId }) {
            snapshot.pins[index] = normalized
        } else {
            snapshot.pins.append(normalized)
        }
        snapshot.pins.sort(by: selectedEvidencePinSort)
        if snapshot.pins.count > maxPins {
            snapshot.pins = Array(snapshot.pins.prefix(maxPins))
        }
        snapshot.updatedAtMs = max(snapshot.updatedAtMs, normalized.createdAtMs)
        try save(snapshot, for: ctx)
        return snapshot
    }

    static func latest(for ctx: AXProjectContext) -> SupervisorSelectedEvidencePin? {
        load(for: ctx).pins.first
    }

    static func save(_ snapshot: SupervisorSelectedEvidenceSnapshot, for ctx: AXProjectContext) throws {
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

private func selectedEvidencePinSort(
    _ lhs: SupervisorSelectedEvidencePin,
    _ rhs: SupervisorSelectedEvidencePin
) -> Bool {
    if lhs.createdAtMs != rhs.createdAtMs {
        return lhs.createdAtMs > rhs.createdAtMs
    }
    return lhs.pinId > rhs.pinId
}

private func normalizedEvidencePinToken(_ raw: String) -> String {
    let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let scalars = lowered.unicodeScalars.filter {
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
    }
    return String(String.UnicodeScalarView(scalars))
}

private func normalizedEvidencePinScalar(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
}
