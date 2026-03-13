import Foundation
import RELFlowHubCore

@MainActor
final class HubLaunchStateMachine {
    static let shared = HubLaunchStateMachine()

    private enum Stage {
        case idle
        case waitGRPC
        case waitBridge
        case waitRuntime
        case done
    }

    private var stage: Stage = .idle
    private var launchId: String = ""
    private var bootStartedAtMs: Int64 = 0
    private var stageStartedAtMs: Int64 = 0
    private var steps: [HubLaunchStep] = []
    private var failures: [HubLaunchComponent: (code: String, hint: String)] = [:]
    private var timer: Timer?
    private var bridgeWasStartedByApp: Bool = false
    private var currentState: HubLaunchState = .bootStart

    private let grpcTimeoutMs: Int64 = 15_000
    private let bridgeTimeoutMs: Int64 = 8_000
    private let runtimeTimeoutMs: Int64 = 25_000

    private init() {}

    func start(bridgeStarted: Bool) {
        stop()
        launchId = UUID().uuidString
        bridgeWasStartedByApp = bridgeStarted
        stage = .idle
        bootStartedAtMs = nowMs()
        stageStartedAtMs = bootStartedAtMs
        steps.removeAll(keepingCapacity: true)
        failures.removeAll(keepingCapacity: true)

        currentState = .bootStart
        appendStep(state: .bootStart, ok: true)

        let envResult = validateEnvironment()
        appendStep(
            state: .envValidate,
            ok: envResult.ok,
            errorCode: envResult.errorCode,
            errorHint: envResult.errorHint
        )
        if !envResult.ok {
            registerFailure(component: envResult.component, code: envResult.errorCode, hint: envResult.errorHint)
        }

        appendStep(state: .startGRPCServer, ok: true)
        if HubGRPCServerSupport.shared.autoStart {
            HubGRPCServerSupport.shared.start()
        }

        stage = .waitGRPC
        stageStartedAtMs = nowMs()
        currentState = .waitGRPCReady
        persist()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        switch stage {
        case .idle:
            return
        case .waitGRPC:
            tickWaitGRPC()
        case .waitBridge:
            tickWaitBridge()
        case .waitRuntime:
            tickWaitRuntime()
        case .done:
            return
        }
    }

    private func tickWaitGRPC() {
        if grpcReady() || !HubGRPCServerSupport.shared.autoStart {
            appendStep(
                state: .waitGRPCReady,
                ok: true,
                errorCode: "",
                errorHint: HubGRPCServerSupport.shared.autoStart ? "" : "gRPC auto-start disabled"
            )
            enterBridgeStage()
            return
        }

        if elapsedSinceStageStartMs() >= grpcTimeoutMs {
            let failure = classifyGRPCFailure()
            appendStep(state: .waitGRPCReady, ok: false, errorCode: failure.code, errorHint: failure.hint)
            registerFailure(component: .grpc, code: failure.code, hint: failure.hint)
            enterBridgeStage()
            return
        }

        persist()
    }

    private func enterBridgeStage() {
        let bridgeOk = bridgeWasStartedByApp
        appendStep(
            state: .startBridge,
            ok: bridgeOk,
            errorCode: bridgeOk ? "" : "XHUB_BRIDGE_UNAVAILABLE",
            errorHint: bridgeOk ? "" : "Bridge start was not invoked by app"
        )
        if !bridgeOk {
            registerFailure(component: .bridge, code: "XHUB_BRIDGE_UNAVAILABLE", hint: "Bridge start was not invoked by app")
        }
        stage = .waitBridge
        stageStartedAtMs = nowMs()
        currentState = .waitBridgeReady
        persist()
    }

    private func tickWaitBridge() {
        if bridgeReady() {
            appendStep(state: .waitBridgeReady, ok: true)
            enterRuntimeStage()
            return
        }

        if elapsedSinceStageStartMs() >= bridgeTimeoutMs {
            let failure = classifyBridgeFailure()
            appendStep(state: .waitBridgeReady, ok: false, errorCode: failure.code, errorHint: failure.hint)
            registerFailure(component: .bridge, code: failure.code, hint: failure.hint)
            enterRuntimeStage()
            return
        }

        persist()
    }

