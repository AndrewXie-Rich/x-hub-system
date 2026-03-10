import Testing
@testable import XTerminal

struct ToolExecutorMemorySnapshotTests {

    @Test
    func renderMemorySnapshotOutputEmitsMachineReadableHeader() {
        let response = HubIPCClient.MemoryContextResponsePayload(
            text: "[MEMORY_V1]\n[L1_CANONICAL]\nKeep release scope frozen.\n[/L1_CANONICAL]\n[/MEMORY_V1]",
            source: "hub_remote_snapshot",
            budgetTotalTokens: 1600,
            usedTotalTokens: 120,
            layerUsage: [
                HubIPCClient.MemoryContextLayerUsage(layer: "l1_canonical", usedTokens: 60, budgetTokens: 400),
                HubIPCClient.MemoryContextLayerUsage(layer: "l3_working_set", usedTokens: 60, budgetTokens: 500),
            ],
            truncatedLayers: ["l4_raw_evidence"],
            redactedItems: 1,
            privateDrops: 2
        )

        let output = ToolExecutor.renderMemorySnapshotOutput(
            response: response,
            projectId: "project-memory",
            mode: "project"
        )

        let summary = toolSummaryObject(output)
        #expect(summary != nil)
        guard let summary else { return }

        #expect(jsonString(summary["tool"]) == ToolName.memory_snapshot.rawValue)
        #expect(jsonString(summary["project_id"]) == "project-memory")
        #expect(jsonString(summary["mode"]) == "project")
        #expect(jsonString(summary["source"]) == "hub_remote_snapshot")
        #expect(jsonNumber(summary["budget_total_tokens"]) == 1600)
        #expect(jsonNumber(summary["used_total_tokens"]) == 120)
        #expect(jsonNumber(summary["redacted_items"]) == 1)
        #expect(jsonNumber(summary["private_drops"]) == 2)
        #expect(jsonArray(summary["truncated_layers"])?.contains(where: { jsonString($0) == "l4_raw_evidence" }) == true)
        #expect(toolBody(output).contains("Keep release scope frozen."))
    }
}
