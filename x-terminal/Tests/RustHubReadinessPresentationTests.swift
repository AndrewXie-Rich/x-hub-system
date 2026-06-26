import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct RustHubReadinessPresentationTests {
    @Test
    func readyShadowPresentationDoesNotPromoteClassicHub() throws {
        let snapshot = try decodeSnapshot(
            """
            {
              "schema_version": "xhub.rust_hub.readiness.v1",
              "ok": true,
              "ready": true,
              "daemon": "xhubd",
              "version": "0.1.0",
              "mode": "shadow_http",
              "http_addr": "127.0.0.1:50151",
              "capabilities": {
                "model_inventory_http": true,
                "model_route_diagnostics_http": true,
                "provider_route_http": true,
                "skills_catalog_http": true,
                "memory_retrieval_http": true
              },
              "runtime": {
                "ml_execution_in_rust": false,
                "model_inventory_http": true,
                "model_route_diagnostics_http": true,
                "provider_route_http": true
              },
              "memory": {
                "authority": "shadow_plan",
                "canonical_writer_in_rust": false,
                "fail_closed": true
              },
              "skills": {
                "authority": "HubRegistry",
                "execution_authority_in_rust": false,
                "hub_executes_third_party_code": false,
                "execution_policy": "policy_gate_only",
                "ready": true
              },
              "network": {
                "host": "127.0.0.1",
                "port": 50151,
                "loopback_bind": true,
                "cross_network_bind": false,
                "ok": true
              },
              "checks": [
                {"name": "proto", "ok": true, "blocking": true}
              ]
            }
            """
        )

        let presentation = RustHubReadinessPresentation.build(
            snapshot: snapshot,
            language: .simplifiedChinese
        )
        let joined = presentation.lines.joined(separator: "\n")

        #expect(presentation.tone == .ready)
        #expect(presentation.badgeText == "Shadow Ready")
        #expect(joined.contains("Rust Hub shadow HTTP 已就绪"))
        #expect(joined.contains("不会把 XT 的 Hub pairing/gRPC 标记为已连接"))
        #expect(joined.contains("model_exec_rust=false"))
        #expect(joined.contains("skills_exec_rust=false"))
    }

    @Test
    func authorityBoundaryIssueRequiresReview() throws {
        let snapshot = RustHubReadinessSnapshot(
            schemaVersion: "xhub.rust_hub.readiness.v1",
            ok: true,
            ready: true,
            daemon: "xhubd",
            version: "0.1.0",
            mode: "shadow_http",
            httpAddr: "127.0.0.1:50151",
            capabilities: [:],
            runtime: RustHubReadinessSnapshot.Runtime(
                mlExecutionInRust: true,
                modelInventoryHTTP: true,
                modelRouteDiagnosticsHTTP: true,
                providerRouteHTTP: true
            ),
            memory: RustHubReadinessSnapshot.Memory(
                authority: "shadow_plan",
                canonicalWriterInRust: false,
                failClosed: true
            ),
            skills: RustHubReadinessSnapshot.Skills(
                authority: "HubRegistry",
                executionAuthorityInRust: false,
                hubExecutesThirdPartyCode: false,
                executionPolicy: "policy_gate_only",
                ready: true
            ),
            network: RustHubReadinessSnapshot.Network(
                host: "127.0.0.1",
                port: 50151,
                loopbackBind: true,
                crossNetworkBind: false,
                ok: true
            ),
            checks: []
        )

        let presentation = RustHubReadinessPresentation.build(
            snapshot: snapshot,
            language: .simplifiedChinese
        )
        let joined = presentation.lines.joined(separator: "\n")

        #expect(presentation.tone == .warning)
        #expect(presentation.badgeText == "需核对")
        #expect(joined.contains("authority 边界需要核对"))
        #expect(joined.contains("model_exec_rust=true"))
    }

    @Test
    func memoryReadinessDecodesWritebackCandidateDiagnostics() throws {
        let raw = """
        {
          "schema_version": "xhub.memory_bridge.v1",
          "ok": true,
          "object_store": {
            "ready": true,
            "object_count": 5,
            "active_object_count": 2,
            "candidate_object_count": 3,
            "writeback_candidates": {
              "schema_version": "xhub.memory.writeback_candidate.v1",
              "ready": true,
              "candidate_object_count": 3,
              "candidate_create_http": true,
              "candidate_list_http": true,
              "candidate_approve_reject_http": true,
              "candidate_maintenance_http": true,
              "authority": "rust_policy_gated_candidate_queue",
              "diagnostics": {
                "schema_version": "xhub.memory.writeback_candidate_diagnostics.v1",
                "ready": true,
                "source": "rust_memory_object_store",
                "candidate_count": 3,
                "conflict_candidate_count": 1,
                "stale_review_required_count": 1,
                "stale_candidate_count": 2,
                "planned_archive_count": 1,
                "planned_stale_review_required_count": 1,
                "queue_pressure": "high",
                "noise_score": 12,
                "production_authority_change": false
              },
              "production_authority_change": false
            }
          }
        }
        """
        let data = try #require(raw.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(RustHubMemoryReadinessSnapshot.self, from: data)

        #expect(snapshot.ok)
        #expect(snapshot.objectStore?.writebackCandidates?.authority == "rust_policy_gated_candidate_queue")
        #expect(snapshot.objectStore?.writebackCandidates?.diagnostics?.conflictCandidateCount == 1)
        #expect(snapshot.objectStore?.writebackCandidates?.diagnostics?.staleReviewRequiredCount == 1)
        #expect(snapshot.objectStore?.writebackCandidates?.diagnostics?.queuePressure == "high")
        #expect(snapshot.objectStore?.writebackCandidates?.productionAuthorityChange == false)
    }

    @Test
    func memoryReadinessDecodesObjectMutationGate() throws {
        let raw = """
        {
          "schema_version": "xhub.memory_bridge.v1",
          "ok": true,
          "object_store": {
            "ready": true,
            "object_count": 5,
            "active_object_count": 2,
            "candidate_object_count": 0,
            "mutation_gate": {
              "schema_version": "xhub.memory.object_mutation.v1",
              "ready": true,
              "archive_http": true,
              "delete_tombstone_http": true,
              "pin_http": true,
              "unpin_http": true,
              "confirmation_required_for": ["archive", "delete"],
              "immutable_fail_closed": true,
              "delete_mode": "tombstone",
              "authority": "rust_memory_object_store",
              "production_authority_change": false
            }
          }
        }
        """
        let data = try #require(raw.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(RustHubMemoryReadinessSnapshot.self, from: data)
        let gate = try #require(snapshot.objectStore?.mutationGate)

        #expect(snapshot.ok)
        #expect(gate.schemaVersion == "xhub.memory.object_mutation.v1")
        #expect(gate.ready == true)
        #expect(gate.archiveHTTP == true)
        #expect(gate.effectiveDeleteHTTP == true)
        #expect(gate.pinHTTP == true)
        #expect(gate.unpinHTTP == true)
        #expect(gate.effectiveConfirmationRequired == true)
        #expect(gate.confirmationRequiredFor == ["archive", "delete"])
        #expect(gate.immutableFailClosed == true)
        #expect(gate.deleteMode == "tombstone")
        #expect(gate.authority == "rust_memory_object_store")
        #expect(gate.productionAuthorityChange == false)
    }

    @Test
    func memoryReadinessDecodesUserRevealGrantGate() throws {
        let raw = """
        {
          "schema_version": "xhub.memory_bridge.v1",
          "ok": true,
          "object_store": {
            "ready": true,
            "object_count": 5,
            "active_object_count": 2,
            "candidate_object_count": 0,
            "user_reveal_grant": {
              "schema_version": "xhub.memory.user_reveal_grant.v1",
              "ready": true,
              "issue_http": true,
              "evaluate_http": true,
              "revoke_http": true,
              "scope": "user",
              "surface": "assistant_user_memory_inspector",
              "default_ttl_ms": 300000,
              "max_ttl_ms": 900000,
              "content_included": false,
              "memory_ids_included": false,
              "project_coder_allowed": false,
              "authority": "rust_memory_user_reveal_gate",
              "model_context_authority": false,
              "memory_serving_authority_change": false,
              "production_authority_change": false
            }
          }
        }
        """
        let data = try #require(raw.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(RustHubMemoryReadinessSnapshot.self, from: data)
        let gate = try #require(snapshot.objectStore?.userRevealGrant)

        #expect(snapshot.ok)
        #expect(gate.schemaVersion == "xhub.memory.user_reveal_grant.v1")
        #expect(gate.ready == true)
        #expect(gate.issueHTTP == true)
        #expect(gate.evaluateHTTP == true)
        #expect(gate.revokeHTTP == true)
        #expect(gate.scope == "user")
        #expect(gate.surface == "assistant_user_memory_inspector")
        #expect(gate.defaultTTLMS == 300000)
        #expect(gate.maxTTLMS == 900000)
        #expect(gate.contentIncluded == false)
        #expect(gate.memoryIDsIncluded == false)
        #expect(gate.projectCoderAllowed == false)
        #expect(gate.authority == "rust_memory_user_reveal_gate")
        #expect(gate.modelContextAuthority == false)
        #expect(gate.memoryServingAuthorityChange == false)
        #expect(gate.productionAuthorityChange == false)
    }

    private func decodeSnapshot(_ raw: String) throws -> RustHubReadinessSnapshot {
        let data = try #require(raw.data(using: .utf8))
        return try JSONDecoder().decode(RustHubReadinessSnapshot.self, from: data)
    }
}
