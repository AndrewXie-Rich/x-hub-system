import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct RustHubModelRouteDiagnosticsPresentationTests {
    @Test
    func readyPresentationSummarizesSafeEvidenceOnly() throws {
        let snapshot = try decodeSnapshot(
            """
            {
              "schema_version": "xhub.model_route_diagnostics.v1",
              "ok": true,
              "command": "diagnostics",
              "component": "model_route",
              "read_only": true,
              "diagnostics_only": true,
              "production_authority_change": false,
              "selected_model_authority_enabled": false,
              "node_remains_model_selection_authority": true,
              "ready": true,
              "decision": "ready",
              "generated_at_ms": 1778106948228,
              "reports_dir_exists": true,
              "observed_authority": {
                "production_authority_changes": 0,
                "selected_model_authority_enabled_reports": 0,
                "node_authority_failures": 0
              },
              "checks": [
                {"name": "production_authority_unchanged", "ok": true, "blocking": true}
              ],
              "latest": {
                "authority_plan": {
                  "kind": "authority_plan",
                  "ready": true,
                  "decision": "ready_for_manual_prep_trial",
                  "authority_mode": "dry_run_only",
                  "report_path": "/Users/andrew.xie/Documents/AX/rust/rust hub/reports/model_route_authority_plan.json",
                  "production_authority_change": false,
                  "selected_model_authority_enabled": false,
                  "node_authority_preserved": true,
                  "raw_stderr": "sk-should-never-render",
                  "env": {"OPENAI_API_KEY": "sk-should-never-render"},
                  "metrics": {
                    "provider": "openai",
                    "remote_model_id": "gpt-5.5",
                    "local_model_id": "local.summary",
                    "rust_can_prepare_model_route_decision": true,
                    "production_cutover_implemented": false
                  }
                },
                "prep_trial": {
                  "kind": "prep_trial",
                  "ready": true,
                  "decision": "ready",
                  "report_path": "reports/model_route_prep_trial.json",
                  "metrics": {
                    "remote": {"prep_match_count": 1, "prep_ready": true, "prep_warning_count": 0},
                    "local": {"prep_match_count": 1, "prep_ready": true, "prep_warning_count": 0}
                  }
                },
                "prep_sustained": {
                  "kind": "prep_sustained",
                  "ready": true,
                  "decision": "ready",
                  "report_path": "reports/model_route_prep_sustained.json",
                  "metrics": {
                    "aggregate": {
                      "ready_cycles": 2,
                      "failed_cycles": 0,
                      "total_remote_prep_matches": 2,
                      "total_local_prep_matches": 2,
                      "total_prep_warnings": 0,
                      "node_authority_failures": 0
                    }
                  }
                },
                "candidate_evidence": {
                  "kind": "candidate_evidence",
                  "ready": true,
                  "decision": "ready",
                  "report_path": "reports/model_route_candidate_evidence.json",
                  "metrics": {
                    "remote": {"total": 1, "fallback": 0, "secret_leak": 0},
                    "local": {"total": 1, "fallback": 0, "secret_leak": 0}
                  }
                }
              }
            }
            """
        )

        let presentation = RustHubModelRouteDiagnosticsPresentation.build(
            snapshot: snapshot,
            language: .simplifiedChinese
        )
        let joined = presentation.lines.joined(separator: "\n")

        #expect(presentation.tone == .ready)
        #expect(presentation.badgeText == "Ready")
        #expect(joined.contains("read_only=true"))
        #expect(joined.contains("selected_model_authority_enabled=false"))
        #expect(joined.contains("remote_matches=1"))
        #expect(joined.contains("ready_cycles=2"))
        #expect(joined.contains("remote_secret_leak=0"))
        #expect(!joined.contains("sk-should-never-render"))
        #expect(!joined.contains("OPENAI_API_KEY"))
        #expect(!joined.contains("/Users/andrew.xie"))
    }

    @Test
    func boundaryIssueBlocksPresentationWithoutGrantingAuthority() throws {
        let snapshot = RustHubModelRouteDiagnosticsSnapshot(
            schemaVersion: "xhub.model_route_diagnostics.v1",
            ok: true,
            command: "diagnostics",
            component: "model_route",
            readOnly: true,
            diagnosticsOnly: true,
            productionAuthorityChange: false,
            selectedModelAuthorityEnabled: true,
            nodeRemainsModelSelectionAuthority: true,
            ready: true,
            decision: "ready",
            observedAuthority: RustHubModelRouteDiagnosticsSnapshot.ObservedAuthority(
                productionAuthorityChanges: 0,
                selectedModelAuthorityEnabledReports: 1,
                nodeAuthorityFailures: 0
            ),
            checks: [
                RustHubModelRouteDiagnosticsSnapshot.Check(
                    name: "selected_model_authority_disabled",
                    ok: false,
                    blocking: true
                )
            ]
        )

        let presentation = RustHubModelRouteDiagnosticsPresentation.build(
            snapshot: snapshot,
            language: .simplifiedChinese
        )
        let joined = presentation.lines.joined(separator: "\n")

        #expect(presentation.tone == .blocked)
        #expect(presentation.badgeText == "边界异常")
        #expect(joined.contains("selected_model_authority_enabled=true"))
        #expect(joined.contains("selected_model_enabled_reports=1"))
        #expect(joined.contains("selected_model_authority_disabled"))
    }

    private func decodeSnapshot(_ raw: String) throws -> RustHubModelRouteDiagnosticsSnapshot {
        let data = try #require(raw.data(using: .utf8))
        return try JSONDecoder().decode(RustHubModelRouteDiagnosticsSnapshot.self, from: data)
    }
}
