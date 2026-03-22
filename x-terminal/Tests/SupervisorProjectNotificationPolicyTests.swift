import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectNotificationPolicyTests {
    private func writeTestHubStatus(base: URL) throws {
        let ipcDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        try FileManager.default.createDirectory(at: ipcDir, withIntermediateDirectories: true)
        let status = HubStatus(
            pid: nil,
            startedAt: Date().timeIntervalSince1970,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: ipcDir.path,
            baseDir: base.path,
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: Date().timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(status)
        try data.write(to: base.appendingPathComponent("hub_status.json"), options: .atomic)
    }

    @Test
    func policyMapsSeveritiesToExpectedChannels() {
        let authEvent = SupervisorProjectActionEvent(
            eventId: "auth",
            projectId: "p-auth",
            projectName: "Auth Project",
            eventType: .awaitingAuthorization,
            severity: .authorizationRequired,
            actionTitle: "项目待授权：Auth Project",
            actionSummary: "grant_required",
            whyItMatters: "needs approval",
            nextAction: "Approve paid model access",
            occurredAt: 1
        )
        let blockedEvent = SupervisorProjectActionEvent(
            eventId: "blocked",
            projectId: "p-blocked",
            projectName: "Blocked Project",
            eventType: .blocked,
            severity: .briefCard,
            actionTitle: "项目阻塞：Blocked Project",
            actionSummary: "Missing require-real sample",
            whyItMatters: "needs unblock",
            nextAction: "Run RR02",
            occurredAt: 1
        )
        let progressEvent = SupervisorProjectActionEvent(
            eventId: "progress",
            projectId: "p-active",
            projectName: "Active Project",
            eventType: .progressed,
            severity: .silentLog,
            actionTitle: "项目推进：Active Project",
            actionSummary: "Implementing feature",
            whyItMatters: "keep track",
            nextAction: "Continue implementation",
            occurredAt: 1
        )

        #expect(SupervisorProjectNotificationPolicy.decide(for: authEvent).channel == .interruptNow)
        #expect(SupervisorProjectNotificationPolicy.decide(for: blockedEvent).channel == .briefCard)
        #expect(SupervisorProjectNotificationPolicy.decide(for: progressEvent).channel == .silentLog)
    }

    @Test
    func policyElevatesDecisionRailCleanupEvenWhenProgressSeverityStartsSilent() {
        let event = SupervisorProjectActionEvent(
            eventId: "rail",
            projectId: "p-rail",
            projectName: "Decision Rail Project",
            eventType: .progressed,
            severity: .silentLog,
            actionTitle: "项目推进：Decision Rail Project",
            actionSummary: "Decision rail cleanup: 1 shadowed background note",
            whyItMatters: "Shadowed background notes should stay visibly non-binding so the approved decision remains the only hard constraint.",
            nextAction: "Review 1 shadowed background note for Decision Rail Project and confirm it stays non-binding under the approved decision.",
            occurredAt: 1
        )

        let decision = SupervisorProjectNotificationPolicy.decide(for: event)

        #expect(decision.channel == .briefCard)
        #expect(decision.recommendation.recommendationType == .decisionRailCleanup)
    }

    @MainActor
    @Test
    func managerOnlyInterruptsAuthorizationAndSuppressesDuplicates() {
        let now = Date(timeIntervalSince1970: 1_773_400_000).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        func systemMessages() -> [SupervisorMessage] {
            manager.messages.filter { $0.role == .system }
        }
        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: "p-auth", displayName: "Auth Project", role: .owner, now: now)
            .upserting(projectId: "p-blocked", displayName: "Blocked Project", role: .owner, now: now)
            .upserting(projectId: "p-created", displayName: "Created Project", role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            registry,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let blockedEntry = AXProjectEntry(
            projectId: "p-blocked",
            rootPath: "/tmp/p-blocked",
            displayName: "Blocked Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "等待 RR02 样本",
            nextStepSummary: "Run RR02",
            blockerSummary: "Missing require-real sample",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let authEntry = AXProjectEntry(
            projectId: "p-auth",
            rootPath: "/tmp/p-auth",
            displayName: "Auth Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "grant_required",
            currentStateSummary: "等待授权批准",
            nextStepSummary: "Approve paid model access",
            blockerSummary: "grant_required",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let createdEntry = AXProjectEntry(
            projectId: "p-created",
            rootPath: "/tmp/p-created",
            displayName: "Created Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        manager.handleEvent(.projectCreated(createdEntry))
        #expect(systemMessages().isEmpty)
        #expect(manager.supervisorProjectNotificationSnapshot.deliveredBadges == 1)

        manager.handleEvent(.projectUpdated(blockedEntry))
        #expect(systemMessages().isEmpty)
        #expect(manager.supervisorProjectNotificationSnapshot.deliveredBriefs == 1)

        manager.handleEvent(.projectUpdated(authEntry))
        #expect(systemMessages().count == 1)
        #expect(manager.supervisorProjectNotificationSnapshot.deliveredInterrupts == 1)

        manager.handleEvent(.projectUpdated(authEntry))
        #expect(systemMessages().count == 1)
        #expect(manager.supervisorProjectNotificationSnapshot.suppressedDuplicates == 1)
    }

    @MainActor
    @Test
    func managerPushesHubNotificationsForBriefAndInterruptOnly() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w331_notif_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try writeTestHubStatus(base: base)
        HubPaths.setBaseDirOverride(base)
        let previousTransportMode = HubAIClient.transportMode()
        HubAIClient.setTransportMode(.fileIPC)
        defer {
            HubAIClient.setTransportMode(previousTransportMode)
            HubPaths.setBaseDirOverride(nil)
            try? FileManager.default.removeItem(at: base)
        }

        let now = Date(timeIntervalSince1970: 1_773_401_000).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: "p-auth", displayName: "Auth Project", role: .owner, now: now)
            .upserting(projectId: "p-blocked", displayName: "Blocked Project", role: .owner, now: now)
            .upserting(projectId: "p-created", displayName: "Created Project", role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let createdEntry = AXProjectEntry(
            projectId: "p-created",
            rootPath: "/tmp/p-created",
            displayName: "Created Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )
        let blockedEntry = AXProjectEntry(
            projectId: "p-blocked",
            rootPath: "/tmp/p-blocked",
            displayName: "Blocked Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "等待 RR02 样本",
            nextStepSummary: "Run RR02",
            blockerSummary: "Missing require-real sample",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let authEntry = AXProjectEntry(
            projectId: "p-auth",
            rootPath: "/tmp/p-auth",
            displayName: "Auth Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "grant_required",
            currentStateSummary: "等待授权批准",
            nextStepSummary: "Approve paid model access",
            blockerSummary: "grant_required",
            lastSummaryAt: now,
            lastEventAt: now
        )

        manager.handleEvent(.projectCreated(createdEntry))
        manager.handleEvent(.projectUpdated(blockedEntry))
        manager.handleEvent(.projectUpdated(authEntry))
        manager.handleEvent(.projectUpdated(authEntry))

        let eventDir = base.appendingPathComponent("ipc_events", isDirectory: true)
        let files = try waitForNotificationFiles(in: eventDir, expectedCount: 2)
        #expect(files.count >= 2)

        let payloads = try files.map { file -> HubIPCClient.NotificationIPCRequest in
            let data = try Data(contentsOf: file)
            return try JSONDecoder().decode(HubIPCClient.NotificationIPCRequest.self, from: data)
        }

        let titles = payloads.map(\.notification.title)
        #expect(titles.contains("项目阻塞：Blocked Project"))
        #expect(titles.filter { $0 == "项目阻塞：Blocked Project" }.count == 1)
        #expect(titles.contains("项目待授权：Auth Project"))
        #expect(titles.filter { $0 == "项目待授权：Auth Project" }.count == 1)
        #expect(!titles.contains("新增项目：Created Project"))
    }

    private func waitForNotificationFiles(in eventDir: URL, expectedCount: Int) throws -> [URL] {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            let files = (try? FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil))?
                .filter(isNotificationEventFile(_:))
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            if files.count >= expectedCount {
                return files
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        return try FileManager.default.contentsOfDirectory(at: eventDir, includingPropertiesForKeys: nil)
            .filter(isNotificationEventFile(_:))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isNotificationEventFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix("xterminal_notify_") && !name.hasPrefix("xterminal_notify_remove_")
    }
}
