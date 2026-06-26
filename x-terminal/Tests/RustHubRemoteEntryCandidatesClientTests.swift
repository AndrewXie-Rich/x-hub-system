import Foundation
import Testing
@testable import XTerminal

struct RustHubRemoteEntryCandidatesClientTests {
    @Test
    func preferredStableDomainCandidateBecomesRemoteHost() throws {
        let snapshot = try RustHubRemoteEntryCandidatesClient.decode(Data("""
        {
          "schema_version": "xhub.rust_hub.remote_entry_candidates.v1",
          "ok": true,
          "source": "rust_core_network_bridge",
          "recommended_setup": "use_stable_domain_or_tunnel",
          "preferred": {
            "route_kind": "stable_domain_or_tunnel",
            "source": "public_base_url",
            "host": "andrew.tailbe79cd.ts.net",
            "public_base_url": "https://andrew.tailbe79cd.ts.net",
            "usable": true,
            "requires_same_private_network": false,
            "requires_mtls": true,
            "classification": {
              "kind": "stable_named",
              "scope": "tailnet_dns",
              "stable": true,
              "encrypted_private_candidate": true,
              "reason_code": ""
            },
            "deny_code": ""
          },
          "candidates": []
        }
        """.utf8))

        #expect(snapshot.preferredStableRemoteHost == "andrew.tailbe79cd.ts.net")
    }

    @Test
    func rawPublicIPCandidateIsNotPromotedToStableRemoteHost() throws {
        let snapshot = try RustHubRemoteEntryCandidatesClient.decode(Data("""
        {
          "schema_version": "xhub.rust_hub.remote_entry_candidates.v1",
          "ok": true,
          "source": "rust_core_network_bridge",
          "recommended_setup": "needs_domain_tunnel_or_private_network",
          "preferred": {
            "route_kind": "stable_domain_or_tunnel",
            "source": "public_base_url",
            "host": "17.81.11.116",
            "public_base_url": "https://17.81.11.116",
            "usable": false,
            "requires_same_private_network": false,
            "requires_mtls": true,
            "classification": {
              "kind": "public_raw_ip",
              "scope": "public_ip",
              "stable": false,
              "encrypted_private_candidate": false,
              "reason_code": "public_raw_ip_forbidden"
            },
            "deny_code": "public_raw_ip_forbidden"
          },
          "candidates": []
        }
        """.utf8))

        #expect(snapshot.preferredStableRemoteHost == nil)
    }
}
