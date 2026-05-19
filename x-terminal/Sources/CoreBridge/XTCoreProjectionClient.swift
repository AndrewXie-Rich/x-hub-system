import Foundation

enum XTCoreProjectionClient {
    struct FetchResult: Equatable, Sendable {
        var ok: Bool
        var envelope: XTCoreProjectionEnvelope?
        var errorCode: String
        var errorMessage: String
        var exitCode: Int32
    }

    static func defaultExecutableURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        resourceURL: URL? = Bundle.main.resourceURL,
        currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) -> URL? {
        for key in ["XTERMINAL_XTD_PATH", "XT_XTD_PATH"] {
            if let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                let url = URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
                if fileManager.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }

        var candidates: [URL] = []
        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent("xtd", isDirectory: false))
        }
        candidates.append(currentDirectoryURL.appendingPathComponent("rust-xtd/target/release/xtd", isDirectory: false))
        candidates.append(currentDirectoryURL.appendingPathComponent("../rust-xtd/target/release/xtd", isDirectory: false))
        candidates.append(currentDirectoryURL.appendingPathComponent("rust-xtd/target/debug/xtd", isDirectory: false))
        candidates.append(currentDirectoryURL.appendingPathComponent("../rust-xtd/target/debug/xtd", isDirectory: false))

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func fetch(
        surface: XTCoreProjectionSurface,
        executableURL: URL? = defaultExecutableURL(),
        generatedAtMs: Int64? = nil,
        inputJSON: String? = nil,
        timeoutSec: Double = 2.5
    ) -> FetchResult {
        guard let executableURL else {
            return FetchResult(
                ok: false,
                envelope: nil,
                errorCode: "xtd_missing",
                errorMessage: "XT Rust sidecar executable not found.",
                exitCode: -1
            )
        }

        var args = ["projection", surface.commandArgument]
        if let generatedAtMs {
            args.append("--generated-at-ms")
            args.append(String(generatedAtMs))
        }
        if let inputJSON {
            args.append("--input-json")
            args.append(inputJSON)
        }

        do {
            let result = try ProcessCapture.run(
                executableURL.path,
                args,
                cwd: executableURL.deletingLastPathComponent(),
                timeoutSec: timeoutSec
            )
            guard result.exitCode == 0 else {
                let detail = normalizedDetail(result.combined)
                return FetchResult(
                    ok: false,
                    envelope: nil,
                    errorCode: "xtd_exit_\(result.exitCode)",
                    errorMessage: detail.isEmpty ? "XT Rust sidecar exited with code \(result.exitCode)." : detail,
                    exitCode: result.exitCode
                )
            }

            let envelope = try JSONDecoder().decode(
                XTCoreProjectionEnvelope.self,
                from: Data(result.stdout.utf8)
            )
            guard envelope.surface == surface else {
                return FetchResult(
                    ok: false,
                    envelope: envelope,
                    errorCode: "surface_mismatch",
                    errorMessage: "XT Rust sidecar returned \(envelope.surface.rawValue) for \(surface.rawValue).",
                    exitCode: result.exitCode
                )
            }

            return FetchResult(
                ok: true,
                envelope: envelope,
                errorCode: "",
                errorMessage: "",
                exitCode: result.exitCode
            )
        } catch {
            return FetchResult(
                ok: false,
                envelope: nil,
                errorCode: "xtd_decode_or_run_failed",
                errorMessage: error.localizedDescription,
                exitCode: -1
            )
        }
    }

    private static func normalizedDetail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension XTCoreProjectionSurface {
    var commandArgument: String {
        switch self {
        case .projectSidebar:
            return "sidebar"
        case .settingsDiagnostics:
            return "settings-diagnostics"
        }
    }
}
