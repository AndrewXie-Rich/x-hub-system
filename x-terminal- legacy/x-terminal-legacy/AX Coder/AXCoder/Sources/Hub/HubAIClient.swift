import Foundation

enum HubTransportMode: String, CaseIterable {
    case auto
    case grpc
    case fileIPC = "file"
}

enum HubAIError: Error, LocalizedError {
    case runtimeNotRunning
    case grpcRouteUnavailable
    case requestWriteFailed(String)
    case responseTimeout
    case responseDoneNotOk(String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotRunning:
            return "Hub AI runtime is not running. Open REL Flow Hub -> Settings -> AI Runtime -> Start."
        case .grpcRouteUnavailable:
            return "Hub gRPC route is unavailable (missing pairing profile). Run Hub one-click pairing first, or switch to `/hub route auto` / `/hub route file`."
        case .requestWriteFailed(let msg):
            return "Failed to write AI request: \(msg)"
        case .responseTimeout:
            return "AI response timed out"
        case .responseDoneNotOk(let reason):
            let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if r == "model_path_missing" {
                return "Hub could not auto-load a model (model_path_missing). Open Hub -> Models, register a model with a valid modelPath, then try again."
            }
            if r == "no_models_registered" || r == "no_model_routed" {
                return "Hub has no loadable model for this task. Open Hub -> Models and register/load at least one model."
            }
            if r == "model_not_loaded" {
                return "No model is loaded. Open Hub -> Models and load a model (or enable auto-load)."
            }
            if r == "model_not_found" {
                return "The selected model id is not found in Hub state. Open Hub -> Models, confirm the model is loaded, then run `/models` and `/model <id>` in X-Terminal to reselect."
            }
            if r == "bridge_disabled" {
                return "Selected model is remote/paid, but Hub Bridge is not enabled. In X-Terminal input box, run `/network 30m` (or `need network 30m`) and approve in Hub if required."
            }
            if r == "remote_model_not_found" {
                return "Hub Bridge cannot find this remote model configuration. Reopen Hub -> Settings -> Remote Models and re-add/import it, then retry."
            }
            if r == "api_key_missing" {
                return "Remote model API key is missing. Set the key in Hub -> Settings -> Remote Models."
            }
            if r == "base_url_invalid" {
                return "Remote model base URL is invalid. Check Base URL in Hub -> Settings -> Remote Models."
            }
            if r == "node_runtime_killed" {
                return "Remote Hub client runtime was killed by macOS. In Hub Setup run Reset Pairing + One-Click to reinstall/sign client kit, or install system Node.js on this Mac."
            }
            if r.hasPrefix("mlx_lm_unavailable") {
                return "Hub runtime is running but MLX is unavailable: \(r)"
            }
            return "AI failed: \(r.isEmpty ? "unknown" : r)"
        }
    }
}

