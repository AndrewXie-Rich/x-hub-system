import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubContractClientTests {
    @Test
    func defaultBaseURLPrefersPairedHubShellPairingEndpoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-contract-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        export HUB_CLIENT_TOKEN='client-token'
        export HUB_DEVICE_ID='xt-1'
        export HUB_HOST='10.0.0.10'
        export HUB_PORT='50058'
        """.write(to: root.appendingPathComponent("hub.env"), atomically: true, encoding: .utf8)
        try """
        export AXHUB_INTERNET_HOST='hub.example.com'
        export AXHUB_PAIRING_PORT='50059'
        """.write(to: root.appendingPathComponent("pairing.env"), atomically: true, encoding: .utf8)

        let url = HubContractClient.defaultBaseURL(
            environment: ["XHUB_RUST_HTTP_BASE_URL": "http://127.0.0.1:50151"],
            stateDir: root
        )

        #expect(url.absoluteString == "http://hub.example.com:50059")
    }

    @Test
    func decodesRustHubXTContractAndBuildsDoctorProjection() throws {
        let snapshot = try sampleReadyHubContractSnapshotForTests()
        let projection = XTUnifiedDoctorHubContractProjection(
            snapshot: snapshot,
            observedAt: Date(timeIntervalSince1970: 1_741_300_001)
        )

        #expect(snapshot.schemaVersion == HubContractSnapshot.currentSchemaVersion)
        #expect(snapshot.capabilities.memory.canonicalWriter == "hub_only")
        #expect(snapshot.capabilities.skills.authority == "hub_policy_gate")
        #expect(snapshot.capabilities.skills.leaseSourceEndpoint == "/skills/preflight")
        #expect(projection.contractReady == true)
        #expect(projection.memoryDurableTruthInXT == false)
        #expect(projection.thirdPartyCodeInHubTrustRoot == false)
        #expect(projection.remoteEntryNoDomainSupported == true)
        #expect(projection.providerRouteSecretFieldsIncluded == false)
        #expect(projection.naturalLanguageDirectGrant == false)
        #expect(projection.detailLines().contains("hub_contract_skills_authority=hub_policy_gate"))
    }
}

func sampleReadyHubContractSnapshotForTests() throws -> HubContractSnapshot {
    let data = Data(sampleReadyHubContractJSONForTests.utf8)
    return try JSONDecoder().decode(HubContractSnapshot.self, from: data)
}

func sampleReadyHubContractProjectionForTests() -> XTUnifiedDoctorHubContractProjection {
    let snapshot = try! sampleReadyHubContractSnapshotForTests()
    return XTUnifiedDoctorHubContractProjection(
        snapshot: snapshot,
        observedAt: Date(timeIntervalSince1970: 1_741_300_001)
    )
}

private let sampleReadyHubContractJSONForTests = """
{
  "schema_version": "xhub.rust_hub.xt_contract.v1",
  "ok": true,
  "generated_at_ms": 1741300000000,
  "daemon": "xhubd",
  "version": "0.1.0",
  "hub_product": {
    "kernel": "rust_core",
    "shell": "swift_macos",
    "xt_role": "paired_deep_client",
    "source_of_truth": "hub"
  },
  "transport_security": {
    "http_addr": "127.0.0.1:50151",
    "loopback_bind": true,
    "http_access_key_required": true,
    "http_access_key_configured": true,
    "remote_xt_requires_pairing": true,
    "remote_xt_requires_mtls_for_runtime_channels": true,
    "remote_http_requires_access_key": true,
    "public_endpoint_enabled": false,
    "secret_fields_included": false
  },
  "xt_update_rule": {
    "must_read_contract_first": true,
    "must_not_recreate_hub_authority_locally": true,
    "must_fail_closed_on_missing_grant_or_stale_contract": true,
    "preferred_refresh_endpoint": "/xt/hub-contract",
    "recommended_contract_ttl_ms": 60000
  },
  "capabilities": {
    "remote_entry": {
      "authority": "rust_core_network_bridge",
      "endpoint": "/network/remote-entry-candidates",
      "requires_auth": true,
      "requires_mtls": true,
      "supports_domain_users": true,
      "supports_no_domain_users": true,
      "fallback_policy": "use_last_known_good_route_pack_then_prompt_repair"
    },
    "models": {
      "authority": "hub_model_route",
      "xt_must_not_select_paid_provider_directly": true,
      "fallback_policy": "fail_closed_or_hub_declared_downgrade_only"
    },
    "provider_route": {
      "authority": "hub_provider_route",
      "secret_fields_included": false,
      "fallback_policy": "never_read_or_export_provider_secret_values"
    },
    "memory": {
      "authority": "rust_core_memory_writer",
      "canonical_writer": "hub_only",
      "writer_authority_in_rust": true,
      "durable_truth_in_xt": false,
      "fallback_policy": "local_ephemeral_context_only_no_durable_claim"
    },
    "skills": {
      "authority": "hub_policy_gate",
      "lease_required": true,
      "lease_source_endpoint": "/skills/preflight",
      "recommended_lease_ttl_ms": 300000,
      "revocation_epoch_required": true,
      "package_hash_pin_required": true,
      "secret_redaction_required": true,
      "requires_pin_or_grant": true,
      "third_party_code_in_hub_trust_root": false,
      "hub_executes_third_party_code": false,
      "execution_authority_in_rust": true,
      "fallback_policy": "fail_closed_on_missing_pin_grant_or_preflight"
    },
    "grants": {
      "authority": "hub_supervisor_policy_gate",
      "high_risk_requires_bound_grant_id": true,
      "natural_language_direct_grant": false,
      "fallback_policy": "fail_closed_on_missing_or_expired_grant"
    },
    "audit": {
      "authority": "hub_append_only_audit",
      "fallback_policy": "do_not_synthesize_audit_refs"
    }
  }
}
"""