    private func enterRuntimeStage() {
        appendStep(state: .startRuntime, ok: true)
        if HubStore.shared.aiRuntimeAutoStart {
            HubStore.shared.startAIRuntime()
        }
        stage = .waitRuntime
        stageStartedAtMs = nowMs()
        currentState = .waitRuntimeReady
        persist()
    }

    private func tickWaitRuntime() {
        let autoStartEnabled = HubStore.shared.aiRuntimeAutoStart
        if runtimeReady() || !autoStartEnabled {
            appendStep(
                state: .waitRuntimeReady,
                ok: true,
                errorCode: "",
                errorHint: autoStartEnabled ? "" : "Runtime auto-start disabled"
            )
            finalize()
            return
        }

        if elapsedSinceStageStartMs() >= runtimeTimeoutMs {
            let failure = classifyRuntimeFailure()
            appendStep(state: .waitRuntimeReady, ok: false, errorCode: failure.code, errorHint: failure.hint)
            registerFailure(component: .runtime, code: failure.code, hint: failure.hint)
            finalize()
            return
        }

        persist()
    }

    private func finalize() {
        let next: HubLaunchState
        if failures.isEmpty {
            next = .serving
        } else {
            let nothingReady = !grpcReady() && !bridgeReady() && !runtimeReady()
            next = nothingReady ? .failed : .degradedServing
        }
        currentState = next
        appendStep(state: next, ok: next == .serving)
        stage = .done
        persist()
        stop()
    }

    private func appendStep(
        state: HubLaunchState,
        ok: Bool,
        errorCode: String = "",
        errorHint: String = ""
    ) {
        let ts = nowMs()
        let elapsed = max(0, ts - bootStartedAtMs)
        steps.append(
            HubLaunchStep(
                state: state,
                tsMs: ts,
                elapsedMs: elapsed,
                ok: ok,
                errorCode: errorCode,
                errorHint: errorHint
            )
        )
    }

    private func registerFailure(component: HubLaunchComponent, code: String, hint: String) {
        if failures[component] == nil {
            failures[component] = (code: code, hint: hint)
        }
    }

    private func rootCause() -> HubLaunchRootCause? {
        let priority: [HubLaunchComponent] = [.env, .db, .grpc, .bridge, .runtime]
        for comp in priority {
            if let f = failures[comp] {
                return HubLaunchRootCause(component: comp, errorCode: f.code, detail: f.hint)
            }
        }
        return nil
    }

    private func blockedCapabilities() -> [String] {
        var blocked: [String] = []
        if failures[.bridge] != nil {
            blocked.append("ai.generate.paid")
            blocked.append("web.fetch")
        }
        if failures[.runtime] != nil {
            blocked.append("ai.generate.local")
        }
        if failures[.grpc] != nil {
            blocked.append("grpc.api")
        }
        if failures[.db] != nil {
            blocked.append("hub.db.write")
        }
        // Preserve order and remove duplicates.
        var seen = Set<String>()
        return blocked.filter { item in
            if seen.contains(item) { return false }
            seen.insert(item)
            return true
        }
    }

    private func persist() {
        let snapshot = HubLaunchStatusSnapshot(
            launchId: launchId,
            updatedAtMs: nowMs(),
            state: currentState,
            steps: steps,
            rootCause: rootCause(),
            degraded: HubLaunchDegraded(
                isDegraded: !failures.isEmpty,
                blockedCapabilities: blockedCapabilities()
            )
        )
        HubLaunchStatusStorage.save(snapshot)
        HubLaunchHistoryStorage.upsert(snapshot)
    }

