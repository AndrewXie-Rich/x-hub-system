import Foundation

struct AXProjectContextAssemblyDiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = "xt.project_context_assembly_diagnostic_event.v1"

    var schemaVersion: String
    var createdAt: Double
    var projectId: String
    var projectDisplayName: String
    var role: String
    var stage: String
    var memoryV1Source: String
    var recentProjectDialogueProfile: String
    var recentProjectDialogueSelectedPairs: Int
    var recentProjectDialogueFloorPairs: Int
    var recentProjectDialogueFloorSatisfied: Bool
    var recentProjectDialogueSource: String
    var recentProjectDialogueLowSignalDropped: Int
    var projectContextDepth: String
    var effectiveProjectServingProfile: String
    var workflowPresent: Bool
    var executionEvidencePresent: Bool
    var reviewGuidancePresent: Bool
    var crossLinkHintsSelected: Int
    var personalMemoryExcludedReason: String

    var id: String {
        [
            projectId,
            role,
            stage,
            String(Int((createdAt * 1000).rounded()))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ":")
    }

    func doctorDetailLines(includeProject: Bool) -> [String] {
        var lines: [String] = []
        if includeProject {
            lines.append("project_context_project=\(projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? projectId : projectDisplayName)")
        }
        let normalizedMemorySource = memoryV1Source.isEmpty ? "unknown" : memoryV1Source
        let normalizedRecentDialogueSource = recentProjectDialogueSource.isEmpty ? "unknown" : recentProjectDialogueSource
        lines.append("project_context_diagnostics_source=latest_coder_usage")
        if !role.isEmpty {
            lines.append("project_context_last_role=\(role)")
        }
        if !stage.isEmpty {
            lines.append("project_context_last_stage=\(stage)")
        }
        lines.append("project_memory_v1_source=\(normalizedMemorySource)")
        lines.append("project_memory_v1_source_label=\(XTMemorySourceTruthPresentation.label(normalizedMemorySource))")
        lines.append("project_memory_v1_source_class=\(XTMemorySourceTruthPresentation.sourceClass(normalizedMemorySource))")
        lines.append("recent_project_dialogue_profile=\(recentProjectDialogueProfile)")
        lines.append("recent_project_dialogue_selected_pairs=\(recentProjectDialogueSelectedPairs)")
        lines.append("recent_project_dialogue_floor_pairs=\(recentProjectDialogueFloorPairs)")
        lines.append("recent_project_dialogue_floor_satisfied=\(recentProjectDialogueFloorSatisfied)")
        lines.append("recent_project_dialogue_source=\(normalizedRecentDialogueSource)")
        lines.append("recent_project_dialogue_source_label=\(XTMemorySourceTruthPresentation.label(normalizedRecentDialogueSource))")
        lines.append("recent_project_dialogue_source_class=\(XTMemorySourceTruthPresentation.sourceClass(normalizedRecentDialogueSource))")
        lines.append("recent_project_dialogue_low_signal_dropped=\(recentProjectDialogueLowSignalDropped)")
        lines.append("project_context_depth=\(projectContextDepth)")
        lines.append("effective_project_serving_profile=\(effectiveProjectServingProfile)")
        lines.append("workflow_present=\(workflowPresent)")
        lines.append("execution_evidence_present=\(executionEvidencePresent)")
        lines.append("review_guidance_present=\(reviewGuidancePresent)")
        lines.append("cross_link_hints_selected=\(crossLinkHintsSelected)")
        if !personalMemoryExcludedReason.isEmpty {
            lines.append("personal_memory_excluded_reason=\(personalMemoryExcludedReason)")
        }
        return lines
    }
}

struct AXProjectContextAssemblyDiagnosticsSummary: Equatable, Sendable {
    static let empty = AXProjectContextAssemblyDiagnosticsSummary(
        latestEvent: nil,
        detailLines: []
    )

    var latestEvent: AXProjectContextAssemblyDiagnosticEvent?
    var detailLines: [String]
}

extension AXProjectContextAssemblyDiagnosticsSummary {
    var presentation: AXProjectContextAssemblyPresentation? {
        AXProjectContextAssemblyPresentation.from(summary: self)
    }
}

