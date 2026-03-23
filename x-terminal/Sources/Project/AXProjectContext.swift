import Foundation

struct AXProjectContext: Equatable {
    let root: URL

    var xterminalDir: URL {
        root.appendingPathComponent(".xterminal", isDirectory: true)
    }

    var memoryJSONURL: URL {
        xterminalDir.appendingPathComponent("ax_memory.json")
    }

    var memoryMarkdownURL: URL {
        xterminalDir.appendingPathComponent("AX_MEMORY.md")
    }

    var rawLogURL: URL {
        xterminalDir.appendingPathComponent("raw_log.jsonl")
    }

    var memoryLifecycleDir: URL {
        xterminalDir.appendingPathComponent("memory_lifecycle", isDirectory: true)
    }

    var latestMemoryLifecycleURL: URL {
        memoryLifecycleDir.appendingPathComponent("latest_after_turn.json")
    }

    var sessionSummariesDir: URL {
        xterminalDir.appendingPathComponent("session_summaries", isDirectory: true)
    }

    var latestSessionSummaryURL: URL {
        sessionSummariesDir.appendingPathComponent("latest.json")
    }

    var supervisorJobsURL: URL {
        xterminalDir.appendingPathComponent("supervisor_jobs.json")
    }

    var supervisorDecisionTrackURL: URL {
        xterminalDir.appendingPathComponent("supervisor_decision_track.json")
    }

    var supervisorBackgroundPreferenceTrackURL: URL {
        xterminalDir.appendingPathComponent("supervisor_background_preference_track.json")
    }

    var supervisorReviewNotesURL: URL {
        xterminalDir.appendingPathComponent("supervisor_review_notes.json")
    }

    var supervisorGuidanceInjectionsURL: URL {
        xterminalDir.appendingPathComponent("supervisor_guidance_injections.json")
    }

    var supervisorPlansURL: URL {
        xterminalDir.appendingPathComponent("supervisor_plans.json")
    }

    var supervisorSkillCallsURL: URL {
        xterminalDir.appendingPathComponent("supervisor_skill_calls.json")
    }

    var supervisorSkillResultsDir: URL {
        xterminalDir.appendingPathComponent("supervisor_skill_results", isDirectory: true)
    }

    var resolvedSkillsCacheURL: URL {
        xterminalDir.appendingPathComponent("resolved_skills_cache.json")
    }

    var usageLogURL: URL {
        xterminalDir.appendingPathComponent("usage.jsonl")
    }

    var modelRouteDiagnosticsLogURL: URL {
        xterminalDir.appendingPathComponent("model_route_diagnostics.jsonl")
    }

    var routeRepairLogURL: URL {
        xterminalDir.appendingPathComponent("route_repair_log.jsonl")
    }

    var configURL: URL {
        xterminalDir.appendingPathComponent("config.json")
    }

    var browserRuntimeDir: URL {
        xterminalDir.appendingPathComponent("browser_runtime", isDirectory: true)
    }

    var browserRuntimeSessionURL: URL {
        browserRuntimeDir.appendingPathComponent("session.json")
    }

    var browserRuntimeSnapshotsDir: URL {
        browserRuntimeDir.appendingPathComponent("snapshots", isDirectory: true)
    }

    var browserRuntimeProfilesDir: URL {
        browserRuntimeDir.appendingPathComponent("profiles", isDirectory: true)
    }

    var browserRuntimeActionLogURL: URL {
        browserRuntimeDir.appendingPathComponent("action_log.jsonl")
    }

    var uiObservationDir: URL {
        xterminalDir.appendingPathComponent("ui_observation", isDirectory: true)
    }

    var uiObservationBundlesDir: URL {
        uiObservationDir.appendingPathComponent("bundles", isDirectory: true)
    }

    var uiObservationArtifactsDir: URL {
        uiObservationDir.appendingPathComponent("artifacts", isDirectory: true)
    }

    var uiObservationLatestBrowserPageURL: URL {
        uiObservationDir.appendingPathComponent("latest_browser_page.json")
    }

    var uiReviewDir: URL {
        xterminalDir.appendingPathComponent("ui_review", isDirectory: true)
    }

    var uiReviewRecordsDir: URL {
        uiReviewDir.appendingPathComponent("reviews", isDirectory: true)
    }

    var uiReviewLatestBrowserPageURL: URL {
        uiReviewDir.appendingPathComponent("latest_browser_page.json")
    }

    var uiReviewAgentEvidenceDir: URL {
        uiReviewDir.appendingPathComponent("agent_evidence", isDirectory: true)
    }

    var uiReviewLatestBrowserPageAgentEvidenceURL: URL {
        uiReviewAgentEvidenceDir.appendingPathComponent("latest_browser_page.json")
    }

    var managedProcessesDir: URL {
        xterminalDir.appendingPathComponent("managed_processes", isDirectory: true)
    }

    var managedProcessesLogsDir: URL {
        managedProcessesDir.appendingPathComponent("logs", isDirectory: true)
    }

    var managedProcessesSnapshotURL: URL {
        managedProcessesDir.appendingPathComponent("processes.json")
    }

    func ensureDirs() throws {
        try FileManager.default.createDirectory(at: xterminalDir, withIntermediateDirectories: true)

        // Keep project memory local by default when the project is a git repo.
        // Users can still override their repo-level .gitignore if desired.
        let gi = xterminalDir.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: gi.path) {
            let s = "*\n!.gitignore\n"
            try? XTStoreWriteSupport.writeUTF8Text(s, to: gi)
        }

        // Create a default config on first run.
        if !FileManager.default.fileExists(atPath: configURL.path) {
            let cfg = AXProjectConfig.default(forProjectRoot: root)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(cfg) {
                try? XTStoreWriteSupport.writeSnapshotData(data, to: configURL)
            }
        }
    }

    func projectName() -> String {
        root.lastPathComponent
    }

    func displayName(
        registry: AXProjectRegistry? = nil,
        preferredDisplayName: String? = nil
    ) -> String {
        AXProjectRegistryStore.displayName(
            forRoot: root,
            registry: registry,
            preferredDisplayName: preferredDisplayName ?? projectName()
        )
    }

    func supervisorSkillResultEvidenceURL(requestId: String) -> URL {
        let base = requestId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let safe = base.isEmpty ? UUID().uuidString.lowercased() : base
        return supervisorSkillResultsDir.appendingPathComponent("\(safe).json")
    }

    func managedProcessLogURL(processId: String) -> URL {
        let base = processId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let safe = base.isEmpty ? UUID().uuidString.lowercased() : base
        return managedProcessesLogsDir.appendingPathComponent("\(safe).log")
    }

    func uiObservationBundleURL(bundleID: String) -> URL {
        let safe = sanitizedObservationToken(bundleID)
        return uiObservationBundlesDir.appendingPathComponent("\(safe).json")
    }

    func uiObservationArtifactDir(bundleID: String) -> URL {
        let safe = sanitizedObservationToken(bundleID)
        return uiObservationArtifactsDir.appendingPathComponent(safe, isDirectory: true)
    }

    func uiReviewRecordURL(reviewID: String) -> URL {
        let safe = sanitizedObservationToken(reviewID)
        return uiReviewRecordsDir.appendingPathComponent("\(safe).json")
    }

    func uiReviewAgentEvidenceURL(reviewID: String) -> URL {
        let safe = sanitizedObservationToken(reviewID)
        return uiReviewAgentEvidenceDir.appendingPathComponent("\(safe).json")
    }

    private func sanitizedObservationToken(_ raw: String) -> String {
        let base = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return base.isEmpty ? UUID().uuidString.lowercased() : base
    }
}
