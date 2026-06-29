import Foundation

extension HubPairingCoordinator {
    func fetchRemoteMemorySnapshot(
        options rawOptions: HubRemoteConnectOptions,
        mode rawMode: String,
        projectId: String?,
        canonicalLimit: Int = 24,
        workingLimit: Int = 12,
        timeoutSec: Double = 1.2,
        allowClientKitInstallRetry: Bool = false
    ) -> HubRemoteMemorySnapshotResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let scriptTimeoutSec = normalizedRemoteAuxTimeoutSec(timeoutSec)
        let mode = rawMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedMode = mode.isEmpty ? "project" : mode

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote memory snapshot"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_MEM_MODE"] = normalizedMode
        scriptEnv["XTERMINAL_MEM_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_MEM_CANONICAL_LIMIT"] = String(max(1, min(80, canonicalLimit)))
        scriptEnv["XTERMINAL_MEM_WORKING_LIMIT"] = String(max(1, min(80, workingLimit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteMemorySnapshotScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: scriptTimeoutSec,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if allowClientKitInstallRetry,
           step.exitCode != 0,
           shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMemorySnapshotScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_memory_snapshot_failed")
            return HubRemoteMemorySnapshotResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                canonicalEntries: [],
                workingEntries: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_memory_snapshot_failed")

        return HubRemoteMemorySnapshotResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            canonicalEntries: decoded.canonicalEntries ?? [],
            workingEntries: decoded.workingEntries ?? [],
            roleTurnMessages: decoded.roleTurnMessages ?? [],
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteMemoryRetrieval(
        options rawOptions: HubRemoteConnectOptions,
        payload: HubIPCClient.MemoryRetrievalPayload,
        timeoutSec: Double = 1.0,
        allowClientKitInstallRetry: Bool = false
    ) -> HubRemoteMemoryRetrievalResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let scriptTimeoutSec = normalizedRemoteAuxTimeoutSec(timeoutSec)

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "hub_env_missing",
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "client_kit_missing",
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: "node_missing",
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: ["missing node runtime for remote memory retrieval"]
            )
        }

        let encodeJSON: ([String]) -> String = { values in
            guard let data = try? JSONEncoder().encode(values),
                  let text = String(data: data, encoding: .utf8) else {
                return "[]"
            }
            return text
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_MEM_RETR_SCHEMA_VERSION"] = payload.schemaVersion
        scriptEnv["XTERMINAL_MEM_RETR_REQUEST_ID"] = payload.requestId
        scriptEnv["XTERMINAL_MEM_RETR_SCOPE"] = payload.scope
        scriptEnv["XTERMINAL_MEM_RETR_REQUESTER_ROLE"] = payload.requesterRole
        scriptEnv["XTERMINAL_MEM_RETR_MODE"] = payload.mode
        scriptEnv["XTERMINAL_MEM_RETR_PROJECT_ID"] = payload.projectId ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_CROSS_PROJECT_TARGET_IDS_JSON"] = encodeJSON(payload.crossProjectTargetIds)
        scriptEnv["XTERMINAL_MEM_RETR_PROJECT_ROOT"] = payload.projectRoot ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_DISPLAY_NAME"] = payload.displayName ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_QUERY"] = payload.query
        scriptEnv["XTERMINAL_MEM_RETR_LATEST_USER"] = payload.latestUser
        scriptEnv["XTERMINAL_MEM_RETR_ALLOWED_LAYERS_JSON"] = encodeJSON(payload.allowedLayers)
        scriptEnv["XTERMINAL_MEM_RETR_RETRIEVAL_KIND"] = payload.retrievalKind
        scriptEnv["XTERMINAL_MEM_RETR_MAX_RESULTS"] = String(max(1, payload.maxResults))
        scriptEnv["XTERMINAL_MEM_RETR_REASON"] = payload.reason ?? ""
        scriptEnv["XTERMINAL_MEM_RETR_REQUIRE_EXPLAINABILITY"] = payload.requireExplainability ? "1" : "0"
        scriptEnv["XTERMINAL_MEM_RETR_REQUESTED_KINDS_JSON"] = encodeJSON(payload.requestedKinds)
        scriptEnv["XTERMINAL_MEM_RETR_EXPLICIT_REFS_JSON"] = encodeJSON(payload.explicitRefs)
        scriptEnv["XTERMINAL_MEM_RETR_MAX_SNIPPETS"] = String(max(1, payload.maxSnippets))
        scriptEnv["XTERMINAL_MEM_RETR_MAX_SNIPPET_CHARS"] = String(max(120, payload.maxSnippetChars))
        scriptEnv["XTERMINAL_MEM_RETR_AUDIT_REF"] = payload.auditRef

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteMemoryRetrievalScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: scriptTimeoutSec,
                    env: scriptEnv
                )
                return StepOutput(exitCode: result.exitCode, output: result.combined, command: command)
            } catch {
                return StepOutput(exitCode: 127, output: String(describing: error), command: command)
            }
        }

        var step = runScript()
        appendStepLogs(into: &logs, step: step)
        if allowClientKitInstallRetry,
           step.exitCode != 0,
           shouldRetryAfterClientKitInstall(step.output) {
            let install = runAxhubctl(args: ["install-client"], options: opts, env: [:], timeoutSec: 120.0)
            appendStepLogs(into: &logs, step: install)
            if install.exitCode == 0 {
                step = runScript()
                appendStepLogs(into: &logs, step: step)
            }
        }

        guard let jsonLine = extractTrailingJSONObjectLine(step.output),
              let data = jsonLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RemoteMemoryRetrievalScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_memory_retrieval_failed")
            return HubRemoteMemoryRetrievalResult(
                ok: false,
                schemaVersion: nil,
                requestId: payload.requestId,
                status: nil,
                resolvedScope: nil,
                source: "hub_memory_retrieval_grpc_v1",
                scope: payload.scope,
                auditRef: payload.auditRef,
                reasonCode: fallback,
                denyCode: nil,
                results: [],
                truncated: false,
                budgetUsedChars: 0,
                truncatedItems: 0,
                redactedItems: 0,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reasonCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_memory_retrieval_failed")

        return HubRemoteMemoryRetrievalResult(
            ok: decoded.ok ?? false,
            schemaVersion: nonEmpty(decoded.schemaVersion),
            requestId: nonEmpty(decoded.requestId) ?? payload.requestId,
            status: nonEmpty(decoded.status),
            resolvedScope: nonEmpty(decoded.resolvedScope),
            source: nonEmpty(decoded.source) ?? "hub_memory_retrieval_grpc_v1",
            scope: nonEmpty(decoded.scope) ?? payload.scope,
            auditRef: nonEmpty(decoded.auditRef) ?? payload.auditRef,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            denyCode: nonEmpty(decoded.denyCode),
            results: (decoded.results ?? []).map { item in
                HubRemoteMemoryRetrievalItem(
                    ref: nonEmpty(item.ref) ?? "",
                    sourceKind: nonEmpty(item.sourceKind) ?? "memory_doc",
                    summary: nonEmpty(item.summary) ?? "",
                    snippet: nonEmpty(item.snippet) ?? "",
                    score: min(1.0, max(0.0, item.score ?? 0)),
                    redacted: item.redacted ?? false
                )
            },
            truncated: decoded.truncated ?? false,
            budgetUsedChars: max(0, decoded.budgetUsedChars ?? 0),
            truncatedItems: max(0, decoded.truncatedItems ?? 0),
            redactedItems: max(0, decoded.redactedItems ?? 0),
            logLines: logs
        )
    }

    func fetchRemoteSchedulerStatus(
        options rawOptions: HubRemoteConnectOptions,
        includeQueueItems: Bool,
        queueItemsLimit: Int
    ) -> HubRemoteSchedulerStatusResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote scheduler status"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SCHED_INCLUDE_QUEUE_ITEMS"] = includeQueueItems ? "1" : "0"
        scriptEnv["XTERMINAL_SCHED_QUEUE_ITEMS_LIMIT"] = String(max(1, min(500, queueItemsLimit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSchedulerStatusScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSchedulerStatusScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_scheduler_status_failed")
            return HubRemoteSchedulerStatusResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                inFlightTotal: 0,
                queueDepth: 0,
                oldestQueuedMs: 0,
                inFlightByScope: [],
                queuedByScope: [],
                queueItems: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_scheduler_status_failed")

        let inFlightByScope: [HubRemoteSchedulerScopeCount] = (decoded.inFlightByScope ?? []).compactMap { row in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return HubRemoteSchedulerScopeCount(
                scopeKey: key,
                count: max(0, row.inFlight ?? 0)
            )
        }

        let queuedByScope: [HubRemoteSchedulerScopeCount] = (decoded.queuedByScope ?? []).compactMap { row in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return HubRemoteSchedulerScopeCount(
                scopeKey: key,
                count: max(0, row.queued ?? 0)
            )
        }

        let queueItems: [HubRemoteSchedulerQueueItem] = (decoded.queueItems ?? []).compactMap { row in
            let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let scopeKey = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestId.isEmpty, !scopeKey.isEmpty else { return nil }
            return HubRemoteSchedulerQueueItem(
                requestId: requestId,
                scopeKey: scopeKey,
                enqueuedAtMs: max(0, row.enqueuedAtMs ?? 0),
                queuedMs: max(0, row.queuedMs ?? 0)
            )
        }

        return HubRemoteSchedulerStatusResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            inFlightTotal: max(0, decoded.inFlightTotal ?? 0),
            queueDepth: max(0, decoded.queueDepth ?? 0),
            oldestQueuedMs: max(0, decoded.oldestQueuedMs ?? 0),
            inFlightByScope: inFlightByScope,
            queuedByScope: queuedByScope,
            queueItems: queueItems,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSupervisorBriefProjection(
        options rawOptions: HubRemoteConnectOptions,
        requestId: String,
        projectId: String,
        runId: String?,
        missionId: String?,
        projectionKind: String,
        trigger: String,
        includeTtsScript: Bool,
        includeCardSummary: Bool,
        maxEvidenceRefs: Int
    ) -> HubRemoteSupervisorBriefProjectionResult {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "request_id_empty",
                logLines: ["supervisor brief projection missing request_id"]
            )
        }
        guard !normalizedProjectId.isEmpty else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "project_id_empty",
                logLines: ["supervisor brief projection missing project_id"]
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
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote supervisor brief projection"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_REQUEST_ID"] = normalizedRequestId
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_PROJECT_ID"] = normalizedProjectId
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_RUN_ID"] = runId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_MISSION_ID"] = missionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_KIND"] = projectionKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "progress_brief"
            : projectionKind.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_TRIGGER"] = trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "daily_digest"
            : trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_TTS"] = includeTtsScript ? "1" : "0"
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_INCLUDE_CARD_SUMMARY"] = includeCardSummary ? "1" : "0"
        scriptEnv["XTERMINAL_SUPERVISOR_BRIEF_MAX_EVIDENCE_REFS"] = String(max(0, min(12, maxEvidenceRefs)))
        scriptEnv["HUB_PROJECT_ID"] = normalizedProjectId

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSupervisorBriefProjectionScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSupervisorBriefProjectionScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_brief_projection_failed")
            return HubRemoteSupervisorBriefProjectionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                projection: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let projection: HubRemoteSupervisorBriefProjection? = {
            guard let row = decoded.projection else { return nil }
            let projectionId = row.projectionId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectionId.isEmpty else { return nil }
            return HubRemoteSupervisorBriefProjection(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "xhub.supervisor_brief_projection.v1"
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                projectionId: projectionId,
                projectionKind: row.projectionKind.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                runId: row.runId.trimmingCharacters(in: .whitespacesAndNewlines),
                missionId: row.missionId.trimmingCharacters(in: .whitespacesAndNewlines),
                trigger: row.trigger.trimmingCharacters(in: .whitespacesAndNewlines),
                status: row.status.trimmingCharacters(in: .whitespacesAndNewlines),
                criticalBlocker: row.criticalBlocker.trimmingCharacters(in: .whitespacesAndNewlines),
                topline: row.topline.trimmingCharacters(in: .whitespacesAndNewlines),
                nextBestAction: row.nextBestAction.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingGrantCount: max(0, row.pendingGrantCount ?? 0),
                ttsScript: (row.ttsScript ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                cardSummary: row.cardSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                evidenceRefs: (row.evidenceRefs ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                generatedAtMs: max(0, row.generatedAtMs ?? 0),
                expiresAtMs: max(0, row.expiresAtMs ?? 0),
                auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }()

        let ok = (decoded.ok ?? (projection != nil)) && projection != nil
        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_supervisor_brief_projection_failed")

        return HubRemoteSupervisorBriefProjectionResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_supervisor_grpc",
            projection: projection,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSupervisorRouteDecision(
        options rawOptions: HubRemoteConnectOptions,
        requestId: String,
        projectId: String,
        runId: String?,
        missionId: String?,
        surfaceType: String,
        trustLevel: String,
        normalizedIntentType: String,
        preferredDeviceId: String?,
        requireXT: Bool,
        requireRunner: Bool,
        actorRef: String?,
        conversationId: String?,
        threadKey: String?
    ) -> HubRemoteSupervisorRouteDecisionResult {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return HubRemoteSupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "request_id_empty",
                logLines: ["supervisor route decision missing request_id"]
            )
        }
        guard !normalizedProjectId.isEmpty else {
            return HubRemoteSupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "project_id_empty",
                logLines: ["supervisor route decision missing project_id"]
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
            return HubRemoteSupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote supervisor route decision"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_REQUEST_ID"] = normalizedRequestId
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_PROJECT_ID"] = normalizedProjectId
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_RUN_ID"] = runId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_MISSION_ID"] = missionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_SURFACE_TYPE"] = surfaceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "xt_ui"
            : surfaceType.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_TRUST_LEVEL"] = trustLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "paired_surface"
            : trustLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_INTENT_TYPE"] = normalizedIntentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "directive"
            : normalizedIntentType.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_PREFERRED_DEVICE_ID"] = preferredDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_REQUIRE_XT"] = requireXT ? "1" : "0"
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_REQUIRE_RUNNER"] = requireRunner ? "1" : "0"
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_ACTOR_REF"] = actorRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_CONVERSATION_ID"] = conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_ROUTE_THREAD_KEY"] = threadKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["HUB_PROJECT_ID"] = normalizedProjectId

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSupervisorRouteDecisionScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSupervisorRouteDecisionScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_route_decision_failed")
            return HubRemoteSupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: nil,
                governanceRuntimeReadiness: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let route: HubRemoteSupervisorRouteDecision? = {
            guard let row = decoded.route else { return nil }
            let routeId = row.routeId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !routeId.isEmpty else { return nil }
            return HubRemoteSupervisorRouteDecision(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "xhub.supervisor_route_decision.v1"
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                routeId: routeId,
                requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                runId: row.runId.trimmingCharacters(in: .whitespacesAndNewlines),
                missionId: row.missionId.trimmingCharacters(in: .whitespacesAndNewlines),
                decision: row.decision.trimmingCharacters(in: .whitespacesAndNewlines),
                riskTier: row.riskTier.trimmingCharacters(in: .whitespacesAndNewlines),
                preferredDeviceId: row.preferredDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                resolvedDeviceId: row.resolvedDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                runnerId: row.runnerId.trimmingCharacters(in: .whitespacesAndNewlines),
                xtOnline: row.xtOnline ?? false,
                runnerRequired: row.runnerRequired ?? false,
                sameProjectScope: row.sameProjectScope ?? false,
                requiresGrant: row.requiresGrant ?? false,
                grantScope: row.grantScope.trimmingCharacters(in: .whitespacesAndNewlines),
                denyCode: row.denyCode.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAtMs: max(0, row.updatedAtMs ?? 0),
                auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }()

        let readiness: HubRemoteSupervisorRouteGovernanceRuntimeReadiness? = {
            guard let row = decoded.governanceRuntimeReadiness else { return nil }
            let state = AXProjectGovernanceRuntimeReadinessState(
                rawValue: row.state.trimmingCharacters(in: .whitespacesAndNewlines)
            ) ?? .blocked
            let blockedComponentKeys = (row.blockedComponentKeys ?? []).compactMap {
                AXProjectGovernanceRuntimeReadinessComponentKey(
                    rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            let components = (row.components ?? []).compactMap { component -> HubRemoteSupervisorRouteGovernanceComponent? in
                guard let key = AXProjectGovernanceRuntimeReadinessComponentKey(
                    rawValue: component.key.trimmingCharacters(in: .whitespacesAndNewlines)
                ) else {
                    return nil
                }
                let componentState = AXProjectGovernanceRuntimeReadinessComponentState(
                    rawValue: component.state.trimmingCharacters(in: .whitespacesAndNewlines)
                ) ?? .notReported
                return HubRemoteSupervisorRouteGovernanceComponent(
                    key: key,
                    state: componentState,
                    denyCode: component.denyCode.trimmingCharacters(in: .whitespacesAndNewlines),
                    summaryLine: component.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines),
                    missingReasonCodes: (component.missingReasonCodes ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
            return HubRemoteSupervisorRouteGovernanceRuntimeReadiness(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "xhub.governance_runtime_readiness.v1"
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                source: row.source.trimmingCharacters(in: .whitespacesAndNewlines),
                governanceSurface: row.governanceSurface.trimmingCharacters(in: .whitespacesAndNewlines),
                context: row.context.trimmingCharacters(in: .whitespacesAndNewlines),
                configured: row.configured ?? false,
                state: state,
                runtimeReady: row.runtimeReady ?? false,
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                blockers: (row.blockers ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                blockedComponentKeys: blockedComponentKeys,
                missingReasonCodes: (row.missingReasonCodes ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                summaryLine: row.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines),
                missingSummaryLine: row.missingSummaryLine.trimmingCharacters(in: .whitespacesAndNewlines),
                components: components
            )
        }()

        let ok = (decoded.ok ?? (route != nil)) && route != nil
        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_supervisor_route_decision_failed")

        return HubRemoteSupervisorRouteDecisionResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_supervisor_grpc",
            route: route,
            governanceRuntimeReadiness: readiness,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemotePendingGrantRequests(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemotePendingGrantRequestsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote pending grants"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PENDING_GRANTS_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANTS_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remotePendingGrantRequestsScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemotePendingGrantRequestsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_pending_grants_failed")
            return HubRemotePendingGrantRequestsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_pending_grants_failed")

        let items: [HubRemotePendingGrantItem] = (decoded.items ?? []).compactMap { row in
            let grantRequestId = row.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grantRequestId.isEmpty else { return nil }
            return HubRemotePendingGrantItem(
                grantRequestId: grantRequestId,
                requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceId: row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                userId: row.userId.trimmingCharacters(in: .whitespacesAndNewlines),
                appId: row.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                capability: row.capability.trimmingCharacters(in: .whitespacesAndNewlines),
                modelId: row.modelId.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                requestedTtlSec: max(0, row.requestedTtlSec ?? 0),
                requestedTokenCap: max(0, row.requestedTokenCap ?? 0),
                status: row.status.trimmingCharacters(in: .whitespacesAndNewlines),
                decision: row.decision.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                decidedAtMs: max(0, row.decidedAtMs ?? 0)
            )
        }

        return HubRemotePendingGrantRequestsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSupervisorCandidateReviewQueue(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemoteSupervisorCandidateReviewQueueResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote supervisor candidate review queue"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = self.remoteSupervisorCandidateReviewQueueScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewQueueScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_candidate_review_queue_failed")
            return HubRemoteSupervisorCandidateReviewQueueResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_supervisor_candidate_review_queue_failed")

        let items: [HubRemoteSupervisorCandidateReviewQueueItem] = (decoded.items ?? []).compactMap { row in
            let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestId.isEmpty else { return nil }
            return HubRemoteSupervisorCandidateReviewQueueItem(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewId: row.reviewId.trimmingCharacters(in: .whitespacesAndNewlines),
                requestId: requestId,
                evidenceRef: row.evidenceRef.trimmingCharacters(in: .whitespacesAndNewlines),
                reviewState: row.reviewState.trimmingCharacters(in: .whitespacesAndNewlines),
                durablePromotionState: row.durablePromotionState.trimmingCharacters(in: .whitespacesAndNewlines),
                promotionBoundary: row.promotionBoundary.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceId: row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                userId: row.userId.trimmingCharacters(in: .whitespacesAndNewlines),
                appId: row.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadId: row.threadId.trimmingCharacters(in: .whitespacesAndNewlines),
                threadKey: row.threadKey.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectIds: row.projectIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                scopes: row.scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                recordTypes: row.recordTypes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                auditRefs: row.auditRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                idempotencyKeys: row.idempotencyKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                candidateCount: max(0, row.candidateCount ?? 0),
                summaryLine: row.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines),
                mirrorTarget: row.mirrorTarget.trimmingCharacters(in: .whitespacesAndNewlines),
                localStoreRole: row.localStoreRole.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierKind: row.carrierKind.trimmingCharacters(in: .whitespacesAndNewlines),
                carrierSchemaVersion: row.carrierSchemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeId: row.pendingChangeId.trimmingCharacters(in: .whitespacesAndNewlines),
                pendingChangeStatus: row.pendingChangeStatus.trimmingCharacters(in: .whitespacesAndNewlines),
                editSessionId: row.editSessionId.trimmingCharacters(in: .whitespacesAndNewlines),
                docId: row.docId.trimmingCharacters(in: .whitespacesAndNewlines),
                writebackRef: row.writebackRef.trimmingCharacters(in: .whitespacesAndNewlines),
                stageCreatedAtMs: max(0, row.stageCreatedAtMs ?? 0),
                stageUpdatedAtMs: max(0, row.stageUpdatedAtMs ?? 0),
                latestEmittedAtMs: max(0, row.latestEmittedAtMs ?? 0),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }

        return HubRemoteSupervisorCandidateReviewQueueResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteConnectorIngressReceipts(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemoteConnectorIngressReceiptsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote connector ingress receipts"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_CONNECTOR_INGRESS_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_CONNECTOR_INGRESS_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteConnectorIngressReceiptsScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemoteConnectorIngressReceiptsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_connector_ingress_receipts_failed")
            return HubRemoteConnectorIngressReceiptsResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_connector_ingress_receipts_failed")

        let items: [HubRemoteConnectorIngressReceipt] = (decoded.items ?? []).compactMap { row in
            let receiptId = row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !receiptId.isEmpty else { return nil }
            return HubRemoteConnectorIngressReceipt(
                receiptId: receiptId,
                requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                connector: row.connector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                targetId: row.targetId.trimmingCharacters(in: .whitespacesAndNewlines),
                ingressType: row.ingressType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                channelScope: row.channelScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                sourceId: row.sourceId.trimmingCharacters(in: .whitespacesAndNewlines),
                messageId: row.messageId.trimmingCharacters(in: .whitespacesAndNewlines),
                dedupeKey: row.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                receivedAtMs: max(0, row.receivedAtMs ?? 0),
                eventSequence: Swift.max(Int64(0), row.eventSequence ?? 0),
                deliveryState: row.deliveryState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                runtimeState: row.runtimeState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }

        return HubRemoteConnectorIngressReceiptsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteRuntimeSurfaceOverrides(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int,
        timeoutSec: Double = 1.0
    ) -> HubRemoteRuntimeSurfaceOverridesResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let scriptTimeoutSec = normalizedRemoteAuxTimeoutSec(timeoutSec)

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote runtime surface overrides"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_RUNTIME_SURFACE_OVERRIDE_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_RUNTIME_SURFACE_OVERRIDE_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteRuntimeSurfaceOverridesScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: scriptTimeoutSec,
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
              let decoded = try? JSONDecoder().decode(RemoteRuntimeSurfaceOverridesScriptResult.self, from: data) else {
            let fallback = inferFailureCode(
                from: step.output,
                fallback: HubRemoteRuntimeSurfaceCompatContract.failureReasonCode
            )
            return HubRemoteRuntimeSurfaceOverridesResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : HubRemoteRuntimeSurfaceCompatContract.failureReasonCode)

        let items: [HubRemoteRuntimeSurfaceOverrideItem] = (decoded.items ?? []).compactMap { row in
            let projectId = row.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawMode = row.overrideMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !projectId.isEmpty,
                  let overrideMode = AXProjectRuntimeSurfaceHubOverrideMode(rawValue: rawMode) else {
                return nil
            }
            return HubRemoteRuntimeSurfaceOverrideItem(
                projectId: projectId,
                overrideMode: overrideMode,
                updatedAtMs: max(0, row.updatedAtMs ?? 0),
                reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return HubRemoteRuntimeSurfaceOverridesResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    @available(*, deprecated, message: "Use fetchRemoteRuntimeSurfaceOverrides(options:projectId:limit:)")
    func fetchRemoteAutonomyPolicyOverrides(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?,
        limit: Int
    ) -> HubRemoteAutonomyPolicyOverridesResult {
        fetchRemoteRuntimeSurfaceOverrides(
            options: rawOptions,
            projectId: projectId,
            limit: limit
        )
    }

    func approveRemotePendingGrantRequest(
        options rawOptions: HubRemoteConnectOptions,
        grantRequestId: String,
        projectId: String?,
        ttlSec: Int?,
        tokenCap: Int?,
        note: String?
    ) -> HubRemotePendingGrantActionResult {
        performRemotePendingGrantAction(
            options: rawOptions,
            action: "approve",
            grantRequestId: grantRequestId,
            projectId: projectId,
            ttlSec: ttlSec,
            tokenCap: tokenCap,
            note: note,
            reason: nil
        )
    }

    func denyRemotePendingGrantRequest(
        options rawOptions: HubRemoteConnectOptions,
        grantRequestId: String,
        projectId: String?,
        reason: String?
    ) -> HubRemotePendingGrantActionResult {
        performRemotePendingGrantAction(
            options: rawOptions,
            action: "deny",
            grantRequestId: grantRequestId,
            projectId: projectId,
            ttlSec: nil,
            tokenCap: nil,
            note: nil,
            reason: reason
        )
    }

    func stageRemoteSupervisorCandidateReview(
        options rawOptions: HubRemoteConnectOptions,
        candidateRequestId: String,
        projectId: String?
    ) -> HubRemoteSupervisorCandidateReviewStageResult {
        let normalizedCandidateRequestId = candidateRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCandidateRequestId.isEmpty else {
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: nil,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "candidate_request_id_empty",
                logLines: ["stage supervisor candidate review missing candidate_request_id"]
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
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote supervisor candidate review stage"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_REQUEST_ID"] = normalizedCandidateRequestId
        scriptEnv["XTERMINAL_SUPERVISOR_CANDIDATE_REVIEW_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = self.remoteSupervisorCandidateReviewStageScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSupervisorCandidateReviewStageScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_supervisor_candidate_review_stage_failed")
            return HubRemoteSupervisorCandidateReviewStageResult(
                ok: false,
                staged: false,
                idempotent: false,
                source: "hub_memory_v1_grpc",
                reviewState: "",
                durablePromotionState: "",
                promotionBoundary: "",
                candidateRequestId: normalizedCandidateRequestId,
                evidenceRef: nil,
                editSessionId: nil,
                pendingChangeId: nil,
                docId: nil,
                baseVersion: nil,
                workingVersion: nil,
                sessionRevision: 0,
                status: nil,
                markdown: nil,
                createdAtMs: 0,
                updatedAtMs: 0,
                expiresAtMs: 0,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let staged = decoded.staged ?? false
        let idempotent = decoded.idempotent ?? false
        let ok = decoded.ok ?? (staged || idempotent)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_supervisor_candidate_review_stage_failed")

        return HubRemoteSupervisorCandidateReviewStageResult(
            ok: ok,
            staged: staged,
            idempotent: idempotent,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            reviewState: nonEmpty(decoded.reviewState) ?? "",
            durablePromotionState: nonEmpty(decoded.durablePromotionState) ?? "",
            promotionBoundary: nonEmpty(decoded.promotionBoundary) ?? "",
            candidateRequestId: nonEmpty(decoded.candidateRequestId) ?? normalizedCandidateRequestId,
            evidenceRef: nonEmpty(decoded.evidenceRef),
            editSessionId: nonEmpty(decoded.editSessionId),
            pendingChangeId: nonEmpty(decoded.pendingChangeId),
            docId: nonEmpty(decoded.docId),
            baseVersion: nonEmpty(decoded.baseVersion),
            workingVersion: nonEmpty(decoded.workingVersion),
            sessionRevision: Int64(decoded.sessionRevision ?? 0),
            status: nonEmpty(decoded.status),
            markdown: decoded.markdown,
            createdAtMs: max(0, decoded.createdAtMs ?? 0),
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            expiresAtMs: max(0, decoded.expiresAtMs ?? 0),
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func performRemotePendingGrantAction(
        options rawOptions: HubRemoteConnectOptions,
        action rawAction: String,
        grantRequestId: String,
        projectId: String?,
        ttlSec: Int?,
        tokenCap: Int?,
        note: String?,
        reason: String?
    ) -> HubRemotePendingGrantActionResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard action == "approve" || action == "deny" else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "invalid_action",
                logLines: ["invalid pending grant action: \(rawAction)"]
            )
        }

        let grantId = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty",
                logLines: ["pending grant action missing grant_request_id"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote pending grant action"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_PENDING_GRANT_ACTION"] = action
        scriptEnv["XTERMINAL_PENDING_GRANT_ID"] = grantId
        scriptEnv["XTERMINAL_PENDING_GRANT_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        scriptEnv["XTERMINAL_PENDING_GRANT_TTL_SEC"] = ttlSec.map { String(max(10, min(86_400, $0))) } ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_TOKEN_CAP"] = tokenCap.map { String(max(0, $0)) } ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_PENDING_GRANT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remotePendingGrantActionScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 12.0,
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
              let decoded = try? JSONDecoder().decode(RemotePendingGrantActionScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_pending_grant_action_failed")
            return HubRemotePendingGrantActionResult(
                ok: false,
                decision: .failed,
                grantRequestId: grantId,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let decisionToken = (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mappedDecision: HubRemotePendingGrantActionDecision = {
            switch decisionToken {
            case "approved":
                return .approved
            case "denied":
                return .denied
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision == .approved || mappedDecision == .denied)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_pending_grant_action_failed")

        return HubRemotePendingGrantActionResult(
            ok: ok,
            decision: mappedDecision,
            grantRequestId: nonEmpty(decoded.grantRequestId) ?? grantId,
            grantId: nonEmpty(decoded.grantId),
            expiresAtMs: decoded.expiresAtMs,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }


}
