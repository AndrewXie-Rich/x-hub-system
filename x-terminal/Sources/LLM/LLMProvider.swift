import Foundation

protocol LLMProvider {
    var displayName: String { get }

    func stream(_ req: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}
