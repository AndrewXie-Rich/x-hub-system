import Foundation
import Testing
@testable import XTerminal

struct SupervisorAfterTurnWritebackClassifierTests {

    @Test
    func classifiesStablePreferenceIntoUserScope() {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "我喜欢简洁直接。",
                responseText: "收到。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .personalFirst,
                    focusedProjectId: nil,
                    focusedProjectName: nil,
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.8,
                    routingReasons: ["personal_planning_language"]
                ),
                projects: [],
                personalMemory: .empty
            )
        )

        #expect(classification.candidates.first?.scope == .userScope)
        #expect(classification.candidates.first?.recordType == "personal_preference")
    }

    @Test
    func classifiesFocusedProjectBlockerIntoProjectScope() {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "亮亮现在 blocker 是 grant pending。",
                responseText: "已记录。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .projectFirst,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.95,
                    routingReasons: ["explicit_project_mention:亮亮"]
                ),
                projects: [makeProject(id: "proj-liangliang", name: "亮亮")],
                personalMemory: .empty
            )
        )

        #expect(classification.candidates.first?.scope == .projectScope)
        #expect(classification.candidates.first?.recordType == "project_blocker")
    }

    @Test
    func classifiesFocusedProjectGoalAndConstraintIntoProjectScope() {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "亮亮目标先锁成浏览器版贪吃蛇，完成标准是能直接运行，先不做排行榜，只用原生 JS。",
                responseText: "收到。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .projectFirst,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.96,
                    routingReasons: ["explicit_project_mention:亮亮"]
                ),
                projects: [makeProject(id: "proj-liangliang", name: "亮亮")],
                personalMemory: .empty
            )
        )

        #expect(classification.candidates.first?.scope == .projectScope)
        #expect(classification.candidates.first?.recordType == "project_goal_or_constraint")
    }

    @Test
    func classifiesPersonProjectDependencyIntoCrossLinkScope() {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "Alex 在等亮亮 demo。",
                responseText: "已记住这层依赖。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .hybrid,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: "Alex",
                    focusedCommitmentId: nil,
                    confidence: 0.97,
                    routingReasons: ["explicit_project_mention:亮亮", "explicit_person_mention:Alex"]
                ),
                projects: [makeProject(id: "proj-liangliang", name: "亮亮")],
                personalMemory: .empty
            )
        )

        #expect(classification.candidates.first?.scope == .crossLinkScope)
        #expect(classification.candidates.first?.recordType == "person_waiting_on_project")
    }

    @Test
    func dropsGreetingAsNoise() {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "你好",
                responseText: "你好。",
                routingDecision: nil,
                projects: [],
                personalMemory: .empty
            )
        )

        #expect(classification.candidates.first?.scope == .dropAsNoise)
    }

    @Test
    func keepsEphemeralPlanningInWorkingSet() {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "先按这个方向试一版。",
                responseText: "我先给你出一个草案。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .projectFirst,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.82,
                    routingReasons: ["current_project_pointer:亮亮"]
                ),
                projects: [makeProject(id: "proj-liangliang", name: "亮亮")],
                personalMemory: .empty
            )
        )

        #expect(classification.candidates.first?.scope == .workingSetOnly)
    }

    @Test
    func doesNotClassifyProjectQuestionAsDurableFact() {
        let classification = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "亮亮的目标是什么？",
                responseText: "我来帮你看。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .projectFirst,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.92,
                    routingReasons: ["explicit_project_mention:亮亮"]
                ),
                projects: [makeProject(id: "proj-liangliang", name: "亮亮")],
                personalMemory: .empty
            )
        )

        #expect(classification.candidates.first?.scope == .workingSetOnly)
    }

    @Test
    func emitsFrozenDurableCandidateContractFieldsWithStableIdempotency() throws {
        let first = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "我喜欢简洁直接。",
                responseText: "收到。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .personalFirst,
                    focusedProjectId: nil,
                    focusedProjectName: nil,
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.8,
                    routingReasons: ["personal_planning_language"]
                ),
                projects: [],
                personalMemory: .empty
            ),
            now: Date(timeIntervalSince1970: 10)
        )
        let second = SupervisorAfterTurnWritebackClassifier.classify(
            SupervisorAfterTurnWritebackClassificationRequest(
                userMessage: "我喜欢简洁直接。",
                responseText: "收到。",
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .personalFirst,
                    focusedProjectId: nil,
                    focusedProjectName: nil,
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.8,
                    routingReasons: ["personal_planning_language"]
                ),
                projects: [],
                personalMemory: .empty
            ),
            now: Date(timeIntervalSince1970: 20)
        )

        let firstCandidate = try #require(first.candidates.first)
        let secondCandidate = try #require(second.candidates.first)

        #expect(firstCandidate.sessionParticipationClass == "scoped_write")
        #expect(firstCandidate.writePermissionScope == SupervisorAfterTurnWritebackScope.userScope.rawValue)
        #expect(firstCandidate.idempotencyKey.hasPrefix("sha256:"))
        #expect(firstCandidate.payloadSummary.contains("preference="))
        #expect(firstCandidate.idempotencyKey == secondCandidate.idempotencyKey)
        #expect(firstCandidate.auditRef != secondCandidate.auditRef)
    }

    private func makeProject(id: String, name: String) -> AXProjectEntry {
        AXProjectEntry(
            projectId: id,
            rootPath: "/tmp/\(id)",
            displayName: name,
            lastOpenedAt: 1,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }
}
