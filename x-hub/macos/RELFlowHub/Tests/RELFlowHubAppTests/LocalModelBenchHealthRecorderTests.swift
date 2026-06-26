import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalModelBenchHealthRecorderTests: XCTestCase {
    func testSuccessfulBenchPromotesModelHealthToHealthy() {
        let result = ModelBenchResult(
            modelId: "qwen-coder",
            providerID: "transformers",
            taskKind: "text_generate",
            fixtureProfile: "default",
            measuredAt: 1_000,
            ok: true,
            verdict: "pass",
            notes: ["response ok"]
        )

        let snapshot = LocalModelBenchHealthRecorder.updatedSnapshot(
            after: result,
            previous: .empty(),
            model: makeModel(),
            detail: "Bench OK",
            now: 1_001
        )

        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.modelId, "qwen-coder")
        XCTAssertEqual(snapshot.records.first?.providerID, "transformers")
        XCTAssertEqual(snapshot.records.first?.state, .healthy)
        XCTAssertEqual(snapshot.records.first?.summary, HubUIStrings.Models.LocalHealth.recommendedBadge)
        XCTAssertEqual(snapshot.records.first?.lastCheckedAt, 1_000)
        XCTAssertEqual(snapshot.records.first?.lastSuccessAt, 1_000)
        XCTAssertTrue(snapshot.records.first?.detail.contains("轻量扫描通过") == true)
    }

    func testFailedBenchPreservesPreviousSuccessAndBlocksRuntime() {
        let previous = LocalModelHealthRecord(
            modelId: "qwen-coder",
            providerID: "transformers",
            state: .healthy,
            summary: "",
            detail: "previous ok",
            lastCheckedAt: 900,
            lastSuccessAt: 900
        )
        let result = ModelBenchResult(
            modelId: "qwen-coder",
            providerID: "transformers",
            taskKind: "text_generate",
            fixtureProfile: "default",
            measuredAt: 1_000,
            ok: false,
            reasonCode: "runtime_command_failed",
            notes: ["mlx provider 当前不可用"]
        )

        let snapshot = LocalModelBenchHealthRecorder.updatedSnapshot(
            after: result,
            previous: LocalModelHealthSnapshot(records: [previous], updatedAt: 900),
            model: makeModel(),
            detail: "mlx provider 当前不可用",
            now: 1_001
        )

        XCTAssertEqual(snapshot.records.first?.state, .blockedRuntime)
        XCTAssertEqual(snapshot.records.first?.summary, HubUIStrings.Models.LocalHealth.discouragedBadge)
        XCTAssertEqual(snapshot.records.first?.lastSuccessAt, 900)
        XCTAssertEqual(snapshot.records.first?.detail, "mlx provider 当前不可用")
    }

    func testOlderBenchDoesNotOverwriteNewerHealth() {
        let previous = LocalModelHealthRecord(
            modelId: "qwen-coder",
            providerID: "transformers",
            state: .healthy,
            summary: "",
            detail: "newer ok",
            lastCheckedAt: 2_000,
            lastSuccessAt: 2_000
        )
        let result = ModelBenchResult(
            modelId: "qwen-coder",
            providerID: "transformers",
            taskKind: "text_generate",
            fixtureProfile: "default",
            measuredAt: 1_000,
            ok: false,
            reasonCode: "runtime_command_failed"
        )

        let snapshot = LocalModelBenchHealthRecorder.updatedSnapshot(
            after: result,
            previous: LocalModelHealthSnapshot(records: [previous], updatedAt: 2_000),
            model: makeModel(),
            detail: "old failure",
            now: 2_100
        )

        XCTAssertEqual(snapshot.records, [previous])
    }

    private func makeModel() -> HubModel {
        HubModel(
            id: "qwen-coder",
            name: "Qwen Coder",
            backend: "transformers",
            quant: "bf16",
            contextLength: 4096,
            paramsB: 7.0,
            state: .available,
            modelPath: "/tmp/qwen-coder",
            taskKinds: ["text_generate"]
        )
    }
}
