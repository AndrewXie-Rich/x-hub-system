import Testing
@testable import XTerminal

struct XTVisibleHubModelInventoryTests {

    @Test
    func buildDedupesCaseInsensitiveIDsAndSortsLoadedModelsFirst() {
        let inventory = XTVisibleHubModelInventorySupport.build(
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "beta", name: "Beta", state: .available),
                    makeModel(id: "Alpha", name: "Alpha", state: .sleeping),
                    makeModel(id: " alpha ", name: "Alpha Prime", state: .loaded)
                ],
                updatedAt: 42
            )
        )

        #expect(inventory.sortedModels.map(\.id) == [" alpha ", "beta"])
        #expect(inventory.snapshot.updatedAt == 42)
    }

    @Test
    func lookupTrimsWhitespaceAndMatchesCaseInsensitively() {
        let model = makeModel(id: "gpt-4o", name: "GPT-4o", state: .loaded)
        let inventory = XTVisibleHubModelInventorySupport.build(
            snapshot: ModelStateSnapshot(models: [model], updatedAt: 1)
        )

        #expect(inventory.model(for: " GPT-4O ") == model)
        #expect(inventory.presentation(for: " GPT-4O ")?.displayName == model.capabilityPresentationModel.displayName)
    }

    private func makeModel(
        id: String,
        name: String,
        state: HubModelState
    ) -> HubModel {
        HubModel(
            id: id,
            name: name,
            backend: "llama.cpp",
            quant: "Q4_K_M",
            contextLength: 8192,
            paramsB: 8,
            state: state
        )
    }
}
