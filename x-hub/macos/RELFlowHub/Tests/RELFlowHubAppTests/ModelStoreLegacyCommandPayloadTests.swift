import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class ModelStoreLegacyCommandPayloadTests: XCTestCase {
    func testUnloadCommandDropsRouteSpecificTargeting() {
        let payload = ModelStore.legacyModelCommandPayload(
            action: "unload",
            requestContext: makeRequestContext(),
            baseCommand: baseCommand(action: "unload")
        )

        XCTAssertEqual(payload["action"] as? String, "unload")
        XCTAssertEqual(payload["model_id"] as? String, "mlx-qwen")
        XCTAssertNil(payload["device_id"])
        XCTAssertNil(payload["instance_key"])
        XCTAssertNil(payload["load_profile_hash"])
        XCTAssertNil(payload["load_config_hash"])
        XCTAssertNil(payload["effective_context_length"])
        XCTAssertNil(payload["current_context_length"])
        XCTAssertNil(payload["load_profile_override"])
    }

    func testLoadCommandKeepsRouteSpecificTargeting() {
        let payload = ModelStore.legacyModelCommandPayload(
            action: "load",
            requestContext: makeRequestContext(),
            baseCommand: baseCommand(action: "load")
        )

        XCTAssertEqual(payload["device_id"] as? String, "terminal_device")
        XCTAssertEqual(payload["instance_key"] as? String, "mlx:mlx-qwen:hash-a")
        XCTAssertEqual(payload["load_profile_hash"] as? String, "hash-a")
        XCTAssertEqual(payload["load_config_hash"] as? String, "hash-a")
        XCTAssertEqual(payload["effective_context_length"] as? Int, 24576)
        XCTAssertEqual(payload["current_context_length"] as? Int, 24576)
        XCTAssertEqual(
            (payload["load_profile_override"] as? [String: Any])?["context_length"] as? Int,
            24576
        )
    }

    private func makeRequestContext() -> LocalModelRuntimeRequestContext {
        LocalModelRuntimeRequestContext(
            providerID: "mlx",
            modelID: "mlx-qwen",
            deviceID: "terminal_device",
            instanceKey: "mlx:mlx-qwen:hash-a",
            loadProfileHash: "hash-a",
            predictedLoadProfileHash: "hash-a",
            effectiveContextLength: 24576,
            loadProfileOverride: LocalModelLoadProfileOverride(
                contextLength: 24576
            ),
            source: "loaded_instance"
        )
    }

    private func baseCommand(action: String) -> [String: Any] {
        [
            "type": "model_command",
            "req_id": "req-1",
            "action": action,
            "model_id": "mlx-qwen",
            "requested_at": 1.0,
        ]
    }
}