    private func validateEnvironment() -> (ok: Bool, component: HubLaunchComponent, errorCode: String, errorHint: String) {
        let base = SharedPaths.ensureHubDirectory()

        let probe = base.appendingPathComponent(".hub_launch_write_probe")
        do {
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try? FileManager.default.removeItem(at: probe)
        } catch {
            return (
                ok: false,
                component: .env,
                errorCode: "XHUB_ENV_INVALID",
                errorHint: "Cannot write to hub base directory: \(base.path)"
            )
        }

        let dbDir = base.appendingPathComponent("hub_grpc", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        } catch {
            return (
                ok: false,
                component: .db,
                errorCode: "XHUB_DB_OPEN_FAILED",
                errorHint: "Cannot create DB directory: \(dbDir.path)"
            )
        }

        let db = dbDir.appendingPathComponent("hub.sqlite3")
        if FileManager.default.fileExists(atPath: db.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: db.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value == 0 {
            return (
                ok: false,
                component: .db,
                errorCode: "XHUB_DB_INTEGRITY_FAILED",
                errorHint: "DB file is empty: \(db.path)"
            )
        }

        return (ok: true, component: .env, errorCode: "", errorHint: "")
    }

    private func classifyGRPCFailure() -> (code: String, hint: String) {
        let err = HubGRPCServerSupport.shared.lastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = err.lowercased()
        if lower.contains("already in use") || lower.contains("eaddrinuse") {
            return ("XHUB_GRPC_PORT_IN_USE", err.isEmpty ? "gRPC port is already in use" : err)
        }
        if lower.contains("node not found") {
            return ("XHUB_GRPC_NODE_MISSING", err.isEmpty ? "Node.js not found" : err)
        }
        return ("XHUB_GRPC_SERVER_EXITED", err.isEmpty ? "gRPC did not become ready within timeout" : err)
    }

    private func classifyBridgeFailure() -> (code: String, hint: String) {
        let st = BridgeSupport.shared.statusSnapshot()
        if st.updatedAt <= 0 {
            return ("XHUB_BRIDGE_UNAVAILABLE", "Bridge status heartbeat is missing")
        }
        return ("XHUB_BRIDGE_UNAVAILABLE", "Bridge heartbeat is stale or unavailable")
    }

    private func classifyRuntimeFailure() -> (code: String, hint: String) {
        let err = HubStore.shared.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = err.lowercased()
        if lower.contains("script is missing") {
            return ("XHUB_RT_SCRIPT_MISSING", err)
        }
        if lower.contains("python path") || lower.contains("xcrun stub") || lower.contains("not executable") {
            return ("XHUB_RT_PYTHON_INVALID", err)
        }
        if lower.contains("lock") {
            return ("XHUB_RT_LOCK_BUSY", err)
        }
        if lower.contains("mlx is unavailable") || lower.contains("import") {
            return ("XHUB_RT_IMPORT_ERROR", err)
        }
        if let st = AIRuntimeStatusStorage.load(),
           let importError = st.importError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !importError.isEmpty {
            return ("XHUB_RT_IMPORT_ERROR", importError)
        }
        return ("XHUB_RT_IMPORT_ERROR", err.isEmpty ? "Runtime did not become ready within timeout" : err)
    }

    private func grpcReady() -> Bool {
        if HubGRPCServerSupport.shared.isRunning {
            return true
        }
        let status = HubGRPCServerSupport.shared.statusText.lowercased()
        if status.contains("running (external)") {
            return true
        }
        return false
    }

    private func bridgeReady() -> Bool {
        BridgeSupport.shared.statusSnapshot().alive
    }

    private func runtimeReady() -> Bool {
        if let st = AIRuntimeStatusStorage.load() {
            if st.isAlive(ttl: 3.0) && st.hasReadyProvider(ttl: 3.0) {
                return true
            }
        }
        let status = HubStore.shared.aiRuntimeStatusText.lowercased()
        if status.contains("running") && !status.contains("no providers ready") {
            return true
        }
        return false
    }

    private func elapsedSinceStageStartMs() -> Int64 {
        max(0, nowMs() - stageStartedAtMs)
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }
}
