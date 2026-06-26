import Foundation
import Testing
@testable import XTerminal

actor MemoryInspectorRecorder {
    private var requests: [(HubIPCClient.MemoryObjectListFilter, Double)] = []
    private var getRequests: [(String, Double)] = []
    private var historyRequests: [(String, Int, Double)] = []
    private var mutationRequests: [(String, String, HubIPCClient.MemoryObjectMutationPayload, Double)] = []

    func append(filter: HubIPCClient.MemoryObjectListFilter, timeoutSec: Double) {
        requests.append((filter, timeoutSec))
    }

    func appendHistory(memoryId: String, limit: Int, timeoutSec: Double) {
        historyRequests.append((memoryId, limit, timeoutSec))
    }

    func appendGet(memoryId: String, timeoutSec: Double) {
        getRequests.append((memoryId, timeoutSec))
    }

    func appendMutation(
        action: String,
        memoryId: String,
        payload: HubIPCClient.MemoryObjectMutationPayload,
        timeoutSec: Double
    ) {
        mutationRequests.append((action, memoryId, payload, timeoutSec))
    }

    func all() -> [(HubIPCClient.MemoryObjectListFilter, Double)] {
        requests
    }

    func histories() -> [(String, Int, Double)] {
        historyRequests
    }

    func gets() -> [(String, Double)] {
        getRequests
    }

    func mutations() -> [(String, String, HubIPCClient.MemoryObjectMutationPayload, Double)] {
        mutationRequests
    }

    func clear() {
        requests.removeAll()
        getRequests.removeAll()
        historyRequests.removeAll()
        mutationRequests.removeAll()
    }
}

struct MemoryInspectorTests {
    private static let gate = HubGlobalStateTestGate.shared

    @Test
    func rustMemoryObjectListResultDecodesActiveObjects() throws {
        let json = """
        {
          "schema_version": "xhub.memory.object_list.v1",
          "ok": true,
          "status": "ok",
          "count": 1,
          "objects": [{
            "schema_version": "xhub.memory.object.v1",
            "memory_id": "mem_project_decision",
            "scope": "project",
            "project_id": "project_alpha",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Active project decision",
            "text": "Decision: keep Rust as memory authority.",
            "summary": "Keep Rust as memory authority.",
            "sensitivity": "internal",
            "visibility": "local_only",
            "status": "active",
            "version": 2,
            "policy": {},
            "provenance": {}
          }],
          "filter": {
            "scope": "project",
            "project_id": "project_alpha",
            "status": "active",
            "limit": 50
          }
        }
        """

        let result = try JSONDecoder().decode(
            HubIPCClient.MemoryObjectListResult.self,
            from: Data(json.utf8)
        )

        #expect(result.ok)
        #expect(result.count == 1)
        #expect(result.filter?.scope == "project")
        #expect(result.objects.first?.memoryId == "mem_project_decision")
        #expect(result.objects.first?.status == "active")
        #expect(XTMemoryInspectorPresentation.bodyPreview(for: try #require(result.objects.first)) == "Keep Rust as memory authority.")
    }

    @Test
    func rustMemoryObjectHistoryResultDecodesEvents() throws {
        let json = """
        {
          "schema_version": "xhub.memory.object_history.v1",
          "ok": true,
          "status": "ok",
          "memory_id": "mem_project_decision",
          "count": 1,
          "events": [{
            "schema_version": "xhub.memory.event.v1",
            "event_id": "evt_decision_create",
            "memory_id": "mem_project_decision",
            "operation": "object_create",
            "actor": "rust_hub",
            "reason": "sync_project_canonical",
            "before_version": 0,
            "after_version": 1,
            "before_json": null,
            "after_json": {"text": "Sensitive body should stay out of inspector evidence."},
            "policy_decision": "allow",
            "deny_code": "",
            "audit_ref": "audit-create",
            "created_at_ms": 1779660000000
          }]
        }
        """

        let result = try JSONDecoder().decode(
            HubIPCClient.MemoryObjectHistoryResult.self,
            from: Data(json.utf8)
        )
        let event = try #require(result.events.first)

        #expect(result.ok)
        #expect(result.memoryId == "mem_project_decision")
        #expect(event.operation == "object_create")
        #expect(event.afterJson != nil)
        #expect(XTMemoryInspectorPresentation.historyLine(for: event).contains("object_create"))
        #expect(XTMemoryInspectorPresentation.historyLine(for: event).contains("v0->v1"))
        #expect(!XTMemoryInspectorPresentation.historyDetailLine(for: event).contains("Sensitive body"))
    }

    @Test
    func rustMemoryObjectMutationResultDecodesGovernedEnvelope() throws {
        let json = """
        {
          "schema_version": "xhub.memory.object_mutation.v1",
          "ok": true,
          "status": "archive",
          "memory_id": "mem_project_decision",
          "version": 3,
          "event_id": "evt_archive",
          "deny_code": "",
          "production_authority_change": false,
          "mutation": {
            "operation": "archive",
            "from_status": "active",
            "to_status": "archived",
            "from_pinned": true,
            "to_pinned": false,
            "confirmation_required": true,
            "confirmed": true,
            "confirmation_satisfied": true,
            "active_memory_mutation": true,
            "delete_mode": "",
            "authority": "rust_memory_object_store",
            "production_authority_change": false
          },
          "object": {
            "schema_version": "xhub.memory.object.v1",
            "memory_id": "mem_project_decision",
            "scope": "project",
            "project_id": "project_alpha",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Archived project decision",
            "text": "Sensitive body should not enter mutation evidence.",
            "summary": "Archived.",
            "sensitivity": "internal",
            "visibility": "local_only",
            "status": "archived",
            "pinned": false,
            "version": 3
          }
        }
        """

        let result = try JSONDecoder().decode(
            HubIPCClient.MemoryObjectMutationResult.self,
            from: Data(json.utf8)
        )

        #expect(result.ok)
        #expect(result.status == "archive")
        #expect(result.mutation?.operation == "archive")
        #expect(result.mutation?.fromPinned == true)
        #expect(result.mutation?.toPinned == false)
        #expect(result.mutation?.confirmationRequired == true)
        #expect(result.mutation?.confirmationSatisfied == true)
        #expect(result.mutation?.authority == "rust_memory_object_store")
        #expect(result.object?.status == "archived")
        #expect(result.productionAuthorityChange == false)
    }

    @Test
    func rustUserRevealGrantResultDecodesContentFreeEnvelope() throws {
        let json = """
        {
          "schema_version": "xhub.memory.user_reveal_grant.v1",
          "ok": true,
          "source": "rust_memory_user_reveal_grant",
          "status": "granted",
          "grant_id": "user_reveal_1779660000000_1",
          "scope": "user",
          "surface": "assistant_user_memory_inspector",
          "actor": "xt_swift_shell",
          "issued_at_ms": 1779660000000,
          "expires_at_ms": 1779660300000,
          "ttl_ms": 300000,
          "reason_code": "",
          "audit_ref_present": true,
          "content_included": false,
          "memory_ids_included": false,
          "project_coder_allowed": false,
          "model_context_authority": false,
          "memory_serving_authority_change": false,
          "production_authority_change": false
        }
        """

        let result = try JSONDecoder().decode(
            HubIPCClient.MemoryUserRevealGrantResult.self,
            from: Data(json.utf8)
        )

        #expect(result.ok)
        #expect(result.schemaVersion == "xhub.memory.user_reveal_grant.v1")
        #expect(result.scope == "user")
        #expect(result.surface == "assistant_user_memory_inspector")
        #expect(result.contentIncluded == false)
        #expect(result.memoryIdsIncluded == false)
        #expect(result.projectCoderAllowed == false)
        #expect(result.modelContextAuthority == false)
        #expect(result.memoryServingAuthorityChange == false)
        #expect(result.productionAuthorityChange == false)
        #expect(result.isActive(nowMs: 1779660001000))
        #expect(!result.isActive(nowMs: 1779660300000))
    }

