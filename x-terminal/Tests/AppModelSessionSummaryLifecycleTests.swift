import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelSessionSummaryLifecycleTests {
    @Test
    func appExitWritesSessionSummaryCapsuleForCurrentProject() async throws {
        let fixture = ToolExecutorProjectFixture(name: "app-exit-session-summary")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "app-exit-session-summary", projectRoot: fixture.root.path)
        memory.goal = "Persist a final session summary on app exit."
        memory.currentState = ["Loaded in the current project window"]
        memory.nextSteps = ["Resume after restart"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Remember this state before the app closes.",
            createdAt: 100
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "I will keep a resumable summary for the current project.",
            createdAt: 101
        )

        let appModel = AppModel()
        appModel.projectContext = ctx
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)

        appModel.persistSessionSummariesForLifecycle(reason: "app_exit")

        #expect(FileManager.default.fileExists(atPath: ctx.latestSessionSummaryURL.path))
        let data = try Data(contentsOf: ctx.latestSessionSummaryURL)
        let summary = try JSONDecoder().decode(AXSessionSummaryCapsule.self, from: data)
        #expect(summary.reason == "app_exit")
        #expect(summary.memorySummary.goal == "Persist a final session summary on app exit.")
        #expect(summary.workingSetSummary.latestAssistantMessage == "I will keep a resumable summary for the current project.")
    }

    @Test
    func globalModelAssignmentSwitchWritesSessionSummaryCapsuleForCurrentProject() async throws {
        let fixture = ToolExecutorProjectFixture(name: "global-ai-switch-session-summary")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "global-ai-switch-session-summary", projectRoot: fixture.root.path)
        memory.goal = "Preserve handoff before switching the active AI assignment."
        memory.currentState = ["Current project context is loaded"]
        memory.nextSteps = ["Continue after switching the default coder model"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Switch the default coder AI after preserving this state.",
            createdAt: 200
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "I will write a summary at the AI switch boundary.",
            createdAt: 201
        )

        let appModel = AppModel()
        appModel.projectContext = ctx
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)

        let currentModel = appModel.settingsStore.settings.assignment(for: .coder).model ?? ""
        let nextModel = currentModel == "xterminal-test-ai-switch-a"
            ? "xterminal-test-ai-switch-b"
            : "xterminal-test-ai-switch-a"
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .coder,
            providerKind: .hub,
            model: nextModel
        )

        try await waitUntilFileExists(ctx.latestSessionSummaryURL)

        let data = try Data(contentsOf: ctx.latestSessionSummaryURL)
        let summary = try JSONDecoder().decode(AXSessionSummaryCapsule.self, from: data)
        #expect(summary.reason == "ai_switch")
        #expect(summary.memorySummary.nextStep == "Continue after switching the default coder model")
        #expect(summary.workingSetSummary.latestUserMessage == "Switch the default coder AI after preserving this state.")
    }

    @Test
    func projectSwitchWritesSessionSummaryCapsuleForPreviousProjectViaAppModelSelection() async throws {
        let oldFixture = ToolExecutorProjectFixture(name: "app-model-project-switch-old")
        let newFixture = ToolExecutorProjectFixture(name: "app-model-project-switch-new")
        let registryFixture = ToolExecutorProjectFixture(name: "app-model-project-switch-registry")
        defer {
            oldFixture.cleanup()
            newFixture.cleanup()
            registryFixture.cleanup()
        }

        let oldCtx = AXProjectContext(root: oldFixture.root)
        let newCtx = AXProjectContext(root: newFixture.root)
        try oldCtx.ensureDirs()
        try newCtx.ensureDirs()

        var memory = AXMemory.new(projectName: "app-model-project-switch-old", projectRoot: oldFixture.root.path)
        memory.goal = "Persist the latest project state before switching selection."
        memory.currentState = ["Current project is loaded in AppModel"]
        memory.nextSteps = ["Continue work after switching to another project"]
        try AXProjectStore.saveMemory(memory, for: oldCtx)

        AXRecentContextStore.appendUserMessage(
            ctx: oldCtx,
            text: "Capture this state before I switch projects.",
            createdAt: 400
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: oldCtx,
            text: "I will write a project switch summary before loading the next project.",
            createdAt: 401
        )

        try await withTemporaryEnvironment([
            "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryFixture.root.path
        ]) {
            var registry = AXProjectRegistry.empty()
            registry.globalHomeVisible = false
            let oldRes = AXProjectRegistryStore.upsertProject(registry, root: oldFixture.root)
            registry = oldRes.0
            let newRes = AXProjectRegistryStore.upsertProject(registry, root: newFixture.root)
            registry = newRes.0
            registry.lastSelectedProjectId = oldRes.1.projectId

            let appModel = AppModel()
            appModel.registry = registry
            appModel.selectProject(oldRes.1.projectId)
            try await waitUntilProjectLoaded(appModel, root: oldFixture.root)

            appModel.selectProject(newRes.1.projectId)
            try await waitUntilProjectLoaded(appModel, root: newFixture.root)

            #expect(FileManager.default.fileExists(atPath: oldCtx.latestSessionSummaryURL.path))
            let data = try Data(contentsOf: oldCtx.latestSessionSummaryURL)
            let summary = try JSONDecoder().decode(AXSessionSummaryCapsule.self, from: data)
            #expect(summary.reason == "project_switch")
            #expect(summary.memorySummary.goal == "Persist the latest project state before switching selection.")
            #expect(summary.workingSetSummary.latestUserMessage == "Capture this state before I switch projects.")
        }
    }

    @Test
    func resumeReminderHidesAfterDismissAndReappearsForNewerSessionSummary() throws {
        let fixture = ToolExecutorProjectFixture(name: "app-model-resume-reminder")
        defer { fixture.cleanup() }

        let ctx = AXProjectContext(root: fixture.root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "app-model-resume-reminder", projectRoot: fixture.root.path)
        memory.goal = "Show a startup resume reminder without polluting the main prompt."
        memory.currentState = ["A recent lifecycle boundary summary exists"]
        memory.nextSteps = ["Offer a resumable handoff when the project is reopened"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        let firstSummary = try #require(
            AXMemoryLifecycleStore.writeSessionSummaryCapsule(
                ctx: ctx,
                reason: "app_exit",
                now: 1_000
            )
        )

        var registry = AXProjectRegistry.empty()
        registry.globalHomeVisible = false
        let upsert = AXProjectRegistryStore.upsertProject(registry, root: fixture.root)
        registry = upsert.0

        let appModel = AppModel()
        appModel.registry = registry

        let projectId = upsert.1.projectId
        let initialReminder = try #require(appModel.resumeReminderPresentation(projectId: projectId))
        #expect(initialReminder.createdAtMs == firstSummary.createdAtMs)
        #expect(initialReminder.reason == "app_exit")

        appModel.dismissResumeReminder(projectId: projectId)
        #expect(appModel.resumeReminderPresentation(projectId: projectId) == nil)

        let newerSummary = try #require(
            AXMemoryLifecycleStore.writeSessionSummaryCapsule(
                ctx: ctx,
                reason: "ai_switch",
                now: 1_005
            )
        )
        let resumedReminder = try #require(appModel.resumeReminderPresentation(projectId: projectId))
        #expect(resumedReminder.createdAtMs == newerSummary.createdAtMs)
        #expect(resumedReminder.reason == "ai_switch")
    }

    @Test
    func latestResumeReminderProjectPrefersNewestUnacknowledgedSummary() throws {
        let olderFixture = ToolExecutorProjectFixture(name: "app-model-home-reminder-older")
        let newerFixture = ToolExecutorProjectFixture(name: "app-model-home-reminder-newer")
        defer {
            olderFixture.cleanup()
            newerFixture.cleanup()
        }

        let olderCtx = AXProjectContext(root: olderFixture.root)
        let newerCtx = AXProjectContext(root: newerFixture.root)
        try olderCtx.ensureDirs()
        try newerCtx.ensureDirs()

        var olderMemory = AXMemory.new(projectName: "app-model-home-reminder-older", projectRoot: olderFixture.root.path)
        olderMemory.goal = "Keep an older resumable summary visible until it is acknowledged."
        olderMemory.currentState = ["Older project is waiting for a handoff review"]
        olderMemory.nextSteps = ["Resume if nothing newer exists"]
        try AXProjectStore.saveMemory(olderMemory, for: olderCtx)

        var newerMemory = AXMemory.new(projectName: "app-model-home-reminder-newer", projectRoot: newerFixture.root.path)
        newerMemory.goal = "Prefer the newest project handoff on Global Home."
        newerMemory.currentState = ["Newer project was closed more recently"]
        newerMemory.nextSteps = ["Resume this project first"]
        try AXProjectStore.saveMemory(newerMemory, for: newerCtx)

        let olderSummary = try #require(
            AXMemoryLifecycleStore.writeSessionSummaryCapsule(
                ctx: olderCtx,
                reason: "project_switch",
                now: 1_000
            )
        )
        let newerSummary = try #require(
            AXMemoryLifecycleStore.writeSessionSummaryCapsule(
                ctx: newerCtx,
                reason: "app_exit",
                now: 1_200
            )
        )

        var registry = AXProjectRegistry.empty()
        registry.globalHomeVisible = false
        let olderUpsert = AXProjectRegistryStore.upsertProject(registry, root: olderFixture.root)
        registry = olderUpsert.0
        let newerUpsert = AXProjectRegistryStore.upsertProject(registry, root: newerFixture.root)
        registry = newerUpsert.0

        let appModel = AppModel()
        appModel.registry = registry

        let initial = try #require(appModel.latestResumeReminderProject())
        #expect(initial.projectId == newerUpsert.1.projectId)
        #expect(initial.summary.createdAtMs == newerSummary.createdAtMs)
        #expect(initial.summary.reason == "app_exit")

        appModel.dismissResumeReminder(projectId: newerUpsert.1.projectId)

        let fallback = try #require(appModel.latestResumeReminderProject())
        #expect(fallback.projectId == olderUpsert.1.projectId)
        #expect(fallback.summary.createdAtMs == olderSummary.createdAtMs)
        #expect(fallback.summary.reason == "project_switch")

        appModel.dismissResumeReminder(projectId: olderUpsert.1.projectId)
        #expect(appModel.latestResumeReminderProject() == nil)
    }

    @Test
    func preferredResumeProjectPrefersSelectedProjectThenFallsBackToLatestSummary() throws {
        let selectedFixture = ToolExecutorProjectFixture(name: "app-model-preferred-resume-selected")
        let latestFixture = ToolExecutorProjectFixture(name: "app-model-preferred-resume-latest")
        defer {
            selectedFixture.cleanup()
            latestFixture.cleanup()
        }

        let selectedCtx = AXProjectContext(root: selectedFixture.root)
        let latestCtx = AXProjectContext(root: latestFixture.root)
        try selectedCtx.ensureDirs()
        try latestCtx.ensureDirs()

        var selectedMemory = AXMemory.new(projectName: "app-model-preferred-resume-selected", projectRoot: selectedFixture.root.path)
        selectedMemory.goal = "Prefer the currently selected project's handoff when the user explicitly asks to resume."
        selectedMemory.currentState = ["Selected project still has a valid handoff summary"]
        selectedMemory.nextSteps = ["Resume this project from the Project menu"]
        try AXProjectStore.saveMemory(selectedMemory, for: selectedCtx)

        var latestMemory = AXMemory.new(projectName: "app-model-preferred-resume-latest", projectRoot: latestFixture.root.path)
        latestMemory.goal = "Fallback to the latest overall handoff when Home is selected."
        latestMemory.currentState = ["Another project has the newest summary"]
        latestMemory.nextSteps = ["Resume this project from Home if nothing is selected"]
        try AXProjectStore.saveMemory(latestMemory, for: latestCtx)

        let selectedSummary = try #require(
            AXMemoryLifecycleStore.writeSessionSummaryCapsule(
                ctx: selectedCtx,
                reason: "project_switch",
                now: 1_000
            )
        )
        let latestSummary = try #require(
            AXMemoryLifecycleStore.writeSessionSummaryCapsule(
                ctx: latestCtx,
                reason: "app_exit",
                now: 1_200
            )
        )

        var registry = AXProjectRegistry.empty()
        let selectedUpsert = AXProjectRegistryStore.upsertProject(registry, root: selectedFixture.root)
        registry = selectedUpsert.0
        let latestUpsert = AXProjectRegistryStore.upsertProject(registry, root: latestFixture.root)
        registry = latestUpsert.0

        let appModel = AppModel()
        appModel.registry = registry

        appModel.selectProject(selectedUpsert.1.projectId)
        let selectedTarget = try #require(appModel.preferredResumeProject())
        #expect(selectedTarget.projectId == selectedUpsert.1.projectId)
        #expect(selectedTarget.summary.createdAtMs == selectedSummary.createdAtMs)

        appModel.selectProject(AXProjectRegistry.globalHomeId)
        let homeTarget = try #require(appModel.preferredResumeProject())
        #expect(homeTarget.projectId == latestUpsert.1.projectId)
        #expect(homeTarget.summary.createdAtMs == latestSummary.createdAtMs)

        appModel.dismissResumeReminder(projectId: selectedUpsert.1.projectId)
        appModel.dismissResumeReminder(projectId: latestUpsert.1.projectId)
        let fallbackTarget = try #require(appModel.preferredResumeProject())
        #expect(fallbackTarget.projectId == latestUpsert.1.projectId)
        #expect(fallbackTarget.summary.createdAtMs == latestSummary.createdAtMs)
    }

    @Test
    func supervisorGrantFocusRequestPersistsUntilCleared() throws {
        let appModel = AppModel()

        appModel.requestSupervisorGrantFocus(
            projectId: "project-focus",
            grantRequestId: "grant-focus-1",
            capability: "ai.generate.paid"
        )

        let request = try #require(appModel.supervisorFocusRequest)
        #expect(request.projectId == "project-focus")
        #expect(
            request.subject == .grant(
                grantRequestId: "grant-focus-1",
                capability: "ai.generate.paid"
            )
        )

        appModel.clearSupervisorFocusRequest(request)
        #expect(appModel.supervisorFocusRequest == nil)
    }

    @Test
    func supervisorApprovalFocusRequestPersistsUntilCleared() throws {
        let appModel = AppModel()

        appModel.requestSupervisorApprovalFocus(
            projectId: "project-approval",
            requestId: "request-approval-1"
        )

        let request = try #require(appModel.supervisorFocusRequest)
        #expect(request.projectId == "project-approval")
        #expect(request.subject == .approval(requestId: "request-approval-1"))

        appModel.clearSupervisorFocusRequest(request)
        #expect(appModel.supervisorFocusRequest == nil)
    }

    @Test
    func supervisorBoardFocusRequestPersistsUntilCleared() throws {
        let appModel = AppModel()

        appModel.requestSupervisorBoardFocus(
            anchorID: SupervisorFocusPresentation.laneHealthBoardAnchorID,
            projectId: "project-board"
        )

        let request = try #require(appModel.supervisorFocusRequest)
        #expect(request.projectId == "project-board")
        #expect(
            request.subject == .board(anchorID: SupervisorFocusPresentation.laneHealthBoardAnchorID)
        )

        appModel.clearSupervisorFocusRequest(request)
        #expect(appModel.supervisorFocusRequest == nil)
    }

    @Test
    func supervisorSkillRecordFocusRequestPersistsUntilCleared() throws {
        let appModel = AppModel()

        appModel.requestSupervisorSkillRecordFocus(
            projectId: "project-record",
            requestId: "request-record-1"
        )

        let request = try #require(appModel.supervisorFocusRequest)
        #expect(request.projectId == "project-record")
        #expect(request.subject == .skillRecord(requestId: "request-record-1"))

        appModel.clearSupervisorFocusRequest(request)
        #expect(appModel.supervisorFocusRequest == nil)
    }

    @Test
    func supervisorCandidateReviewFocusRequestPersistsUntilCleared() throws {
        let appModel = AppModel()

        appModel.requestSupervisorCandidateReviewFocus(
            projectId: "project-review",
            requestId: "request-review-1"
        )

        let request = try #require(appModel.supervisorFocusRequest)
        #expect(request.projectId == "project-review")
        #expect(request.subject == .candidateReview(requestId: "request-review-1"))

        appModel.clearSupervisorFocusRequest(request)
        #expect(appModel.supervisorFocusRequest == nil)
    }

    @Test
    func projectToolApprovalFocusRequestPersistsUntilCleared() throws {
        let appModel = AppModel()

        appModel.requestProjectToolApprovalFocus(
            projectId: "project-tool-approval",
            requestId: "tool-call-11"
        )

        let request = try #require(appModel.projectFocusRequest)
        #expect(request.projectId == "project-tool-approval")
        #expect(request.subject == .toolApproval(requestId: "tool-call-11"))

        appModel.clearProjectFocusRequest(request)
        #expect(appModel.projectFocusRequest == nil)
    }

    @Test
    func projectRouteDiagnoseFocusRequestPersistsUntilCleared() throws {
        let appModel = AppModel()

        appModel.requestProjectRouteDiagnoseFocus(projectId: "project-route-diagnose")

        let request = try #require(appModel.projectFocusRequest)
        #expect(request.projectId == "project-route-diagnose")
        #expect(request.subject == .routeDiagnose)

        appModel.clearProjectFocusRequest(request)
        #expect(appModel.projectFocusRequest == nil)
    }

    private func waitUntilProjectLoaded(_ appModel: AppModel, root: URL) async throws {
        try await waitUntil(timeoutMs: 5_000) {
            appModel.projectRoot?.standardizedFileURL.path == root.standardizedFileURL.path
                && appModel.projectContext?.root.standardizedFileURL.path == root.standardizedFileURL.path
        }
    }

    private func waitUntilFileExists(_ url: URL) async throws {
        try await waitUntil(timeoutMs: 5_000) {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    private func currentEnvironmentValue(_ key: String) -> String? {
        guard let value = getenv(key) else { return nil }
        return String(cString: value)
    }

    private func withTemporaryEnvironment<T>(
        _ overrides: [String: String?],
        operation: () async throws -> T
    ) async rethrows -> T {
        let original = Dictionary(uniqueKeysWithValues: overrides.keys.map { ($0, currentEnvironmentValue($0)) })
        for (key, value) in overrides {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
        defer {
            for (key, value) in original {
                if let value {
                    setenv(key, value, 1)
                } else {
                    unsetenv(key)
                }
            }
        }
        return try await operation()
    }

    private func waitUntil(timeoutMs: UInt64, condition: @escaping () -> Bool) async throws {
        let deadline = Date().timeIntervalSince1970 + (Double(timeoutMs) / 1_000.0)
        while Date().timeIntervalSince1970 < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("Timed out waiting for expected state.")
        throw CancellationError()
    }
}
