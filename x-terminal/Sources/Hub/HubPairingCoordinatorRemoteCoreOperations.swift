import Foundation

extension HubPairingCoordinator {
    func fetchRemoteModels(options rawOptions: HubRemoteConnectOptions) -> HubRemoteModelsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let list = runRemoteModelsListScript(
            options: opts,
            timeoutSec: Self.remoteModelsListTimeoutSec,
            logs: &logs
        )
        appendStepLogs(into: &logs, step: list)

        guard list.exitCode == 0 else {
            let reason = inferFailureCode(from: list.output, fallback: "remote_models_list_failed")
            return HubRemoteModelsResult(
                ok: false,
                models: [],
                paidAccessSnapshot: nil,
                reasonCode: reason,
                logLines: logs
            )
        }

        let parsed = Self.parseListModelsResultText(list.output)
        return HubRemoteModelsResult(
            ok: true,
            models: parsed.models,
            paidAccessSnapshot: parsed.paidAccessSnapshot,
            reasonCode: nil,
            logLines: logs
        )
    }

    func runRemoteModelsListScript(
        options opts: HubRemoteConnectOptions,
        timeoutSec: Double,
        logs: inout [String]
    ) -> StepOutput {
        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let listModelsScript = clientKitBase
            .appendingPathComponent("hub_grpc_server", isDirectory: true)
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("list_models_client.js", isDirectory: false)
        let commandDisplay = "remote_models_list"

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return StepOutput(
                exitCode: 127,
                output: "missing hub env: \(hubEnv.path)",
                command: commandDisplay
            )
        }

        var exported = readEnvExports(from: hubEnv)
        guard nonEmpty(exported["HUB_CLIENT_TOKEN"]) != nil else {
            return StepOutput(
                exitCode: 127,
                output: "missing HUB_CLIENT_TOKEN in \(hubEnv.path)",
                command: commandDisplay
            )
        }

        let resolvedHost = nonEmpty(opts.internetHost)
            ?? nonEmpty(exported["HUB_HOST"])
        guard let resolvedHost else {
            return StepOutput(
                exitCode: 127,
                output: "missing HUB_HOST for remote models list",
                command: commandDisplay
            )
        }

        exported["HUB_HOST"] = resolvedHost
        exported["HUB_PORT"] = "\(max(1, min(65_535, opts.grpcPort)))"
        let merged = mergedAxhubEnv(options: opts, extra: exported)

        var nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        if !FileManager.default.fileExists(atPath: listModelsScript.path) || nodeBin == nil {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: Self.remoteClientInstallTimeoutSec
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode != 0 {
                return install
            }
            nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        }

        guard FileManager.default.fileExists(atPath: listModelsScript.path) else {
            return StepOutput(
                exitCode: 127,
                output: "missing client kit script: \(listModelsScript.path)",
                command: commandDisplay
            )
        }

        guard let nodeBin else {
            return StepOutput(
                exitCode: 127,
                output: "missing node runtime for remote models list",
                command: commandDisplay
            )
        }

        do {
            let result = try ProcessCapture.run(
                nodeBin,
                [listModelsScript.path],
                cwd: nil,
                timeoutSec: timeoutSec,
                env: merged
            )
            return StepOutput(
                exitCode: result.exitCode,
                output: result.combined,
                command: [nodeBin, listModelsScript.path].joined(separator: " ")
            )
        } catch {
            return StepOutput(
                exitCode: 127,
                output: String(describing: error),
                command: [nodeBin, listModelsScript.path].joined(separator: " ")
            )
        }
    }

    func generateRemoteText(
        options rawOptions: HubRemoteConnectOptions,
        modelId rawModelId: String?,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        taskType: String,
        appId: String?,
        projectId: String?,
        sessionId: String?,
        timeoutSec: Double = 120.0,
        failClosedOnDowngrade: Bool = false,
        requestId: String?
    ) -> HubRemoteGenerateResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let modelId = rawModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let promptText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "prompt_empty",
                logLines: ["prompt is empty for remote generate"]
            )
        }

        let limitedMaxTokens = max(1, min(8192, maxTokens))
        let limitedTemp = max(0, min(2, temperature))
        let limitedTopP = max(0.01, min(1.0, topP))
        let limitedTaskType = nonEmpty(taskType) ?? "assist"
        let limitedAppId = nonEmpty(appId) ?? "x_terminal"
        let limitedProjectId = nonEmpty(projectId) ?? ""
        let limitedSessionId = nonEmpty(sessionId) ?? ""
        let limitedReqId = nonEmpty(requestId) ?? "gen_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6))"
        let limitedTimeoutSec = Self.normalizedRemoteGenerateTimeoutSec(timeoutSec)

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        var nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        if nodeBin == nil {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: Self.remoteClientInstallTimeoutSec
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
            }
        }
        guard let nodeBin else {
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: nil,
                reasonCode: "node_missing",
                logLines: logs + [
                    "missing node runtime for remote generate",
                    "looked for bundled X-Terminal node, client_kit/bin/relflowhub_node, and system node"
                ]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_GEN_REQUEST_ID"] = limitedReqId
        scriptEnv["XTERMINAL_GEN_MODEL_ID"] = modelId
        scriptEnv["XTERMINAL_GEN_TASK_TYPE"] = limitedTaskType
        scriptEnv["XTERMINAL_GEN_APP_ID"] = limitedAppId
        scriptEnv["XTERMINAL_GEN_PROJECT_ID"] = limitedProjectId
        scriptEnv["XTERMINAL_GEN_SESSION_ID"] = limitedSessionId
        scriptEnv["XTERMINAL_GEN_PROMPT_B64"] = Data(prompt.utf8).base64EncodedString()
        scriptEnv["XTERMINAL_GEN_MAX_TOKENS"] = "\(limitedMaxTokens)"
        scriptEnv["XTERMINAL_GEN_TEMPERATURE"] = "\(limitedTemp)"
        scriptEnv["XTERMINAL_GEN_TOP_P"] = "\(limitedTopP)"
        scriptEnv["XTERMINAL_GEN_TIMEOUT_SEC"] = "\(limitedTimeoutSec)"
        scriptEnv["XTERMINAL_GEN_FAIL_CLOSED_ON_DOWNGRADE"] = failClosedOnDowngrade ? "1" : "0"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteGenerateScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: limitedTimeoutSec + Self.remoteGenerateProcessGraceSec,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: Self.remoteClientInstallTimeoutSec
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        func decodeGenerateStep(_ step: StepOutput) -> RemoteGenerateScriptResult? {
            guard let jsonLine = extractTrailingJSONObjectLine(step.output),
                  let data = jsonLine.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(RemoteGenerateScriptResult.self, from: data) else {
                return nil
            }
            return decoded
        }

        func normalizedFailureReason(
            from decoded: RemoteGenerateScriptResult,
            step: StepOutput,
            fallback: String
        ) -> String {
            let rawReason = nonEmpty(decoded.errorCode)
                ?? nonEmpty(decoded.reason)
                ?? nonEmpty(decoded.errorMessage)
            return normalizedRemoteReasonCode(
                rawReason: rawReason,
                stepOutput: step.output,
                fallback: fallback
            )
        }

        func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        func failedGenerateResult(
            decoded: RemoteGenerateScriptResult?,
            reason: String,
            grantDecision: HubRemoteGrantDecision? = nil,
            grantRequestId: String? = nil
        ) -> HubRemoteGenerateResult {
            HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: cleaned(decoded?.modelId) ?? cleaned(modelId),
                requestedModelId: cleaned(decoded?.requestedModelId) ?? cleaned(modelId),
                actualModelId: cleaned(decoded?.actualModelId) ?? cleaned(decoded?.modelId) ?? cleaned(modelId),
                runtimeProvider: cleaned(decoded?.runtimeProvider),
                executionPath: cleaned(decoded?.executionPath),
                fallbackReasonCode: cleaned(decoded?.fallbackReasonCode) ?? cleaned(decoded?.denyCode),
                auditRef: cleaned(decoded?.auditRef),
                denyCode: cleaned(decoded?.denyCode),
                memoryPromptProjection: decoded?.memoryPromptProjection,
                grantDecision: grantDecision,
                grantRequestId: cleaned(grantRequestId),
                reasonCode: reason,
                logLines: logs
            )
        }

        func finalizeGenerateStep(_ step: StepOutput) -> HubRemoteGenerateResult {
            guard let decoded = decodeGenerateStep(step) else {
                let reason = inferFailureCode(from: step.output, fallback: "remote_chat_failed")
                return failedGenerateResult(decoded: nil, reason: reason)
            }

            guard decoded.ok == true else {
                return failedGenerateResult(
                    decoded: decoded,
                    reason: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_failed")
                )
            }

            guard let success = Self.successfulRemoteGenerateResult(
                from: decoded,
                fallbackModelId: modelId,
                logLines: logs
            ) else {
                return failedGenerateResult(
                    decoded: decoded,
                    reason: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_empty_output")
                )
            }

            return success
        }

        guard let decoded = decodeGenerateStep(step) else {
            let reason = inferFailureCode(from: step.output, fallback: "remote_chat_failed")
            return failedGenerateResult(decoded: nil, reason: reason)
        }

        if decoded.ok != true {
            let reason = normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_failed")
            if reason == "grant_required" {
                let paidModelId = nonEmpty(decoded.modelId) ?? nonEmpty(modelId)
                if let paidModelId {
                    let grant = requestRemotePaidAIGrant(
                        options: opts,
                        modelId: paidModelId,
                        appId: limitedAppId,
                        requestedSeconds: 1800,
                        requestedTokenCap: min(5000, max(1024, limitedMaxTokens * 2)),
                        reason: "x_terminal paid generate \(limitedTaskType)",
                        projectId: limitedProjectId.isEmpty ? nil : limitedProjectId
                    )
                    logs.append(contentsOf: grant.logLines)

                    switch grant.decision {
                    case .approved where grant.ok:
                        step = runScript()
                        appendStepLogs(into: &logs, step: step)
                        var result = finalizeGenerateStep(step)
                        result.grantDecision = .approved
                        result.grantRequestId = cleaned(grant.grantRequestId)
                        return result
                    case .queued:
                        return failedGenerateResult(
                            decoded: decoded,
                            reason: "grant_pending",
                            grantDecision: .queued,
                            grantRequestId: grant.grantRequestId
                        )
                    case .denied:
                        return failedGenerateResult(
                            decoded: decoded,
                            reason: grant.reasonCode ?? "grant_denied",
                            grantDecision: .denied,
                            grantRequestId: grant.grantRequestId
                        )
                    case .failed, .approved:
                        return failedGenerateResult(decoded: decoded, reason: grant.reasonCode ?? reason)
                    }
                }
            }

            return failedGenerateResult(decoded: decoded, reason: reason)
        }

        guard let success = Self.successfulRemoteGenerateResult(
            from: decoded,
            fallbackModelId: modelId,
            logLines: logs
        ) else {
            return failedGenerateResult(
                decoded: decoded,
                reason: normalizedFailureReason(from: decoded, step: step, fallback: "remote_chat_empty_output")
            )
        }

        return success
    }

    func requestRemoteNetworkGrant(
        options rawOptions: HubRemoteConnectOptions,
        requestedSeconds: Int,
        reason: String?,
        projectId: String? = nil
    ) -> HubRemoteGrantResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for client kit grant request"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_GRANT_CAPABILITY"] = "CAPABILITY_WEB_FETCH"
        scriptEnv["XTERMINAL_GRANT_SECONDS"] = "\(max(30, min(86_400, requestedSeconds)))"
        scriptEnv["XTERMINAL_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_GRANT_WAIT_SEC"] = "10"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runGrantScript() -> StepOutput {
            do {
                let script = remoteNetworkGrantScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 28.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runGrantScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runGrantScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteNetworkGrantScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_grant_failed")
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemoteGrantDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "queued":
                return .queued
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .queued)
        let rawReasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
        let reasonCode = rawReasonCode.map {
            normalizedRemoteReasonCode(
                rawReason: $0,
                stepOutput: step.output,
                fallback: "remote_grant_failed"
            )
        } ?? (ok ? nil : normalizedRemoteReasonCode(
            rawReason: nil,
            stepOutput: step.output,
            fallback: "remote_grant_failed"
        ))

        let expiresAtSec: Double? = {
            guard let ms = decoded.expiresAtMs, ms > 0 else { return nil }
            return ms / 1000.0
        }()

        return HubRemoteGrantResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId),
            expiresAtSec: expiresAtSec,
            reasonCode: reasonCode,
            logLines: logs
        )
    }

    func requestRemotePaidAIGrant(
        options rawOptions: HubRemoteConnectOptions,
        modelId rawModelId: String,
        appId rawAppId: String? = nil,
        requestedSeconds: Int,
        requestedTokenCap: Int,
        reason: String?,
        projectId: String? = nil
    ) -> HubRemoteGrantResult {
        let paidModelId = rawModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paidModelId.isEmpty else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "grant_model_id_missing",
                logLines: ["missing model id for paid AI grant request"]
            )
        }

        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for paid AI grant request"]
            )
        }

        var scriptEnv = merged
        let effectiveAppId = canonicalHubAppID(rawAppId) ?? ""
        if !effectiveAppId.isEmpty {
            scriptEnv["HUB_APP_ID"] = effectiveAppId
        }
        scriptEnv["XTERMINAL_GRANT_CAPABILITY"] = "CAPABILITY_AI_GENERATE_PAID"
        scriptEnv["XTERMINAL_GRANT_MODEL_ID"] = paidModelId
        scriptEnv["XTERMINAL_GRANT_SECONDS"] = "\(max(30, min(86_400, requestedSeconds)))"
        scriptEnv["XTERMINAL_GRANT_TOKEN_CAP"] = "\(max(0, min(5000, requestedTokenCap)))"
        scriptEnv["XTERMINAL_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_GRANT_WAIT_SEC"] = "10"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runGrantScript() -> StepOutput {
            do {
                let script = remoteNetworkGrantScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 28.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runGrantScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runGrantScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteNetworkGrantScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_paid_grant_failed")
            return HubRemoteGrantResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                expiresAtSec: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemoteGrantDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "queued":
                return .queued
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .queued)
        let rawReasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
        let reasonCode = rawReasonCode.map {
            normalizedRemoteReasonCode(
                rawReason: $0,
                stepOutput: step.output,
                fallback: "remote_paid_grant_failed"
            )
        } ?? (ok ? nil : normalizedRemoteReasonCode(
            rawReason: nil,
            stepOutput: step.output,
            fallback: "remote_paid_grant_failed"
        ))

        let expiresAtSec: Double? = {
            guard let ms = decoded.expiresAtMs, ms > 0 else { return nil }
            return ms / 1000.0
        }()

        return HubRemoteGrantResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId),
            expiresAtSec: expiresAtSec,
            reasonCode: reasonCode,
            logLines: logs
        )
    }

    func requestRemoteWebFetch(
        options rawOptions: HubRemoteConnectOptions,
        url: String,
        timeoutSec: Double,
        maxBytes: Int
    ) -> HubRemoteWebFetchResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let requestURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestURL.isEmpty else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "empty_url",
                reasonCode: "empty_url",
                logLines: ["empty url for web fetch"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "hub_env_missing",
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "client_kit_missing",
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: "",
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: "node_missing",
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote web fetch"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_FETCH_URL"] = requestURL
        scriptEnv["XTERMINAL_FETCH_TIMEOUT_SEC"] = String(max(2.0, min(60.0, timeoutSec)))
        scriptEnv["XTERMINAL_FETCH_MAX_BYTES"] = String(max(1024, min(5_000_000, maxBytes)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runFetchScript() -> StepOutput {
            do {
                let script = remoteWebFetchScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: max(8.0, min(90.0, timeoutSec + 20.0)),
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runFetchScript()
        appendStepLogs(into: &logs, step: step)

        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(
                args: ["install-client"],
                options: opts,
                env: [:],
                timeoutSec: 120.0
            )
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runFetchScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteWebFetchScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_web_fetch_failed")
            return HubRemoteWebFetchResult(
                ok: false,
                status: 0,
                finalURL: requestURL,
                contentType: "",
                truncated: false,
                bytes: 0,
                text: "",
                errorMessage: fallback,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (decoded.ok == true ? nil : "remote_web_fetch_failed")
        let message = nonEmpty(decoded.errorMessage)
            ?? nonEmpty(decoded.reason)

        return HubRemoteWebFetchResult(
            ok: decoded.ok ?? false,
            status: decoded.status ?? 0,
            finalURL: nonEmpty(decoded.finalURL) ?? requestURL,
            contentType: nonEmpty(decoded.contentType) ?? "",
            truncated: decoded.truncated ?? false,
            bytes: decoded.bytes ?? 0,
            text: decoded.text ?? "",
            errorMessage: message,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func syncRemoteProjectSnapshot(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteProjectSyncPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let pid = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "project_id_empty", logLines: ["project_id is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote project sync"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SYNC_PROJECT_ID"] = pid
        scriptEnv["XTERMINAL_SYNC_ROOT_PATH"] = payload.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SYNC_DISPLAY_NAME"] = payload.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SYNC_STATUS_DIGEST"] = payload.statusDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SYNC_LAST_SUMMARY_AT"] = payload.lastSummaryAt.map { String($0) } ?? ""
        scriptEnv["XTERMINAL_SYNC_LAST_EVENT_AT"] = payload.lastEventAt.map { String($0) } ?? ""
        scriptEnv["XTERMINAL_SYNC_UPDATED_AT"] = payload.updatedAt.map { String($0) } ?? String(Date().timeIntervalSince1970)

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteProjectSyncScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_project_sync_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_project_sync_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func appendRemoteProjectConversationTurn(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteProjectConversationPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let pid = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadKey = payload.threadKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestId = payload.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = payload.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantText = payload.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = payload.messages.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !pid.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "project_id_empty", logLines: ["conversation project_id is empty"])
        }
        guard !threadKey.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "thread_key_empty", logLines: ["conversation thread_key is empty"])
        }
        guard !requestId.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "request_id_empty", logLines: ["conversation request_id is empty"])
        }
        guard !messages.isEmpty || !userText.isEmpty || !assistantText.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "turn_empty", logLines: ["conversation turn payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote project conversation append"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_CONV_PROJECT_ID"] = pid
        scriptEnv["XTERMINAL_CONV_THREAD_KEY"] = threadKey
        scriptEnv["XTERMINAL_CONV_REQUEST_ID"] = requestId
        scriptEnv["XTERMINAL_CONV_CREATED_AT_MS"] = String(max(Int64(0), payload.createdAtMs))
        scriptEnv["XTERMINAL_CONV_USER_TEXT"] = userText
        scriptEnv["XTERMINAL_CONV_ASSISTANT_TEXT"] = assistantText
        if let data = try? JSONEncoder().encode(messages),
           let json = String(data: data, encoding: .utf8) {
            scriptEnv["XTERMINAL_CONV_MESSAGES_JSON"] = json
        } else {
            scriptEnv["XTERMINAL_CONV_MESSAGES_JSON"] = "[]"
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteProjectConversationAppendScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_project_conversation_append_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_project_conversation_append_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func appendRemoteSupervisorConversationTurn(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteSupervisorConversationPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let threadKey = payload.threadKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestId = payload.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = payload.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantText = payload.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadKey.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "thread_key_empty", logLines: ["conversation thread_key is empty"])
        }
        guard !requestId.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "request_id_empty", logLines: ["conversation request_id is empty"])
        }
        guard !userText.isEmpty || !assistantText.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "turn_empty", logLines: ["conversation turn payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote supervisor conversation append"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_THREAD_KEY"] = threadKey
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_REQUEST_ID"] = requestId
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_CREATED_AT_MS"] = String(max(Int64(0), payload.createdAtMs))
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_USER_TEXT"] = userText
        scriptEnv["XTERMINAL_SUPERVISOR_CONV_ASSISTANT_TEXT"] = assistantText

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = self.remoteSupervisorConversationAppendScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_conversation_append_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_supervisor_conversation_append_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func upsertRemoteProjectCanonicalMemory(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteProjectCanonicalMemoryPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let projectId = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectId.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "project_id_empty", logLines: ["canonical memory project_id is empty"])
        }

        let items = payload.items.compactMap { raw -> HubRemoteCanonicalMemoryItem? in
            let key = raw.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = raw.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return HubRemoteCanonicalMemoryItem(key: key, value: value)
        }
        guard !items.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "canonical_memory_items_empty", logLines: ["canonical memory payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        guard let itemsData = try? JSONEncoder().encode(items) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "canonical_memory_encode_failed", logLines: ["failed to encode canonical memory items"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote project canonical memory upsert"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PROJECT_MEMORY_PROJECT_ID"] = projectId
        scriptEnv["XTERMINAL_PROJECT_MEMORY_ITEMS_B64"] = itemsData.base64EncodedString()
        scriptEnv["XTERMINAL_PROJECT_MEMORY_REQUEST_ID"] = "project_canonical_memory_\(UUID().uuidString.lowercased())"
        scriptEnv["XTERMINAL_PROJECT_MEMORY_AUDIT_REF"] = "audit-memory-canonical-upsert-\(projectId)-\(Int(Date().timeIntervalSince1970 * 1000.0))"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteProjectCanonicalMemoryUpsertScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_project_canonical_memory_upsert_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_project_canonical_memory_upsert_failed")
        let auditRefs = orderedUniqueNonEmptyStrings([decoded.auditRef] + (decoded.auditRefs ?? []))
        let evidenceRefs = orderedUniqueNonEmptyStrings([decoded.evidenceRef] + (decoded.evidenceRefs ?? []))
        let writebackRefs = orderedUniqueNonEmptyStrings([decoded.writebackRef] + (decoded.writebackRefs ?? []))

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            auditRefs: auditRefs,
            evidenceRefs: evidenceRefs,
            writebackRefs: writebackRefs,
            updatedAtMs: decoded.updatedAtMs,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func upsertRemoteDeviceCanonicalMemory(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteDeviceCanonicalMemoryPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let items = payload.items.compactMap { raw -> HubRemoteCanonicalMemoryItem? in
            let key = raw.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = raw.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return HubRemoteCanonicalMemoryItem(key: key, value: value)
        }
        guard !items.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "device_canonical_memory_items_empty", logLines: ["device canonical memory payload is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        guard let itemsData = try? JSONEncoder().encode(items) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "device_canonical_memory_encode_failed", logLines: ["failed to encode device canonical memory items"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote device canonical memory upsert"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_DEVICE_MEMORY_ITEMS_B64"] = itemsData.base64EncodedString()
        scriptEnv["XTERMINAL_DEVICE_MEMORY_REQUEST_ID"] = "device_canonical_memory_\(UUID().uuidString.lowercased())"
        scriptEnv["XTERMINAL_DEVICE_MEMORY_AUDIT_REF"] = "audit-memory-canonical-upsert-device-\(Int(Date().timeIntervalSince1970 * 1000.0))"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteDeviceCanonicalMemoryUpsertScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_device_canonical_memory_upsert_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_device_canonical_memory_upsert_failed")
        let auditRefs = orderedUniqueNonEmptyStrings([decoded.auditRef] + (decoded.auditRefs ?? []))
        let evidenceRefs = orderedUniqueNonEmptyStrings([decoded.evidenceRef] + (decoded.evidenceRefs ?? []))
        let writebackRefs = orderedUniqueNonEmptyStrings([decoded.writebackRef] + (decoded.writebackRefs ?? []))

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            auditRefs: auditRefs,
            evidenceRefs: evidenceRefs,
            writebackRefs: writebackRefs,
            updatedAtMs: decoded.updatedAtMs,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func pushRemoteNotificationMemory(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubRemoteNotificationPayload
    ) -> HubRemoteMutationResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return HubRemoteMutationResult(ok: false, reasonCode: "title_empty", logLines: ["notification title is empty"])
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "hub_env_missing", logLines: ["missing hub env: \(hubEnv.path)"])
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMutationResult(ok: false, reasonCode: "client_kit_missing", logLines: ["missing client kit src: \(clientKitSrc.path)"])
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMutationResult(ok: false, reasonCode: "node_missing", logLines: ["missing node runtime for remote notification"])
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_NOTIFY_SOURCE"] = payload.source.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_NOTIFY_TITLE"] = title
        scriptEnv["XTERMINAL_NOTIFY_BODY"] = payload.body.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_NOTIFY_DEDUPE"] = payload.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_NOTIFY_ACTION_URL"] = payload.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_NOTIFY_UNREAD"] = payload.unread ? "1" : "0"

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteNotificationScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 20.0,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if step.exitCode != 0, shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMutationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_notification_failed")
            return HubRemoteMutationResult(ok: false, reasonCode: fallback, logLines: logs)
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_notification_failed")

        return HubRemoteMutationResult(
            ok: decoded.ok ?? false,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }
}
