import Testing
@testable import XTerminal

struct ToolCallParserTests {
    @Test
    func plainTextWithoutToolCallsUsesFastTextPath() {
        let content = "这里是一段普通助手输出，包含代码块和说明，但没有工具调用。"

        #expect(!ToolCallParser.mightContainToolCalls(content))

        let parsed = ToolCallParser.parse(content)
        #expect(parsed.parts.count == 1)
        guard case .text(let text) = parsed.parts.first else {
            Issue.record("Expected plain text parsed part")
            return
        }
        #expect(text == content)
    }

    @Test
    func toolCallEnvelopeStillParsesAfterFastPathGuard() {
        let content = """
        {"tool_calls":[{"id":"call-1","tool":"read_file","args":{"path":"README.md"}}],"final":"完成"}
        """

        #expect(ToolCallParser.mightContainToolCalls(content))

        let parsed = ToolCallParser.parse(content)
        #expect(parsed.parts.count == 2)
        guard case .toolCall(let call) = parsed.parts.first else {
            Issue.record("Expected tool call parsed part")
            return
        }
        #expect(call.id == "call-1")
        #expect(call.tool == .read_file)
        guard case .text(let finalText) = parsed.parts.last else {
            Issue.record("Expected final text parsed part")
            return
        }
        #expect(finalText == "完成")
    }

    @Test
    func largePlainTextWithoutToolCallsStaysOnFastTextPath() {
        let content = String(repeating: "普通助手输出。", count: 3_000)

        #expect(!ToolCallParser.mightContainToolCalls(content))
    }

    @Test
    func largeToolCallEnvelopeDetectsMarkerNearEdges() {
        let prefixEnvelope = #"{"tool_calls":[{"id":"call-1","tool":"read_file","args":{"path":"README.md"}}]}"#
            + String(repeating: " done", count: 4_000)
        let suffixEnvelope = String(repeating: "prefix ", count: 4_000)
            + #"{"tool_calls":[{"id":"call-2","tool":"list_dir","args":{"path":"."}}]}"#

        #expect(ToolCallParser.mightContainToolCalls(prefixEnvelope))
        #expect(ToolCallParser.mightContainToolCalls(suffixEnvelope))
    }
}
