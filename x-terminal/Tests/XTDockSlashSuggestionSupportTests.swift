import Testing
@testable import XTerminal

struct XTDockSlashSuggestionSupportTests {

    @Test
    func modelSuggestionsKeepLoadedInventoryOrderAndOfferAutoOption() {
        let suggestions = XTDockSlashSuggestionSupport.suggestions(
            for: "/model",
            models: [
                makeModel(id: "b-model", state: .loaded),
                makeModel(id: "a-model", state: .loaded),
                makeModel(id: "sleeping-model", state: .sleeping)
            ]
        )

        #expect(suggestions.map(\.insertion) == [
            "/model auto",
            "/model b-model",
            "/model a-model"
        ])
    }

    @Test
    func baseSuggestionsFilterBySlashQuery() {
        let suggestions = XTDockSlashSuggestionSupport.suggestions(
            for: "/hub",
            models: []
        )

        #expect(suggestions.map(\.insertion) == ["/hub route"])
    }

    @Test
    func suggestionsUseStableInsertionIdentity() {
        let suggestion = XTDockSlashSuggestion(
            title: "/help",
            subtitle: "查看帮助",
            insertion: "/help"
        )

        #expect(suggestion.id == "/help")
    }

    private func makeModel(
        id: String,
        state: HubModelState
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: "llama.cpp",
            quant: "Q4_K_M",
            contextLength: 8192,
            paramsB: 8,
            state: state
        )
    }
}
