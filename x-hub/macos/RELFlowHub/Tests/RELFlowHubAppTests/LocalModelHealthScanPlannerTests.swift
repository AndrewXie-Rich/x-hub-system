import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalModelHealthScanPlannerTests: XCTestCase {
    func testBulkFullScanUsesFullTrialsForLoadedRoutedAndRecentHealthyModels() {
        let now = Date().timeIntervalSince1970
        let loaded = makeModel(id: "loaded", state: .loaded)
        let translate = makeModel(id: "translate", roles: ["translate"])
        let summarize = makeModel(id: "summarize", roles: ["summarize"])
        let recentHealthy = makeModel(id: "recent")
        let other = makeModel(id: "other")
        let jobs = LocalModelHealthScanPlanner.jobs(
            for: [loaded, translate, summarize, recentHealthy, other],
            requestedMode: .full,
            explicitlyLimited: false,
            healthByModelID: [
                recentHealthy.id: LocalModelHealthRecord(
                    modelId: recentHealthy.id,
                    providerID: "mlx",
                    state: .healthy,
                    summary: "ok",
                    detail: "ok",
                    lastCheckedAt: now - 300,
                    lastSuccessAt: now - 300
                )
            ],
            preferredModelIDByTask: [
                HubTaskType.translate.rawValue: translate.id,
                HubTaskType.summarize.rawValue: summarize.id,
            ],
            requestedTrialStatusUpdates: true,
            now: now
        )

        XCTAssertEqual(jobMode(in: jobs, modelID: loaded.id), .full)
        XCTAssertEqual(jobMode(in: jobs, modelID: translate.id), .full)
        XCTAssertEqual(jobMode(in: jobs, modelID: summarize.id), .full)
        XCTAssertEqual(jobMode(in: jobs, modelID: recentHealthy.id), .full)
        XCTAssertEqual(jobMode(in: jobs, modelID: other.id), .preflightOnly)
        XCTAssertTrue(jobUpdatesTrialStatus(in: jobs, modelID: loaded.id))
        XCTAssertFalse(jobUpdatesTrialStatus(in: jobs, modelID: other.id))
    }

    func testExplicitFullSelectionKeepsEverySelectedModelOnFullTrial() {
        let models = [
            makeModel(id: "a"),
            makeModel(id: "b"),
            makeModel(id: "c"),
        ]
        let jobs = LocalModelHealthScanPlanner.jobs(
            for: models,
            requestedMode: .full,
            explicitlyLimited: true,
            healthByModelID: [:],
            preferredModelIDByTask: [:],
            requestedTrialStatusUpdates: true
        )

        XCTAssertEqual(jobs.map(\.mode), [.full, .full, .full])
        XCTAssertEqual(jobs.map(\.updatesTrialStatus), [true, true, true])
    }

    func testPreflightRequestNeverPromotesToFullTrial() {
        let jobs = LocalModelHealthScanPlanner.jobs(
            for: [makeModel(id: "a"), makeModel(id: "b")],
            requestedMode: .preflightOnly,
            explicitlyLimited: false,
            healthByModelID: [:],
            preferredModelIDByTask: [:],
            requestedTrialStatusUpdates: false
        )

        XCTAssertEqual(jobs.map(\.mode), [.preflightOnly, .preflightOnly])
        XCTAssertEqual(jobs.map(\.updatesTrialStatus), [false, false])
    }

    private func jobMode(in jobs: [LocalModelHealthScanJob], modelID: String) -> LocalModelHealthScanMode? {
        jobs.first(where: { $0.model.id == modelID })?.mode
    }

    private func jobUpdatesTrialStatus(in jobs: [LocalModelHealthScanJob], modelID: String) -> Bool {
        jobs.first(where: { $0.model.id == modelID })?.updatesTrialStatus ?? false
    }

    private func makeModel(
        id: String,
        roles: [String]? = nil,
        state: HubModelState = .available
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: "mlx",
            quant: "Q4_K_M",
            contextLength: 8192,
            paramsB: 7.0,
            roles: roles,
            state: state,
            modelPath: "/tmp/\(id)"
        )
    }
}
