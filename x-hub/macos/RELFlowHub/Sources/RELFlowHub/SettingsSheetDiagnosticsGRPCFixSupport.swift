import AppKit
import Foundation
import RELFlowHubCore

extension SettingsSheetView {
func grpcPortConflictLikely(snapshot: HubLaunchStatusSnapshot?) -> Bool {
        if snapshot?.rootCause?.errorCode == "XHUB_GRPC_PORT_IN_USE" {
            return true
        }
        let err = store.grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if err.isEmpty { return false }
        return err.contains("port") && err.contains("already in use")
    }

    @MainActor
    func repairGRPCPortConflictAsync() async -> FixNowOutcome {
        let oldPort = store.grpc.port
        if let free = HubGRPCServerSupport.diagnosticsFindAvailablePort(startingAt: oldPort + 1) {
            store.grpc.port = free
            store.grpc.start()
            return await verifyGRPCAfterFix(
                successCode: "FIX_GRPC_PORT_SWITCH_OK",
                failureCode: "FIX_GRPC_PORT_SWITCH_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedPortSwitch(oldPort: oldPort, newPort: free)
            )
        }

        store.grpc.restart()
        return await verifyGRPCAfterFix(
            successCode: "FIX_GRPC_RESTART_OK",
            failureCode: "FIX_GRPC_RESTART_FAILED",
            actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartOnSamePort(oldPort)
        )
    }

    @MainActor

    func repairDBSafeForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=repair_db_safe")

