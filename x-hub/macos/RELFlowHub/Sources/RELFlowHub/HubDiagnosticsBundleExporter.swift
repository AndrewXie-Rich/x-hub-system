import Foundation
import CryptoKit
import RELFlowHubCore

// Export a small, shareable diagnostics bundle for debugging startup/runtime issues.
//
// Goals:
// - Make failures attributable: include launch attribution (hub_launch_status.json) + key heartbeats/logs.
// - Default safe: redact tokens/secrets and avoid exporting raw token stores.
// - Low friction: write to /tmp/RELFlowHub so users can easily attach/share.
enum HubDiagnosticsBundleExporter {
    static let exportStrings = HubUIStrings.Settings.Diagnostics.Export.self

    static func exportDiagnosticsBundle(
        redactTokens: Bool = true,
        maxLogTailBytes: Int = 2_000_000
    ) throws -> ExportResult {
        try exportDiagnosticsBundleCore(
            redactTokens: redactTokens,
            maxLogTailBytes: maxLogTailBytes,
            operatorChannelLiveTestSnapshot: .empty
        )
    }

    static func exportDiagnosticsBundle(
        redactTokens: Bool = true,
        maxLogTailBytes: Int = 2_000_000,
        operatorChannelAdminToken: String,
        operatorChannelGRPCPort: Int
    ) async throws -> ExportResult {
        let operatorChannelLiveTestSnapshot = await loadOperatorChannelLiveTestSnapshot(
            adminToken: operatorChannelAdminToken,
            grpcPort: operatorChannelGRPCPort
        )
        return try exportDiagnosticsBundleCore(
            redactTokens: redactTokens,
            maxLogTailBytes: maxLogTailBytes,
            operatorChannelLiveTestSnapshot: operatorChannelLiveTestSnapshot
        )
    }

    static func exportUnifiedDoctorReports(
        status: AIRuntimeStatus? = AIRuntimeStatusStorage.load(),
        blockedCapabilities: [String] = HubLaunchStatusStorage.load()?.degraded.blockedCapabilities ?? [],
        statusURL: URL = AIRuntimeStatusStorage.url(),
        operatorChannelAdminToken: String,
        operatorChannelGRPCPort: Int,
        runtimeOutputURL: URL = XHubDoctorOutputStore.defaultHubReportURL(),
        channelOutputURL: URL = XHubDoctorOutputStore.defaultHubChannelOnboardingReportURL(),
        surface: XHubDoctorSurface = .hubUI
    ) async -> UnifiedDoctorReportsResult {
        let runtimeReport = XHubDoctorOutputStore.writeCurrentHubRuntimeReadinessReport(
            status: status,
            blockedCapabilities: blockedCapabilities,
            outputURL: runtimeOutputURL,
            surface: surface,
            statusURL: statusURL
        )
        let operatorChannelSnapshot = await loadOperatorChannelLiveTestSnapshot(
            adminToken: operatorChannelAdminToken,
            grpcPort: operatorChannelGRPCPort
        )
        let channelReport = XHubDoctorOutputStore.writeHubChannelOnboardingReadinessReport(
            readinessRows: operatorChannelSnapshot.readinessRows,
            runtimeRows: operatorChannelSnapshot.runtimeRows,
            liveTestReports: operatorChannelSnapshot.reports,
            sourceStatus: operatorChannelSnapshot.sourceStatus,
            fetchErrors: operatorChannelSnapshot.fetchErrors,
            adminBaseURL: operatorChannelSnapshot.adminBaseURL,
            outputURL: channelOutputURL,
            surface: surface
        )
        let runtimeBaseURL = runtimeOutputURL.deletingLastPathComponent()
        return UnifiedDoctorReportsResult(
            runtimeReportPath: runtimeReport.reportPath,
            channelOnboardingReportPath: channelReport.reportPath,
            localServiceSnapshotPath: runtimeBaseURL
                .appendingPathComponent("xhub_local_service_snapshot.redacted.json").path,
            localServiceRecoveryGuidancePath: runtimeBaseURL
                .appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json").path
        )
    }

