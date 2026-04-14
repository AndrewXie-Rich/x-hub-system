import Foundation
import Darwin
import Testing
@testable import XTerminal

@Suite(.serialized)
struct SupervisorStoreWriteSupportTests {
    @Test
    func decisionTrackStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("decision-track")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try Data("{\"stale\":true}\n".utf8).write(to: ctx.supervisorDecisionTrackURL)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        _ = try SupervisorDecisionTrackStore.upsert(
            SupervisorDecisionTrackBuilder.build(
                decisionId: "decision-1",
                projectId: "proj-alpha",
                category: .techStack,
                status: .approved,
                statement: "Use the memory-backed supervisor path.",
                source: "user",
                reversible: true,
                approvalRequired: false,
                approvedBy: "user",
                auditRef: "audit-decision-1",
                createdAtMs: 100
            ),
            for: ctx
        )

        let snapshot = SupervisorDecisionTrackStore.load(for: ctx)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(snapshot.events.count == 1)
        #expect(snapshot.events.first?.decisionId == "decision-1")
    }

    @Test
    func reviewNoteStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("review-note")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try Data("{\"stale\":true}\n".utf8).write(to: ctx.supervisorReviewNotesURL)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: "review-1",
                projectId: "proj-alpha",
                trigger: .manualRequest,
                reviewLevel: .r2Strategic,
                verdict: .watch,
                targetRole: .supervisor,
                deliveryMode: .priorityInsert,
                ackRequired: false,
                summary: "Project is drifting from the approved path.",
                recommendedActions: ["Re-anchor on the approved scope."],
                anchorGoal: "Keep the project on the approved path.",
                anchorDoneDefinition: "Supervisor can explain current direction and next step.",
                anchorConstraints: ["Preserve the evidence trail."],
                currentState: "Implementation is pushing outside scope.",
                nextStep: "Refocus on the approved sequence.",
                blocker: "Direction drift.",
                createdAtMs: 200,
                auditRef: "audit-review-1"
            ),
            for: ctx
        )

        let snapshot = SupervisorReviewNoteStore.load(for: ctx)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(snapshot.notes.count == 1)
        #expect(snapshot.notes.first?.reviewId == "review-1")
    }

    @Test
    func selectedEvidenceStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("selected-evidence")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let target = ctx.xterminalDir.appendingPathComponent("supervisor_selected_evidence_pins.json")
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        _ = try SupervisorSelectedEvidencePinStore.upsert(
            SupervisorSelectedEvidencePinBuilder.build(
                pinId: "pin-1",
                projectId: "proj-alpha",
                summary: "The live grant gate already blocked a risky call.",
                sourceNote: "incident export",
                whyItMatters: "This proves the safety boundary is active.",
                createdAtMs: 300,
                auditRef: "audit-pin-1"
            ),
            for: ctx
        )

        let latest = try #require(SupervisorSelectedEvidencePinStore.latest(for: ctx))
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(latest.pinId == "pin-1")
    }

    @Test
    func skillCallStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("skill-call")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try Data("{\"stale\":true}\n".utf8).write(to: ctx.supervisorSkillCallsURL)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: "request-1",
            projectId: "proj-alpha",
            projectName: "Project Alpha",
            requestedSkillId: "agent-browser",
            effectiveSkillId: "guarded-automation",
            toolName: ToolName.deviceBrowserControl.rawValue,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["browser_operator"],
            deltaProfiles: ["browser_operator"],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["web.navigate", "web.dom.write"],
            deltaCapabilityFamilies: ["web.navigate", "web.dom.write"],
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requestedTTLSeconds: 900,
            reason: "waiting for local governed approval",
            summary: "当前可直接运行：observe_only；本次请求：browser_operator；新增放开：browser_operator；grant=none；approval=local_approval",
            disposition: "pending",
            auditRef: "audit-delta-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "proj-alpha",
            skillId: "guarded-automation",
            packageSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["browser.operate"],
            capabilityFamilies: ["web.navigate", "web.dom.write"],
            capabilityProfiles: ["browser_operator"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            runnableNow: false,
            denyCode: "local_approval_required",
            reasonCode: "approval floor local_approval requires local confirmation",
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            requiredGrantCapabilities: [],
            requiredRuntimeSurfaces: ["device_browser_runtime"],
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(XTSkillExecutionReadinessState.localApprovalRequired.rawValue),
            installHint: "install browser runtime",
            unblockActions: ["approve_local_skill_request"],
            auditRef: "audit-readiness-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-1",
            grantSnapshotRef: ""
        )

        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "request-1",
                projectId: "proj-alpha",
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "memory_snapshot",
                toolName: "memory_snapshot",
                status: .completed,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "snapshot refreshed",
                denyCode: "",
                resultEvidenceRef: "evidence://memory/1",
                profileDeltaRef: "evidence://memory/1#profile_delta",
                deltaApproval: deltaApproval,
                readinessRef: "evidence://memory/1#readiness",
                readiness: readiness,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 400,
                updatedAtMs: 420,
                auditRef: "audit-skill-1"
            ),
            for: ctx
        )

        let snapshot = SupervisorProjectSkillCallStore.load(for: ctx)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(snapshot.calls.count == 1)
        #expect(snapshot.calls.first?.requestId == "request-1")
        #expect(snapshot.calls.first?.profileDeltaRef == "evidence://memory/1#profile_delta")
        #expect(snapshot.calls.first?.deltaApproval?.deltaProfiles == ["browser_operator"])
        #expect(snapshot.calls.first?.readinessRef == "evidence://memory/1#readiness")
        #expect(snapshot.calls.first?.readiness?.executionReadiness == XTSkillExecutionReadinessState.localApprovalRequired.rawValue)
    }

    @Test
    func jobStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("job")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try Data("{\"stale\":true}\n".utf8).write(to: ctx.supervisorJobsURL)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        try SupervisorProjectJobStore.append(
            SupervisorJobRecord(
                schemaVersion: SupervisorJobRecord.currentSchemaVersion,
                jobId: "job-1",
                projectId: "proj-alpha",
                goal: "Recover the blocked plan",
                priority: .high,
                status: .queued,
                source: .supervisor,
                currentOwner: "supervisor",
                activePlanId: "",
                createdAtMs: 500,
                updatedAtMs: 520,
                auditRef: "audit-job-1"
            ),
            for: ctx
        )

        let snapshot = SupervisorProjectJobStore.load(for: ctx)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(snapshot.jobs.count == 1)
        #expect(snapshot.jobs.first?.jobId == "job-1")
    }

    @Test
    func planStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("plan")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try Data("{\"stale\":true}\n".utf8).write(to: ctx.supervisorPlansURL)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        try SupervisorProjectPlanStore.upsert(
            SupervisorPlanRecord(
                schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
                planId: "plan-1",
                jobId: "job-1",
                projectId: "proj-alpha",
                status: .active,
                currentOwner: "supervisor",
                steps: [
                    SupervisorPlanStepRecord(
                        schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                        stepId: "step-1",
                        title: "Review the current blocker",
                        kind: .writeMemory,
                        status: .pending,
                        skillId: "memory_snapshot",
                        currentOwner: "supervisor",
                        detail: "Refresh strategic memory before replanning.",
                        orderIndex: 0,
                        updatedAtMs: 600
                    )
                ],
                createdAtMs: 600,
                updatedAtMs: 620,
                auditRef: "audit-plan-1"
            ),
            for: ctx
        )

        let snapshot = SupervisorProjectPlanStore.load(for: ctx)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(snapshot.plans.count == 1)
        #expect(snapshot.plans.first?.planId == "plan-1")
    }

    @Test
    func guidanceInjectionStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("guidance")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try Data("{\"stale\":true}\n".utf8).write(to: ctx.supervisorGuidanceInjectionsURL)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-1",
                reviewId: "review-1",
                projectId: "proj-alpha",
                targetRole: .projectChat,
                deliveryMode: .priorityInsert,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "Pause and re-anchor on the approved plan.",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 700,
                ackUpdatedAtMs: 700,
                auditRef: "audit-guidance-1"
            ),
            for: ctx
        )

        let latest = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(latest.injectionId == "guidance-1")
    }

    @Test
    func specCapsuleStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("spec-capsule")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let target = ctx.xterminalDir.appendingPathComponent("supervisor_project_spec_capsule.json")
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        _ = try SupervisorProjectSpecCapsuleStore.upsert(
            SupervisorProjectSpecCapsuleBuilder.build(
                projectId: "proj-alpha",
                goal: "Keep the supervisor aligned with the full project context.",
                mvpDefinition: "Supervisor can inspect current state and steer safely.",
                nonGoals: ["Cross-tenant rollout"],
                approvedTechStack: ["SwiftUI", "Hub memory"],
                milestoneMap: [
                    SupervisorProjectSpecMilestone(
                        milestoneId: "mvp",
                        title: "MVP",
                        status: .active
                    )
                ],
                updatedAtMs: 800
            ),
            for: ctx
        )

        let capsule = try #require(SupervisorProjectSpecCapsuleStore.load(for: ctx))
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(capsule.projectId == "proj-alpha")
    }

    @Test
    func backgroundPreferenceStoreFallsBackToNonAtomicOverwriteWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("background")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try Data("{\"stale\":true}\n".utf8).write(to: ctx.supervisorBackgroundPreferenceTrackURL)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        _ = try SupervisorBackgroundPreferenceTrackStore.upsert(
            SupervisorBackgroundPreferenceTrackBuilder.build(
                noteId: "background-1",
                projectId: "proj-alpha",
                domain: .uxStyle,
                strength: .medium,
                statement: "Prefer concise, action-first guidance.",
                createdAtMs: 900
            ),
            for: ctx
        )

        let snapshot = SupervisorBackgroundPreferenceTrackStore.load(for: ctx)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(snapshot.notes.count == 1)
        #expect(snapshot.notes.first?.noteId == "background-1")
    }

    @Test
    func reviewScheduleStoreFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("review-schedule")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let target = ctx.xterminalDir.appendingPathComponent("supervisor_review_schedule.json")
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        let config = AXProjectConfig.default(forProjectRoot: root)
        let state = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            nowMs: 1_773_900_000_000
        )

        let loaded = SupervisorReviewScheduleStore.load(for: ctx)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(loaded.updatedAtMs == state.updatedAtMs)
        #expect(loaded.lastHeartbeatAtMs == 1_773_900_000_000)
    }

    @Test
    func skillResultEvidenceStoreFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("skill-result-evidence")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let requestId = "request-evidence-1"
        let target = ctx.supervisorSkillResultEvidenceURL(requestId: requestId)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        let deltaApproval = XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: requestId,
            projectId: "proj-alpha",
            projectName: "Project Alpha",
            requestedSkillId: "memory_snapshot",
            effectiveSkillId: "memory_snapshot",
            toolName: ToolName.memory_snapshot.rawValue,
            currentRunnableProfiles: ["observe_only"],
            requestedProfiles: ["observe_only"],
            deltaProfiles: [],
            currentRunnableCapabilityFamilies: ["repo.read"],
            requestedCapabilityFamilies: ["repo.read"],
            deltaCapabilityFamilies: [],
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.none.rawValue,
            requestedTTLSeconds: 900,
            reason: "ready",
            summary: "当前可直接运行：observe_only；本次请求：observe_only；这次没有新增 profile；grant=none；approval=none",
            disposition: "approved",
            auditRef: "audit-delta-evidence-1"
        )
        let readiness = XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "proj-alpha",
            skillId: "memory_snapshot",
            packageSHA256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            publisherID: "xt_builtin",
            policyScope: "xt_builtin",
            intentFamilies: ["memory.read"],
            capabilityFamilies: ["repo.read"],
            capabilityProfiles: ["observe_only"],
            discoverabilityState: "discoverable",
            installabilityState: "installable",
            pinState: "xt_builtin",
            resolutionState: "resolved",
            executionReadiness: XTSkillExecutionReadinessState.ready.rawValue,
            runnableNow: true,
            denyCode: "",
            reasonCode: "request-scoped authorization satisfied",
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.none.rawValue,
            requiredGrantCapabilities: [],
            requiredRuntimeSurfaces: ["project_local_fs"],
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(XTSkillExecutionReadinessState.ready.rawValue),
            installHint: "",
            unblockActions: [],
            auditRef: "audit-readiness-evidence-1",
            doctorAuditRef: "",
            vetterAuditRef: "",
            resolvedSnapshotId: "snapshot-evidence-1",
            grantSnapshotRef: ""
        )

        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: "proj-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "memory_snapshot",
            toolName: ToolName.memory_snapshot.rawValue,
            status: .completed,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "memory refreshed",
            denyCode: "",
            resultEvidenceRef: nil,
            profileDeltaRef: nil,
            deltaApproval: deltaApproval,
            readinessRef: nil,
            readiness: readiness,
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 1_000,
            updatedAtMs: 1_020,
            auditRef: "audit-evidence-1"
        )

        let ref = SupervisorSkillResultEvidenceStore.write(
            record: record,
            toolCall: ToolCall(id: requestId, tool: .memory_snapshot, args: ["mode": .string("retrospective")]),
            rawOutput: "snapshot ok",
            triggerSource: "retry",
            ctx: ctx
        )

        let loaded = try #require(SupervisorSkillResultEvidenceStore.load(requestId: requestId, for: ctx))
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(ref == "local://supervisor_skill_results/\(requestId).json")
        #expect(loaded.requestId == requestId)
        #expect(loaded.rawOutput == "snapshot ok")
        #expect(loaded.profileDeltaRef == "\(ref!)#profile_delta")
        #expect(loaded.deltaApproval?.requestId == requestId)
        #expect(loaded.readinessRef == "\(ref!)#readiness")
        #expect(loaded.readiness?.executionReadiness == XTSkillExecutionReadinessState.ready.rawValue)
    }

    @Test
    func automationRetryPackageFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("retry-package")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let runId = "run-retry-1"
        let target = ctx.root.appendingPathComponent(xtAutomationRetryPackageRelativePath(for: runId))
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        let persisted = try #require(
            xtAutomationPersistRetryPackage(
                XTAutomationRetryPackage(
                    schemaVersion: XTAutomationRetryPackage.currentSchemaVersion,
                    generatedAt: 1_773_000_000,
                    projectID: "proj-alpha",
                    lineage: XTAutomationRunLineage.root(runID: "run-source-1"),
                    sourceRunID: "run-source-1",
                    sourceFinalState: .failed,
                    sourceHoldReason: "tool_failed",
                    sourceHandoffArtifactPath: "build/reports/handoff.json",
                    retryStrategy: "retry_failed_action",
                    retryReason: "action_failed",
                    suggestedNextActions: ["rerun failed action"],
                    additionalEvidenceRefs: ["audit://retry"],
                    planningMode: nil,
                    planningSummary: nil,
                    runtimePatchOverlay: nil,
                    revisedActionGraph: nil,
                    revisedVerifyCommands: nil,
                    planningArtifactPath: nil,
                    recipeProposalArtifactPath: nil,
                    retryRunID: runId,
                    retryArtifactPath: ""
                ),
                ctx: ctx
            )
        )

        let data = try Data(contentsOf: target)
        let decoded = try JSONDecoder().decode(XTAutomationRetryPackage.self, from: data)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(decoded.retryRunID == runId)
        #expect(persisted.retryArtifactPath == xtAutomationRetryPackageRelativePath(for: runId))
    }

    @Test
    func automationRetryPlanningArtifactFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("retry-planning")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let runId = "run-source-1"
        let relativePath = xtAutomationRetryPlanningArtifactRelativePath(for: runId)
        let target = ctx.root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        let savedPath = xtAutomationPersistRetryPlanningArtifact(
            XTAutomationRetryPlanningArtifact(
                schemaVersion: XTAutomationRetryPlanningArtifact.currentSchemaVersion,
                generatedAt: 1_773_000_001,
                projectID: "proj-alpha",
                lineage: XTAutomationRunLineage.root(runID: runId),
                sourceRunID: runId,
                sourceHandoffArtifactPath: "build/reports/handoff.json",
                baseRecipeRef: "retry@v1",
                retryStrategy: "retry_failed_action",
                retryReason: "action_failed",
                planningMode: "resume",
                planningSummary: "resume failed action only",
                runtimePatchOverlay: nil,
                proposedActionGraph: [],
                proposedVerifyCommands: ["swift test --filter RetryOnly"],
                suggestedNextActions: ["resume"],
                additionalEvidenceRefs: ["audit://planning"]
            ),
            ctx: ctx
        )

        let data = try Data(contentsOf: target)
        let decoded = try JSONDecoder().decode(XTAutomationRetryPlanningArtifact.self, from: data)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(savedPath == relativePath)
        #expect(decoded.sourceRunID == runId)
    }

    @Test
    func automationRetryRecipeProposalArtifactFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("retry-recipe")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let runId = "run-source-2"
        let relativePath = xtAutomationRetryRecipeProposalArtifactRelativePath(for: runId)
        let target = ctx.root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        let savedPath = xtAutomationPersistRetryRecipeProposalArtifact(
            XTAutomationRecipeProposalArtifact(
                schemaVersion: XTAutomationRecipeProposalArtifact.currentSchemaVersion,
                generatedAt: 1_773_000_002,
                projectID: "proj-alpha",
                lineage: XTAutomationRunLineage.root(runID: runId),
                sourceRunID: runId,
                sourceHandoffArtifactPath: "build/reports/handoff.json",
                sourcePlanningArtifactPath: "build/reports/planning.json",
                baseRecipeRef: "retry@v1",
                retryStrategy: "retry_failed_action",
                retryReason: "action_failed",
                proposalMode: "resume_from_failed_action",
                proposalSummary: "resume first failed action",
                runtimePatchOverlay: nil,
                proposedActionGraph: [],
                proposedVerifyCommands: ["swift test --filter RetryOnly"],
                suggestedNextActions: ["resume"],
                additionalEvidenceRefs: ["audit://proposal"]
            ),
            ctx: ctx
        )

        let data = try Data(contentsOf: target)
        let decoded = try JSONDecoder().decode(XTAutomationRecipeProposalArtifact.self, from: data)
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(savedPath == relativePath)
        #expect(decoded.sourceRunID == runId)
    }

    @Test
    func jurisdictionRegistryStoreFallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("jurisdiction-registry")
        defer { try? FileManager.default.removeItem(at: root) }

        let envKey = "XTERMINAL_PROJECT_REGISTRY_BASE_DIR"
        let previous = getenv(envKey).map { String(cString: $0) }
        setenv(envKey, root.path, 1)
        defer {
            if let previous {
                setenv(envKey, previous, 1)
            } else {
                unsetenv(envKey)
            }
        }

        let target = SupervisorJurisdictionRegistryStore.url()
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: target)

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        SupervisorJurisdictionRegistryStore.save(
            SupervisorJurisdictionRegistry.ownerDefault(now: 1_773_000_003).upserting(
                projectId: "proj-alpha",
                displayName: "Project Alpha",
                role: .observer,
                now: 1_773_000_003
            )
        )

        let loaded = SupervisorJurisdictionRegistryStore.load()
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(loaded.entries.first?.projectId == "proj-alpha")
        #expect(loaded.entries.first?.role == .observer)
    }

    @Test
    func writeSnapshotDataThrowsForNewTargetWhenAtomicTempWriteRunsOutOfSpace() throws {
        let root = try makeProjectRoot("new-target-out-of-space")
        defer { try? FileManager.default.removeItem(at: root) }

        let capture = SupervisorStoreWriteCapture()
        installScopedOutOfSpaceOverride(root: root, capture: capture)
        defer { SupervisorStoreWriteSupport.resetWriteBehaviorForTesting() }

        let target = root.appendingPathComponent("fresh.json")
        let payload = Data("{\"ok\":true}\n".utf8)

        #expect(throws: Error.self) {
            try SupervisorStoreWriteSupport.writeSnapshotData(payload, to: target)
        }

        let options = capture.writeOptionsSnapshot()
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(options.count == 1)
        #expect(options[0].contains(.atomic))
    }

    private func makeProjectRoot(_ suffix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_store_write_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func installScopedOutOfSpaceOverride(root: URL, capture: SupervisorStoreWriteCapture) {
        SupervisorStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            if !Self.normalizedPath(url).hasPrefix(Self.normalizedPath(root)) {
                try data.write(to: url, options: options)
                return
            }
            capture.appendWriteOption(options)
            if options.contains(.atomic) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
    }
}

private final class SupervisorStoreWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}
