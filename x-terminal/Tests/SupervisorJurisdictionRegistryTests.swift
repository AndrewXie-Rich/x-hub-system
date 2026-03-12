import Foundation
import Testing
@testable import XTerminal

struct SupervisorJurisdictionRegistryTests {
    @Test
    func registryNormalizesKnownProjectsWithOwnerDefault() {
        let now = Date(timeIntervalSince1970: 1_773_300_000).timeIntervalSince1970
        let projects = [
            AXProjectEntry(
                projectId: "p1",
                rootPath: "/tmp/p1",
                displayName: "Project One",
                lastOpenedAt: now,
                manualOrderIndex: nil,
                pinned: false,
                statusDigest: nil,
                currentStateSummary: "进行中",
                nextStepSummary: "继续推进",
                blockerSummary: nil,
                lastSummaryAt: now,
                lastEventAt: now
            ),
            AXProjectEntry(
                projectId: "p2",
                rootPath: "/tmp/p2",
                displayName: "Project Two",
                lastOpenedAt: now,
                manualOrderIndex: nil,
                pinned: false,
                statusDigest: nil,
                currentStateSummary: "阻塞中",
                nextStepSummary: "等待修复",
                blockerSummary: "compile blocked",
                lastSummaryAt: now,
                lastEventAt: now
            ),
        ]

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now).normalized(for: projects, now: now)

        #expect(registry.entries.count == 2)
        #expect(registry.role(for: "p1") == .owner)
        #expect(registry.role(for: "p2") == .owner)
        #expect(registry.summaryLine.contains("owner=2"))
    }

    @Test
    func triageOnlyVisibilityKeepsOnlyCriticalProjectsAndEvents() {
        let now = Date(timeIntervalSince1970: 1_773_300_100).timeIntervalSince1970
        let activeDigest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-active",
            displayName: "Active Project",
            runtimeState: "进行中",
            source: "registry_summary",
            goal: "Ship",
            currentState: "Implementing feature",
            nextStep: "Run tests",
            blocker: "(无)",
            updatedAt: now,
            recentMessageCount: 2
        )
        let blockedDigest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-blocked",
            displayName: "Blocked Project",
            runtimeState: "阻塞中",
            source: "registry_summary",
            goal: "Ship",
            currentState: "等待修复",
            nextStep: "Fix compile failure",
            blocker: "compile blocked",
            updatedAt: now,
            recentMessageCount: 4
        )
        let progressedEvent = SupervisorProjectActionEvent(
            eventId: "evt-progress",
            projectId: "p-active",
            projectName: "Active Project",
            eventType: .progressed,
            severity: .silentLog,
            actionTitle: "项目推进：Active Project",
            actionSummary: "Implementing feature",
            whyItMatters: "keep track",
            nextAction: "Run tests",
            occurredAt: now
        )
        let blockedEvent = SupervisorProjectActionEvent(
            eventId: "evt-blocked",
            projectId: "p-blocked",
            projectName: "Blocked Project",
            eventType: .blocked,
            severity: .briefCard,
            actionTitle: "项目阻塞：Blocked Project",
            actionSummary: "compile blocked",
            whyItMatters: "needs triage",
            nextAction: "Fix compile failure",
            occurredAt: now
        )

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: "p-active", displayName: "Active Project", role: .triageOnly, now: now)
            .upserting(projectId: "p-blocked", displayName: "Blocked Project", role: .triageOnly, now: now)

        let visibleDigests = registry.filteredDigests([activeDigest, blockedDigest])
        let visibleEvents = registry.filteredEvents([progressedEvent, blockedEvent])

        #expect(visibleDigests.count == 1)
        #expect(visibleDigests.first?.projectId == "p-blocked")
        #expect(visibleEvents.count == 1)
        #expect(visibleEvents.first?.projectId == "p-blocked")
    }

    @Test
    func observerAndTriageOnlyCannotEscalateDrillDownScope() {
        let now = Date(timeIntervalSince1970: 1_773_300_200).timeIntervalSince1970
        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: "p-owner", displayName: "Owner", role: .owner, now: now)
            .upserting(projectId: "p-observer", displayName: "Observer", role: .observer, now: now)
            .upserting(projectId: "p-triage", displayName: "Triage", role: .triageOnly, now: now)

        #expect(registry.allowsDrillDown(projectId: "p-owner", requestedScope: .capsulePlusRecent))
        #expect(!registry.allowsDrillDown(projectId: "p-owner", requestedScope: .rawEvidence))
        #expect(registry.allowsDrillDown(projectId: "p-observer", requestedScope: .capsuleOnly))
        #expect(!registry.allowsDrillDown(projectId: "p-observer", requestedScope: .capsulePlusRecent))
        #expect(registry.allowsDrillDown(projectId: "p-triage", requestedScope: .capsuleOnly))
        #expect(!registry.allowsDrillDown(projectId: "p-triage", requestedScope: .capsulePlusRecent))
    }

    @MainActor
    @Test
    func supervisorManagerAppliesJurisdictionWhenReceivingProjectEvents() {
        let now = Date(timeIntervalSince1970: 1_773_300_300).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: "p-active", displayName: "Active Project", role: .triageOnly, now: now)
            .upserting(projectId: "p-blocked", displayName: "Blocked Project", role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            registry,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let activeEntry = AXProjectEntry(
            projectId: "p-active",
            rootPath: "/tmp/p-active",
            displayName: "Active Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "implementing",
            currentStateSummary: "Implementing feature",
            nextStepSummary: "Run tests",
            blockerSummary: "(无)",
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
            currentStateSummary: "等待修复",
            nextStepSummary: "Fix compile failure",
            blockerSummary: "compile blocked",
            lastSummaryAt: now,
            lastEventAt: now
        )

        manager.handleEvent(.projectUpdated(activeEntry))
        #expect(manager.supervisorRecentProjectActionEvents.isEmpty)

        manager.handleEvent(.projectUpdated(blockedEntry))
        #expect(manager.supervisorRecentProjectActionEvents.count == 1)
        #expect(manager.supervisorRecentProjectActionEvents.first?.projectId == "p-blocked")
        #expect(manager.supervisorRecentProjectActionEvents.first?.eventType == .blocked)
    }
}
