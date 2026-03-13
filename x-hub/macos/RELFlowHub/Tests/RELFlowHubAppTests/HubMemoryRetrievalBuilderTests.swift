import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubMemoryRetrievalBuilderTests: XCTestCase {
    func testBuildReturnsRecentContextAndDecisionSnippetsForCurrentProject() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w335_memory_retrieval_\(UUID().uuidString)", isDirectory: true)
        let stateDir = projectRoot.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try writeJSON(
            [
                "schema_version": 1,
                "updated_at": 123.0,
                "messages": [
                    ["role": "user", "content": "我们之前说过要先修付费模型 grant", "created_at": 1.0],
                    ["role": "assistant", "content": "你还提到 supervisor 默认只有最近几轮上下文", "created_at": 2.0],
                    ["role": "user", "content": "新的消息 1", "created_at": 3.0],
                    ["role": "assistant", "content": "新的消息 2", "created_at": 4.0],
                    ["role": "user", "content": "新的消息 3", "created_at": 5.0],
                    ["role": "assistant", "content": "新的消息 4", "created_at": 6.0],
                    ["role": "user", "content": "新的消息 5", "created_at": 7.0],
                    ["role": "assistant", "content": "新的消息 6", "created_at": 8.0],
                    ["role": "user", "content": "新的消息 7", "created_at": 9.0],
                    ["role": "assistant", "content": "新的消息 8", "created_at": 10.0],
                    ["role": "user", "content": "新的消息 9", "created_at": 11.0],
                    ["role": "assistant", "content": "新的消息 10", "created_at": 12.0],
                    ["role": "user", "content": "新的消息 11", "created_at": 13.0],
                    ["role": "assistant", "content": "新的消息 12", "created_at": 14.0],
                    ["role": "user", "content": "新的消息 13", "created_at": 15.0],
                    ["role": "assistant", "content": "新的消息 14", "created_at": 16.0],
                    ["role": "user", "content": "新的消息 15", "created_at": 17.0],
                    ["role": "assistant", "content": "新的消息 16", "created_at": 18.0]
                ]
            ],
            to: stateDir.appendingPathComponent("recent_context.json")
        )

        try writeJSON(
            [
                "schema_version": "xt.supervisor_decision_track.v1",
                "updated_at_ms": 456,
                "events": [
                    [
                        "schema_version": "xt.supervisor_decision_track_event.v1",
                        "decision_id": "decision-1",
                        "project_id": "project-1",
                        "category": "tech_stack",
                        "status": "approved",
                        "statement": "技术栈固定为 Swift + SwiftUI",
                        "source": "owner",
                        "reversible": true,
                        "approval_required": false,
                        "approved_by": "owner",
                        "audit_ref": "audit-1",
                        "evidence_refs": [],
                        "created_at_ms": 100,
                        "updated_at_ms": 200
                    ]
                ]
            ],
            to: stateDir.appendingPathComponent("supervisor_decision_track.json")
        )

        let response = HubMemoryRetrievalBuilder.build(
            from: IPCMemoryRetrievalRequestPayload(
                scope: "current_project",
                requesterRole: "chat",
                projectId: "project-1",
                projectRoot: projectRoot.path,
                displayName: "Project One",
                latestUser: "你之前说过的 tech stack 决策是什么",
                reason: "project_chat_progressive_disclosure_seed",
                requestedKinds: ["recent_context", "decision_track"],
                explicitRefs: [],
                maxSnippets: 3,
                maxSnippetChars: 240,
                auditRef: "audit-xt-memory-retrieval-1"
            )
        )

        XCTAssertNil(response.denyCode)
        XCTAssertEqual(response.auditRef, "audit-xt-memory-retrieval-1")
        XCTAssertFalse(response.snippets.isEmpty)
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "recent_context" }))
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "decision_track" }))
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