    @MainActor
    @Test
    func projectInspectorRefreshUsesRustProjectScopeAndDropsCrossScopeObjects() async throws {
        let root = try makeProjectRoot(named: "memory-inspector-refresh")
        let ctx = AXProjectContext(root: root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let recorder = MemoryInspectorRecorder()
        let projectObject = makeMemoryObject(
            memoryId: "mem_project_active",
            projectId: projectId,
            scope: "project",
            sensitivity: "internal",
            text: "Decision: visible project memory."
        )
        let personalObject = makeMemoryObject(
            memoryId: "mem_personal_private",
            projectId: nil,
            scope: "user",
            sensitivity: "private",
            text: "Private personal memory must not render in project inspector."
        )

        HubIPCClient.installMemoryObjectListOverrideForTesting { filter, timeoutSec in
            await recorder.append(filter: filter, timeoutSec: timeoutSec)
            return HubIPCClient.MemoryObjectListResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                count: 2,
                objects: [projectObject, personalObject],
                filter: filter
            )
        }
        defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

        let store = XTMemoryInspectorStore()
        await store.refreshProject(
            ctx: ctx,
            filter: XTMemoryInspectorFilter(
                status: "active",
                layer: "l1_canonical",
                sourceKind: "decision_track",
                sensitivity: "internal",
                limit: 25
            ),
            timeoutSec: 0.25
        )

        let requests = await recorder.all()
        #expect(requests.count == 1)
        #expect(requests[0].0.scope == "project")
        #expect(requests[0].0.projectId == projectId)
        #expect(requests[0].0.status == "active")
        #expect(requests[0].0.layer == "l1_canonical")
        #expect(requests[0].0.sourceKind == "decision_track")
        #expect(requests[0].0.sensitivity == "internal")
        #expect(requests[0].0.limit == 25)

        #expect(store.snapshot.objects.map(\.memoryId) == ["mem_project_active"])
        #expect(store.snapshot.droppedCrossScopeCount == 1)
        #expect(XTMemoryInspectorPresentation.statusText(snapshot: store.snapshot).contains("1 active"))
        #expect(XTMemoryInspectorPresentation.statusText(snapshot: store.snapshot).contains("dropped 1 cross-scope"))

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"type\":\"memory_inspector_refresh\""))
        #expect(rawLog.contains("\"visible_object_count\":1"))
        #expect(rawLog.contains("\"dropped_cross_scope_count\":1"))
        #expect(!rawLog.contains("Private personal memory must not render"))
    }

    @MainActor
    @Test
    func assistantUserInspectorGateDeniesByDefaultAndDoesNotListRustObjects() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            HubIPCClient.installMemoryObjectListOverrideForTesting { filter, timeoutSec in
                await recorder.append(filter: filter, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectListResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    count: 0,
                    objects: [],
                    filter: filter
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let store = XTMemoryInspectorStore()
            await store.refreshAssistantUser(
                readiness: nil,
                userScopeGrantSatisfied: false,
                timeoutSec: 0.25
            )

            #expect(await recorder.all().isEmpty)
            #expect(store.assistantUserSnapshot.gate.ready == false)
            #expect(store.assistantUserSnapshot.gate.userScopeGrantRequired)
            #expect(store.assistantUserSnapshot.gate.userScopeGrantSatisfied == false)
            #expect(store.assistantUserSnapshot.gate.rustObjectStoreReady == false)
            #expect(store.assistantUserSnapshot.lastError == "assistant_user_memory_inspector_grant_required")

            let status = XTAssistantUserMemoryInspectorPresentation.statusText(
                snapshot: store.assistantUserSnapshot
            )
            #expect(status.contains("fail-closed"))
            #expect(status.contains("scope=user"))
            #expect(status.contains("grant required"))
            #expect(status.contains("object store not ready"))
            #expect(!status.contains("memory_id"))
            #expect(!status.contains("project_"))
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorUsesUserScopeOnlyAfterReadinessAndGrant() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let userObject = makeMemoryObject(
                memoryId: "mem_user_visible",
                projectId: nil,
                scope: "user",
                sensitivity: "private",
                text: "Private personal memory should not leak into gate status."
            )
            let projectObject = makeMemoryObject(
                memoryId: "mem_project_cross_scope",
                projectId: "project_cross_scope",
                scope: "project",
                sensitivity: "internal",
                text: "Project memory must not render in Assistant/User inspector."
            )

            HubIPCClient.installMemoryObjectListOverrideForTesting { filter, timeoutSec in
                await recorder.append(filter: filter, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectListResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    count: 2,
                    objects: [userObject, projectObject],
                    filter: filter
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let grant = HubIPCClient.MemoryUserRevealGrantResult(
                ok: true,
                source: "rust_http",
                status: "granted",
                grantId: "user_reveal_active",
                scope: "user",
                surface: "assistant_user_memory_inspector",
                actor: "xt_swift_shell",
                issuedAtMs: 1779660000000,
                expiresAtMs: 4779660000000,
                ttlMs: 300000,
                reasonCode: "",
                auditRefPresent: true,
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false
            )
            let store = XTMemoryInspectorStore()
            await store.refreshAssistantUser(
                readiness: readiness,
                userScopeGrantSatisfied: false,
                userRevealGrant: grant,
                filter: XTMemoryInspectorFilter(
                    status: "active",
                    layer: "l1_canonical",
                    sourceKind: "personal_preference",
                    sensitivity: "private",
                    limit: 20
                ),
                timeoutSec: 0.25
            )

            let requests = await recorder.all()
            #expect(requests.count == 1)
            #expect(requests[0].0.scope == "user")
            #expect(requests[0].0.projectId == nil)
            #expect(requests[0].0.ownerId == nil)
            #expect(requests[0].0.layer == "l1_canonical")
            #expect(requests[0].0.sourceKind == "personal_preference")
            #expect(requests[0].0.sensitivity == "private")
            #expect(requests[0].0.limit == 20)
            #expect(requests[0].1 == 0.25)

            #expect(store.assistantUserSnapshot.gate.ready)
            #expect(store.assistantUserSnapshot.objects.map(\.memoryId) == ["mem_user_visible"])
            #expect(store.assistantUserSnapshot.objects.first?.title == "Rust user memory object")
            #expect(store.assistantUserSnapshot.objects.first?.text == nil)
            #expect(store.assistantUserSnapshot.objects.first?.summary == nil)
            #expect(store.assistantUserSnapshot.droppedCrossScopeCount == 1)
            let status = XTAssistantUserMemoryInspectorPresentation.statusText(
                snapshot: store.assistantUserSnapshot
            )
            #expect(status.contains("1 user objects"))
            #expect(!status.contains("mem_user_visible"))
            #expect(!status.contains("Private personal memory"))
            #expect(
                XTAssistantUserMemoryInspectorPresentation.scopeLine(
                    snapshot: store.assistantUserSnapshot
                ) == "scope=user · authority=rust_memory_object_store · Swift shell only"
            )
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorExpiredRustGrantDoesNotListObjects() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            HubIPCClient.installMemoryObjectListOverrideForTesting { filter, timeoutSec in
                await recorder.append(filter: filter, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectListResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    count: 0,
                    objects: [],
                    filter: filter
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let expiredGrant = HubIPCClient.MemoryUserRevealGrantResult(
                ok: false,
                source: "rust_http",
                status: "expired",
                grantId: "user_reveal_expired",
                scope: "user",
                surface: "assistant_user_memory_inspector",
                actor: "xt_swift_shell",
                issuedAtMs: 1779660000000,
                expiresAtMs: 1779660001000,
                ttlMs: 1000,
                reasonCode: "memory_user_reveal_grant_expired",
                auditRefPresent: false,
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false
            )
            let store = XTMemoryInspectorStore()
            await store.refreshAssistantUser(
                readiness: readiness,
                userScopeGrantSatisfied: true,
                userRevealGrant: expiredGrant,
                timeoutSec: 0.25
            )

            #expect(await recorder.all().isEmpty)
            #expect(store.assistantUserSnapshot.gate.ready == false)
            #expect(store.assistantUserSnapshot.gate.userScopeGrantSatisfied == false)
            #expect(store.assistantUserSnapshot.lastError == "assistant_user_memory_inspector_grant_required")
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorLoadsGatedDetailAndHistoryWithoutContent() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let userObject: HubIPCClient.MemoryWritebackCandidateObject = {
                var object = makeMemoryObject(
                    memoryId: "mem_user_detail",
                    projectId: nil,
                    scope: "user",
                    sensitivity: "private",
                    text: "Private user memory body must stay hidden."
                )
                object.title = "Private title must stay hidden"
                object.summary = "Private summary must stay hidden."
                return object
            }()

            HubIPCClient.installMemoryObjectListOverrideForTesting { filter, timeoutSec in
                await recorder.append(filter: filter, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectListResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    count: 1,
                    objects: [userObject],
                    filter: filter
                )
            }
            HubIPCClient.installMemoryObjectGetOverrideForTesting { memoryId, timeoutSec in
                await recorder.appendGet(memoryId: memoryId, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    memoryId: memoryId,
                    object: userObject
                )
            }
            HubIPCClient.installMemoryObjectHistoryOverrideForTesting { memoryId, limit, timeoutSec in
                await recorder.appendHistory(memoryId: memoryId, limit: limit, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectHistoryResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    memoryId: memoryId,
                    count: 2,
                    events: [
                        HubIPCClient.MemoryObjectHistoryEvent(
                            schemaVersion: "xhub.memory.event.v1",
                            eventId: "evt_user_detail",
                            memoryId: memoryId,
                            operation: "object_update",
                            actor: "rust_hub",
                            reason: "assistant_user_review",
                            beforeVersion: 1,
                            afterVersion: 2,
                            beforeJson: nil,
                            afterJson: .object(["text": .string("Private event body must stay hidden.")]),
                            policyDecision: "allow",
                            denyCode: "",
                            auditRef: "audit-user-detail",
                            createdAtMs: 1779660000000
                        ),
                        HubIPCClient.MemoryObjectHistoryEvent(
                            schemaVersion: "xhub.memory.event.v1",
                            eventId: "evt_other_detail",
                            memoryId: "mem_other_user",
                            operation: "object_update",
                            actor: "rust_hub",
                            reason: "other_object",
                            beforeVersion: 1,
                            afterVersion: 2,
                            beforeJson: nil,
                            afterJson: .object([:]),
                            policyDecision: "allow",
                            denyCode: "",
                            auditRef: "audit-other",
                            createdAtMs: 1779660000001
                        )
                    ]
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let grant = HubIPCClient.MemoryUserRevealGrantResult(
                ok: true,
                source: "rust_http",
                status: "granted",
                grantId: "user_reveal_active",
                scope: "user",
                surface: "assistant_user_memory_inspector",
                actor: "xt_swift_shell",
                issuedAtMs: 1779660000000,
                expiresAtMs: 4779660000000,
                ttlMs: 300000,
                reasonCode: "",
                auditRefPresent: true,
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false
            )
            let store = XTMemoryInspectorStore()
            await store.refreshAssistantUser(
                readiness: readiness,
                userScopeGrantSatisfied: false,
                userRevealGrant: grant,
                timeoutSec: 0.25
            )
            guard let shellObject = store.assistantUserSnapshot.objects.first else {
                Issue.record("expected shell object")
                return
            }
            await store.loadAssistantUserDetail(
                object: shellObject,
                readiness: readiness,
                userRevealGrant: grant,
                timeoutSec: 0.25
            )
            await store.loadAssistantUserHistory(
                object: shellObject,
                readiness: readiness,
                userRevealGrant: grant,
                limit: 6,
                timeoutSec: 0.25
            )

            #expect((await recorder.gets()).map(\.0) == ["mem_user_detail"])
            #expect((await recorder.histories()).map(\.0) == ["mem_user_detail"])
            #expect((await recorder.histories()).first?.1 == 6)
            #expect(store.assistantUserSnapshot.lastResult?.objects.first?.text == nil)
            #expect(store.assistantUserSnapshot.lastResult?.objects.first?.summary == nil)
            guard let detail = store.assistantUserSnapshot.details["mem_user_detail"] else {
                Issue.record("expected assistant/user detail")
                return
            }
            #expect(detail.object?.title == "Rust user memory object")
            #expect(detail.object?.text == nil)
            #expect(detail.object?.summary == nil)
            #expect(detail.object?.provenance == nil)
            #expect(detail.object?.policy == nil)
            let detailLine = XTMemoryInspectorPresentation.assistantUserDetailLine(
                for: detail.object ?? shellObject
            )
            #expect(detailLine.contains("scope=user"))
            #expect(!detailLine.contains("mem_user_detail"))
            #expect(!detailLine.contains("Private user memory"))
            #expect(!detailLine.contains("Private title"))
            #expect(!detailLine.contains("Private summary"))
            guard let history = store.assistantUserSnapshot.histories["mem_user_detail"],
                  let firstEvent = history.events.first else {
                Issue.record("expected assistant/user history")
                return
            }
            #expect(history.events.map(\.eventId) == ["evt_user_detail"])
            #expect(XTMemoryInspectorPresentation.historyLine(for: firstEvent).contains("object_update"))
            #expect(!XTMemoryInspectorPresentation.historyDetailLine(for: firstEvent).contains("Private event body"))
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorDetailAndHistoryRequireActiveRustGrant() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let object = makeMemoryObject(
                memoryId: "mem_user_denied",
                projectId: nil,
                scope: "user",
                sensitivity: "private",
                text: "Denied detail body."
            )
            HubIPCClient.installMemoryObjectGetOverrideForTesting { memoryId, timeoutSec in
                await recorder.appendGet(memoryId: memoryId, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    memoryId: memoryId,
                    object: object
                )
            }
            HubIPCClient.installMemoryObjectHistoryOverrideForTesting { memoryId, limit, timeoutSec in
                await recorder.appendHistory(memoryId: memoryId, limit: limit, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectHistoryResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    memoryId: memoryId,
                    count: 0,
                    events: []
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let expiredGrant = HubIPCClient.MemoryUserRevealGrantResult(
                ok: false,
                source: "rust_http",
                status: "expired",
                grantId: "user_reveal_expired",
                scope: "user",
                surface: "assistant_user_memory_inspector",
                actor: "xt_swift_shell",
                issuedAtMs: 1779660000000,
                expiresAtMs: 1779660001000,
                ttlMs: 1000,
                reasonCode: "memory_user_reveal_grant_expired",
                auditRefPresent: false,
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false
            )
            let store = XTMemoryInspectorStore()
            let shellObject = XTMemoryInspectorPresentation.assistantUserShellObject(object)
            await store.loadAssistantUserDetail(
                object: shellObject,
                readiness: readiness,
                userRevealGrant: expiredGrant,
                timeoutSec: 0.25
            )
            await store.loadAssistantUserHistory(
                object: shellObject,
                readiness: readiness,
                userRevealGrant: expiredGrant,
                limit: 6,
                timeoutSec: 0.25
            )

            #expect((await recorder.gets()).isEmpty)
            #expect((await recorder.histories()).isEmpty)
            #expect(store.assistantUserSnapshot.details["mem_user_denied"]?.lastError == "assistant_user_memory_inspector_grant_required")
            #expect(store.assistantUserSnapshot.histories["mem_user_denied"]?.lastError == "assistant_user_memory_inspector_grant_required")
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorMutationRequiresActiveRustGrant() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let object = makeMemoryObject(
                memoryId: "mem_user_mutation_denied",
                projectId: nil,
                scope: "user",
                sensitivity: "private",
                text: "Denied mutation body."
            )
            HubIPCClient.installMemoryObjectMutationOverrideForTesting { action, memoryId, payload, timeoutSec in
                await recorder.appendMutation(
                    action: action,
                    memoryId: memoryId,
                    payload: payload,
                    timeoutSec: timeoutSec
                )
                return HubIPCClient.MemoryObjectMutationResult(
                    ok: true,
                    source: "rust_http",
                    status: action,
                    memoryId: memoryId,
                    action: action,
                    object: object,
                    productionAuthorityChange: false
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let expiredGrant = HubIPCClient.MemoryUserRevealGrantResult(
                ok: false,
                source: "rust_http",
                status: "expired",
                grantId: "user_reveal_expired",
                scope: "user",
                surface: "assistant_user_memory_inspector",
                actor: "xt_swift_shell",
                issuedAtMs: 1779660000000,
                expiresAtMs: 1779660001000,
                ttlMs: 1000,
                reasonCode: "memory_user_reveal_grant_expired",
                auditRefPresent: false,
                contentIncluded: false,
                memoryIdsIncluded: false,
                projectCoderAllowed: false,
                modelContextAuthority: false,
                memoryServingAuthorityChange: false,
                productionAuthorityChange: false
            )
            let store = XTMemoryInspectorStore()
            let result = await store.mutateAssistantUserObject(
                object: XTMemoryInspectorPresentation.assistantUserShellObject(object),
                action: "archive",
                payload: XTMemoryInspectorPresentation.mutationPayload(action: .archive),
                readiness: readiness,
                userRevealGrant: expiredGrant,
                timeoutSec: 0.25
            )

            #expect(await recorder.mutations().isEmpty)
            #expect(result.ok == false)
            #expect(result.reasonCode == "assistant_user_memory_inspector_grant_required")
            #expect(result.memoryId == nil)
            #expect(store.assistantUserSnapshot.lastMutationResult?.reasonCode == "assistant_user_memory_inspector_grant_required")
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorMutationRejectsProjectScopeObject() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let object = makeMemoryObject(
                memoryId: "mem_project_wrong_scope",
                projectId: "project_wrong_scope",
                scope: "project",
                sensitivity: "internal",
                text: "Project object must not be mutated from Assistant/User inspector."
            )
            HubIPCClient.installMemoryObjectMutationOverrideForTesting { action, memoryId, payload, timeoutSec in
                await recorder.appendMutation(
                    action: action,
                    memoryId: memoryId,
                    payload: payload,
                    timeoutSec: timeoutSec
                )
                return HubIPCClient.MemoryObjectMutationResult(
                    ok: true,
                    source: "rust_http",
                    status: action,
                    memoryId: memoryId,
                    action: action,
                    object: object,
                    productionAuthorityChange: false
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let store = XTMemoryInspectorStore()
            let result = await store.mutateAssistantUserObject(
                object: object,
                action: "pin",
                payload: XTMemoryInspectorPresentation.mutationPayload(action: .pin),
                readiness: readiness,
                userRevealGrant: Self.makeActiveUserRevealGrant(),
                timeoutSec: 0.25
            )

            #expect(await recorder.mutations().isEmpty)
            #expect(result.ok == false)
            #expect(result.reasonCode == "assistant_user_memory_mutation_scope_mismatch")
            #expect(store.assistantUserSnapshot.lastError == "assistant_user_memory_mutation_scope_mismatch")
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorMutationUsesRustGateAndKeepsShellContentHidden() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let object: HubIPCClient.MemoryWritebackCandidateObject = {
                var object = makeMemoryObject(
                    memoryId: "mem_user_mutation",
                    projectId: nil,
                    scope: "user",
                    sensitivity: "private",
                    text: "Private mutation body must stay hidden."
                )
                object.title = "Private title must stay hidden"
                object.summary = "Private summary must stay hidden"
                return object
            }()
            let archivedObject: HubIPCClient.MemoryWritebackCandidateObject = {
                var archived = object
                archived.status = "archived"
                archived.pinned = false
                archived.version = 2
                return archived
            }()

            HubIPCClient.installMemoryObjectMutationOverrideForTesting { action, memoryId, payload, timeoutSec in
                await recorder.appendMutation(
                    action: action,
                    memoryId: memoryId,
                    payload: payload,
                    timeoutSec: timeoutSec
                )
                return HubIPCClient.MemoryObjectMutationResult(
                    ok: true,
                    source: "rust_http",
                    status: action,
                    memoryId: memoryId,
                    version: 2,
                    eventId: "evt_user_mutation_should_not_render",
                    action: action,
                    mutation: HubIPCClient.MemoryObjectMutationSummary(
                        operation: action,
                        fromStatus: "active",
                        toStatus: "archived",
                        fromPinned: false,
                        toPinned: false,
                        confirmationRequired: true,
                        confirmed: true,
                        confirmationSatisfied: true,
                        activeMemoryMutation: true,
                        deleteMode: "",
                        authority: "rust_memory_object_store",
                        productionAuthorityChange: false
                    ),
                    object: archivedObject,
                    productionAuthorityChange: false
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let store = XTMemoryInspectorStore()
            let result = await store.mutateAssistantUserObject(
                object: XTMemoryInspectorPresentation.assistantUserShellObject(object),
                action: "archive",
                payload: XTMemoryInspectorPresentation.mutationPayload(action: .archive),
                readiness: readiness,
                userRevealGrant: Self.makeActiveUserRevealGrant(),
                timeoutSec: 0.25
            )

            let requests = await recorder.mutations()
            #expect(requests.count == 1)
            #expect(requests[0].0 == "archive")
            #expect(requests[0].1 == "mem_user_mutation")
            #expect(requests[0].2.actor == "xt_swift_shell")
            #expect(requests[0].2.requesterRole == "supervisor")
            #expect(requests[0].2.useMode == "assistant_user_memory_inspector")
            #expect(requests[0].2.userRevealGrantId == "user_reveal_active")
            #expect(requests[0].2.confirmArchive == true)
            #expect(requests[0].3 == 0.25)
            #expect(result.ok)
            #expect(result.memoryId == nil)
            #expect(result.eventId == nil)
            #expect(result.object?.title == "Rust user memory object")
            #expect(result.object?.text == nil)
            #expect(result.object?.summary == nil)
            #expect(result.object?.provenance == nil)
            #expect(result.object?.policy == nil)
            #expect(store.assistantUserSnapshot.lastMutationResult?.eventId == nil)
            #expect(store.assistantUserSnapshot.objects.isEmpty)
            #expect(store.assistantUserSnapshot.details["mem_user_mutation"]?.object?.status == "archived")
            #expect(store.assistantUserSnapshot.details["mem_user_mutation"]?.object?.text == nil)
            let status = XTMemoryInspectorPresentation.mutationStatusText(result) ?? ""
            #expect(status.contains("archive ok"))
            #expect(!status.contains("mem_user_mutation"))
            #expect(!status.contains("evt_user_mutation"))
            #expect(!status.contains("Private mutation body"))
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorMutationDoesNotRefreshHistoryUnlessAlreadyLoaded() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let object = makeMemoryObject(
                memoryId: "mem_user_mutation_no_history",
                projectId: nil,
                scope: "user",
                sensitivity: "private",
                text: "Private body should not be fetched through history refresh."
            )
            let pinnedObject: HubIPCClient.MemoryWritebackCandidateObject = {
                var updated = object
                updated.pinned = true
                updated.version = 2
                return updated
            }()

            HubIPCClient.installMemoryObjectMutationOverrideForTesting { action, memoryId, payload, timeoutSec in
                await recorder.appendMutation(
                    action: action,
                    memoryId: memoryId,
                    payload: payload,
                    timeoutSec: timeoutSec
                )
                return HubIPCClient.MemoryObjectMutationResult(
                    ok: true,
                    source: "rust_http",
                    status: action,
                    memoryId: memoryId,
                    version: 2,
                    eventId: "evt_user_pin_should_not_render",
                    action: action,
                    mutation: HubIPCClient.MemoryObjectMutationSummary(
                        operation: action,
                        fromStatus: "active",
                        toStatus: "active",
                        fromPinned: false,
                        toPinned: true,
                        confirmationRequired: false,
                        confirmed: true,
                        confirmationSatisfied: true,
                        activeMemoryMutation: true,
                        deleteMode: "",
                        authority: "rust_memory_object_store",
                        productionAuthorityChange: false
                    ),
                    object: pinnedObject,
                    productionAuthorityChange: false
                )
            }
            HubIPCClient.installMemoryObjectHistoryOverrideForTesting { memoryId, limit, timeoutSec in
                await recorder.appendHistory(memoryId: memoryId, limit: limit, timeoutSec: timeoutSec)
                return HubIPCClient.MemoryObjectHistoryResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    memoryId: memoryId,
                    count: 0,
                    events: []
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let store = XTMemoryInspectorStore()
            let result = await store.mutateAssistantUserObject(
                object: XTMemoryInspectorPresentation.assistantUserShellObject(object),
                action: "pin",
                payload: XTMemoryInspectorPresentation.mutationPayload(action: .pin),
                readiness: readiness,
                userRevealGrant: Self.makeActiveUserRevealGrant(),
                refreshHistoryIfLoaded: true,
                historyLimit: 8,
                timeoutSec: 0.25
            )

            #expect(result.ok)
            #expect((await recorder.histories()).isEmpty)
            #expect(store.assistantUserSnapshot.lastMutationHistoryRefresh?.attempted == false)
            #expect(store.assistantUserSnapshot.lastMutationHistoryRefresh?.reasonCode == "history_not_open_on_demand")
            let line = XTMemoryInspectorPresentation.assistantUserMutationHistoryRefreshText(
                store.assistantUserSnapshot.lastMutationHistoryRefresh
            ) ?? ""
            #expect(line.contains("history not refreshed"))
            #expect(!line.contains("mem_user_mutation_no_history"))
            #expect(!line.contains("Private body"))
        }
    }

    @MainActor
    @Test
    func assistantUserInspectorMutationRefreshesLoadedHistoryContentFree() async {
        await Self.gate.runOnMainActor {
            let recorder = MemoryInspectorRecorder()
            let readiness = Self.makeReadyMemoryReadiness()
            let object = makeMemoryObject(
                memoryId: "mem_user_mutation_history",
                projectId: nil,
                scope: "user",
                sensitivity: "private",
                text: "Private body must not enter refreshed history status."
            )
            let archivedObject: HubIPCClient.MemoryWritebackCandidateObject = {
                var updated = object
                updated.status = "archived"
                updated.version = 2
                return updated
            }()

            HubIPCClient.installMemoryObjectHistoryOverrideForTesting { memoryId, limit, timeoutSec in
                await recorder.appendHistory(memoryId: memoryId, limit: limit, timeoutSec: timeoutSec)
                let requestCount = await recorder.histories().count
                let operation = requestCount == 1 ? "object_create" : "archive"
                let eventId = requestCount == 1 ? "evt_user_history_initial" : "evt_user_history_archive"
                return HubIPCClient.MemoryObjectHistoryResult(
                    ok: true,
                    source: "rust_http",
                    status: "ok",
                    memoryId: memoryId,
                    count: 1,
                    events: [
                        HubIPCClient.MemoryObjectHistoryEvent(
                            schemaVersion: "xhub.memory.event.v1",
                            eventId: eventId,
                            memoryId: memoryId,
                            operation: operation,
                            actor: "rust_hub",
                            reason: "private reason should not render as body",
                            beforeVersion: requestCount == 1 ? nil : 1,
                            afterVersion: requestCount == 1 ? 1 : 2,
                            beforeJson: nil,
                            afterJson: .object(["text": .string("Private history body should stay hidden.")]),
                            policyDecision: "allow",
                            denyCode: "",
                            auditRef: "audit-user-history-refresh",
                            createdAtMs: 1779660000000 + Int64(requestCount)
                        )
                    ]
                )
            }
            HubIPCClient.installMemoryObjectMutationOverrideForTesting { action, memoryId, payload, timeoutSec in
                await recorder.appendMutation(
                    action: action,
                    memoryId: memoryId,
                    payload: payload,
                    timeoutSec: timeoutSec
                )
                return HubIPCClient.MemoryObjectMutationResult(
                    ok: true,
                    source: "rust_http",
                    status: action,
                    memoryId: memoryId,
                    version: 2,
                    eventId: "evt_user_archive_should_not_render",
                    action: action,
                    mutation: HubIPCClient.MemoryObjectMutationSummary(
                        operation: action,
                        fromStatus: "active",
                        toStatus: "archived",
                        fromPinned: false,
                        toPinned: false,
                        confirmationRequired: true,
                        confirmed: true,
                        confirmationSatisfied: true,
                        activeMemoryMutation: true,
                        deleteMode: "",
                        authority: "rust_memory_object_store",
                        productionAuthorityChange: false
                    ),
                    object: archivedObject,
                    productionAuthorityChange: false
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let store = XTMemoryInspectorStore()
            let shellObject = XTMemoryInspectorPresentation.assistantUserShellObject(object)
            await store.loadAssistantUserHistory(
                object: shellObject,
                readiness: readiness,
                userRevealGrant: Self.makeActiveUserRevealGrant(),
                limit: 4,
                timeoutSec: 0.25
            )
            let result = await store.mutateAssistantUserObject(
                object: shellObject,
                action: "archive",
                payload: XTMemoryInspectorPresentation.mutationPayload(action: .archive),
                readiness: readiness,
                userRevealGrant: Self.makeActiveUserRevealGrant(),
                refreshHistoryIfLoaded: true,
                historyLimit: 7,
                timeoutSec: 0.25
            )

            #expect(result.ok)
            let historyRequests = await recorder.histories()
            #expect(historyRequests.count == 2)
            #expect(historyRequests[0].0 == "mem_user_mutation_history")
            #expect(historyRequests[0].1 == 4)
            #expect(historyRequests[1].0 == "mem_user_mutation_history")
            #expect(historyRequests[1].1 == 7)
            #expect(store.assistantUserSnapshot.lastMutationHistoryRefresh?.attempted == true)
            #expect(store.assistantUserSnapshot.lastMutationHistoryRefresh?.refreshed == true)
            #expect(store.assistantUserSnapshot.lastMutationHistoryRefresh?.eventCount == 1)
            #expect(store.assistantUserSnapshot.histories["mem_user_mutation_history"]?.events.first?.operation == "archive")
            let line = XTMemoryInspectorPresentation.assistantUserMutationHistoryRefreshText(
                store.assistantUserSnapshot.lastMutationHistoryRefresh
            ) ?? ""
            #expect(line == "history refreshed · events=1 · content=hidden")
            #expect(!line.contains("mem_user_mutation_history"))
            #expect(!line.contains("evt_user_history_archive"))
            #expect(!line.contains("Private history body"))
        }
    }

    @MainActor
    @Test
    func projectInspectorHistoryLoadsGovernanceEventsWithoutLoggingContent() async throws {
        let root = try makeProjectRoot(named: "memory-inspector-history")
        let ctx = AXProjectContext(root: root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let recorder = MemoryInspectorRecorder()
        let object = makeMemoryObject(
            memoryId: "mem_project_active",
            projectId: projectId,
            scope: "project",
            sensitivity: "internal",
            text: "Decision: visible project memory."
        )

        HubIPCClient.installMemoryObjectHistoryOverrideForTesting { memoryId, limit, timeoutSec in
            await recorder.appendHistory(memoryId: memoryId, limit: limit, timeoutSec: timeoutSec)
            return HubIPCClient.MemoryObjectHistoryResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                memoryId: memoryId,
                count: 2,
                events: [
                    HubIPCClient.MemoryObjectHistoryEvent(
                        schemaVersion: "xhub.memory.event.v1",
                        eventId: "evt_visible",
                        memoryId: memoryId,
                        operation: "object_create",
                        actor: "rust_hub",
                        reason: "sync_project_canonical",
                        beforeVersion: 0,
                        afterVersion: 1,
                        beforeJson: nil,
                        afterJson: .object(["text": .string("Secret body should not enter evidence.")]),
                        policyDecision: "allow",
                        denyCode: "",
                        auditRef: "audit-visible",
                        createdAtMs: 1779660000000
                    ),
                    HubIPCClient.MemoryObjectHistoryEvent(
                        schemaVersion: "xhub.memory.event.v1",
                        eventId: "evt_other",
                        memoryId: "mem_other",
                        operation: "object_update",
                        actor: "rust_hub",
                        reason: "other_object",
                        beforeVersion: 1,
                        afterVersion: 2,
                        beforeJson: nil,
                        afterJson: .object([:]),
                        policyDecision: "allow",
                        denyCode: "",
                        auditRef: "audit-other",
                        createdAtMs: 1779660000001
                    )
                ]
            )
        }
        defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

        let store = XTMemoryInspectorStore()
        await store.loadHistory(object: object, ctx: ctx, limit: 12, timeoutSec: 0.25)

        let requests = await recorder.histories()
        #expect(requests.count == 1)
        #expect(requests[0].0 == "mem_project_active")
        #expect(requests[0].1 == 12)
        #expect(store.snapshot.histories["mem_project_active"]?.events.map(\.eventId) == ["evt_visible"])
        #expect(XTMemoryInspectorPresentation.historyStatusText(store.snapshot.histories["mem_project_active"]) == "1 history events")

        let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(rawLog.contains("\"type\":\"memory_inspector_history\""))
        #expect(rawLog.contains("\"visible_event_count\":1"))
        #expect(rawLog.contains("\"dropped_event_count\":1"))
        #expect(!rawLog.contains("Secret body should not enter evidence"))
        #expect(!rawLog.contains("mem_project_active"))
    }

    @MainActor
    @Test
    func projectInspectorMutationUsesRustGateAndLogsBoundedEvidenceOnly() async throws {
        try await Self.gate.runOnMainActor {
            let root = try makeProjectRoot(named: "memory-inspector-mutation")
            let ctx = AXProjectContext(root: root)
            let projectId = AXProjectRegistryStore.projectId(forRoot: root)
            let recorder = MemoryInspectorRecorder()
            let object = makeMemoryObject(
                memoryId: "mem_project_mutate",
                projectId: projectId,
                scope: "project",
                sensitivity: "internal",
                text: "Sensitive mutation body should not enter raw evidence."
            )
            var archived = object
            archived.status = "archived"
            archived.pinned = false
            archived.version = 2
            let archivedObject = archived

            HubIPCClient.installMemoryObjectMutationOverrideForTesting { action, memoryId, payload, timeoutSec in
                await recorder.appendMutation(
                    action: action,
                    memoryId: memoryId,
                    payload: payload,
                    timeoutSec: timeoutSec
                )
                return HubIPCClient.MemoryObjectMutationResult(
                    ok: true,
                    source: "rust_http",
                    status: action,
                    memoryId: memoryId,
                    version: 2,
                    eventId: "evt_archive_should_not_be_logged",
                    action: action,
                    mutation: HubIPCClient.MemoryObjectMutationSummary(
                        operation: action,
                        fromStatus: "active",
                        toStatus: "archived",
                        fromPinned: true,
                        toPinned: false,
                        confirmationRequired: true,
                        confirmed: true,
                        confirmationSatisfied: true,
                        activeMemoryMutation: true,
                        deleteMode: "",
                        authority: "rust_memory_object_store",
                        productionAuthorityChange: false
                    ),
                    object: archivedObject,
                    productionAuthorityChange: false
                )
            }
            defer { HubIPCClient.resetMemoryObjectOverridesForTesting() }

            let store = XTMemoryInspectorStore()
            let result = await store.mutateProjectObject(
                ctx: ctx,
                object: object,
                action: "archive",
                payload: HubIPCClient.MemoryObjectMutationPayload(
                    auditRef: "memory-inspector-archive",
                    reason: "user_confirmed_archive_from_inspector",
                    confirm: true
                ),
                timeoutSec: 0.25
            )

            let requests = await recorder.mutations()
            #expect(requests.count == 1)
            #expect(requests[0].0 == "archive")
            #expect(requests[0].1 == "mem_project_mutate")
            #expect(requests[0].2.actor == "xt_swift_shell")
            #expect(requests[0].2.confirm == true)
            #expect(requests[0].2.confirmArchive == true)
            #expect(requests[0].3 == 0.25)
            #expect(result.ok)
            #expect(store.snapshot.lastMutationResult?.mutation?.authority == "rust_memory_object_store")
            #expect(store.snapshot.objects.isEmpty)

            let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
            #expect(rawLog.contains("\"type\":\"memory_inspector_object_mutation\""))
            #expect(rawLog.contains("\"action\":\"archive\""))
            #expect(rawLog.contains("\"event_id_present\":true"))
            #expect(rawLog.contains("\"confirmation_satisfied\":true"))
            #expect(rawLog.contains("\"mutation_authority\":\"rust_memory_object_store\""))
            #expect(rawLog.contains("\"production_authority_change\":false"))
            #expect(!rawLog.contains("mem_project_mutate"))
            #expect(!rawLog.contains("evt_archive_should_not_be_logged"))
            #expect(!rawLog.contains("Sensitive mutation body"))
        }
    }

    @Test
    func oldSelectionEvidenceCacheDecodesWithoutSelectedRefs() throws {
        let json = """
        {
          "schema_version": "xt.rust_memory_gateway_model_call_plan_shadow.v1",
          "ok": true,
          "source": "xt_rust_memory_gateway_model_call_plan_shadow",
          "mode": "shadow_preflight_no_product_cutover",
          "request_id": "old-plan",
          "requester_role": "chat",
          "use_mode": "project_chat",
          "scope": "project",
          "project_id": "project_old",
          "task_kind": "chat_plan",
          "plan_status": "planned",
          "plan_source": "rust_memory_gateway_model_call_plan",
          "plan_mode": "plan_only_no_model_call",
          "plan_authority": "rust_memory_gateway_plan_only",
          "context_char_count": 128,
          "selected_ref_count": 2,
          "prompt_char_count": 64,
          "message_count": 0,
          "would_call_model": false,
          "model_call_executed": false,
          "production_authority_change": false,
          "context_text_included": false,
          "prompt_text_included": false,
          "issue_codes": [],
          "recorded_at_ms": 1779660000000
        }
        """

        let evidence = try JSONDecoder().decode(
            HubIPCClient.RustMemoryGatewayModelCallPlanEvidence.self,
            from: Data(json.utf8)
        )

        #expect(evidence.selectedRefCount == 2)
        #expect(evidence.selectedRefs == nil)
        #expect(evidence.selectedChunkCount == nil)
        #expect(evidence.omittedRefCount == nil)
        #expect(evidence.omittedCount == nil)
        #expect(XTMemorySelectionEvidencePresentation.countLine(for: evidence).contains("selected_refs=2"))
        #expect(!XTMemorySelectionEvidencePresentation.countLine(for: evidence).contains("selected_chunks="))
    }

    @Test
    func selectionEvidenceCacheDecodesChunkRefsWithoutContent() throws {
        let json = """
        {
          "schema_version": "xt.rust_memory_gateway_model_call_plan_shadow.v1",
          "ok": true,
          "source": "xt_rust_memory_gateway_model_call_plan_shadow",
          "mode": "shadow_preflight_no_product_cutover",
          "request_id": "chunk-plan",
          "requester_role": "chat",
          "use_mode": "project_chat",
          "scope": "project",
          "project_id": "project_chunk",
          "task_kind": "chat_plan",
          "plan_status": "planned",
          "plan_source": "rust_memory_gateway_model_call_plan",
          "plan_mode": "plan_only_no_model_call",
          "plan_authority": "rust_memory_gateway_plan_only",
          "context_char_count": 128,
          "selected_ref_count": 1,
          "selected_count": 1,
          "selected_chunk_count": 1,
          "omitted_count": 1,
          "omitted_ref_count": 1,
          "index_granularity": "object_chunk",
          "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
          "chunk_expand_via_get_ref": true,
          "selected_refs": [
            {
              "ref": "memory://rust/object/mem_chunk_selected",
              "chunk_ref": "memory://rust/object/mem_chunk_selected#object-0-lines-1-12",
              "chunk_id": "object-0-lines-1-12",
              "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
              "chunk_start_line": 1,
              "chunk_end_line": 12,
              "memory_id": "mem_chunk_selected",
              "layer": "l1_canonical",
              "source_kind": "project_fact",
              "scope": "project",
              "project_id": "project_chunk",
              "sensitivity": "internal",
              "visibility": "local_only",
              "reason_code": "selected",
              "content_included": false
            }
          ],
          "omitted_refs": [
            {
              "ref": "memory://rust/object/mem_chunk_omitted",
              "chunk_ref": "memory://rust/object/mem_chunk_omitted#object-1-lines-13-20",
              "chunk_id": "object-1-lines-13-20",
              "memory_id": "mem_chunk_omitted",
              "layer": "l2_observation",
              "source_kind": "tool_result",
              "scope": "project",
              "project_id": "project_chunk",
              "reason_code": "budget_limit",
              "content_included": false
            }
          ],
          "prompt_char_count": 64,
          "message_count": 0,
          "would_call_model": false,
          "model_call_executed": false,
          "production_authority_change": false,
          "context_text_included": false,
          "prompt_text_included": false,
          "issue_codes": [],
          "recorded_at_ms": 1779660000000
        }
        """

        let evidence = try JSONDecoder().decode(
            HubIPCClient.RustMemoryGatewayModelCallPlanEvidence.self,
            from: Data(json.utf8)
        )

        #expect(evidence.selectedChunkCount == 1)
        #expect(evidence.omittedRefCount == 1)
        #expect(evidence.indexGranularity == "object_chunk")
        #expect(evidence.chunkExpandViaGetRef == true)
        #expect(evidence.selectedRefs?.first?.chunkRef == "memory://rust/object/mem_chunk_selected#object-0-lines-1-12")
        #expect(evidence.selectedRefs?.first?.contentIncluded == false)
        #expect(evidence.omittedRefs?.first?.reasonCode == "budget_limit")
        let line = XTMemorySelectionEvidencePresentation.refLine(for: try #require(evidence.selectedRefs?.first))
        #expect(line.contains("ref=present"))
        #expect(line.contains("chunk=present"))
        #expect(line.contains("lines=1-12"))
        #expect(!line.contains("mem_chunk_selected"))
    }

    @MainActor
    @Test
    func selectionEvidenceRefreshReadsCachedRustStatusWithoutLoggingRefs() async throws {
        try await Self.gate.runOnMainActor {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("memory-selection-evidence-hub-\(UUID().uuidString)", isDirectory: true)
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("memory-selection-evidence-project-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: root)
            }

            let ctx = AXProjectContext(root: root)
            let projectId = AXProjectRegistryStore.projectId(forRoot: root)
            let visibleRef = HubIPCClient.RustMemoryGatewaySelectedRef(
                ref: "memory://rust/object/mem_visible_ref_should_not_enter_raw_log",
                chunkRef: "memory://rust/object/mem_visible_ref_should_not_enter_raw_log#object-0-lines-1-8",
                chunkId: "object-0-lines-1-8",
                chunkIdentitySchema: "xhub.memory.object_chunk_identity.v1",
                chunkStartLine: 1,
                chunkEndLine: 8,
                memoryId: "mem_visible_ref_should_not_enter_raw_log",
                layer: "l1_canonical",
                sourceKind: "decision_track",
                scope: "project",
                projectId: projectId,
                sensitivity: "internal",
                visibility: "local_only",
                updatedAtMs: 1779660000000,
                version: 3,
                reasonCode: "selected",
                contentIncluded: false
            )
            let crossScopeRef = HubIPCClient.RustMemoryGatewaySelectedRef(
                ref: "memory://rust/object/mem_cross_scope_should_not_render",
                chunkRef: "memory://rust/object/mem_cross_scope_should_not_render#object-0-lines-1-4",
                chunkId: "object-0-lines-1-4",
                chunkIdentitySchema: "xhub.memory.object_chunk_identity.v1",
                chunkStartLine: 1,
                chunkEndLine: 4,
                memoryId: "mem_cross_scope_should_not_render",
                layer: "l1_canonical",
                sourceKind: "personal_preference",
                scope: "user",
                projectId: nil,
                sensitivity: "private",
                visibility: "private",
                updatedAtMs: 1779660000001,
                version: 1,
                reasonCode: "selected",
                contentIncluded: false
            )
            let current = Self.makeSelectionEvidence(
                projectId: projectId,
                requestId: "plan-current",
                recordedAtMs: 1779660000200,
                selectedRefs: [visibleRef, crossScopeRef]
            )
            let otherProject = Self.makeSelectionEvidence(
                projectId: "project_other",
                requestId: "plan-other",
                recordedAtMs: 1779660000100,
                selectedRefs: []
            )
            let history = HubIPCClient.RustMemoryGatewayModelCallPlanHistory(
                generatedAtMs: 1779660000300,
                itemLimit: 2,
                items: [current, otherProject]
            )
            let encoder = JSONEncoder()
            try encoder.encode(current).write(
                to: hubBase.appendingPathComponent("memory_gateway_model_call_plan_status.json"),
                options: .atomic
            )
            try encoder.encode(history).write(
                to: hubBase.appendingPathComponent("memory_gateway_model_call_plan_history.json"),
                options: .atomic
            )

            let store = XTMemoryInspectorStore()
            await store.refreshSelectionEvidence(ctx: ctx, historyLimit: 3, refLimit: 8)

            #expect(store.selectionEvidenceSnapshot.samples.map(\.requestId) == ["plan-current"])
            #expect(store.selectionEvidenceSnapshot.droppedCrossScopeCount == 1)
            let refs = XTMemorySelectionEvidencePresentation.visibleSelectedRefs(
                for: try #require(store.selectionEvidenceSnapshot.latest),
                projectId: projectId,
                limit: 8
            )
            #expect(refs.map(\.memoryId) == ["mem_visible_ref_should_not_enter_raw_log"])
            #expect(refs.first?.chunkRef?.contains("#object-0-lines-1-8") == true)
            #expect(XTMemorySelectionEvidencePresentation.statusText(snapshot: store.selectionEvidenceSnapshot).contains("selected 2"))
            #expect(XTMemorySelectionEvidencePresentation.countLine(for: current).contains("selected_chunks=2"))
            #expect(XTMemorySelectionEvidencePresentation.countLine(for: current).contains("omitted_refs=1"))
            #expect(XTMemorySelectionEvidencePresentation.countLine(for: current).contains("index=object_chunk"))
            #expect(XTMemorySelectionEvidencePresentation.skippedLine(for: try #require(store.selectionEvidenceSnapshot.latest)).contains("budget=5"))
            #expect(
                XTMemorySelectionEvidencePresentation.omittedReasonLine(
                    for: try #require(store.selectionEvidenceSnapshot.latest)
                ).contains("budget_limit=5")
            )

            let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
            #expect(rawLog.contains("\"type\":\"memory_selection_evidence_view\""))
            #expect(rawLog.contains("\"visible_selected_ref_count\":1"))
            #expect(rawLog.contains("\"visible_selected_chunk_ref_count\":1"))
            #expect(rawLog.contains("\"selected_chunk_count\":2"))
            #expect(rawLog.contains("\"omitted_ref_count\":1"))
            #expect(rawLog.contains("\"index_granularity\":\"object_chunk\""))
            #expect(rawLog.contains("\"chunk_identity_schema_present\":true"))
            #expect(rawLog.contains("\"chunk_expand_via_get_ref\":true"))
            #expect(rawLog.contains("\"dropped_cross_scope_count\":1"))
            #expect(rawLog.contains("\"omitted_reason_counts\""))
            #expect(rawLog.contains("\"budget_limit\":5"))
            #expect(rawLog.contains("\"secret_or_secret_like\":1"))
            #expect(!rawLog.contains("mem_visible_ref_should_not_enter_raw_log"))
            #expect(!rawLog.contains("mem_cross_scope_should_not_render"))
            #expect(!rawLog.contains("mem_omitted_should_not_log"))
            #expect(!rawLog.contains("object-0-lines-1-8"))
        }
    }

    @MainActor
    @Test
    func selectionEvidenceRefreshIsUnavailableWhenNoCacheExists() async throws {
        try await Self.gate.runOnMainActor {
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("memory-selection-empty-hub-\(UUID().uuidString)", isDirectory: true)
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("memory-selection-empty-project-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            HubPaths.setPinnedBaseDirOverride(hubBase)
            defer {
                HubPaths.clearPinnedBaseDirOverride()
                try? FileManager.default.removeItem(at: hubBase)
                try? FileManager.default.removeItem(at: root)
            }

            let ctx = AXProjectContext(root: root)
            let store = XTMemoryInspectorStore()
            await store.refreshSelectionEvidence(ctx: ctx)

            #expect(store.selectionEvidenceSnapshot.samples.isEmpty)
            #expect(store.selectionEvidenceSnapshot.lastError == "memory_selection_evidence_unavailable")
            #expect(XTMemorySelectionEvidencePresentation.statusText(snapshot: store.selectionEvidenceSnapshot) == "memory_selection_evidence_unavailable")

            let rawLog = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
            #expect(rawLog.contains("\"type\":\"memory_selection_evidence_view\""))
            #expect(rawLog.contains("\"ok\":false"))
        }
    }

    @Test
    func secretInspectorPreviewIsHiddenByDefault() {
        let object = makeMemoryObject(
            memoryId: "mem_secret",
            projectId: "project_secret",
            scope: "project",
            sensitivity: "secret",
            text: "api_key_live_should_not_render"
        )

        #expect(object.redactedContentByDefault)
        #expect(XTMemoryInspectorPresentation.bodyPreview(for: object) == "content hidden by Rust memory policy")
    }

    @Test
    func mutationActionsMatchRustGateStateRules() {
        var active = makeMemoryObject(
            memoryId: "mem_active",
            projectId: "project_mutation_rules",
            scope: "project",
            sensitivity: "internal",
            text: "Active object"
        )
        #expect(XTMemoryInspectorPresentation.mutationActions(for: active) == [.pin, .archive, .delete])

        active.pinned = true
        #expect(XTMemoryInspectorPresentation.mutationActions(for: active) == [.unpin, .archive, .delete])

        var rejected = active
        rejected.status = "rejected"
        rejected.pinned = false
        #expect(XTMemoryInspectorPresentation.mutationActions(for: rejected) == [.archive, .delete])

        var archived = active
        archived.status = "archived"
        archived.pinned = false
        #expect(XTMemoryInspectorPresentation.mutationActions(for: archived) == [.delete])

        var deleted = active
        deleted.status = "deleted"
        #expect(XTMemoryInspectorPresentation.mutationActions(for: deleted).isEmpty)

        var immutable = active
        immutable.immutable = true
        #expect(XTMemoryInspectorPresentation.mutationActions(for: immutable).isEmpty)

        let archivePayload = XTMemoryInspectorPresentation.mutationPayload(action: .archive)
        #expect(archivePayload.confirm)
        #expect(archivePayload.confirmArchive == true)
        #expect(archivePayload.confirmation == "archive")

        let pinPayload = XTMemoryInspectorPresentation.mutationPayload(action: .pin)
        #expect(pinPayload.confirm == false)
        #expect(pinPayload.confirmArchive == nil)
        #expect(pinPayload.confirmDelete == nil)
    }

    @Test
    func assistantUserMutationActionStatesExplainDisabledRustGateRules() {
        let readyGate = XTAssistantUserMemoryInspectorGateSnapshot.evaluate(
            readiness: Self.makeReadyMemoryReadiness(),
            userScopeGrantSatisfied: true
        )
        var active = makeMemoryObject(
            memoryId: "mem_user_action_hint",
            projectId: nil,
            scope: "user",
            sensitivity: "private",
            text: "Private action hint body must not render."
        )
        var states = XTMemoryInspectorPresentation.assistantUserMutationActionStates(
            for: active,
            gate: readyGate,
            grantActive: true,
            gateRefreshing: false,
            mutationInFlight: false
        )
        #expect(states.first(where: { $0.action == .pin })?.enabled == true)
        #expect(states.first(where: { $0.action == .unpin })?.enabled == false)
        #expect(states.first(where: { $0.action == .unpin })?.reasonCode == "memory_object_not_pinned")
        #expect(states.first(where: { $0.action == .archive })?.enabled == true)
        #expect(states.first(where: { $0.action == .delete })?.enabled == true)
        let activeLine = XTMemoryInspectorPresentation.assistantUserMutationDisabledReasonLine(states: states) ?? ""
        #expect(activeLine == "disabled actions · memory_object_not_pinned=1")
        #expect(!activeLine.contains("mem_user_action_hint"))
        #expect(!activeLine.contains("Private action hint body"))

        active.pinned = true
        states = XTMemoryInspectorPresentation.assistantUserMutationActionStates(
            for: active,
            gate: readyGate,
            grantActive: true,
            gateRefreshing: false,
            mutationInFlight: false
        )
        #expect(states.first(where: { $0.action == .pin })?.reasonCode == "memory_object_already_pinned")
        #expect(states.first(where: { $0.action == .unpin })?.enabled == true)

        var archived = active
        archived.status = "archived"
        states = XTMemoryInspectorPresentation.assistantUserMutationActionStates(
            for: archived,
            gate: readyGate,
            grantActive: true,
            gateRefreshing: false,
            mutationInFlight: false
        )
        #expect(states.first(where: { $0.action == .delete })?.enabled == true)
        #expect(states.filter { $0.reasonCode == "memory_object_status_not_mutable" }.count == 3)
        #expect(XTMemoryInspectorPresentation.assistantUserMutationDisabledReasonLine(states: states) == "disabled actions · memory_object_status_not_mutable=3")

        var immutable = active
        immutable.immutable = true
        states = XTMemoryInspectorPresentation.assistantUserMutationActionStates(
            for: immutable,
            gate: readyGate,
            grantActive: true,
            gateRefreshing: false,
            mutationInFlight: false
        )
        #expect(states.allSatisfy { !$0.enabled })
        #expect(XTMemoryInspectorPresentation.assistantUserMutationDisabledReasonLine(states: states) == "disabled actions · memory_object_immutable=4")

        states = XTMemoryInspectorPresentation.assistantUserMutationActionStates(
            for: active,
            gate: .failClosed,
            grantActive: false,
            gateRefreshing: false,
            mutationInFlight: false
        )
        #expect(states.allSatisfy { !$0.enabled })
        #expect(XTMemoryInspectorPresentation.assistantUserMutationDisabledReasonLine(states: states) == "disabled actions · assistant_user_memory_inspector_grant_required=4")
    }

    private static func makeSelectionEvidence(
        projectId: String,
        requestId: String,
        recordedAtMs: Int64,
        selectedRefs: [HubIPCClient.RustMemoryGatewaySelectedRef],
        omittedRefs: [HubIPCClient.RustMemoryGatewaySelectedRef] = [
            HubIPCClient.RustMemoryGatewaySelectedRef(
                ref: "memory://rust/object/mem_omitted_should_not_log",
                chunkRef: "memory://rust/object/mem_omitted_should_not_log#object-1-lines-20-30",
                chunkId: "object-1-lines-20-30",
                chunkIdentitySchema: "xhub.memory.object_chunk_identity.v1",
                chunkStartLine: 20,
                chunkEndLine: 30,
                memoryId: "mem_omitted_should_not_log",
                layer: "l2_observation",
                sourceKind: "tool_result",
                scope: "project",
                projectId: nil,
                sensitivity: "internal",
                visibility: "local_only",
                updatedAtMs: nil,
                version: nil,
                reasonCode: "budget_limit",
                contentIncluded: false
            )
        ]
    ) -> HubIPCClient.RustMemoryGatewayModelCallPlanEvidence {
        HubIPCClient.RustMemoryGatewayModelCallPlanEvidence(
            ok: true,
            source: "xt_rust_memory_gateway_model_call_plan_shadow",
            mode: "shadow_preflight_no_product_cutover",
            requestId: requestId,
            auditRef: "audit-\(requestId)",
            requesterRole: "chat",
            useMode: "project_chat",
            scope: "project",
            servingProfileId: "M1_Execute",
            projectId: projectId,
            sessionId: nil,
            appId: "x_terminal",
            providerId: "remote_hub",
            modelId: "model",
            taskKind: "chat_plan",
            planSchemaVersion: "xhub.memory.gateway_model_call_plan.v1",
            planStatus: "planned",
            planSource: "rust_memory_gateway_model_call_plan",
            planMode: "plan_only_no_model_call",
            planAuthority: "rust_memory_gateway_plan_only",
            contextCharCount: 512,
            selectedRefCount: selectedRefs.count,
            selectedCount: selectedRefs.count,
            selectedChunkCount: selectedRefs.count,
            omittedCount: 5,
            omittedRefCount: omittedRefs.count,
            deniedCount: 2,
            effectiveLayers: ["l1_canonical", "l2_observation"],
            selectedRefs: selectedRefs,
            omittedRefs: omittedRefs,
            skipped: HubIPCClient.RustMemoryGatewayPrepareSkipped(
                policyOrFilter: 1,
                remoteVisibility: 0,
                secret: 1,
                budget: 5
            ),
            omittedReasonCounts: [
                "budget_limit": 5,
                "secret_or_secret_like": 1
            ],
            indexGranularity: "object_chunk",
            chunkIdentitySchema: "xhub.memory.object_chunk_identity.v1",
            chunkExpandViaGetRef: true,
            promptCharCount: 128,
            messageCount: 0,
            wouldCallModel: false,
            modelCallExecuted: false,
            productionAuthorityChange: false,
            contextTextIncluded: false,
            promptTextIncluded: false,
            issueCodes: [],
            reasonCode: nil,
            detail: nil,
            recordedAtMs: recordedAtMs
        )
    }

    private static func makeReadyMemoryReadiness() -> RustHubMemoryReadinessSnapshot {
        RustHubMemoryReadinessSnapshot(
            schemaVersion: "xhub.memory_bridge.v1",
            ok: true,
            objectStore: RustHubMemoryReadinessSnapshot.ObjectStore(
                ready: true,
                objectCount: 2,
                activeObjectCount: 2,
                candidateObjectCount: 0,
                writebackCandidates: nil,
                mutationGate: RustHubMemoryReadinessSnapshot.MutationGate(
                    schemaVersion: "xhub.memory.object_mutation.v1",
                    ready: true,
                    archiveHTTP: true,
                    deleteHTTP: true,
                    deleteTombstoneHTTP: true,
                    pinHTTP: true,
                    unpinHTTP: true,
                    confirmationRequired: true,
                    confirmationRequiredFor: ["archive", "delete"],
                    immutableFailClosed: true,
                    deleteMode: "tombstone",
                    authority: "rust_memory_object_store",
                    activeMemoryMutation: true,
                    productionAuthorityChange: false
                )
            )
        )
    }

    private static func makeActiveUserRevealGrant() -> HubIPCClient.MemoryUserRevealGrantResult {
        HubIPCClient.MemoryUserRevealGrantResult(
            ok: true,
            source: "rust_http",
            status: "granted",
            grantId: "user_reveal_active",
            scope: "user",
            surface: "assistant_user_memory_inspector",
            actor: "xt_swift_shell",
            issuedAtMs: 1779660000000,
            expiresAtMs: 4779660000000,
            ttlMs: 300000,
            reasonCode: "",
            auditRefPresent: true,
            contentIncluded: false,
            memoryIdsIncluded: false,
            projectCoderAllowed: false,
            modelContextAuthority: false,
            memoryServingAuthorityChange: false,
            productionAuthorityChange: false
        )
    }

    private func makeMemoryObject(
        memoryId: String,
        projectId: String?,
        scope: String,
        sensitivity: String,
        text: String
    ) -> HubIPCClient.MemoryWritebackCandidateObject {
        HubIPCClient.MemoryWritebackCandidateObject(
            schemaVersion: "xhub.memory.object.v1",
            memoryId: memoryId,
            scope: scope,
            ownerId: scope == "user" ? "user_local" : nil,
            runId: nil,
            projectId: projectId,
            agentId: nil,
            sourceKind: "decision_track",
            layer: "l1_canonical",
            title: "Memory object",
            text: text,
            summary: text,
            sensitivity: sensitivity,
            visibility: sensitivity == "private" ? "private" : "local_only",
            status: "active",
            pinned: false,
            immutable: false,
            ttlMs: nil,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            lastAccessedAtMs: nil,
            version: 1
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
