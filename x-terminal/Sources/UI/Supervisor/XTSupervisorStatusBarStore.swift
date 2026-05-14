import Combine
import Foundation

struct XTSupervisorStatusBarSnapshot: Equatable {
    var executionSnapshot: AXRoleExecutionSnapshot
    var pendingMemoryFollowUpQuestion: String
    var activeProjectCount: Int
    var totalProjectCount: Int
    var pendingWorkCount: Int
    var blockedProjectCount: Int
    var completedProjectCount: Int

    static let empty = XTSupervisorStatusBarSnapshot(
        executionSnapshot: .empty(role: .supervisor, source: "supervisor_status_bar"),
        pendingMemoryFollowUpQuestion: "",
        activeProjectCount: 0,
        totalProjectCount: 0,
        pendingWorkCount: 0,
        blockedProjectCount: 0,
        completedProjectCount: 0
    )
}

@MainActor
final class XTSupervisorStatusBarStore: ObservableObject {
    @Published private(set) var snapshot: XTSupervisorStatusBarSnapshot

    private weak var boundSupervisor: SupervisorManager?
    private var cancellables: Set<AnyCancellable> = []

    init(snapshot: XTSupervisorStatusBarSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func bind(to supervisor: SupervisorManager) {
        if boundSupervisor === supervisor {
            update(from: supervisor)
            return
        }

        cancellables.removeAll()
        boundSupervisor = supervisor
        update(from: supervisor)

        supervisor.$lastSupervisorReplyExecutionMode
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$lastSupervisorRequestedModelId
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$lastSupervisorActualModelId
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$lastSupervisorRemoteFailureReasonCode
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$supervisorPendingMemoryFactFollowUpQuestion
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$supervisorPortfolioSnapshot
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$pendingHubGrants
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$pendingSupervisorSkillApprovals
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$supervisorCandidateReviews
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
        supervisor.$supervisorJurisdictionRegistry
            .sink { [weak self, weak supervisor] _ in self?.scheduleUpdate(from: supervisor) }
            .store(in: &cancellables)
    }

    func isBound(to supervisor: SupervisorManager) -> Bool {
        boundSupervisor === supervisor
    }

    private func update(from supervisor: SupervisorManager) {
        let portfolio = supervisor.supervisorPortfolioSnapshot
        let actionability = portfolio.actionabilitySnapshot()
        let livePending = supervisor.frontstagePendingHubGrants.count +
            supervisor.frontstagePendingSupervisorSkillApprovals.count +
            supervisor.frontstageSupervisorCandidateReviews.count
        let nextSnapshot = XTSupervisorStatusBarSnapshot(
            executionSnapshot: Self.executionSnapshot(from: supervisor),
            pendingMemoryFollowUpQuestion: supervisor.supervisorPendingMemoryFactFollowUpQuestion
                .trimmingCharacters(in: .whitespacesAndNewlines),
            activeProjectCount: portfolio.counts.active,
            totalProjectCount: portfolio.projects.count,
            pendingWorkCount: max(portfolio.counts.awaitingAuthorization, livePending),
            blockedProjectCount: max(portfolio.counts.blocked, actionability.decisionBlockerProjectsCount),
            completedProjectCount: portfolio.counts.completed
        )
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(from supervisor: SupervisorManager?) {
        Task { @MainActor [weak self, weak supervisor] in
            guard let supervisor else { return }
            self?.update(from: supervisor)
        }
    }

    private static func executionSnapshot(from supervisor: SupervisorManager) -> AXRoleExecutionSnapshot {
        let mode = supervisor.lastSupervisorReplyExecutionMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let executionPath: String
        switch mode {
        case "remote_model":
            executionPath = "remote_model"
        case "hub_downgraded_to_local":
            executionPath = "hub_downgraded_to_local"
        case "local_fallback_after_remote_error":
            executionPath = "local_fallback_after_remote_error"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            executionPath = mode
        default:
            executionPath = "no_record"
        }

        let runtimeProvider: String
        switch executionPath {
        case "remote_model":
            runtimeProvider = "Hub (Remote)"
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            runtimeProvider = "Hub (Local)"
        default:
            runtimeProvider = ""
        }

        return AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: executionPath == "no_record" ? 0 : 1,
            stage: "supervisor",
            requestedModelId: supervisor.lastSupervisorRequestedModelId,
            actualModelId: supervisor.lastSupervisorActualModelId,
            runtimeProvider: runtimeProvider,
            executionPath: executionPath,
            fallbackReasonCode: supervisor.lastSupervisorRemoteFailureReasonCode,
            source: "supervisor_status_bar_projection"
        )
    }
}
