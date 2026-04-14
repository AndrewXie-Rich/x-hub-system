import XCTest
@testable import RELFlowHubCore

final class IPCMemoryRetrievalPayloadTests: XCTestCase {
    func testIPCRequestRoundTripsMemoryRetrievalPayload() throws {
        let request = IPCRequest(
            type: "memory_retrieval",
            reqId: "req-1",
            memoryRetrieval: IPCMemoryRetrievalRequestPayload(
                requestId: "memreq-1",
                scope: "current_project",
                requesterRole: "chat",
                mode: "project_chat",
                projectId: "project-1",
                crossProjectTargetIds: [],
                projectRoot: "/tmp/project-1",
                displayName: "Project One",
                query: "你之前说过什么",
                latestUser: "你之前说过什么",
                allowedLayers: ["l1_canonical", "l2_observations"],
                retrievalKind: "search",
                maxResults: 3,
                reason: "project_chat_progressive_disclosure_seed",
                requireExplainability: true,
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
        XCTAssertEqual(decoded.memoryRetrieval?.schemaVersion, "xt.memory_retrieval_request.v1")
        XCTAssertEqual(decoded.memoryRetrieval?.requestId, "memreq-1")
        XCTAssertEqual(decoded.memoryRetrieval?.scope, "current_project")
        XCTAssertEqual(decoded.memoryRetrieval?.requesterRole, "chat")
        XCTAssertEqual(decoded.memoryRetrieval?.mode, "project_chat")
        XCTAssertEqual(decoded.memoryRetrieval?.query, "你之前说过什么")
        XCTAssertEqual(decoded.memoryRetrieval?.allowedLayers, ["l1_canonical", "l2_observations"])
        XCTAssertEqual(decoded.memoryRetrieval?.retrievalKind, "search")
        XCTAssertEqual(decoded.memoryRetrieval?.maxResults, 3)
        XCTAssertEqual(decoded.memoryRetrieval?.requireExplainability, true)
        XCTAssertEqual(decoded.memoryRetrieval?.requestedKinds, ["recent_context", "decision_track"])
        XCTAssertEqual(decoded.memoryRetrieval?.explicitRefs.first, "/tmp/project-1/.xterminal/recent_context.json")
    }
}