    private static func exportDiagnosticsBundleCore(
        redactTokens: Bool = true,
        maxLogTailBytes: Int = 2_000_000,
        operatorChannelLiveTestSnapshot: OperatorChannelLiveTestSnapshot
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
            InputFile(name: "provider_pack_registry.redacted.json", url: base.appendingPathComponent("provider_pack_registry.json"), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
            InputFile(name: "ai_runtime.log", url: base.appendingPathComponent("ai_runtime.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "mlx_runtime_audit.log", url: base.appendingPathComponent("mlx_runtime_audit.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
            InputFile(name: "voice_tts_audit.log", url: base.appendingPathComponent("voice_tts_audit.log"), fallbackURL: nil, kind: .log, optional: true, redact: true, tailBytes: maxLogTailBytes),
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
            InputFile(name: ModelBenchStorage.fileName, url: ModelBenchStorage.url(), fallbackURL: nil, kind: .json, optional: true, redact: true, tailBytes: 0),
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
        let runtimeStatusURL = AIRuntimeStatusStorage.url()
        let runtimeStatus = AIRuntimeStatusStorage.load()
        let blockedCapabilities = HubLaunchStatusStorage.load()?.degraded.blockedCapabilities ?? []

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

        // Provider-aware runtime summary so operators can see partial readiness without
        // opening multiple status files manually.
        do {
            let runtimeSummaryEntry = try exportLocalRuntimeProviderSummary(
                status: runtimeStatus,
                blockedCapabilities: blockedCapabilities,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(runtimeSummaryEntry)
        } catch {
            missing.append("local_runtime_provider_summary.txt (export_failed)")
        }

        do {
            let runtimeMonitorSummaryEntry = try exportLocalRuntimeMonitorSummary(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(runtimeMonitorSummaryEntry)
        } catch {
            missing.append("local_runtime_monitor_summary.txt (export_failed)")
        }

        do {
            let runtimeMonitorSnapshotEntry = try exportLocalRuntimeMonitorSnapshot(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(runtimeMonitorSnapshotEntry)
        } catch {
            missing.append("local_runtime_monitor_snapshot.redacted.json (export_failed)")
        }

        do {
            let managedServiceSnapshotEntry = try exportXHubLocalServiceSnapshot(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(managedServiceSnapshotEntry)
        } catch {
            missing.append("xhub_local_service_snapshot.redacted.json (export_failed)")
        }

        do {
            let managedServiceRecoveryEntry = try Self.exportXHubLocalServiceRecoveryGuidance(
                status: runtimeStatus,
                blockedCapabilities: blockedCapabilities,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(managedServiceRecoveryEntry)
        } catch {
            missing.append("xhub_local_service_recovery_guidance.redacted.json (export_failed)")
        }

        do {
            let runtimeBenchSummaryEntry = try exportLocalRuntimeBenchSummary(
                status: runtimeStatus,
                statusURL: runtimeStatusURL,
                benchURL: ModelBenchStorage.url(),
                to: bundleDir
            )
            exported.append(runtimeBenchSummaryEntry)
        } catch {
            missing.append("local_runtime_bench_summary.txt (export_failed)")
        }

        do {
            let doctorOutputEntry = try exportHubDoctorOutput(
                status: runtimeStatus,
                blockedCapabilities: blockedCapabilities,
                statusURL: runtimeStatusURL,
                to: bundleDir
            )
            exported.append(doctorOutputEntry)
        } catch {
            missing.append("xhub_doctor_output_hub.redacted.json (export_failed)")
        }

        if operatorChannelLiveTestSnapshot.shouldExport {
            do {
                let operatorChannelEntries = try exportOperatorChannelLiveTestEvidence(
                    snapshot: operatorChannelLiveTestSnapshot,
                    to: bundleDir
                )
                exported.append(contentsOf: operatorChannelEntries)
            } catch {
                missing.append("operator_channel_live_test_summary.txt (export_failed)")
                missing.append("operator_channel_live_test_evidence.redacted.json (export_failed)")
            }
            do {
                let onboardingReadinessEntry = try exportOperatorChannelOnboardingReadinessReport(
                    snapshot: operatorChannelLiveTestSnapshot,
                    to: bundleDir
                )
                exported.append(onboardingReadinessEntry)
            } catch {
                missing.append("xhub_doctor_output_channel_onboarding.redacted.json (export_failed)")
            }
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
        lines.append("sqlite3_launch_error: \(qc.launchError.isEmpty ? exportStrings.none : qc.launchError)")
        lines.append("sqlite3_exit_code: \(qc.exitCode)")
        lines.append("quick_check_elapsed_ms: \(qc.elapsedMs)")

        let out = qc.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = qc.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let outNorm = out.lowercased()
        let okLine = outNorm == "ok" || outNorm.hasSuffix("\nok")
        let checkOK = qc.launchError.isEmpty && qc.exitCode == 0 && okLine
        lines.append("quick_check_ok: \(checkOK ? "1" : "0")")
        lines.append("quick_check_stdout:\n" + (out.isEmpty ? exportStrings.empty : limitForReport(out)))
        lines.append("quick_check_stderr:\n" + (err.isEmpty ? exportStrings.empty : limitForReport(err)))

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

    static func localRuntimeProviderSummaryReport(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> String {
        let summary = status?.providerOperatorSummary(
            ttl: AIRuntimeStatus.recommendedHeartbeatTTL,
            blockedCapabilities: blockedCapabilities
        ) ?? "runtime_alive=0\nready_providers=none\nproviders:\ncapabilities:"
        let doctor = status?.providerDoctorText(
            ttl: AIRuntimeStatus.recommendedHeartbeatTTL,
            blockedCapabilities: blockedCapabilities
        ) ?? exportStrings.runtimeNotStarted
        let monitorSummary = status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? "runtime_alive=0\nmonitor_snapshot=none"

        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_provider_summary.v2")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append(
            "blocked_capabilities:\n" +
            (blockedCapabilities.isEmpty ? exportStrings.none : blockedCapabilities.joined(separator: "\n"))
        )
        lines.append("doctor:\n" + (doctor.isEmpty ? exportStrings.none : doctor))
        lines.append("operator_summary:\n" + summary)
        lines.append("runtime_monitor:\n" + monitorSummary)

        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeMonitorSummaryReport(
        status: AIRuntimeStatus?,
        models: [HubModel] = ModelStateStorage.load().models,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> String {
        let summary = status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? "runtime_alive=0\nmonitor_snapshot=none"
        let runtimeOps = localRuntimeOperationsSummary(
            status: status,
            models: models,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )

        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_monitor_summary.v1")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append("monitor_summary:\n" + summary)
        lines.append("runtime_ops_summary:\n" + runtimeOpsSummaryBlock(runtimeOps))
        if runtimeOps.instanceRows.isEmpty {
            lines.append("loaded_instances:\n\(exportStrings.none)")
        } else {
            lines.append(
                "loaded_instances:\n" +
                runtimeOps.instanceRows.map(runtimeOpsInstanceLine).joined(separator: "\n")
            )
        }

        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeConsoleClipboardReport(
        status: AIRuntimeStatus?,
        models: [HubModel] = ModelStateStorage.load().models,
        currentTargetsByModelID: [String: LocalModelRuntimeRequestContext]? = nil,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> String {
        let localModels = localRuntimeModels(models)
        let resolvedCurrentTargetsByModelID = currentTargetsByModelID ?? localRuntimeCurrentTargetsByModelID(
            status: status,
            models: localModels,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )
        let runtimeOps = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: localModels,
            currentTargetsByModelID: resolvedCurrentTargetsByModelID
        )
        let runtimeOperations = localRuntimeOperationsExport(
            summary: runtimeOps,
            status: status,
            models: localModels,
            currentTargetsByModelID: resolvedCurrentTargetsByModelID
        )
        let providerDiagnoses = status?.providerDiagnoses(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? []
        let providerDiagnosisByID = Dictionary(uniqueKeysWithValues: providerDiagnoses.map { ($0.provider, $0) })
        let providerMonitorByID = Dictionary(uniqueKeysWithValues: (status?.monitorSnapshot?.providers ?? []).map { ($0.provider, $0) })
        let modelByID = Dictionary(uniqueKeysWithValues: localModels.map { ($0.id, $0) })
        let activeTasks = status?.monitorSnapshot?.activeTasks ?? []

        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_console_clipboard.v1")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append(
            "monitor_summary:\n" +
            (status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? "runtime_alive=0\nmonitor_snapshot=none")
        )
        lines.append("runtime_ops_summary:\n" + runtimeOpsSummaryBlock(runtimeOps))
        lines.append(
            "loaded_instances:\n" +
            (runtimeOps.instanceRows.isEmpty
                ? exportStrings.none
                : runtimeOps.instanceRows.map(runtimeOpsInstanceLine).joined(separator: "\n"))
        )
        lines.append(
            "current_targets:\n" +
            (runtimeOperations.currentTargets.isEmpty
                ? exportStrings.none
                : runtimeOperations.currentTargets.map {
                    localRuntimeConsoleCurrentTargetLine(
                        $0,
                        providerDiagnosis: providerDiagnosisByID[$0.providerID]
                    )
                }
                .joined(separator: "\n"))
        )
        lines.append(
            "active_tasks:\n" +
            (activeTasks.isEmpty
                ? exportStrings.none
                : activeTasks.map {
                    localRuntimeConsoleActiveTaskLine(
                        $0,
                        model: modelByID[$0.modelId],
                        providerDiagnosis: providerDiagnosisByID[$0.provider],
                        queuedTaskCount: providerMonitorByID[$0.provider]?.queuedTaskCount ?? 0
                    )
                }
                .joined(separator: "\n"))
        )

        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeMonitorSnapshotExportData(
        status: AIRuntimeStatus?,
        models: [HubModel] = ModelStateStorage.load().models,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url(),
        hostMetrics: XHubLocalRuntimeHostMetricsSnapshot? = XHubLocalRuntimeHostMetricsSampler.capture()
    ) -> Data? {
        let localModels = localRuntimeModels(models)
        let currentTargetsByModelID = localRuntimeCurrentTargetsByModelID(
            status: status,
            models: localModels,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferencesSnapshot: targetPreferencesSnapshot
        )
        let runtimeOperationsSummary = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: localModels,
            currentTargetsByModelID: currentTargetsByModelID
        )
        let envelope = LocalRuntimeMonitorSnapshotEnvelope(
            schemaVersion: "xhub_local_runtime_monitor_export.v1",
            generatedAtMs: nowMs(),
            statusSource: redactPathForManifest(statusURL.path),
            runtimeAlive: status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false,
            statusSchemaVersion: status?.schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            monitorSummary: localRuntimeMonitorSummary(
                status: status,
                hostMetrics: hostMetrics
            ),
            monitorSnapshot: status?.monitorSnapshot,
            runtimeOperations: localRuntimeOperationsExport(
                summary: runtimeOperationsSummary,
                status: status,
                models: localModels,
                currentTargetsByModelID: currentTargetsByModelID
            ),
            hostMetrics: hostMetrics
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    private static func localRuntimeMonitorSummary(
        status: AIRuntimeStatus?,
        hostMetrics: XHubLocalRuntimeHostMetricsSnapshot?
    ) -> String {
        let base = status?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            ?? "runtime_alive=0\nmonitor_snapshot=none"
        guard let hostMetrics else { return base }

        let metricLines = hostMetrics.detailLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !metricLines.isEmpty else { return base }
        return ([base] + metricLines).joined(separator: "\n")
    }

    static func xhubLocalServiceSnapshotExportData(
        status: AIRuntimeStatus?,
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> Data? {
        let providers = XHubLocalServiceDiagnostics.providerEvidence(status: status, ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let primaryIssue = XHubLocalServiceDiagnostics.primaryIssue(in: providers).map {
            XHubLocalServiceSnapshotPrimaryIssue(
                reasonCode: $0.reasonCode,
                headline: $0.headline,
                message: $0.message,
                nextStep: $0.nextStep
            )
        }
        let doctorReport = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: status,
            blockedCapabilities: [],
            outputPath: "",
            surface: .xtExport,
            statusURL: statusURL
        )
        let doctorProjection = doctorReport.checks
            .first(where: { $0.checkKind == "provider_readiness" })
            .map { providerCheck in
                XHubLocalServiceSnapshotDoctorProjection(
                    overallState: doctorReport.overallState,
                    readyForFirstTask: doctorReport.readyForFirstTask,
                    currentFailureCode: doctorReport.currentFailureCode,
                    currentFailureIssue: doctorReport.currentFailureIssue ?? "",
                    providerCheckStatus: providerCheck.status,
                    providerCheckBlocking: providerCheck.blocking,
                    headline: providerCheck.headline,
                    message: providerCheck.message,
                    nextStep: providerCheck.nextStep,
                    repairDestinationRef: providerCheck.repairDestinationRef ?? ""
                )
            }
        let envelope = XHubLocalServiceSnapshotEnvelope(
            schemaVersion: "xhub_local_service_snapshot_export.v1",
            generatedAtMs: nowMs(),
            statusSource: redactPathForManifest(statusURL.path),
            runtimeAlive: status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false,
            providerCount: providers.count,
            readyProviderCount: providers.filter(\.ready).count,
            primaryIssue: primaryIssue,
            doctorProjection: doctorProjection,
            providers: providers
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func xhubLocalServiceRecoveryGuidanceExportData(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String] = [],
        statusURL: URL = AIRuntimeStatusStorage.url()
    ) -> Data? {
        let providers = XHubLocalServiceDiagnostics.providerEvidence(status: status, ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let guidance = XHubLocalServiceRecoveryGuidanceBuilder.build(
            status: status,
            blockedCapabilities: blockedCapabilities
        )
        let primaryIssue = guidance.map {
            XHubLocalServiceSnapshotPrimaryIssue(
                reasonCode: $0.primaryIssue.reasonCode,
                headline: $0.primaryIssue.headline,
                message: $0.primaryIssue.message,
                nextStep: $0.primaryIssue.nextStep
            )
        }
        let envelope = XHubLocalServiceRecoveryGuidanceEnvelope(
            schemaVersion: "xhub_local_service_recovery_guidance_export.v1",
            generatedAtMs: nowMs(),
            statusSource: redactPathForManifest(statusURL.path),
            runtimeAlive: status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false,
            guidancePresent: guidance != nil,
            providerCount: providers.count,
            readyProviderCount: providers.filter(\.ready).count,
            currentFailureCode: guidance?.currentFailureCode ?? "",
            currentFailureIssue: guidance?.currentFailureIssue ?? "",
            providerCheckStatus: guidance?.providerCheckStatus ?? "",
            providerCheckBlocking: guidance?.providerCheckBlocking ?? false,
            actionCategory: guidance?.actionCategory ?? "",
            severity: guidance?.severity ?? "",
            installHint: guidance?.installHint ?? "",
            repairDestinationRef: guidance?.repairDestinationRef ?? "",
            serviceBaseURL: guidance?.serviceBaseURL ?? "",
            managedProcessState: guidance?.managedProcessState ?? "",
            managedStartAttemptCount: guidance?.managedStartAttemptCount ?? 0,
            managedLastStartError: guidance?.managedLastStartError ?? "",
            managedLastProbeError: guidance?.managedLastProbeError ?? "",
            blockedCapabilities: blockedCapabilities,
            primaryIssue: primaryIssue,
            recommendedActions: (guidance?.recommendedActions ?? []).enumerated().map { index, action in
                XHubLocalServiceRecoveryGuidanceEnvelope.RecoveryAction(
                    rank: index + 1,
                    actionID: action.actionID,
                    title: action.title,
                    why: action.why,
                    commandOrReference: action.commandOrReference
                )
            },
            supportFAQ: (guidance?.supportFAQ ?? []).map { item in
                XHubLocalServiceRecoveryGuidanceEnvelope.SupportFAQItem(
                    faqID: item.faqID,
                    question: item.question,
                    answer: item.answer
                )
            }
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func operatorChannelLiveTestEvidenceSummaryReport(
        reports: [HubOperatorChannelLiveTestEvidenceReport],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        generatedAtMs: Int64 = nowMs()
    ) -> String {
        let sortedReports = sortOperatorChannelLiveTestReports(reports)
        let normalizedErrors = operatorChannelUniqueNormalizedStrings(fetchErrors)
        var lines: [String] = []
        lines.append("schema_version: xhub_operator_channel_live_test_summary.v1")
        lines.append("generated_at_ms: \(generatedAtMs)")
        lines.append("source_status: \(sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : sourceStatus)")
        lines.append("admin_base_url: \(adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? exportStrings.none : adminBaseURL)")
        lines.append(
            "fetch_errors:\n" +
            (normalizedErrors.isEmpty ? exportStrings.none : normalizedErrors.joined(separator: "\n"))
        )
        lines.append("provider_count: \(sortedReports.count)")
        if sortedReports.isEmpty {
            lines.append("providers:\n\(exportStrings.none)")
        } else {
            lines.append("providers:\n" + sortedReports.map(operatorChannelLiveTestSummaryBlock).joined(separator: "\n\n---\n\n"))
        }
        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func operatorChannelLiveTestEvidenceExportData(
        reports: [HubOperatorChannelLiveTestEvidenceReport],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        generatedAtMs: Int64 = nowMs()
    ) -> Data? {
        let envelope = OperatorChannelLiveTestEvidenceEnvelope(
            schemaVersion: "xhub_operator_channel_live_test_export.v1",
            generatedAtMs: generatedAtMs,
            sourceStatus: sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : sourceStatus,
            adminBaseURL: adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            fetchErrors: operatorChannelUniqueNormalizedStrings(fetchErrors),
            providerCount: reports.count,
            reports: sortOperatorChannelLiveTestReports(reports)
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(envelope) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func operatorChannelOnboardingReadinessExportData(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        liveTestReports: [HubOperatorChannelLiveTestEvidenceReport] = [],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        outputPath: String = XHubDoctorOutputStore.defaultHubChannelOnboardingReportURL().path,
        surface: XHubDoctorSurface = .hubUI,
        generatedAtMs: Int64 = nowMs()
    ) -> Data? {
        let report = XHubDoctorOutputReport.hubChannelOnboardingReadinessBundle(
            readinessRows: readinessRows,
            runtimeRows: runtimeRows,
            liveTestReports: liveTestReports,
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            sourceReportPath: operatorChannelOnboardingSourcePath(adminBaseURL: adminBaseURL),
            outputPath: outputPath,
            surface: surface,
            generatedAtMs: generatedAtMs
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let raw = try? enc.encode(report) else {
            return nil
        }
        return redactJsonBytes(raw) ?? raw
    }

    static func localRuntimeBenchSummaryReport(
        models: [HubModel],
        benchSnapshot: ModelsBenchSnapshot,
        status: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load(),
        targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load(),
        statusURL: URL = AIRuntimeStatusStorage.url(),
        benchURL: URL = ModelBenchStorage.url()
    ) -> String {
        var lines: [String] = []
        lines.append("schema_version: xhub_local_runtime_bench_summary.v1")
        lines.append("generated_at_ms: \(nowMs())")
        lines.append("status_source: \(redactPathForManifest(statusURL.path))")
        lines.append("bench_source: \(redactPathForManifest(benchURL.path))")
        lines.append("runtime_alive: \((status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false) ? "1" : "0")")

        let localModels = models
            .filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
            .sorted {
                let lhsName = ($0.name.isEmpty ? $0.id : $0.name).localizedCaseInsensitiveCompare($1.name.isEmpty ? $1.id : $1.name)
                if lhsName != .orderedSame {
                    return lhsName == .orderedAscending
                }
                return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            }
        if localModels.isEmpty {
            lines.append("models:\n\(exportStrings.none)")
            return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
        }

        var modelBlocks: [String] = []
        for model in localModels {
            let targetPreference = targetPreferencesSnapshot.preferences.first(where: { $0.modelId == model.id })
            let requestContext = LocalModelRuntimeRequestContextResolver.resolve(
                model: model,
                runtimeStatus: status,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: targetPreference
            )
            let allRows = benchSnapshot.results
                .filter { $0.modelId == model.id }
                .sorted {
                    if $0.measuredAt == $1.measuredAt {
                        return $0.id < $1.id
                    }
                    return $0.measuredAt > $1.measuredAt
                }
            let preferredBench = allRows.first(where: { requestContext.matchesBenchResult($0) }) ?? allRows.first
            let taskKind = preferredBench?.taskKind
                ?? LocalTaskRoutingCatalog.supportedDescriptors(in: model.taskKinds).first?.taskKind
                ?? model.taskKinds.first
                ?? ""
            let explanation = LocalModelBenchMonitorExplanationBuilder.build(
                model: model,
                taskKind: taskKind,
                requestContext: requestContext,
                benchResult: preferredBench,
                runtimeStatus: status
            )
            let capabilityCard = LocalModelBenchCapabilityCardBuilder.build(
                model: model,
                taskKind: taskKind,
                requestContext: requestContext,
                benchResult: preferredBench,
                explanation: explanation,
                runtimeStatus: status
            )
            modelBlocks.append(
                localRuntimeBenchModelBlock(
                    model: model,
                    requestContext: requestContext,
                    benchResult: preferredBench,
                    explanation: explanation,
                    capabilityCard: capabilityCard
                )
            )
        }

        lines.append("models:\n" + modelBlocks.joined(separator: "\n\n---\n\n"))
        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    static func localRuntimeBenchModelReport(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext?,
        benchResult: ModelBenchResult?,
        runtimeStatus: AIRuntimeStatus?,
        generatedAtMs: Int64 = nowMs()
    ) -> String {
        let resolvedRequestContext = requestContext ?? LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: runtimeStatus
        )
        let taskKind = benchResult?.taskKind
            ?? LocalTaskRoutingCatalog.supportedDescriptors(in: model.taskKinds).first?.taskKind
            ?? model.taskKinds.first
            ?? ""
        let explanation = LocalModelBenchMonitorExplanationBuilder.build(
            model: model,
            taskKind: taskKind,
            requestContext: resolvedRequestContext,
            benchResult: benchResult,
            runtimeStatus: runtimeStatus
        )
        let capabilityCard = LocalModelBenchCapabilityCardBuilder.build(
            model: model,
            taskKind: taskKind,
            requestContext: resolvedRequestContext,
            benchResult: benchResult,
            explanation: explanation,
            runtimeStatus: runtimeStatus
        )

        let lines = [
            "schema_version: xhub_local_runtime_bench_model_report.v1",
            "generated_at_ms: \(generatedAtMs)",
            localRuntimeBenchModelBlock(
                model: model,
                requestContext: resolvedRequestContext,
                benchResult: benchResult,
                explanation: explanation,
                capabilityCard: capabilityCard
            )
        ]
        return redactTextSecrets(lines.joined(separator: "\n\n") + "\n")
    }

    private static func exportLocalRuntimeProviderSummary(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let report = localRuntimeProviderSummaryReport(
            status: status,
            blockedCapabilities: blockedCapabilities,
            statusURL: statusURL
        )
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_provider_summary.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_provider_summary.txt",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportLocalRuntimeMonitorSummary(
        status: AIRuntimeStatus?,
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let report = localRuntimeMonitorSummaryReport(status: status, statusURL: statusURL)
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_monitor_summary.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_monitor_summary.txt",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportLocalRuntimeMonitorSnapshot(
        status: AIRuntimeStatus?,
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let data = localRuntimeMonitorSnapshotExportData(status: status, statusURL: statusURL)
            ?? Data("{\"schema_version\":\"xhub_local_runtime_monitor_export.v1\",\"runtime_alive\":false,\"monitor_snapshot\":null}\n".utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_monitor_snapshot.redacted.json")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_monitor_snapshot.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportXHubLocalServiceSnapshot(
        status: AIRuntimeStatus?,
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let data = xhubLocalServiceSnapshotExportData(status: status, statusURL: statusURL)
            ?? Data("{\"schema_version\":\"xhub_local_service_snapshot_export.v1\",\"runtime_alive\":false,\"provider_count\":0,\"ready_provider_count\":0,\"providers\":[]}\n".utf8)
        let dst = bundleDir.appendingPathComponent("xhub_local_service_snapshot.redacted.json")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "xhub_local_service_snapshot.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportXHubLocalServiceRecoveryGuidance(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let data = xhubLocalServiceRecoveryGuidanceExportData(
            status: status,
            blockedCapabilities: blockedCapabilities,
            statusURL: statusURL
        )
            ?? Data("""
            {"schema_version":"xhub_local_service_recovery_guidance_export.v1","runtime_alive":false,"guidance_present":false,"provider_count":0,"ready_provider_count":0,"recommended_actions":[],"support_faq":[]}
            """.utf8)
        let dst = bundleDir.appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "xhub_local_service_recovery_guidance.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportLocalRuntimeBenchSummary(
        status: AIRuntimeStatus?,
        statusURL: URL,
        benchURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let report = localRuntimeBenchSummaryReport(
            models: ModelStateStorage.load().models,
            benchSnapshot: ModelBenchStorage.load(),
            status: status,
            statusURL: statusURL,
            benchURL: benchURL
        )
        let data = Data(report.utf8)
        let dst = bundleDir.appendingPathComponent("local_runtime_bench_summary.txt")
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "local_runtime_bench_summary.txt",
            sourcePath: redactPathForManifest(benchURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportHubDoctorOutput(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String],
        statusURL: URL,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let dst = bundleDir.appendingPathComponent("xhub_doctor_output_hub.redacted.json")
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: status,
            blockedCapabilities: blockedCapabilities,
            outputPath: dst.path,
            surface: .hubUI,
            statusURL: statusURL
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let raw = try encoder.encode(report)
        let data = redactJsonBytes(raw)
            ?? Data(((String(data: raw, encoding: .utf8) ?? "") + "\n").utf8)
        try writeDataAtomic(data, to: dst)

        return ExportedFileEntry(
            name: "xhub_doctor_output_hub.redacted.json",
            sourcePath: redactPathForManifest(statusURL.path),
            bytes: data.count,
            sha256: sha256Hex(data),
            truncated: false,
            redacted: true
        )
    }

    private static func exportOperatorChannelLiveTestEvidence(
        snapshot: OperatorChannelLiveTestSnapshot,
        to bundleDir: URL
    ) throws -> [ExportedFileEntry] {
        let summary = operatorChannelLiveTestEvidenceSummaryReport(
            reports: snapshot.reports,
            sourceStatus: snapshot.sourceStatus,
            fetchErrors: snapshot.fetchErrors,
            adminBaseURL: snapshot.adminBaseURL
        )
        let summaryData = Data(summary.utf8)
        let summaryURL = bundleDir.appendingPathComponent("operator_channel_live_test_summary.txt")
        try writeDataAtomic(summaryData, to: summaryURL)

        let jsonData = operatorChannelLiveTestEvidenceExportData(
            reports: snapshot.reports,
            sourceStatus: snapshot.sourceStatus,
            fetchErrors: snapshot.fetchErrors,
            adminBaseURL: snapshot.adminBaseURL
        )
            ?? Data("""
            {"schema_version":"xhub_operator_channel_live_test_export.v1","source_status":"\(snapshot.sourceStatus)","provider_count":0,"reports":[]}
            """.utf8)
        let jsonURL = bundleDir.appendingPathComponent("operator_channel_live_test_evidence.redacted.json")
        try writeDataAtomic(jsonData, to: jsonURL)

        let sourcePath = snapshot.adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "hub://admin/operator-channels/live-test/evidence"
            : snapshot.adminBaseURL + "/admin/operator-channels/live-test/evidence"

        return [
            ExportedFileEntry(
                name: "operator_channel_live_test_summary.txt",
                sourcePath: sourcePath,
                bytes: summaryData.count,
                sha256: sha256Hex(summaryData),
                truncated: false,
                redacted: true
            ),
            ExportedFileEntry(
                name: "operator_channel_live_test_evidence.redacted.json",
                sourcePath: sourcePath,
                bytes: jsonData.count,
                sha256: sha256Hex(jsonData),
                truncated: false,
                redacted: true
            ),
        ]
    }

    @discardableResult
    static func writeOperatorChannelOnboardingReadinessReport(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        liveTestReports: [HubOperatorChannelLiveTestEvidenceReport] = [],
        sourceStatus: String = "ok",
        fetchErrors: [String] = [],
        adminBaseURL: String = "",
        generatedAtMs: Int64 = nowMs(),
        to bundleDir: URL
    ) throws -> URL {
        let dst = bundleDir.appendingPathComponent("xhub_doctor_output_channel_onboarding.redacted.json")
        guard let data = operatorChannelOnboardingReadinessExportData(
            readinessRows: readinessRows,
            runtimeRows: runtimeRows,
            liveTestReports: liveTestReports,
            sourceStatus: sourceStatus,
            fetchErrors: fetchErrors,
            adminBaseURL: adminBaseURL,
            outputPath: dst.path,
            generatedAtMs: generatedAtMs
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        try writeDataAtomic(data, to: dst)
        return dst
    }

    private static func exportOperatorChannelOnboardingReadinessReport(
        snapshot: OperatorChannelLiveTestSnapshot,
        to bundleDir: URL
    ) throws -> ExportedFileEntry {
        let dst = try writeOperatorChannelOnboardingReadinessReport(
            readinessRows: snapshot.readinessRows,
            runtimeRows: snapshot.runtimeRows,
            liveTestReports: snapshot.reports,
            sourceStatus: snapshot.sourceStatus,
            fetchErrors: snapshot.fetchErrors,
            adminBaseURL: snapshot.adminBaseURL,
            to: bundleDir
        )
        let data = try Data(contentsOf: dst)
        return ExportedFileEntry(
            name: dst.lastPathComponent,
            sourcePath: operatorChannelOnboardingSourcePath(adminBaseURL: snapshot.adminBaseURL),
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
        if lowerKey == "request_payload" { return true }
        if lowerKey == "payload" { return true }
        if lowerKey == "prompt" { return true }
        if lowerKey == "messages" { return true }
        if lowerKey == "input_path" { return true }
        if lowerKey == "file_path" { return true }
        if lowerKey == "image_path" { return true }
        if lowerKey == "audio_path" { return true }
        if lowerKey == "video_path" { return true }
        if lowerKey == "account_id" { return true }
        if lowerKey == "external_user_id" { return true }
        if lowerKey == "external_tenant_id" { return true }
        if lowerKey == "conversation_id" { return true }
        if lowerKey == "thread_key" { return true }
        if lowerKey == "first_message_preview" { return true }
        if lowerKey == "proposed_scope_id" { return true }
        if lowerKey == "scope_id" { return true }
        if lowerKey == "hub_user_id" { return true }
        if lowerKey == "approved_by_hub_user_id" { return true }
        if lowerKey == "preferred_device_id" { return true }
        if lowerKey == "project_id" { return true }
        if lowerKey == "binding_id" { return true }
        if lowerKey == "ack_outbox_item_id" { return true }
        if lowerKey == "smoke_outbox_item_id" { return true }
        if lowerKey == "provider_message_ref" { return true }
        if lowerKey == "identity_actor_ref" { return true }
        if lowerKey == "channel_binding_id" { return true }
        if lowerKey == "revoked_by_hub_user_id" { return true }
        if lowerKey == "audit_ref" { return true }
        if lowerKey == "last_request_id" { return true }
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
