import Foundation

enum LaneReviewVerdict: String, Codable, Equatable, CaseIterable {
    case approved
    case changesRequested = "changes_requested"
    case blocked
    case needsHuman = "needs_human"

    var allowsMergeback: Bool {
        self == .approved
    }
}

struct CoderLaneOutput: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = "xt.coder_lane_output.v1"

    var id: String { laneID }

    let schemaVersion: String
    let laneID: String
    let role: String
    let projectID: String
    let changedFiles: [String]
    let diffRef: String
    let diagnosticsRunIDs: [String]
    let artifactRefs: [String]
    let summary: String
    let outputRef: String
    let auditRef: String
    let createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case laneID = "lane_id"
        case role
        case projectID = "project_id"
        case changedFiles = "changed_files"
        case diffRef = "diff_ref"
        case diagnosticsRunIDs = "diagnostics_run_ids"
        case artifactRefs = "artifact_refs"
        case summary
        case outputRef = "output_ref"
        case auditRef = "audit_ref"
        case createdAtMs = "created_at_ms"
    }
}

struct LaneReviewReport: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = "xt.lane_review_report.v1"

    var id: String { laneID }

    let schemaVersion: String
    let laneID: String
    let role: String
    let reviewerID: String
    let verdict: LaneReviewVerdict
    let summary: String
    let issues: [String]
    let recommendedActions: [String]
    let residualRisks: [String]
    let evidenceRefs: [String]
    let coderOutputRef: String
    let reviewRef: String
    let auditRef: String
    let createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case laneID = "lane_id"
        case role
        case reviewerID = "reviewer_id"
        case verdict
        case summary
        case issues
        case recommendedActions = "recommended_actions"
        case residualRisks = "residual_risks"
        case evidenceRefs = "evidence_refs"
        case coderOutputRef = "coder_output_ref"
        case reviewRef = "review_ref"
        case auditRef = "audit_ref"
        case createdAtMs = "created_at_ms"
    }
}
