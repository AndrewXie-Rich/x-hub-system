import XCTest
@testable import RELFlowHub
import RELFlowHubCore

@MainActor
final class LocalModelHealthScannerTests: XCTestCase {
    func testScanMarksBlockedReadinessWhenPreflightFails() async {
        let model = makeModel(id: "mlx/qwen")

        let record = await LocalModelHealthScanner.scan(
            model: model,
            readinessResolver: { _ in .unavailable("缺少本地运行时配置。") },
            trialRunner: { _ in
                XCTFail("trialRunner should not run when readiness fails")
                return ""
            }
        )

        XCTAssertEqual(record.state, .blockedReadiness)
        XCTAssertEqual(record.detail, "缺少本地运行时配置。")
        XCTAssertNil(record.lastSuccessAt)
    }

    func testScanMarksHealthyWhenSmokeTrialSucceeds() async {
        let model = makeModel(id: "mlx/qwen")

        let record = await LocalModelHealthScanner.scan(
            model: model,
            readinessResolver: { _ in .ready("已导入，可用于 Hub 本地执行。") },
            trialRunner: { _ in "Response OK" }
        )

        XCTAssertEqual(record.state, .healthy)
        XCTAssertTrue(record.detail.contains("轻量扫描通过。") == true)
        XCTAssertNotNil(record.lastSuccessAt)
    }

    func testPreflightOnlyUsesDegradedWhenNoHealthyHistoryExists() async {
        let model = makeModel(id: "mlx/phi")

        let record = await LocalModelHealthScanner.scan(
            model: model,
            mode: .preflightOnly,
            readinessResolver: { _ in .ready("已导入，可用于 Hub 本地执行。") },
            trialRunner: { _ in
                XCTFail("trialRunner should not run in preflight-only mode")
                return ""
            }
        )

        XCTAssertEqual(record.state, .degraded)
        XCTAssertEqual(record.detail, HubUIStrings.Models.LocalHealth.preflightPassedDetail)
    }

    func testPreflightOnlyKeepsHealthyWhenRecentHealthyHistoryExists() async {
        let model = makeModel(id: "mlx/phi")
        let previous = LocalModelHealthRecord(
            modelId: model.id,
            providerID: model.backend,
            state: .healthy,
            summary: "ok",
            detail: "ok",
            lastCheckedAt: Date().timeIntervalSince1970 - 120,
            lastSuccessAt: Date().timeIntervalSince1970 - 120
        )

        let record = await LocalModelHealthScanner.scan(
            model: model,
            mode: .preflightOnly,
            previous: previous,
            readinessResolver: { _ in .ready("已导入，可用于 Hub 本地执行。") },
            trialRunner: { _ in
                XCTFail("trialRunner should not run in preflight-only mode")
                return ""
            }
        )

        XCTAssertEqual(record.state, .healthy)
        XCTAssertEqual(record.detail, HubUIStrings.Models.LocalHealth.preflightPassedDetail)
        XCTAssertEqual(record.lastSuccessAt, previous.lastSuccessAt)
    }

    func testScanMarksBlockedRuntimeWhenSmokeTrialFails() async {
        let model = makeModel(id: "llama.cpp/coder")

        let record = await LocalModelHealthScanner.scan(
            model: model,
            readinessResolver: { _ in .ready("已导入，可用于 Hub 本地执行。") },
            trialRunner: { _ in
                throw NSError(
                    domain: "relflowhub",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "provider runtime unavailable"]
                )
            }
        )

        XCTAssertEqual(record.state, .blockedRuntime)
        XCTAssertEqual(record.detail, "provider runtime unavailable")
    }

    private func makeModel(id: String) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: "mlx",
            quant: "Q4_K_M",
            contextLength: 8192,
            paramsB: 7.0,
            state: .available,
            modelPath: "/tmp/\(id.replacingOccurrences(of: "/", with: "_"))"
        )
    }
}
