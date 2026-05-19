import Foundation
import Testing
@testable import XTerminal

struct XTCoreProjectionClientTests {
    @Test
    func resolvesExplicitExecutablePathBeforeBundledFallback() throws {
        let root = try makeTempDirectory("resolve")
        defer { try? FileManager.default.removeItem(at: root) }

        let explicit = try writeFakeXtd(
            in: root,
            fileName: "explicit_xtd",
            output: sidebarEnvelope()
        )
        let bundledDir = root.appendingPathComponent("bundle-resources", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledDir, withIntermediateDirectories: true)
        _ = try writeFakeXtd(
            in: bundledDir,
            fileName: "xtd",
            output: sidebarEnvelope(source: "bundled_should_not_win")
        )

        let resolved = XTCoreProjectionClient.defaultExecutableURL(
            environment: ["XTERMINAL_XTD_PATH": explicit.path],
            resourceURL: bundledDir,
            currentDirectoryURL: root
        )

        #expect(resolved?.path == explicit.path)
    }

    @Test
    func fetchRunsSidecarAndDecodesMatchingEnvelope() throws {
        let root = try makeTempDirectory("fetch")
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = try writeFakeXtd(
            in: root,
            output: sidebarEnvelope()
        )

        let result = XTCoreProjectionClient.fetch(
            surface: .projectSidebar,
            executableURL: executable,
            generatedAtMs: 0
        )

        #expect(result.ok)
        #expect(result.errorCode.isEmpty)
        #expect(result.envelope?.surface == .projectSidebar)
        #expect(result.envelope?.authority["hub_owns_truth"]?.boolValue == true)
        #expect(result.envelope?.authority["xtd_owns_authority"]?.boolValue == false)
        #expect(readInvocationLog(from: root) == ["projection sidebar --generated-at-ms 0"])
    }

    @Test
    func fetchPassesInputJSONToSidecar() throws {
        let root = try makeTempDirectory("input-json")
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = try writeFakeXtd(
            in: root,
            output: sidebarEnvelope()
        )
        let inputJSON = #"{"revision":1,"projects":[]}"#

        let result = XTCoreProjectionClient.fetch(
            surface: .projectSidebar,
            executableURL: executable,
            generatedAtMs: 0,
            inputJSON: inputJSON
        )

        #expect(result.ok)
        #expect(readInvocationLog(from: root) == [
            #"projection sidebar --generated-at-ms 0 --input-json {"revision":1,"projects":[]}"#
        ])
    }

    @Test
    func fetchRejectsSurfaceMismatch() throws {
        let root = try makeTempDirectory("mismatch")
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = try writeFakeXtd(
            in: root,
            output: settingsEnvelope()
        )

        let result = XTCoreProjectionClient.fetch(
            surface: .projectSidebar,
            executableURL: executable,
            generatedAtMs: 0
        )

        #expect(result.ok == false)
        #expect(result.errorCode == "surface_mismatch")
        #expect(result.envelope?.surface == .settingsDiagnostics)
    }

    @Test
    func fetchReportsNonZeroSidecarExit() throws {
        let root = try makeTempDirectory("exit")
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = try writeFakeXtd(
            in: root,
            output: "blocked by fixture",
            exitCode: 64
        )

        let result = XTCoreProjectionClient.fetch(
            surface: .projectSidebar,
            executableURL: executable,
            generatedAtMs: 0
        )

        #expect(result.ok == false)
        #expect(result.errorCode == "xtd_exit_64")
        #expect(result.errorMessage.contains("blocked by fixture"))
        #expect(result.exitCode == 64)
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_core_projection_client_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFakeXtd(
        in directory: URL,
        fileName: String = "fake_xtd",
        output: String,
        exitCode: Int = 0
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try output.write(to: directory.appendingPathComponent("projection-output.json"), atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> "\(directory.path)/xtd_calls.log"
        if [ \(exitCode) -eq 0 ]; then
          cat "\(directory.path)/projection-output.json"
          exit 0
        fi
        cat "\(directory.path)/projection-output.json" >&2
        exit \(exitCode)
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func readInvocationLog(from directory: URL) -> [String] {
        let logURL = directory.appendingPathComponent("xtd_calls.log", isDirectory: false)
        guard let raw = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func sidebarEnvelope(source: String = "fake_xtd") -> String {
        """
        {
          "protocol": "xt-core-projection.v1",
          "surface": "project_sidebar",
          "revision": 1,
          "generated_at_ms": 0,
          "source": "\(source)",
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
        """
    }

    private func settingsEnvelope() -> String {
        """
        {
          "protocol": "xt-core-projection.v1",
          "surface": "settings_diagnostics",
          "revision": 1,
          "generated_at_ms": 0,
          "source": "fake_xtd",
          "payload": {
            "diagnostics_lines": []
          }
        }
        """
    }
}
