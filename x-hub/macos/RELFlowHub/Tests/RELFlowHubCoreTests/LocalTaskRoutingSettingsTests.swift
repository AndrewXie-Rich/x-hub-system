import XCTest
@testable import RELFlowHubCore

final class LocalTaskRoutingSettingsTests: XCTestCase {
    func testSchemaV2DecodesHubDefaultsAndDeviceOverrides() throws {
        let json = """
        {
          "type": "routing_settings",
          "schemaVersion": "xhub.routing_settings.v2",
          "updatedAt": 1741850000.0,
          "hubDefaultModelIdByTaskKind": {
            "text_generate": "mlx-qwen",
            "embedding": "hf-embed"
          },
          "devicePreferredModelIdByTaskKind": {
            "terminal_device": {
              "embedding": "hf-embed-device"
            }
          }
        }
        """

        let settings = try JSONDecoder().decode(LocalTaskRoutingSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.schemaVersion, LocalTaskRoutingSettings.schemaVersionV2)
        XCTAssertEqual(settings.preferredModelIdByTask["embedding"], "hf-embed")
        XCTAssertEqual(settings.devicePreferredModelIdByTaskKind["terminal_device"]?["embedding"], "hf-embed-device")

        let deviceResolved = settings.resolvedModelId(taskKind: "embedding", deviceId: "terminal_device")
        XCTAssertEqual(deviceResolved.modelId, "hf-embed-device")
        XCTAssertEqual(deviceResolved.source, "device_override")

        let hubResolved = settings.resolvedModelId(taskKind: "text_generate", deviceId: "terminal_device")
        XCTAssertEqual(hubResolved.modelId, "mlx-qwen")
        XCTAssertEqual(hubResolved.source, "hub_default")
    }

    func testLegacyPreferredModelMapStaysBackwardCompatible() throws {
        let json = """
        {
          "preferredModelIdByTask": {
            "summarize": "mlx-summary"
          }
        }
        """

        let settings = try JSONDecoder().decode(LocalTaskRoutingSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.preferredModelIdByTask["summarize"], "mlx-summary")

        let resolved = settings.resolvedModelId(taskKind: "summarize")
        XCTAssertEqual(resolved.modelId, "mlx-summary")
        XCTAssertEqual(resolved.source, "hub_default")
    }

    func testSetModelIdNormalizesTaskKindsAndPrunesEmptyOverrides() {
        var settings = LocalTaskRoutingSettings()
        settings.setModelId("hf-embed", for: "Embedding")
        settings.setModelId("hf-embed-device", for: "Embedding", deviceId: "Terminal_Device")
        settings.setModelId(nil, for: "Embedding", deviceId: "Terminal_Device")

        XCTAssertEqual(settings.preferredModelIdByTask["embedding"], "hf-embed")
        XCTAssertNil(settings.devicePreferredModelIdByTaskKind["terminal_device"])
    }
}
