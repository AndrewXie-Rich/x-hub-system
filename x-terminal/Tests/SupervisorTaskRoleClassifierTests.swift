import Foundation
import Testing
@testable import XTerminal

struct SupervisorTaskRoleClassifierTests {
    private let classifier = SupervisorTaskRoleClassifier()

    @Test
    func explicitTaskTagsMapToExpectedRoles() {
        let cases: [([String], SupervisorTaskRole)] = [
            (["scope_freeze"], .planner),
            (["decision_blocker"], .planner),
            (["codegen"], .coder),
            (["refactor"], .coder),
            (["runtime_fix"], .coder),
            (["review"], .reviewer),
            (["regression"], .reviewer),
            (["gate_review"], .reviewer),
            (["docs"], .doc),
            (["release_notes"], .doc),
            (["spec_freeze_writeup"], .doc),
            (["runbook"], .ops),
            (["rollout"], .ops),
            (["runtime_probe"], .ops),
            (["operator_action"], .ops),
        ]

        for (taskTags, expectedRole) in cases {
            let output = classifier.classify(.init(taskTags: taskTags))
            #expect(output.role == expectedRole)
            #expect(!output.reasons.isEmpty)
            #expect(output.matchedRouteTags == taskTags)
        }
    }

    @Test
    func fallbackSignalsUseRiskSideEffectAndCodeExecution() {
        let codeExecution = classifier.classify(.init(taskTags: [], codeExecution: true))
        #expect(codeExecution.role == .coder)

        let operational = classifier.classify(
            .init(taskTags: [], sideEffect: .externalWrite)
        )
        #expect(operational.role == .ops)

        let highRisk = classifier.classify(
            .init(taskTags: [], risk: .high)
        )
        #expect(highRisk.role == .reviewer)

        let safeUnknown = classifier.classify(
            .init(taskTags: ["unknown_tag"])
        )
        #expect(safeUnknown.role == .planner)
    }

    @Test
    func conflictingRoleSignalsResolveConservatively() {
        let reviewAndCode = classifier.classify(
            .init(taskTags: ["codegen", "review"], risk: .high, codeExecution: true)
        )
        #expect(reviewAndCode.role == .reviewer)

        let opsAndDoc = classifier.classify(
            .init(taskTags: ["runbook", "docs"], sideEffect: .externalWrite)
        )
        #expect(opsAndDoc.role == .ops)

        let codeAndDoc = classifier.classify(
            .init(taskTags: ["docs", "refactor"], codeExecution: true)
        )
        #expect(codeAndDoc.role == .coder)
    }
}
