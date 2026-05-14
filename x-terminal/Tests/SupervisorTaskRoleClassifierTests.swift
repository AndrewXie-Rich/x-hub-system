import Foundation
import Testing
@testable import XTerminal

struct SupervisorTaskRoleClassifierTests {
    private let classifier = SupervisorTaskRoleClassifier()

    @Test
    func explicitTaskTagsCollapseIntoThreeRoles() {
        let cases: [([String], SupervisorTaskRole)] = [
            (["scope_freeze"], .supervisor),
            (["decision_blocker"], .supervisor),
            (["codegen"], .coder),
            (["refactor"], .coder),
            (["runtime_fix"], .coder),
            (["review"], .reviewer),
            (["regression"], .reviewer),
            (["gate_review"], .reviewer),
            (["docs"], .supervisor),
            (["release_notes"], .supervisor),
            (["spec_freeze_writeup"], .supervisor),
            (["runbook"], .supervisor),
            (["rollout"], .supervisor),
            (["runtime_probe"], .supervisor),
            (["operator_action"], .supervisor),
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
        #expect(operational.role == .supervisor)

        let highRisk = classifier.classify(
            .init(taskTags: [], risk: .high)
        )
        #expect(highRisk.role == .supervisor)
        #expect(highRisk.reasons.contains { $0.contains("high_risk") })

        let safeUnknown = classifier.classify(
            .init(taskTags: ["unknown_tag"])
        )
        #expect(safeUnknown.role == .supervisor)
    }

    @Test
    func conflictingRoleSignalsResolveConservatively() {
        let reviewAndCode = classifier.classify(
            .init(taskTags: ["codegen", "review"], risk: .high, codeExecution: true)
        )
        #expect(reviewAndCode.role == .coder)

        let supervisorSignals = classifier.classify(
            .init(taskTags: ["runbook", "docs"], sideEffect: .externalWrite)
        )
        #expect(supervisorSignals.role == .supervisor)

        let codeAndDoc = classifier.classify(
            .init(taskTags: ["docs", "refactor"], codeExecution: true)
        )
        #expect(codeAndDoc.role == .coder)

        let reviewAndRollout = classifier.classify(
            .init(taskTags: ["review", "rollout"], sideEffect: .externalWrite)
        )
        #expect(reviewAndRollout.role == .supervisor)
    }

    @Test
    func reviewerStaysReviewOnlyAndDoesNotLeakIntoExecutionPaths() {
        let reviewOnly = classifier.classify(
            .init(taskTags: ["review"], risk: .high, sideEffect: .externalRead)
        )
        #expect(reviewOnly.role == .reviewer)

        let reviewWithCodeExecution = classifier.classify(
            .init(taskTags: ["review"], codeExecution: true)
        )
        #expect(reviewWithCodeExecution.role == .coder)
        #expect(reviewWithCodeExecution.reasons.contains { $0.contains("explicit_review_role_clamped_to:coder") })

        let reviewWithExternalWrite = classifier.classify(
            .init(taskTags: ["gate_review"], sideEffect: .externalWrite)
        )
        #expect(reviewWithExternalWrite.role == .supervisor)
        #expect(reviewWithExternalWrite.reasons.contains { $0.contains("explicit_review_role_clamped_to:supervisor") })
    }
}
