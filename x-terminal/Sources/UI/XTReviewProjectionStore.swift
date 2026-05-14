import Combine
import Foundation

struct XTReviewSurfaceSnapshot: Equatable {
    var grants: [SupervisorManager.SupervisorPendingGrant]
    var approvals: [SupervisorManager.SupervisorPendingSkillApproval]
    var candidateReviews: [HubIPCClient.SupervisorCandidateReviewItem]
    var candidateProjectNamesByID: [String: String]

    static let empty = XTReviewSurfaceSnapshot(
        grants: [],
        approvals: [],
        candidateReviews: [],
        candidateProjectNamesByID: [:]
    )

    @MainActor
    static func make(from supervisor: SupervisorManager) -> XTReviewSurfaceSnapshot {
        XTReviewSurfaceSnapshot(
            grants: supervisor.frontstagePendingHubGrants,
            approvals: supervisor.frontstagePendingSupervisorSkillApprovals,
            candidateReviews: supervisor.frontstageSupervisorCandidateReviews,
            candidateProjectNamesByID: supervisor.frontstageSupervisorCandidateReviewProjectNames
        )
    }
}

@MainActor
final class XTReviewProjectionStore: ObservableObject {
    @Published private(set) var snapshot: XTReviewSurfaceSnapshot

    private let minimumUpdateIntervalNanoseconds: UInt64
    private weak var boundSupervisor: SupervisorManager?
    private weak var boundAppModel: AppModel?
    private var cancellables: Set<AnyCancellable> = []
    private var updateScheduled = false
    private var lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds

    init(
        snapshot: XTReviewSurfaceSnapshot = .empty,
        minimumUpdateIntervalNanoseconds: UInt64 = 0
    ) {
        self.snapshot = snapshot
        self.minimumUpdateIntervalNanoseconds = minimumUpdateIntervalNanoseconds
    }

    func bind(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) {
        if boundSupervisor === supervisor,
           boundAppModel === appModel {
            update(from: supervisor)
            return
        }

        cancellables.removeAll()
        boundSupervisor = supervisor
        boundAppModel = appModel
        updateScheduled = false
        update(from: supervisor)

        observe(supervisor.$pendingHubGrants, supervisor: supervisor)
        observe(supervisor.$pendingSupervisorSkillApprovals, supervisor: supervisor)
        observe(supervisor.$supervisorCandidateReviews, supervisor: supervisor)
        observe(supervisor.$supervisorJurisdictionRegistry, supervisor: supervisor)
        observe(appModel.$registry, supervisor: supervisor)
    }

    func unbind(resetSnapshot: Bool = true) {
        cancellables.removeAll()
        boundSupervisor = nil
        boundAppModel = nil
        updateScheduled = false
        if resetSnapshot, snapshot != .empty {
            snapshot = .empty
        }
    }

    private func observe<P: Publisher>(
        _ publisher: P,
        supervisor: SupervisorManager
    ) where P.Failure == Never {
        publisher
            .dropFirst()
            .sink { [weak self, weak supervisor] _ in
                guard let self, let supervisor else { return }
                self.scheduleUpdate(from: supervisor)
            }
            .store(in: &cancellables)
    }

    private func update(from supervisor: SupervisorManager) {
        let nextSnapshot = XTReviewSurfaceSnapshot.make(from: supervisor)
        guard snapshot != nextSnapshot else { return }
        lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(from supervisor: SupervisorManager) {
        guard !updateScheduled else { return }
        updateScheduled = true
        let delayNanoseconds = nextUpdateDelayNanoseconds()
        Task { @MainActor [weak self, weak supervisor] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self else { return }
            self.updateScheduled = false
            guard let supervisor,
                  self.boundSupervisor === supervisor else {
                return
            }
            self.update(from: supervisor)
        }
    }

    private func nextUpdateDelayNanoseconds() -> UInt64 {
        guard minimumUpdateIntervalNanoseconds > 0 else { return 0 }
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= lastUpdateNanoseconds
            ? now - lastUpdateNanoseconds
            : minimumUpdateIntervalNanoseconds
        guard elapsed < minimumUpdateIntervalNanoseconds else { return 0 }
        return minimumUpdateIntervalNanoseconds - elapsed
    }
}
