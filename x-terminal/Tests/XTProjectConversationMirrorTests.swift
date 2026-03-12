import Foundation
import Testing
@testable import XTerminal

struct XTProjectConversationMirrorTests {
    @Test
    func projectThreadKeyUsesProjectScopeNamespace() {
        #expect(
            XTProjectConversationMirror.projectThreadKey(projectId: " abc-123 ")
                == "xterminal_project_abc-123"
        )
        #expect(
            XTProjectConversationMirror.projectThreadKey(projectId: "")
                == "xterminal_project_unknown"
        )
    }

    @Test
    func requestIDIsDeterministicForProjectAndTimestamp() {
        let req = XTProjectConversationMirror.requestID(
            projectId: "12345678-1234-1234-1234-1234567890ab",
            createdAt: 1_772_200_000.125
        )

        #expect(req == "xterminal_turn_123456781234_1772200000125")
    }

    @Test
    func messagesTrimAndTruncateLargeConversationContent() {
        let large = String(repeating: "a", count: XTProjectConversationMirror.maxCharsPerMessage + 32)
        let mirrored = XTProjectConversationMirror.messages(
            userText: "  hello  ",
            assistantText: large
        )

        #expect(mirrored.count == 2)
        #expect(mirrored[0] == XTProjectConversationMirrorMessage(role: "user", content: "hello"))
        #expect(mirrored[1].role == "assistant")
        #expect(mirrored[1].content.hasSuffix("[x-terminal] truncated"))
        #expect(mirrored[1].content.count > XTProjectConversationMirror.maxCharsPerMessage)
    }
}