enum AXProjectContextAssemblyDiagnosticsStore {
    static func latestEvent(for ctx: AXProjectContext) -> AXProjectContextAssemblyDiagnosticEvent? {
        recentEvents(for: ctx, limit: 1).first
    }

    static func doctorSummary(
        for ctx: AXProjectContext?,
        config: AXProjectConfig? = nil
    ) -> AXProjectContextAssemblyDiagnosticsSummary {
        guard let ctx else { return .empty }

        if let latest = latestEvent(for: ctx) {
            return AXProjectContextAssemblyDiagnosticsSummary(
                latestEvent: latest,
                detailLines: latest.doctorDetailLines(includeProject: true)
            )
        }

        let projectName = resolvedProjectDisplayName(for: ctx)
        let recentProfile = config?.projectRecentDialogueProfile.rawValue
            ?? AXProjectRecentDialogueProfile.defaultProfile.rawValue
        let depthProfile = config?.projectContextDepthProfile.rawValue
            ?? AXProjectContextDepthProfile.defaultProfile.rawValue
        return AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=config_only",
                "project_context_project=\(projectName)",
                "configured_recent_project_dialogue_profile=\(recentProfile)",
                "configured_project_context_depth=\(depthProfile)",
                "project_context_diagnostics=no_recent_coder_usage"
            ]
        )
    }

    private static func recentEvents(
        for ctx: AXProjectContext,
        limit: Int
    ) -> [AXProjectContextAssemblyDiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: ctx.usageLogURL.path),
              let data = try? Data(contentsOf: ctx.usageLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return Array(
            text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return nil
                    }
                    return event(from: obj, ctx: ctx)
                }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.id > rhs.id
                }
                .prefix(limit)
        )
    }

    private static func event(
        from obj: [String: Any],
        ctx: AXProjectContext
    ) -> AXProjectContextAssemblyDiagnosticEvent? {
        guard text(obj["type"]) == "ai_usage" else { return nil }

        let recentDialogueProfile = text(obj["recent_project_dialogue_profile"])
        let projectContextDepth = text(obj["project_context_depth"])
        guard !recentDialogueProfile.isEmpty || !projectContextDepth.isEmpty else { return nil }

        let selectedPairs = int(obj["recent_project_dialogue_selected_pairs"])
        let floorPairs = max(AXProjectRecentDialogueProfile.hardFloorPairs, int(obj["recent_project_dialogue_floor_pairs"]))
        let floorSatisfied = bool(obj["recent_project_dialogue_floor_satisfied"])
            ?? (selectedPairs >= floorPairs)
        return AXProjectContextAssemblyDiagnosticEvent(
            schemaVersion: AXProjectContextAssemblyDiagnosticEvent.currentSchemaVersion,
            createdAt: number(obj["created_at"]),
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectDisplayName: resolvedProjectDisplayName(for: ctx),
            role: text(obj["role"]),
            stage: text(obj["stage"]),
            memoryV1Source: text(obj["memory_v1_source"]),
            recentProjectDialogueProfile: recentDialogueProfile,
            recentProjectDialogueSelectedPairs: selectedPairs,
            recentProjectDialogueFloorPairs: floorPairs,
            recentProjectDialogueFloorSatisfied: floorSatisfied,
            recentProjectDialogueSource: text(obj["recent_project_dialogue_source"]),
            recentProjectDialogueLowSignalDropped: int(obj["recent_project_dialogue_low_signal_dropped"]),
            projectContextDepth: projectContextDepth,
            effectiveProjectServingProfile: text(obj["effective_project_serving_profile"]),
            workflowPresent: bool(obj["workflow_present"]) ?? false,
            executionEvidencePresent: bool(obj["execution_evidence_present"]) ?? false,
            reviewGuidancePresent: bool(obj["review_guidance_present"]) ?? false,
            crossLinkHintsSelected: int(obj["cross_link_hints_selected"]),
            personalMemoryExcludedReason: text(obj["personal_memory_excluded_reason"])
        )
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

    private static func int(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String, let parsed = Int(value) { return parsed }
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
}
