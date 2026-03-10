import Foundation
import CryptoKit
import RELFlowHubCore

// Export a small, shareable diagnostics bundle for debugging startup/runtime issues.
//
// Goals:
// - "可定位/可归因": include launch attribution (hub_launch_status.json) + key heartbeats/logs.
// - Default safe: redact tokens/secrets and avoid exporting raw token stores.
// - Low friction: write to /tmp/RELFlowHub so users can easily attach/share.
enum HubDiagnosticsBundleExporter {
    struct ExportResult: Sendable {
        var archivePath: String
        var manifestPath: String
        var missingFiles: [String]
    }

    private struct ExportedFileEntry: Codable, Sendable {
        var name: String
        var sourcePath: String
        var bytes: Int
        var sha256: String
        var truncated: Bool
        var redacted: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case sourcePath = "source_path"
            case bytes
            case sha256
            case truncated
            case redacted
        }
    }

    private struct Manifest: Codable, Sendable {
        var schemaVersion: String
        var exportedAtMs: Int64

        var appBundleId: String
        var appVersion: String
        var appBuild: String
        var appPath: String

        var osVersion: String
        var pid: Int32
        var sandboxed: Bool

        var hubBaseDir: String
        var config: [String: String]

        var exportedFiles: [ExportedFileEntry]
        var missingFiles: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case exportedAtMs = "exported_at_ms"
            case appBundleId = "app_bundle_id"
            case appVersion = "app_version"
            case appBuild = "app_build"
            case appPath = "app_path"
            case osVersion = "os_version"
            case pid
            case sandboxed
            case hubBaseDir = "hub_base_dir"
            case config
            case exportedFiles = "exported_files"
            case missingFiles = "missing_files"
        }
    }

    private enum FileKind {
        case json
        case log
        case text
    }

    private struct InputFile {
        var name: String
        var url: URL
        var fallbackURL: URL?
        var kind: FileKind
        var optional: Bool
        var redact: Bool
        var tailBytes: Int
    }

    static func exportDiagnosticsBundle(
        redactTokens: Bool = true,
        maxLogTailBytes: Int = 2_000_000
    ) throws -> ExportResult {
        let base = SharedPaths.ensureHubDirectory()
        // Prefer /tmp for easy sharing, but fall back to the Hub base dir for sandboxed builds
        // where global temp paths may not be writable.
        let outRoot: URL = {
            let candidates: [URL] = [
                URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent("diagnostics_exports", isDirectory: true),
                base.appendingPathComponent("diagnostics_exports", isDirectory: true),
            ]
            for c in candidates {
                do {
                    try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
                    return c
                } catch {
                    continue
                }
            }
            return base
        }()

        let ts = timestampForFileName()
        let bundleDir = outRoot.appendingPathComponent("xhub_diagnostics_\(ts)", isDirectory: true)
        let zipURL = outRoot.appendingPathComponent("xhub_diagnostics_\(ts).zip")
        let manifestURL = bundleDir.appendingPathComponent("manifest.json")
        // Persisted next to the zip so it's still accessible after we delete the staging folder.
        let manifestCopyURL = outRoot.appendingPathComponent("xhub_diagnostics_\(ts).manifest.json")

        // Create staging dir.
        try? FileManager.default.removeItem(at: bundleDir)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        // IMPORTANT: do NOT export raw token stores. If needed, export redacted views instead.
        let inputs: [InputFile] = [
            InputFile(
                name: HubLaunchStatusStorage.fileName,
                url: HubLaunchStatusStorage.url(),
                fallbackURL: URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchStatusStorage.fileName),
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
            InputFile(
                name: HubLaunchHistoryStorage.fileName,
                url: HubLaunchHistoryStorage.url(),
                fallbackURL: URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchHistoryStorage.fileName),
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
            InputFile(name: "hub_status.json", url: base.appendingPathComponent("hub_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "hub_debug.log", url: base.appendingPathComponent("hub_debug.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "hub_grpc.log", url: base.appendingPathComponent("hub_grpc.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "bridge_status.json", url: base.appendingPathComponent("bridge_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "bridge_audit.log", url: base.appendingPathComponent("bridge_audit.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "bridge_settings.redacted.json", url: base.appendingPathComponent("bridge_settings.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "ai_runtime_status.json", url: base.appendingPathComponent("ai_runtime_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "ai_runtime.log", url: base.appendingPathComponent("ai_runtime.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "mlx_runtime_audit.log", url: base.appendingPathComponent("mlx_runtime_audit.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(
                name: "ax_constitution.redacted.json",
                url: base.appendingPathComponent("memory", isDirectory: true).appendingPathComponent("ax_constitution.json"),
                fallbackURL: nil,
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
            InputFile(name: "models_state.json", url: base.appendingPathComponent("models_state.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "models_catalog.json", url: base.appendingPathComponent("models_catalog.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: GRPCDeniedAttemptsStorage.fileName, url: GRPCDeniedAttemptsStorage.url(), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: GRPCDevicesStatusStorage.fileName, url: GRPCDevicesStatusStorage.url(), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "file_ipc_status.json", url: base.appendingPathComponent("file_ipc_status.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),

            // Helpful for diagnosing pairing/auth mismatches; tokens are redacted.
            InputFile(
                name: "hub_grpc_clients.redacted.json",
                url: base.appendingPathComponent("hub_grpc_clients.json"),
                fallbackURL: nil,
                kind: .json,
                optional: true,
                redact: true,
                tailBytes: 0
            ),
        ]

        var exported: [ExportedFileEntry] = []
        var missing: [String] = []

        for f in inputs {
            let fm = FileManager.default
            let src: URL? = {
                if fm.fileExists(atPath: f.url.path) { return f.url }
                if let fb = f.fallbackURL, fm.fileExists(atPath: fb.path) { return fb }
                return nil
            }()
            guard let src else {
                // Record missing files even if optional; bundle export is best-effort.
                missing.append(f.name)
                continue
            }
            let dst = bundleDir.appendingPathComponent(f.name)
            do {
                let (data, truncated) = try readForExport(url: src, kind: f.kind, tailBytes: f.tailBytes)
                let outData: Data
                if redactTokens && f.redact {
                    outData = redactDataForExport(data, kind: f.kind)
                } else {
                    outData = data
                }
                try writeDataAtomic(outData, to: dst)
                exported.append(
                    ExportedFileEntry(
                        name: f.name,
                        sourcePath: redactPathForManifest(src.path),
                        bytes: outData.count,
                        sha256: sha256Hex(outData),
                        truncated: truncated,
                        redacted: redactTokens && f.redact
                    )
                )
            } catch {
                // Best-effort: record as missing so the operator knows it failed to export.
                missing.append("\(f.name) (export_failed)")
            }
        }

        // DB integrity check report (text) so operators can quickly spot corruption/locking.
        do {
            let dbEntry = try exportDBIntegrityReport(base: base, to: bundleDir)
            exported.append(dbEntry)
        } catch {
            missing.append("db_integrity_check.txt (export_failed)")
        }

        // Write a small manifest for quick debugging without opening each file.
        let bid = Bundle.main.bundleIdentifier ?? ""
        let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        let appPath = Bundle.main.bundleURL.path
        let manifest = Manifest(
            schemaVersion: "xhub_diagnostics_bundle.v1",
            exportedAtMs: nowMs(),
            appBundleId: bid,
            appVersion: ver,
            appBuild: build,
            appPath: redactPathForManifest(appPath),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            pid: getpid(),
            sandboxed: SharedPaths.isSandboxedProcess(),
            hubBaseDir: redactPathForManifest(base.path),
            config: [
                "redact_tokens": redactTokens ? "1" : "0",
                "max_log_tail_bytes": String(max(1, maxLogTailBytes)),
            ],
            exportedFiles: exported.sorted { $0.name < $1.name },
            missingFiles: missing.sorted()
        )
        var manifestCopyPath: String = ""
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data0 = try enc.encode(manifest)
            let data = (String(data: data0, encoding: .utf8) ?? "") + "\n"
            try writeDataAtomic(Data(data.utf8), to: manifestURL)
            try writeDataAtomic(Data(data.utf8), to: manifestCopyURL)
            manifestCopyPath = manifestCopyURL.path
        } catch {
            // ignore
        }

        // Create a single-file archive for easy sharing. If archiving fails (e.g. sandbox restrictions),
        // keep the folder and return its path so the user can compress/share manually.
        var archivePath = bundleDir.path
        do {
            try? FileManager.default.removeItem(at: zipURL)
            try createZipWithDitto(srcDir: bundleDir, dstZip: zipURL)
            try? FileManager.default.removeItem(at: bundleDir)
            archivePath = zipURL.path
        } catch {
            // Best-effort: record that archiving failed, but still return the folder path.
            missing.append("_archive.zip (zip_failed)")
        }

        return ExportResult(archivePath: archivePath, manifestPath: manifestCopyPath, missingFiles: missing.sorted())
    }

    // MARK: - Internals

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private static func timestampForFileName() -> String {
        let d = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: d)
    }

    private static func sha256Hex(_ data: Data) -> String {
        let h = SHA256.hash(data: data)
        return h.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func writeDataAtomic(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func readForExport(url: URL, kind: FileKind, tailBytes: Int) throws -> (data: Data, truncated: Bool) {
        let maxTail = max(0, tailBytes)
        if kind == .log && maxTail > 0 {
            return try tailFile(url: url, maxBytes: maxTail)
        }
        let data = try Data(contentsOf: url)
        return (data, false)
    }

    private static func tailFile(url: URL, maxBytes: Int) throws -> (data: Data, truncated: Bool) {
        let cap = max(256, maxBytes)
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        let end = try fh.seekToEnd()
        if end <= UInt64(cap) {
            try fh.seek(toOffset: 0)
            let data = try fh.readToEnd() ?? Data()
            return (data, false)
        }
        let start = end - UInt64(cap)
        try fh.seek(toOffset: start)
        let data = try fh.readToEnd() ?? Data()
        return (data, true)
    }

    private static func createZipWithDitto(srcDir: URL, dstZip: URL) throws {
        // `ditto -c -k --sequesterRsrc --keepParent <dir> <zip>` is the macOS-recommended way to zip folders.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", srcDir.path, dstZip.path]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        try p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let msg = (String(data: data, encoding: .utf8) ?? "ditto exited \(p.terminationStatus)")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw NSError(
            domain: "HubDiagnosticsBundleExporter",
            code: Int(p.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "ditto failed" : msg]
        )
    }

    private struct SQLiteQuickCheckResult {
        var launchError: String
        var exitCode: Int32
        var elapsedMs: Int64
        var stdout: String
        var stderr: String
    }

    private static func exportDBIntegrityReport(base: URL, to bundleDir: URL) throws -> ExportedFileEntry {
        let db = base.appendingPathComponent("hub_grpc", isDirectory: true).appendingPathComponent("hub.sqlite3")
        let wal = URL(fileURLWithPath: db.path + "-wal")
        let shm = URL(fileURLWithPath: db.path + "-shm")
        let fm = FileManager.default

        func sizeOf(_ url: URL) -> Int64 {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let n = attrs[.size] as? NSNumber else { return -1 }
            return n.int64Value
        }

        var lines: [String] = []
        lines.append("schema_version: xhub_db_integrity_report.v1")
        lines.append("checked_at_ms: \(nowMs())")
        lines.append("db_path: \(redactPathForManifest(db.path))")
        lines.append("db_exists: \(fm.fileExists(atPath: db.path) ? "1" : "0")")
        lines.append("db_bytes: \(sizeOf(db))")
        lines.append("wal_exists: \(fm.fileExists(atPath: wal.path) ? "1" : "0")")
        lines.append("wal_bytes: \(sizeOf(wal))")
        lines.append("shm_exists: \(fm.fileExists(atPath: shm.path) ? "1" : "0")")
        lines.append("shm_bytes: \(sizeOf(shm))")

        let qc = runSQLiteQuickCheck(dbPath: db.path)
        lines.append("sqlite3_launch_error: \(qc.launchError.isEmpty ? "(none)" : qc.launchError)")
        lines.append("sqlite3_exit_code: \(qc.exitCode)")
        lines.append("quick_check_elapsed_ms: \(qc.elapsedMs)")

        let out = qc.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = qc.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let outNorm = out.lowercased()
        let okLine = outNorm == "ok" || outNorm.hasSuffix("\nok")
        let checkOK = qc.launchError.isEmpty && qc.exitCode == 0 && okLine
        lines.append("quick_check_ok: \(checkOK ? "1" : "0")")
        lines.append("quick_check_stdout:\n" + (out.isEmpty ? "(empty)" : limitForReport(out)))
        lines.append("quick_check_stderr:\n" + (err.isEmpty ? "(empty)" : limitForReport(err)))

        let report = redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("db_integrity_check.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "db_integrity_check.txt",
            sourcePath: redactPathForManifest(db.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func runSQLiteQuickCheck(dbPath: String) -> SQLiteQuickCheckResult {
        let started = Date().timeIntervalSince1970
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [
            "-readonly",
            "-batch",
            "-cmd", "PRAGMA busy_timeout=1500;",
            dbPath,
            "PRAGMA quick_check;"
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do {
            try p.run()
            p.waitUntilExit()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            return SQLiteQuickCheckResult(
                launchError: "",
                exitCode: p.terminationStatus,
                elapsedMs: Int64((Date().timeIntervalSince1970 - started) * 1000.0),
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        } catch {
            return SQLiteQuickCheckResult(
                launchError: error.localizedDescription,
                exitCode: -1,
                elapsedMs: Int64((Date().timeIntervalSince1970 - started) * 1000.0),
                stdout: "",
                stderr: ""
            )
        }
    }

    private static func limitForReport(_ text: String, maxChars: Int = 8_000) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= maxChars {
            return t
        }
        return String(t.suffix(maxChars))
    }

    private static func redactDataForExport(_ data: Data, kind: FileKind) -> Data {
        if kind == .json {
            if let redactedJson = redactJsonBytes(data) {
                return redactedJson
            }
            // Fall back to text redaction.
        }
        guard let s = String(data: data, encoding: .utf8) else { return data }
        let out = redactTextSecrets(s)
        return Data(out.utf8)
    }

    private static func redactJsonBytes(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let redacted = redactJsonObject(obj)
        guard let out = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: out, encoding: .utf8) else {
            return nil
        }
        return Data((s + "\n").utf8)
    }

    private static func redactJsonObject(_ obj: Any) -> Any {
        if let arr = obj as? [Any] {
            return arr.map { redactJsonObject($0) }
        }
        if let dict = obj as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                let kl = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if shouldRedactJsonKey(kl) {
                    out[k] = "[REDACTED]"
                    continue
                }
                if let s = v as? String {
                    out[k] = redactTextSecrets(s)
                    continue
                }
                out[k] = redactJsonObject(v)
            }
            return out
        }
        if let s = obj as? String {
            return redactTextSecrets(s)
        }
        return obj
    }

    private static func shouldRedactJsonKey(_ lowerKey: String) -> Bool {
        if lowerKey == "token" { return true }
        if lowerKey == "client_token" { return true }
        if lowerKey == "admin_token" { return true }
        if lowerKey == "access_token" { return true }
        if lowerKey == "refresh_token" { return true }
        if lowerKey == "api_key" { return true }
        if lowerKey == "apikey" { return true }
        if lowerKey == "secret" { return true }
        if lowerKey == "password" { return true }
        if lowerKey.contains("authorization") { return true }
        if lowerKey.contains("cookie") { return true }
        if lowerKey.contains("password") { return true }
        if lowerKey.hasSuffix("_token") { return true }
        if lowerKey.hasSuffix("_secret") { return true }
        if lowerKey.contains("private_key") { return true }
        return false
    }

    private static func redactPathForManifest(_ path: String) -> String {
        let s = path
        let home = SharedPaths.realHomeDirectory().path
        if !home.isEmpty, s.contains(home) {
            return s.replacingOccurrences(of: home, with: "/Users/USER")
        }
        return s
    }

    private static func redactTextSecrets(_ text: String) -> String {
        var out = text

        // User home path -> stable placeholder.
        let home = SharedPaths.realHomeDirectory().path
        if !home.isEmpty {
            out = out.replacingOccurrences(of: home, with: "/Users/USER")
        }

        // Common Hub tokens.
        out = out.replacingOccurrences(
            of: #"axhub_client_[A-Za-z0-9_\-]{10,}"#,
            with: "axhub_client_[REDACTED]",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"axhub_admin_[A-Za-z0-9_\-]{10,}"#,
            with: "axhub_admin_[REDACTED]",
            options: .regularExpression
        )

        // Generic bearer header.
        out = out.replacingOccurrences(
            of: #"(?i)\bBearer\s+[A-Za-z0-9_\-\.=]{12,}"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )

        // Common provider keys (defense-in-depth).
        out = out.replacingOccurrences(of: #"\bsk-[A-Za-z0-9]{20,}\b"#, with: "sk-[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bghp_[A-Za-z0-9]{36}\b"#, with: "ghp_[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bhf_[A-Za-z0-9]{20,}\b"#, with: "hf_[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bAIza[0-9A-Za-z_\-]{35}\b"#, with: "AIza[REDACTED]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b"#, with: "xox*-REDACTED", options: .regularExpression)

        return out
    }

    static func redactTextForSharing(_ text: String) -> String {
        redactTextSecrets(text)
    }
}
