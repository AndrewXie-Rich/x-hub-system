import Foundation

enum SupervisorMemoryAssemblyIssueSeverity: String, Codable, Sendable {
    case warning
    case blocking
}

struct SupervisorMemoryAssemblyIssue: Codable, Equatable, Identifiable, Sendable {
    var id: String { code }
    var code: String
    var severity: SupervisorMemoryAssemblyIssueSeverity
    var summary: String
    var detail: String
}

struct SupervisorMemoryAssemblyReadiness: Codable, Equatable, Sendable {
    var ready: Bool
    var statusLine: String
    var issues: [SupervisorMemoryAssemblyIssue]

    var issueCodes: [String] {
        issues.map(\.code)
    }

    var blockingCount: Int {
        issues.filter { $0.severity == .blocking }.count
    }

    var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }
}

enum SupervisorMemoryAssemblyDiagnostics {
    private static let strategicAnchorSections: Set<String> = [
        "focused_project_anchor_pack",
        "longterm_outline",
        "evidence_pack",
    ]

    private static let coreContextLayers: Set<String> = [
        "l1_canonical",
        "l2_observations",
        "l3_working_set",
    ]

    static func evaluate(
        snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> SupervisorMemoryAssemblyReadiness {
        guard let snapshot else {
            let issue = SupervisorMemoryAssemblyIssue(
                code: "memory_assembly_snapshot_missing",
                severity: .warning,
                summary: "尚未捕获 Supervisor memory assembly 快照",
                detail: "Doctor / incident export 当前没有可用的 assembly snapshot，无法判断 strategic review 是否喂够项目背景与当前状态。"
            )
            return SupervisorMemoryAssemblyReadiness(
                ready: false,
                statusLine: "underfed:memory_assembly_snapshot_missing",
                issues: [issue]
            )
        }

        let reviewLevel = SupervisorReviewLevel(rawValue: snapshot.reviewLevelHint) ?? .r1Pulse
        let focusedProjectId = snapshot.focusedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let focusedStrategicReview = !focusedProjectId.isEmpty && reviewLevel >= .r2Strategic
        let elevatedReview = focusedStrategicReview || reviewLevel == .r3Rescue
        let floor = XTMemoryServingProfile.parse(snapshot.profileFloor)
        let resolved = XTMemoryServingProfile.parse(snapshot.resolvedProfile)
        var issues: [SupervisorMemoryAssemblyIssue] = []

        if let floor, let resolved, resolved.rank < floor.rank {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_review_floor_not_met",
                    severity: elevatedReview ? .blocking : .warning,
                    summary: "Supervisor memory 供给没有达到 review floor",
                    detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) requested=\(snapshot.requestedProfile) floor=\(snapshot.profileFloor) resolved=\(snapshot.resolvedProfile) downgrade=\(snapshot.downgradeCode ?? "(none)") deny=\(snapshot.denyCode ?? "(none)")
"""
                )
            )
        }

        let omittedStrategicAnchors = snapshot.omittedSections.filter { strategicAnchorSections.contains($0) }
        if focusedStrategicReview && !omittedStrategicAnchors.isEmpty {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_strategic_anchor_underfed",
                    severity: .warning,
                    summary: "Focused strategic review 缺少关键战略锚点",
                    detail: """
focus=\(focusedProjectId) omitted_sections=\(omittedStrategicAnchors.joined(separator: ",")) selected_sections=\(snapshot.selectedSections.joined(separator: ",")) compression=\(snapshot.compressionPolicy)
"""
                )
            )
        }

        let truncatedCoreLayers = snapshot.truncatedLayers.filter { coreContextLayers.contains($0) }
        if elevatedReview && !truncatedCoreLayers.isEmpty {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_core_layers_truncated",
                    severity: .warning,
                    summary: "Supervisor 核心记忆层被截断",
                    detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) truncated_layers=\(truncatedCoreLayers.joined(separator: ",")) tokens=\(snapshot.usedTotalTokens ?? 0)/\(snapshot.budgetTotalTokens ?? 0)
"""
                )
            )
        }

        if focusedStrategicReview &&
            (snapshot.contextRefsSelected == 0 || snapshot.evidenceItemsSelected == 0) {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_focus_evidence_missing",
                    severity: .warning,
                    summary: "Focused strategic review 缺少可追溯证据",
                    detail: """
focus=\(focusedProjectId) context_refs=\(snapshot.contextRefsSelected)/\(snapshot.contextRefsSelected + snapshot.contextRefsOmitted) evidence_items=\(snapshot.evidenceItemsSelected)/\(snapshot.evidenceItemsSelected + snapshot.evidenceItemsOmitted)
"""
                )
            )
        }

        let statusLine: String
        if issues.isEmpty {
            statusLine = "ready · \(snapshot.statusLine)"
        } else {
            statusLine = "underfed:\(issues.map(\.code).joined(separator: ",")) · \(snapshot.statusLine)"
        }

        return SupervisorMemoryAssemblyReadiness(
            ready: issues.isEmpty,
            statusLine: statusLine,
            issues: issues
        )
    }
}
