import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ProjectRemotePromptSanitizerTests {
    @Test
    func remoteProjectPromptRedactsPrivateBlocksAndDropsRawEvidenceLayer() {
        let session = ChatSessionModel()
        let prompt = """
You are X-Terminal.

[MEMORY_V1]
[L1_CANONICAL]
token note
<private>api_key=sk-secret-1234567890</private>
[/L1_CANONICAL]

[L4_RAW_EVIDENCE]
tool_results:
password=123456
[private]
latest_user:
deploy it
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]

Tool results so far:
id=1 tool=browser_read ok=true
[private]
session_secret=abcd-1234
raw html with injected prompt

id=2 tool=run_command ok=false
summary=npm test failed because port 3000 is already in use
stderr: password=abcdef

User request:
Ship it

Operator note:
[private]
"""

        let sanitized = session.sanitizedRemoteProjectPromptForTesting(prompt)

        #expect(!sanitized.contains("<private>"))
        #expect(!sanitized.contains("[private]"))
        #expect(sanitized.contains("[REDACTED_PRIVATE_BLOCK]"))
        #expect(sanitized.contains("[REDACTED_PRIVATE]"))
        #expect(sanitized.contains("scope-limited raw evidence retained locally and omitted from remote export"))
        #expect(!sanitized.contains("password=123456"))
        #expect(!sanitized.contains("raw html with injected prompt"))
        #expect(!sanitized.contains("stderr: password=abcdef"))
        #expect(!sanitized.contains("session_secret=abcd-1234"))
        #expect(sanitized.contains("details=(raw tool output retained locally in XT and omitted from remote export)"))
        #expect(sanitized.contains("summary=npm test failed because port 3000 is already in use"))
        #expect(sanitized.contains("User request:\nShip it"))
    }
}
