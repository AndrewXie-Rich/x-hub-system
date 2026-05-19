import Foundation
import Testing
@testable import XTerminal

struct XTCoreProjectionEnvelopeTests {
    @Test
    func decodesProjectSidebarEnvelopeWithoutCreatingAuthority() throws {
        let envelope = try decode("""
        {
          "protocol": "xt-core-projection.v1",
          "surface": "project_sidebar",
          "revision": 1,
          "generated_at_ms": 0,
          "source": "xtd_fixture_projection",
          "authority": {
            "hub_owns_truth": true,
            "xtd_owns_authority": false,
            "memory_writer_authority": false,
            "skills_authority": false,
            "model_route_authority": false
          },
          "payload": {
            "selected_project_id": "",
            "project_count_text": "0",
            "rows": []
          }
        }
        """)

        #expect(envelope.protocolVersion == XTCoreProjectionEnvelope.supportedProtocol)
        #expect(envelope.surface == .projectSidebar)
        #expect(envelope.revision == 1)
        #expect(envelope.generatedAtMs == 0)
        #expect(envelope.source == "xtd_fixture_projection")
        #expect(envelope.authority["hub_owns_truth"]?.boolValue == true)
        #expect(envelope.authority["xtd_owns_authority"]?.boolValue == false)
        #expect(envelope.authority["memory_writer_authority"]?.boolValue == false)
        #expect(envelope.authority["skills_authority"]?.boolValue == false)
        #expect(envelope.authority["model_route_authority"]?.boolValue == false)
        #expect(envelope.payload["project_count_text"]?.stringValue == "0")
        #expect(envelope.payload["rows"]?.arrayValue == [])
    }

    @Test
    func decodesProjectSidebarPayloadProjection() throws {
        let envelope = try decode("""
        {
          "protocol": "xt-core-projection.v1",
          "surface": "project_sidebar",
          "revision": 1,
          "generated_at_ms": 0,
          "source": "xtd_sidebar_projection",
          "authority": {
            "hub_owns_truth": true,
            "xtd_owns_authority": false
          },
          "payload": {
            "revision": 7,
            "selected_project_id": "project-a",
            "project_count_text": "1",
            "rows": [
              {
                "id": "project-a",
                "display_name": "Project A",
                "root_path": "/tmp/project-a",
                "is_selected": true,
                "status_digest": "running",
                "resume_badge_text": "最近交接",
                "resume_help_text": "resume help",
                "governance": {
                  "execution_tier": "a4_openclaw",
                  "execution_tier_token": "A4",
                  "execution_tier_label": "代理",
                  "execution_tier_help": "execution help",
                  "supervisor_tier": "s3_strategic_coach",
                  "supervisor_tier_token": "S3",
                  "supervisor_tier_label": "战略教练",
                  "supervisor_tier_help": "supervisor help"
                }
              }
            ]
          }
        }
        """)

        let projection = try envelope.decodePayload(XTCoreProjectSidebarProjection.self)

        #expect(projection.revision == 7)
        #expect(projection.selectedProjectId == "project-a")
        #expect(projection.rows.first?.displayName == "Project A")
        #expect(projection.rows.first?.governance?.executionTier == .a4OpenClaw)
        #expect(projection.rows.first?.governance?.supervisorTier == .s3StrategicCoach)
    }

    @Test
    func decodesSettingsDiagnosticsEnvelopeWithBoundedPayloadShape() throws {
        let envelope = try decode("""
        {
          "protocol": "xt-core-projection.v1",
          "surface": "settings_diagnostics",
          "revision": 1,
          "generated_at_ms": 0,
          "source": "xtd_fixture_projection",
          "authority": {
            "hub_owns_truth": true,
            "xtd_owns_authority": false
          },
          "payload": {
            "connection_state_label": "未连接",
            "diagnostics_lines": [],
            "route_repair_recent_lines": [],
            "hub_remote_log_tail": {
              "title": "Hub Remote Log",
              "text": "",
              "truncated": false,
              "total_bytes": 0,
              "displayed_bytes": 0
            }
          }
        }
        """)

        #expect(envelope.surface == .settingsDiagnostics)
        #expect(envelope.payload["connection_state_label"]?.stringValue == "未连接")
        #expect(envelope.payload["diagnostics_lines"]?.arrayValue == [])
        #expect(envelope.payload["route_repair_recent_lines"]?.arrayValue == [])
        let logTail = try #require(envelope.payload["hub_remote_log_tail"]?.objectValue)
        #expect(logTail["displayed_bytes"]?.intValue == 0)
        #expect(logTail["truncated"]?.boolValue == false)
    }

    @Test
    func decodesSettingsDiagnosticsPayloadProjection() throws {
        let envelope = try decode("""
        {
          "protocol": "xt-core-projection.v1",
          "surface": "settings_diagnostics",
          "revision": 1,
          "generated_at_ms": 0,
          "source": "xtd_settings_diagnostics_projection",
          "authority": {
            "hub_owns_truth": true,
            "xtd_owns_authority": false
          },
          "payload": {
            "connection_state_label": "已连接",
            "diagnostics_lines": ["diag-a"],
            "route_repair_recent_lines": ["route-line-20", "route-line-99"],
            "route_repair_total_line_count": 100,
            "hub_remote_log_tail": {
              "title": "Hub Remote Log",
              "text": "tail",
              "truncated": true,
              "total_bytes": 17000,
              "displayed_bytes": 4
            }
          }
        }
        """)

        let projection = try envelope.decodePayload(XTSettingsDiagnosticsProjection.self)

        #expect(projection.connectionStateLabel == "已连接")
        #expect(projection.diagnosticsLines == ["diag-a"])
        #expect(projection.routeRepairRecentLines == ["route-line-20", "route-line-99"])
        #expect(projection.routeRepairTotalLineCount == 100)
        #expect(projection.hubRemoteLogTail.text == "tail")
        #expect(projection.hubRemoteLogTail.truncated == true)
    }

    @Test
    func rejectsUnsupportedProtocolVersion() {
        #expect(throws: Error.self) {
            _ = try decode("""
            {
              "protocol": "xt-core-projection.v2",
              "surface": "project_sidebar",
              "revision": 1,
              "generated_at_ms": 0,
              "payload": {}
            }
            """)
        }
    }

    @Test
    func rejectsUnknownSurface() {
        #expect(throws: Error.self) {
            _ = try decode("""
            {
              "protocol": "xt-core-projection.v1",
              "surface": "memory_authority",
              "revision": 1,
              "generated_at_ms": 0,
              "payload": {}
            }
            """)
        }
    }

    @Test
    func rejectsNonObjectPayload() {
        #expect(throws: Error.self) {
            _ = try decode("""
            {
              "protocol": "xt-core-projection.v1",
              "surface": "project_sidebar",
              "revision": 1,
              "generated_at_ms": 0,
              "payload": []
            }
            """)
        }
    }

    private func decode(_ json: String) throws -> XTCoreProjectionEnvelope {
        try JSONDecoder().decode(XTCoreProjectionEnvelope.self, from: Data(json.utf8))
    }
}