actor HubAIClient {
    static let shared = HubAIClient()
    private static let hubTransportModeKey = "xterminal_hub_transport_mode"
    private static let legacyHubTransportModeKey = "axcoder_hub_transport_mode"
    private static let hubPairingPortKey = "xterminal_hub_pairing_port"
    private static let legacyHubPairingPortKey = "axcoder_hub_pairing_port"
    private static let hubGrpcPortKey = "xterminal_hub_grpc_port"
    private static let legacyHubGrpcPortKey = "axcoder_hub_grpc_port"
    private static let hubInternetHostKey = "xterminal_hub_internet_host"
    private static let legacyHubInternetHostKey = "axcoder_hub_internet_host"
    private static let hubAxhubctlPathKey = "xterminal_hub_axhubctl_path"
    private static let legacyHubAxhubctlPathKey = "axcoder_hub_axhubctl_path"

    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    private let jsonDecoder = JSONDecoder()
    private struct PendingRemoteGenerate {
        var prompt: String
        var preferredModelId: String?
        var explicitModelId: String?
        var maxTokens: Int
        var temperature: Double
        var topP: Double
        var taskType: String
        var appId: String
        var projectId: String?
        var sessionId: String?
    }

    private var pendingRemoteGenerates: [String: PendingRemoteGenerate] = [:]
    private var remoteModelsCache: ModelStateSnapshot = .empty()
    private var remoteModelsLastFetchAt: Date = .distantPast

    static func transportMode() -> HubTransportMode {
        let d = UserDefaults.standard
        let raw = (d.string(forKey: hubTransportModeKey) ?? d.string(forKey: legacyHubTransportModeKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mode = HubTransportMode(rawValue: raw) {
            return mode
        }
        return .auto
    }

    static func setTransportMode(_ mode: HubTransportMode) {
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: hubTransportModeKey)
        d.set(mode.rawValue, forKey: legacyHubTransportModeKey)
    }

    static func parseTransportModeToken(_ token: String) -> HubTransportMode? {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "auto":
            return .auto
        case "grpc", "remote":
            return .grpc
        case "file", "fileipc", "ipc", "local":
            return .fileIPC
        default:
            return nil
        }
    }

    static func remoteConnectOptionsFromDefaults(stateDir: URL? = nil) -> HubRemoteConnectOptions {
        let d = UserDefaults.standard
        let pairing = d.object(forKey: hubPairingPortKey) as? Int
            ?? d.object(forKey: legacyHubPairingPortKey) as? Int
            ?? 50052
        let grpc = d.object(forKey: hubGrpcPortKey) as? Int
            ?? d.object(forKey: legacyHubGrpcPortKey) as? Int
            ?? 50051
        let internetHost = d.string(forKey: hubInternetHostKey)
            ?? d.string(forKey: legacyHubInternetHostKey)
            ?? ""
        let axhubctlPath = d.string(forKey: hubAxhubctlPathKey)
            ?? d.string(forKey: legacyHubAxhubctlPathKey)
            ?? ""

        return HubRemoteConnectOptions(
            grpcPort: max(1, min(65_535, grpc)),
            pairingPort: max(1, min(65_535, pairing)),
            deviceName: Host.current().localizedName ?? "X-Terminal",
            internetHost: internetHost,
            axhubctlPath: axhubctlPath,
            stateDir: stateDir
        )
    }

    func loadRuntimeStatus() -> AIRuntimeStatus? {
        let url = HubPaths.runtimeStatusURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? jsonDecoder.decode(AIRuntimeStatus.self, from: data)
    }

    func loadModelsState() async -> ModelStateSnapshot {
        let mode = Self.transportMode()
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        switch mode {
        case .grpc:
            guard hasRemote else { return .empty() }
            return await loadRemoteModelsThrottled() ?? .empty()
        case .fileIPC:
            return loadLocalModelsState()
        case .auto:
            if hasRemote, let remote = await loadRemoteModelsThrottled() {
                return remote
            }
            let local = loadLocalModelsState()
            if !local.models.isEmpty {
                return local
            }
            if hasRemote, let remote = await loadRemoteModelsThrottled() {
                return remote
            }
            return local
        }
    }

    func enqueueGenerate(
        prompt: String,
        taskType: String,
        preferredModelId: String? = nil,
        explicitModelId: String? = nil,
        appId: String = "x_terminal",
        projectId: String? = nil,
        sessionId: String? = nil,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true
    ) async throws -> String {
        let mode = Self.transportMode()
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        let runtimeAlive = (loadRuntimeStatus()?.isAlive(ttl: 3.0) == true)

        if mode == .grpc {
            guard hasRemote else {
                throw HubAIError.grpcRouteUnavailable
            }
            return enqueueRemoteGenerate(
                prompt: prompt,
                preferredModelId: preferredModelId,
                explicitModelId: explicitModelId,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                taskType: taskType,
                appId: appId,
                projectId: projectId,
                sessionId: sessionId,
                autoLoad: autoLoad
            )
        }

        if mode == .auto {
            if hasRemote {
                return enqueueRemoteGenerate(
                    prompt: prompt,
                    preferredModelId: preferredModelId,
                    explicitModelId: explicitModelId,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    topP: topP,
                    taskType: taskType,
                    appId: appId,
                    projectId: projectId,
                    sessionId: sessionId,
                    autoLoad: autoLoad
                )
            }
            guard runtimeAlive else {
                throw HubAIError.runtimeNotRunning
            }
        } else {
            // file route
            guard runtimeAlive else {
                throw HubAIError.runtimeNotRunning
            }
        }

        let rid = UUID().uuidString
        let req = HubAIRequest(
            req_id: rid,
            app_id: appId,
            task_type: taskType,
            preferred_model_id: preferredModelId,
            model_id: explicitModelId,
            prompt: prompt,
            max_tokens: max(1, min(8192, maxTokens)),
            temperature: temperature,
            top_p: topP,
            created_at: Date().timeIntervalSince1970,
            auto_load: autoLoad
        )

        let reqDir = HubPaths.reqDir()
        let respDir = HubPaths.respDir()
        let cancelDir = HubPaths.cancelDir()
        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cancelDir, withIntermediateDirectories: true)

        let reqURL = reqDir.appendingPathComponent("req_\(rid).json")
        let tmpURL = reqDir.appendingPathComponent(".req_\(rid).tmp")

        do {
            let data = try jsonEncoder.encode(req)
            try data.write(to: tmpURL, options: .atomic)
            try FileManager.default.moveItem(at: tmpURL, to: reqURL)
        } catch {
            throw HubAIError.requestWriteFailed("\(type(of: error)):\(error.localizedDescription)")
        }

        return rid
    }

    private func enqueueRemoteGenerate(
        prompt: String,
        preferredModelId: String?,
        explicitModelId: String?,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        taskType: String,
        appId: String,
        projectId: String?,
        sessionId: String?,
        autoLoad: Bool
    ) -> String {
        let rid = UUID().uuidString
        pendingRemoteGenerates[rid] = PendingRemoteGenerate(
            prompt: prompt,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            maxTokens: max(1, min(8192, maxTokens)),
            temperature: temperature,
            topP: topP,
            taskType: taskType,
            appId: appId,
            projectId: projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionId: sessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        _ = autoLoad
        return rid
    }

    private func loadLocalModelsState() -> ModelStateSnapshot {
        let url = HubPaths.modelsStateURL()
        if let data = try? Data(contentsOf: url),
           let decoded = try? jsonDecoder.decode(ModelStateSnapshot.self, from: data) {
            return decoded
        }
        return .empty()
    }

    private func loadRemoteModelsThrottled() async -> ModelStateSnapshot? {
        let now = Date()
        if now.timeIntervalSince(remoteModelsLastFetchAt) < 8.0, !remoteModelsCache.models.isEmpty {
            return remoteModelsCache
        }

        remoteModelsLastFetchAt = now
        let report = await HubPairingCoordinator.shared.fetchRemoteModels(options: loadRemoteConnectOptions())
        if report.ok {
            let snap = ModelStateSnapshot(models: report.models, updatedAt: Date().timeIntervalSince1970)
            remoteModelsCache = snap
            return snap
        }

        if !remoteModelsCache.models.isEmpty {
            return remoteModelsCache
        }
        return nil
    }

    func cancel(reqId: String) {
        pendingRemoteGenerates.removeValue(forKey: reqId)
        let cancelDir = HubPaths.cancelDir()
        try? FileManager.default.createDirectory(at: cancelDir, withIntermediateDirectories: true)
        let url = cancelDir.appendingPathComponent("cancel_\(reqId).json")
        let tmp = cancelDir.appendingPathComponent(".cancel_\(reqId).tmp")
        let obj: [String: Any] = ["req_id": reqId, "created_at": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
            try? data.write(to: tmp, options: .atomic)
            try? FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    func streamResponse(
        reqId: String,
        timeoutSec: Double = 120.0,
        pollMs: UInt64 = 50
    ) -> AsyncThrowingStream<HubAIResponseEvent, Error> {
        if let remote = pendingRemoteGenerates.removeValue(forKey: reqId) {
            return remoteStreamResponse(reqId: reqId, pending: remote)
        }

        let respURL = HubPaths.respDir().appendingPathComponent("resp_\(reqId).jsonl")
        let decoder = jsonDecoder

        return AsyncThrowingStream { continuation in
            let task = Task {
                let deadline = Date().addingTimeInterval(timeoutSec)
                var offset: UInt64 = 0
                var buf = Data()

                func drainLines() {
                    while true {
                        if let range = buf.firstRange(of: Data([0x0A])) { // '\n'
                            let lineData = buf.subdata(in: buf.startIndex ..< range.lowerBound)
                            buf.removeSubrange(buf.startIndex ... range.lowerBound)

                            let trimmed = lineData.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D } // space/tab/CR
                            if trimmed.isEmpty { continue }

                            do {
                                let ev = try decoder.decode(HubAIResponseEvent.self, from: Data(trimmed))
                                continuation.yield(ev)
                                if ev.type == "done" {
                                    if ev.ok == true {
                                        continuation.finish()
                                    } else {
                                        continuation.finish(throwing: HubAIError.responseDoneNotOk(ev.reason ?? ""))
                                    }
                                    return
                                }
                            } catch {
                                // Ignore malformed lines (best-effort tailing).
                                continue
                            }
                        } else {
                            break
                        }
                    }
                }

                while Date() < deadline {
                    try Task.checkCancellation()

                    if FileManager.default.fileExists(atPath: respURL.path) {
                        do {
                            let fh = try FileHandle(forReadingFrom: respURL)
                            defer { try? fh.close() }
                            try fh.seek(toOffset: offset)
                            if let chunk = try fh.readToEnd(), !chunk.isEmpty {
                                offset += UInt64(chunk.count)
                                buf.append(chunk)
                                drainLines()
                            }
                        } catch {
                            // Read races are expected; just retry.
                        }
                    }

                    try await Task.sleep(nanoseconds: pollMs * 1_000_000)
                }

                continuation.finish(throwing: HubAIError.responseTimeout)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func remoteStreamResponse(
        reqId: String,
        pending: PendingRemoteGenerate
    ) -> AsyncThrowingStream<HubAIResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let preferred = pending.explicitModelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? pending.explicitModelId
                    : pending.preferredModelId

                let report = await HubPairingCoordinator.shared.generateRemoteText(
                    options: loadRemoteConnectOptions(),
                    modelId: preferred,
                    prompt: pending.prompt,
                    maxTokens: pending.maxTokens,
                    temperature: pending.temperature,
                    topP: pending.topP,
                    taskType: pending.taskType,
                    appId: pending.appId,
                    projectId: pending.projectId,
                    sessionId: pending.sessionId,
                    requestId: reqId
                )

                if report.ok {
                    continuation.yield(
                        HubAIResponseEvent(
                            type: "delta",
                            req_id: reqId,
                            ok: true,
                            reason: nil,
                            text: report.text,
                            seq: 1
                        )
                    )
                    continuation.yield(
                        HubAIResponseEvent(
                            type: "done",
                            req_id: reqId,
                            ok: true,
                            reason: "eos"
                        )
                    )
                    continuation.finish()
                } else {
                    continuation.finish(throwing: HubAIError.responseDoneNotOk(report.reasonCode ?? "remote_chat_failed"))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func loadRemoteConnectOptions() -> HubRemoteConnectOptions {
        Self.remoteConnectOptionsFromDefaults(stateDir: nil)
    }

    func generateText(
        prompt: String,
        taskType: String,
        preferredModelId: String? = nil,
        explicitModelId: String? = nil,
        appId: String = "x_terminal",
        projectId: String? = nil,
        sessionId: String? = nil,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true,
        timeoutSec: Double = 120.0
    ) async throws -> String {
        let (rid, text, _) = try await generateTextWithReqId(
            prompt: prompt,
            taskType: taskType,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            appId: appId,
            projectId: projectId,
            sessionId: sessionId,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            autoLoad: autoLoad
        )
        _ = rid
        return text
    }

    func generateTextWithReqId(
        prompt: String,
        taskType: String,
        preferredModelId: String? = nil,
        explicitModelId: String? = nil,
        appId: String = "x_terminal",
        projectId: String? = nil,
        sessionId: String? = nil,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true,
        timeoutSec: Double = 120.0
    ) async throws -> (reqId: String, text: String, usage: HubAIUsage?) {
        let rid = try await enqueueGenerate(
            prompt: prompt,
            taskType: taskType,
            preferredModelId: preferredModelId,
            explicitModelId: explicitModelId,
            appId: appId,
            projectId: projectId,
            sessionId: sessionId,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            autoLoad: autoLoad
        )

        var out = ""
        var usage: HubAIUsage? = nil
        for try await ev in streamResponse(reqId: rid, timeoutSec: timeoutSec) {
            if ev.type == "delta", let t = ev.text {
                out += t
            }
            if ev.type == "done" {
                if let pt = ev.promptTokens, let gt = ev.generationTokens {
                    usage = HubAIUsage(promptTokens: pt, generationTokens: gt, generationTPS: ev.generationTPS ?? 0.0)
                }
            }
        }
        return (rid, out, usage)
    }
}
