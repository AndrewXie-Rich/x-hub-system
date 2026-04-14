import Foundation
import Testing

struct XHubDoctorRouteTruthDocsSyncTests {
    @Test
    func routingContractFreezesProjectionEnvelopeAndXtPartialSemantics() throws {
        let contract = try read(
            repoRoot().appendingPathComponent(
                "docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md"
            )
        )

        #expect(contract.contains("`projection_source`"))
        #expect(contract.contains("`completeness`"))
        #expect(contract.contains("`partial_xt_projection`"))
        #expect(contract.contains("`partial_counts_only`"))
        #expect(contract.contains("`detail_lines` 仍可作为迁移期兼容输入"))
    }

    @Test
    func docsAndSchemaKeepStructuredRouteTruthVisible() throws {
        let root = repoRoot()
        let readme = try read(root.appendingPathComponent("README.md"))
        let schema = try read(
            root.appendingPathComponent("docs/memory-new/schema/xhub_doctor_output_contract.v1.json")
        )
        let workingIndex = try read(root.appendingPathComponent("docs/WORKING_INDEX.md"))
        let xMemory = try read(root.appendingPathComponent("X_MEMORY.md"))
        let xtReadme = try read(root.appendingPathComponent("x-terminal/README.md"))
        let runtimePack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md"
            )
        )
        let ciReadme = try read(root.appendingPathComponent("scripts/ci/README.md"))

        #expect(schema.contains("\"projection_source\""))
        #expect(schema.contains("\"completeness\""))
        #expect(schema.contains("\"source_badge\""))
        #expect(schema.contains("\"status_line\""))
        #expect(schema.contains("Structured producer fields should be preferred over reparsing detail_lines"))

        #expect(workingIndex.contains("memoryRouteTruthProjection"))
        #expect(workingIndex.contains("memory_route_truth_snapshot"))
        #expect(workingIndex.contains("model_route_readiness"))
        #expect(workingIndex.contains("projection_source"))
        #expect(workingIndex.contains("completeness"))

        #expect(readme.contains("memory_route_truth_snapshot"))
        #expect(readme.contains("projection_source"))
        #expect(readme.contains("memory_route_truth_support"))
        #expect(readme.contains("source_badge / status_line"))

        #expect(xMemory.contains("memoryRouteTruthProjection"))
        #expect(xMemory.contains("memory_route_truth_snapshot"))
        #expect(xMemory.contains("projection_source / completeness"))
        #expect(xMemory.contains("source_badge / status_line"))

        #expect(xtReadme.contains("memory_route_truth_snapshot"))
        #expect(xtReadme.contains("projection_source"))
        #expect(xtReadme.contains("structured snapshot is the primary machine-readable surface"))
        #expect(xtReadme.contains("source_badge / status_line"))

        #expect(runtimePack.contains("memoryRouteTruthProjection"))
        #expect(runtimePack.contains("legacy migration fallback"))
        #expect(runtimePack.contains("projection_source / completeness"))

        #expect(ciReadme.contains("memory_route_truth_support"))
        #expect(ciReadme.contains("source_badge / status_line"))
    }

    private func repoRoot() -> URL {
        monorepoTestRepoRoot(filePath: #filePath)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
