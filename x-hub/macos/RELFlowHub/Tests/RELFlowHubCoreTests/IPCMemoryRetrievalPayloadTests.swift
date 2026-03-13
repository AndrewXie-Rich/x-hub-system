import XCTest
@testable import RELFlowHubCore

final class IPCMemoryRetrievalPayloadTests: XCTestCase {
    func testIPCRequestRoundTripsMemoryRetrievalPayload() throws {
        let request = IPCRequest(
            type: "memory_retrieval",
            reqId: "req-1",
            memoryRetrieval: IPCMemoryRetrievalRequestPayload(
                scope: "current_project",
                requesterRole: "chat",
                projectId: "project-1",
                projectRoot: "/tmp/project-1",
                displayName: "Project One",
                latestUser: "你之前说过什么",
                reason: "project_chat_progressive_disclosure_seed",
                requestedKinds: ["recent_context", "decision_track"],
                explicitRefs: ["/tmp/project-1/.xterminal/recent_context.json"],
                maxSnippets: 3,
                maxSnippetChars: 360,
                auditRef: "audit-xt-memory-retrieval-abc123"
            )
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)

        XCTAssertEqual(decoded.type, "memory_retrieval")
        XCTAssertEqual(decoded.memoryRetrieval?.scope, "current_project")
        XCTAssertEqual(decoded.memoryRetrieval?.requesterRole, "chat")
        XCTAssertEqual(decoded.memoryRetrieval?.requestedKinds, ["recent_context", "decision_track"])
        XCTAssertEqual(decoded.memoryRetrieval?.explicitRefs.first, "/tmp/project-1/.xterminal/recent_context.json")
    }
}