        let res = await repairGRPCDBSafeAndRestart()

        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        if res.ok {
            diagnosticsActionResultText = res.render()
        } else {
            diagnosticsActionErrorText = res.render()
        }
    }

    @MainActor
    func repairGRPCDBSafeAndRestart() async -> FixNowOutcome {
        // Stop gRPC first to reduce chances of DB locks during checkpoint/check.
        store.grpc.stop()

        let base = SharedPaths.ensureHubDirectory()
        let dbDir = base.appendingPathComponent("hub_grpc", isDirectory: true)
        let db = dbDir.appendingPathComponent("hub.sqlite3")

        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

            // Fix a common crash-loop case: a zero-byte DB file.
            if FileManager.default.fileExists(atPath: db.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: db.path),
               let size = attrs[.size] as? NSNumber,
               size.int64Value == 0 {
                try? FileManager.default.removeItem(at: db)
            }

            // Backup (best-effort) before touching WAL/checkpoint.
            if FileManager.default.fileExists(atPath: db.path) {
                let ts = Int(Date().timeIntervalSince1970)
                let bak = dbDir.appendingPathComponent("hub.sqlite3.bak_\(ts)")
                if !FileManager.default.fileExists(atPath: bak.path) {
                    try? FileManager.default.copyItem(at: db, to: bak)
                }
            }

            // Best-effort: checkpoint WAL (safe) to reduce "stuck WAL" and shrink temporary files.
            _ = runSQLite(dbPath: db.path, readonly: false, sql: "PRAGMA busy_timeout=1500; PRAGMA wal_checkpoint(TRUNCATE);")

            // Quick check for corruption/locking.
            let qc = runSQLite(dbPath: db.path, readonly: true, sql: "PRAGMA busy_timeout=1500; PRAGMA quick_check;")
            let out = qc.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = qc.exitCode == 0 && (out.lowercased() == "ok" || out.lowercased().hasSuffix("\nok"))

            store.grpc.start()

            if ok {
                return await verifyGRPCAfterFix(
                    successCode: "FIX_GRPC_DB_REPAIR_OK",
                    failureCode: "FIX_GRPC_DB_REPAIR_RESTART_FAILED",
                    actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairQuickCheckPassed
                )
            }

            let err = (qc.stderr + "\n" + qc.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = err.isEmpty
                ? HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairQuickCheckFailed(exitCode: qc.exitCode)
                : HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairQuickCheckFailed(errorText: err)
            return FixNowOutcome(ok: false, code: "FIX_GRPC_DB_REPAIR_CHECK_FAILED", detail: msg)
        } catch {
            store.grpc.start()
            return FixNowOutcome(
                ok: false,
                code: "FIX_GRPC_DB_REPAIR_EXCEPTION",
                detail: HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairException(error.localizedDescription)
            )
        }
    }

    struct SQLiteRunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    func grpcLogTail(maxBytes: Int = 64 * 1024) -> String {
        let base = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("hub_grpc.log")
        guard let data = try? Data(contentsOf: logURL), !data.isEmpty else {
            return ""
        }
        let tail = data.suffix(max(2048, min(maxBytes, 512 * 1024)))
        return String(data: tail, encoding: .utf8) ?? ""
    }

    func grpcLikelyTLSPEMFailure() -> Bool {
        let lower = grpcLogTail().lowercased()
        if lower.isEmpty { return false }
        let pemNoStartLine =
            lower.contains("err_ossl_pem_no_start_line") ||
            lower.contains("pem routines::no start line") ||
            (lower.contains("node:internal/tls/secure-context") && lower.contains("setcert"))
        let opensslSerialWriteDenied =
            (lower.contains("openssl x509 -req") && lower.contains("-cacreateserial") && lower.contains(".srl: operation not permitted")) ||
            (lower.contains("getting ca private key") && lower.contains(".srl: operation not permitted"))
        return
            pemNoStartLine ||
            opensslSerialWriteDenied
    }

    func runSQLite(dbPath: String, readonly: Bool, sql: String) -> SQLiteRunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        var args: [String] = []
        if readonly {
            args.append("-readonly")
        }
        args.append(contentsOf: ["-batch", dbPath, sql])
        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return SQLiteRunResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return SQLiteRunResult(
            exitCode: p.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }


    struct GRPCFixSnapshot {
        var running: Bool
        var statusText: String
        var lastError: String
    }

    func grpcFixSnapshot() -> GRPCFixSnapshot {
        store.grpc.refresh()
        let status = store.grpc.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = store.grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let running = status.lowercased().contains("grpc: running")
        return GRPCFixSnapshot(running: running, statusText: status, lastError: err)
    }

    @MainActor
    func waitForGRPCFixSnapshot(timeoutNs: UInt64 = 3_500_000_000, pollNs: UInt64 = 250_000_000) async -> GRPCFixSnapshot {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = grpcFixSnapshot()
        while !snap.running && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = grpcFixSnapshot()
        }
        return snap
    }

    func classifyGRPCFailureCode(_ errorOrStatus: String, fallback: String) -> String {
        let lower = errorOrStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return fallback }
        if lower.contains("already in use") || lower.contains("eaddrinuse") {
            return "FIX_GRPC_PORT_IN_USE"
        }
        if lower.contains("node not found") || lower.contains("node missing") {
            return "FIX_GRPC_NODE_MISSING"
        }
        if lower.contains("pem") || lower.contains("certificate") || lower.contains("tls") || lower.contains("secure-context") || lower.contains(".srl") {
            return "FIX_GRPC_TLS_INVALID"
        }
        if lower.contains("db") {
            return "FIX_GRPC_DB_ERROR"
        }
        if lower.contains("exited") {
            return "FIX_GRPC_EXITED"
        }
        return fallback
    }

    @MainActor
    func verifyGRPCAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let snap = await waitForGRPCFixSnapshot()
        if snap.running {
            return FixNowOutcome(ok: true, code: successCode, detail: actionSummary)
        }
        let failureText = !snap.lastError.isEmpty
            ? snap.lastError
            : (!snap.statusText.isEmpty ? snap.statusText : HubUIStrings.Settings.Diagnostics.grpcStillNotRunning)
        let code = classifyGRPCFailureCode(failureText, fallback: failureCode)
        return FixNowOutcome(
            ok: false,
            code: code,
            detail: "\(actionSummary)\n\n\(failureText)"
        )
    }
}
