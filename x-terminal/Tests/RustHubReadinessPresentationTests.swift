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
        #expect(presentation.badgeText == "内核就绪")
        #expect(joined.contains("Hub 内核 HTTP 已就绪"))
        #expect(joined.contains("不会单独把 XT 的 Hub pairing/gRPC 标记为已连接"))
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

    private func decodeSnapshot(_ raw: String) throws -> RustHubReadinessSnapshot {
        let data = try #require(raw.data(using: .utf8))
        return try JSONDecoder().decode(RustHubReadinessSnapshot.self, from: data)
    }
}
