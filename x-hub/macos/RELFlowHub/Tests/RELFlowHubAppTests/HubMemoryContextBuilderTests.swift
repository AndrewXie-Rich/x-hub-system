import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubMemoryContextBuilderTests: XCTestCase {
    func testProjectChatMarksProgressiveDisclosureAndRetrievalAvailability() {
        let response = HubMemoryContextBuilder.build(
            from: IPCMemoryContextRequestPayload(
                mode: "project_chat",
                projectId: "project-ctx",
                projectRoot: "/tmp/project-ctx",
                displayName: "Project Context",
                latestUser: "你之前怎么定 tech stack 的",
                constitutionHint: "真实透明",
                canonicalText: "goal: keep current project memory thin",
                observationsText: "decision track landed",
                workingSetText: "ask for history if summary is insufficient",
                rawEvidenceText: "build/reports/example.json",
                servingProfile: "m2_plan_review",
                budgets: nil
            )
        )

        XCTAssertEqual(response.longtermMode, "progressive_disclosure")
        XCTAssertEqual(response.retrievalAvailable, true)
        XCTAssertEqual(response.fulltextNotLoaded, true)
        XCTAssertTrue(response.text.contains("[LONGTERM_MEMORY]"))
        XCTAssertTrue(response.text.contains("longterm_mode=progressive_disclosure"))
        XCTAssertTrue(response.text.contains("retrieval_available=true"))
        XCTAssertTrue(response.text.contains("fulltext_not_loaded=true"))
    }
}
