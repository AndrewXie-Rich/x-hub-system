import Foundation
import RELFlowHubCore

extension SettingsSheetView {
    func refreshRustHubRuntimeSnapshot(force: Bool = false) {
        let now = Date()
        if rustHubRuntimeRefreshing { return }
        if !force && now.timeIntervalSince(rustHubRuntimeLastRefreshAt) < 10.0 { return }
        rustHubRuntimeRefreshing = true
        Task {
            let snapshot = await RustHubRuntimeSupport.loadSnapshot()
            await MainActor.run {
                rustHubRuntimeSnapshot = snapshot
                rustHubRuntimeLastRefreshAt = Date()
                rustHubRuntimeRefreshing = false
            }
        }
    }

    func refreshRustLocalMLExecutionReadiness(force: Bool = false) {
        let now = Date()
        if rustLocalMLExecutionReadinessRefreshing { return }
        if !force && now.timeIntervalSince(rustLocalMLExecutionReadinessLastRefreshAt) < 10.0 { return }
        rustLocalMLExecutionReadinessRefreshing = true
        Task {
            let snapshot = await RustHubRuntimeSupport.loadLocalMLExecutionReadiness()
            await MainActor.run {
                rustLocalMLExecutionReadinessSnapshot = snapshot
                rustLocalMLExecutionReadinessLastRefreshAt = Date()
                rustLocalMLExecutionReadinessRefreshing = false
            }
        }
    }

    func refreshRustLocalModelRepairPlan(force: Bool = false) {
        let now = Date()
        if rustLocalModelRepairPlanRefreshing { return }
        if !force && now.timeIntervalSince(rustLocalModelRepairPlanLastRefreshAt) < 10.0 { return }
        rustLocalModelRepairPlanRefreshing = true
        Task {
            let plan = await RustHubRuntimeSupport.loadLocalModelRepairPlan()
            await MainActor.run {
                rustLocalModelRepairPlan = plan
                rustLocalModelRepairPlanLastRefreshAt = Date()
                rustLocalModelRepairPlanRefreshing = false
            }
        }
    }

    func refreshRustLocalModelRepairJobs(force: Bool = false) {
        let now = Date()
        if rustLocalModelRepairJobsRefreshing { return }
        if !force && now.timeIntervalSince(rustLocalModelRepairJobsLastRefreshAt) < 5.0 { return }
        rustLocalModelRepairJobsRefreshing = true
        Task {
            let snapshot = await RustHubRuntimeSupport.loadLocalModelRepairJobs()
            await MainActor.run {
                rustLocalModelRepairJobsSnapshot = snapshot
                rustLocalModelRepairJobsLastRefreshAt = Date()
                rustLocalModelRepairJobsRefreshing = false
            }
        }
    }

    func presentRustLocalModelRepairApplyDialog() {
        guard !rustLocalModelRepairApplyInFlight,
              let plan = rustLocalModelRepairPlan,
              plan.isActionableRepair else {
            return
        }
        rustLocalModelRepairApplyPendingPlan = plan
        rustLocalModelRepairApplyErrorText = ""
        rustLocalModelRepairApplyDialogPresented = true
    }

    func applyRustLocalModelRepair(_ plan: RustLocalModelRepairPlan) {
        guard !rustLocalModelRepairApplyInFlight else { return }
        rustLocalModelRepairApplyInFlight = true
        rustLocalModelRepairApplyErrorText = ""
        rustLocalModelRepairApplyResult = nil
        rustLocalModelRepairExecutorResult = nil
        rustLocalModelRepairApplyDialogPresented = false
        Task {
            let result = await RustHubRuntimeSupport.applyLocalModelRepair(plan: plan)
            await MainActor.run {
                rustLocalModelRepairApplyInFlight = false
                rustLocalModelRepairApplyPendingPlan = nil
                if let result {
                    rustLocalModelRepairApplyResult = result
                    if result.accepted {
                        refreshRustLocalModelRepairPlan(force: true)
                        refreshRustLocalModelRepairJobs(force: true)
                        refreshRustHubRuntimeSnapshot(force: true)
                        startRustLocalModelRepairExecutor()
                    }
                } else {
                    rustLocalModelRepairApplyErrorText = HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairApplyFailed
                }
            }
        }
    }

    private func startRustLocalModelRepairExecutor() {
        guard !rustLocalModelRepairExecutorInFlight else { return }
        rustLocalModelRepairExecutorInFlight = true
        Task {
            let result = await RustHubRuntimeSupport.runLocalModelRepairExecutor()
            await MainActor.run {
                rustLocalModelRepairExecutorInFlight = false
                if let result {
                    rustLocalModelRepairExecutorResult = result
                } else {
                    rustLocalModelRepairApplyErrorText = HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairExecutorFailed
                }
                refreshRustLocalModelRepairPlan(force: true)
                refreshRustLocalModelRepairJobs(force: true)
                refreshRustHubRuntimeSnapshot(force: true)
            }
        }
    }

    func refreshRustHubRemoteEntryCandidates(force: Bool = false) {
        let now = Date()
        if rustHubRemoteEntryRefreshing { return }
        if !force && now.timeIntervalSince(rustHubRemoteEntryLastRefreshAt) < 10.0 { return }
        rustHubRemoteEntryRefreshing = true
        Task {
            let candidates = await RustHubRuntimeSupport.loadRemoteEntryCandidates()
            await MainActor.run {
                rustHubRemoteEntryCandidates = candidates
                rustHubRemoteEntryLastRefreshAt = Date()
                rustHubRemoteEntryRefreshing = false
            }
        }
    }

}
