import Foundation

extension HubPairingCoordinator {
    func fetchRemoteSecretVaultItems(
        options rawOptions: HubRemoteConnectOptions,
        scope: String?,
        namePrefix: String?,
        limit: Int
    ) -> HubRemoteSecretVaultItemsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
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
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault list"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_SCOPE"] = scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_NAME_PREFIX"] = namePrefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_LIMIT"] = String(max(1, min(500, limit)))

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultListScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultItemsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_list_failed")
            return HubRemoteSecretVaultItemsResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                updatedAtMs: 0,
                items: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_list_failed")

        let items = (decoded.items ?? []).compactMap { row -> HubRemoteSecretVaultItem? in
            let itemId = row.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            let itemScope = row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let itemName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemId.isEmpty, !itemScope.isEmpty, !itemName.isEmpty else { return nil }
            return HubRemoteSecretVaultItem(
                itemId: itemId,
                scope: itemScope,
                name: itemName,
                sensitivity: row.sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }

        return HubRemoteSecretVaultItemsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: items,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func createRemoteSecretVaultItem(
        options rawOptions: HubRemoteConnectOptions,
        scope: String,
        name: String,
        plaintext: String,
        sensitivity: String,
        projectId: String?,
        displayName: String?,
        reason: String?
    ) -> HubRemoteSecretVaultCreateResult {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPlaintext = plaintext.trimmingCharacters(in: .newlines)
        guard !normalizedScope.isEmpty, !normalizedName.isEmpty, !normalizedPlaintext.isEmpty else {
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "invalid_request",
                logLines: ["secret vault create missing scope/name/plaintext"]
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
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault create"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_SCOPE"] = normalizedScope
        scriptEnv["XTERMINAL_SECRET_VAULT_NAME"] = normalizedName
        scriptEnv["XTERMINAL_SECRET_VAULT_PLAINTEXT_B64"] = Data(normalizedPlaintext.utf8).base64EncodedString()
        scriptEnv["XTERMINAL_SECRET_VAULT_SENSITIVITY"] = sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        scriptEnv["XTERMINAL_SECRET_VAULT_DISPLAY_NAME"] = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_REASON"] = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultCreateScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultCreateScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_create_failed")
            return HubRemoteSecretVaultCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_create_failed")

        let item: HubRemoteSecretVaultItem? = {
            guard let row = decoded.item else { return nil }
            let itemId = row.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            let itemScope = row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let itemName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemId.isEmpty, !itemScope.isEmpty, !itemName.isEmpty else { return nil }
            return HubRemoteSecretVaultItem(
                itemId: itemId,
                scope: itemScope,
                name: itemName,
                sensitivity: row.sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                createdAtMs: max(0, row.createdAtMs ?? 0),
                updatedAtMs: max(0, row.updatedAtMs ?? 0)
            )
        }()

        let ok = (decoded.ok ?? (item != nil)) && item != nil

        return HubRemoteSecretVaultCreateResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            item: item,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func beginRemoteSecretVaultUse(
        options rawOptions: HubRemoteConnectOptions,
        itemId: String?,
        scope: String?,
        name: String?,
        projectId: String?,
        purpose: String,
        target: String?,
        ttlMs: Int
    ) -> HubRemoteSecretVaultUseResult {
        let normalizedItemId = itemId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScope = scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPurpose.isEmpty,
              (normalizedItemId?.isEmpty == false || ((normalizedScope?.isEmpty == false) && (normalizedName?.isEmpty == false))) else {
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "invalid_request",
                logLines: ["secret vault begin use missing item reference or purpose"]
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
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault use"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_ITEM_ID"] = normalizedItemId ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_SCOPE"] = normalizedScope ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_NAME"] = normalizedName ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_PURPOSE"] = normalizedPurpose
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_TARGET"] = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_TTL_MS"] = String(max(1_000, min(600_000, ttlMs)))
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultBeginUseScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultUseScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_use_failed")
            return HubRemoteSecretVaultUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: normalizedItemId,
                expiresAtMs: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_use_failed")

        let ok = decoded.ok ?? false
        return HubRemoteSecretVaultUseResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            leaseId: nonEmpty(decoded.leaseId),
            useToken: nonEmpty(decoded.useToken),
            itemId: nonEmpty(decoded.itemId) ?? normalizedItemId,
            expiresAtMs: decoded.expiresAtMs.map { max(0, $0) },
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func redeemRemoteSecretVaultUse(
        options rawOptions: HubRemoteConnectOptions,
        useToken: String,
        projectId: String?
    ) -> HubRemoteSecretVaultRedeemResult {
        let normalizedUseToken = useToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUseToken.isEmpty else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "invalid_request",
                logLines: ["secret vault redeem missing use token"]
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
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote secret vault redeem"]
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_secret_vault_redeem_\(UUID().uuidString)", isDirectory: false)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SECRET_VAULT_USE_TOKEN"] = normalizedUseToken
        scriptEnv["XTERMINAL_SECRET_VAULT_REDEEM_OUTPUT"] = outputURL.path
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSecretVaultRedeemScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteSecretVaultRedeemScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_secret_vault_redeem_failed")
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_secret_vault_redeem_failed")
        let ok = decoded.ok ?? false
        guard ok else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
                leaseId: nonEmpty(decoded.leaseId),
                itemId: nonEmpty(decoded.itemId),
                plaintext: nil,
                reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
                logLines: logs
            )
        }

        guard let plaintextData = try? Data(contentsOf: outputURL),
              let plaintext = String(data: plaintextData, encoding: .utf8),
              !plaintext.isEmpty else {
            return HubRemoteSecretVaultRedeemResult(
                ok: false,
                source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
                leaseId: nonEmpty(decoded.leaseId),
                itemId: nonEmpty(decoded.itemId),
                plaintext: nil,
                reasonCode: "secret_vault_plaintext_missing",
                logLines: logs
            )
        }

        return HubRemoteSecretVaultRedeemResult(
            ok: true,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            leaseId: nonEmpty(decoded.leaseId),
            itemId: nonEmpty(decoded.itemId),
            plaintext: plaintext,
            reasonCode: nil,
            logLines: logs
        )
    }

    func fetchRemoteVoiceWakeProfile(
        options rawOptions: HubRemoteConnectOptions,
        desiredWakeMode: VoiceWakeMode
    ) -> VoiceWakeProfileSyncResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"],
                syncedAtMs: nil
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"],
                syncedAtMs: nil
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice wake profile fetch"],
                syncedAtMs: nil
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_WAKE_DESIRED_MODE"] = desiredWakeMode.rawValue

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceWakeProfileGetScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteVoiceWakeProfileScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_wake_profile_fetch_failed")
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: fallback,
                logLines: logs,
                syncedAtMs: nil
            )
        }

        let profile: VoiceWakeProfile? = {
            guard let row = decoded.profile else { return nil }
            let sanitized = VoiceWakeProfile(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? VoiceWakeProfile.currentSchemaVersion
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                profileID: row.profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "default"
                    : row.profileID.trimmingCharacters(in: .whitespacesAndNewlines),
                triggerWords: row.triggerWords,
                updatedAtMs: max(0, Int64(row.updatedAtMs ?? 0)),
                scope: .pairedDeviceGroup,
                source: .hubPairingSync,
                wakeMode: desiredWakeMode,
                requiresPairingReady: row.requiresPairingReady ?? true,
                auditRef: nonEmpty(row.auditRef)
            ).sanitized()
            return sanitized.isValid ? sanitized : nil
        }()

        let ok = (decoded.ok ?? (profile != nil)) && profile != nil
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_wake_profile_fetch_failed")

        return VoiceWakeProfileSyncResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            profile: profile,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs,
            syncedAtMs: profile?.updatedAtMs
        )
    }

    func setRemoteVoiceWakeProfile(
        options rawOptions: HubRemoteConnectOptions,
        profile: VoiceWakeProfile
    ) -> VoiceWakeProfileSyncResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        guard let payloadData = try? JSONEncoder().encode(profile.sanitized()) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "voice_wake_profile_encode_failed",
                logLines: ["failed to encode voice wake profile payload"],
                syncedAtMs: nil
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"],
                syncedAtMs: nil
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"],
                syncedAtMs: nil
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice wake profile set"],
                syncedAtMs: nil
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_WAKE_PROFILE_JSON_B64"] = payloadData.base64EncodedString()

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceWakeProfileSetScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteVoiceWakeProfileScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_wake_profile_set_failed")
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: fallback,
                logLines: logs,
                syncedAtMs: nil
            )
        }

        let syncedProfile: VoiceWakeProfile? = {
            guard let row = decoded.profile else { return nil }
            let wakeMode = VoiceWakeMode(rawValue: row.wakeMode.trimmingCharacters(in: .whitespacesAndNewlines)) ?? profile.wakeMode
            let sanitized = VoiceWakeProfile(
                schemaVersion: row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? VoiceWakeProfile.currentSchemaVersion
                    : row.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines),
                profileID: row.profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "default"
                    : row.profileID.trimmingCharacters(in: .whitespacesAndNewlines),
                triggerWords: row.triggerWords,
                updatedAtMs: max(0, Int64(row.updatedAtMs ?? 0)),
                scope: .pairedDeviceGroup,
                source: .hubPairingSync,
                wakeMode: wakeMode,
                requiresPairingReady: row.requiresPairingReady ?? true,
                auditRef: nonEmpty(row.auditRef)
            ).sanitized()
            return sanitized.isValid ? sanitized : nil
        }()

        let ok = (decoded.ok ?? (syncedProfile != nil)) && syncedProfile != nil
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_wake_profile_set_failed")

        return VoiceWakeProfileSyncResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            profile: syncedProfile,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs,
            syncedAtMs: syncedProfile?.updatedAtMs
        )
    }

    func issueRemoteVoiceGrantChallenge(
        options rawOptions: HubRemoteConnectOptions,
        requestId: String,
        projectId: String?,
        templateId: String,
        actionDigest: String,
        scopeDigest: String,
        amountDigest: String?,
        challengeCode: String?,
        riskLevel: String,
        boundDeviceId: String?,
        mobileTerminalId: String?,
        allowVoiceOnly: Bool,
        requiresMobileConfirm: Bool,
        ttlMs: Int
    ) -> HubRemoteVoiceGrantChallengeResult {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "request_id_empty",
                logLines: ["voice grant challenge missing request_id"]
            )
        }

        let normalizedTemplateId = templateId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedActionDigest = actionDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScopeDigest = scopeDigest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTemplateId.isEmpty, !normalizedActionDigest.isEmpty, !normalizedScopeDigest.isEmpty else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "invalid_request",
                logLines: ["voice grant challenge missing template/action/scope digest"]
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
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice grant challenge"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_REQUEST_ID"] = normalizedRequestId
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_TEMPLATE_ID"] = normalizedTemplateId
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_ACTION_DIGEST"] = normalizedActionDigest
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_SCOPE_DIGEST"] = normalizedScopeDigest
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_AMOUNT_DIGEST"] = amountDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_CODE"] = challengeCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_RISK_LEVEL"] = riskLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_BOUND_DEVICE_ID"] = boundDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_MOBILE_TERMINAL_ID"] = mobileTerminalId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_ALLOW_VOICE_ONLY"] = allowVoiceOnly ? "1" : "0"
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_REQUIRES_MOBILE_CONFIRM"] = requiresMobileConfirm ? "1" : "0"
        scriptEnv["XTERMINAL_VOICE_CHALLENGE_TTL_MS"] = String(max(10_000, min(600_000, ttlMs)))
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceGrantChallengeScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteVoiceGrantChallengeScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_grant_challenge_failed")
            return HubRemoteVoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let challenge: HubRemoteVoiceGrantChallenge? = {
            guard let row = decoded.challenge else { return nil }
            let challengeId = row.challengeId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !challengeId.isEmpty else { return nil }
            return HubRemoteVoiceGrantChallenge(
                challengeId: challengeId,
                templateId: row.templateId.trimmingCharacters(in: .whitespacesAndNewlines),
                actionDigest: row.actionDigest.trimmingCharacters(in: .whitespacesAndNewlines),
                scopeDigest: row.scopeDigest.trimmingCharacters(in: .whitespacesAndNewlines),
                amountDigest: row.amountDigest.trimmingCharacters(in: .whitespacesAndNewlines),
                challengeCode: row.challengeCode.trimmingCharacters(in: .whitespacesAndNewlines),
                riskLevel: row.riskLevel.trimmingCharacters(in: .whitespacesAndNewlines),
                requiresMobileConfirm: row.requiresMobileConfirm ?? false,
                allowVoiceOnly: row.allowVoiceOnly ?? false,
                boundDeviceId: row.boundDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
                mobileTerminalId: row.mobileTerminalId.trimmingCharacters(in: .whitespacesAndNewlines),
                issuedAtMs: max(0, row.issuedAtMs ?? 0),
                expiresAtMs: max(0, row.expiresAtMs ?? 0)
            )
        }()

        let ok = (decoded.ok ?? (challenge != nil)) && challenge != nil
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_grant_challenge_failed")

        return HubRemoteVoiceGrantChallengeResult(
            ok: ok,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            challenge: challenge,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func verifyRemoteVoiceGrantResponse(
        options rawOptions: HubRemoteConnectOptions,
        requestId: String,
        projectId: String?,
        challengeId: String,
        challengeCode: String?,
        transcript: String?,
        transcriptHash: String?,
        semanticMatchScore: Double?,
        parsedActionDigest: String?,
        parsedScopeDigest: String?,
        parsedAmountDigest: String?,
        verifyNonce: String,
        boundDeviceId: String?,
        mobileConfirmed: Bool
    ) -> HubRemoteVoiceGrantVerificationResult {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedChallengeId = challengeId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVerifyNonce = verifyNonce.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "request_id_empty",
                logLines: ["voice grant verify missing request_id"]
            )
        }
        guard !normalizedChallengeId.isEmpty else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "challenge_id_empty",
                logLines: ["voice grant verify missing challenge_id"]
            )
        }
        guard !normalizedVerifyNonce.isEmpty else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "verify_nonce_empty",
                logLines: ["voice grant verify missing verify_nonce"]
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
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote voice grant verify"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_VOICE_VERIFY_REQUEST_ID"] = normalizedRequestId
        scriptEnv["XTERMINAL_VOICE_VERIFY_CHALLENGE_ID"] = normalizedChallengeId
        scriptEnv["XTERMINAL_VOICE_VERIFY_CHALLENGE_CODE"] = challengeCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_TRANSCRIPT"] = transcript ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_TRANSCRIPT_HASH"] = transcriptHash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let semanticMatchScore, semanticMatchScore.isFinite {
            scriptEnv["XTERMINAL_VOICE_VERIFY_SEMANTIC_MATCH_SCORE"] = String(semanticMatchScore)
        } else {
            scriptEnv["XTERMINAL_VOICE_VERIFY_SEMANTIC_MATCH_SCORE"] = ""
        }
        scriptEnv["XTERMINAL_VOICE_VERIFY_PARSED_ACTION_DIGEST"] = parsedActionDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_PARSED_SCOPE_DIGEST"] = parsedScopeDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_PARSED_AMOUNT_DIGEST"] = parsedAmountDigest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_NONCE"] = normalizedVerifyNonce
        scriptEnv["XTERMINAL_VOICE_VERIFY_BOUND_DEVICE_ID"] = boundDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_VOICE_VERIFY_MOBILE_CONFIRMED"] = mobileConfirmed ? "1" : "0"
        if let projectId, !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scriptEnv["HUB_PROJECT_ID"] = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteVoiceGrantVerifyScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteVoiceGrantVerificationScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_voice_grant_verify_failed")
            return HubRemoteVoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: mobileConfirmed,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let mappedDecision: HubRemoteVoiceGrantVerificationDecision = {
            switch (decoded.decision ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "allow":
                return .allow
            case "deny":
                return .deny
            default:
                return .failed
            }
        }()

        let ok = decoded.ok ?? (mappedDecision != .failed)
        let reasonCode = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? (ok ? nil : "remote_voice_grant_verify_failed")

        return HubRemoteVoiceGrantVerificationResult(
            ok: ok,
            verified: decoded.verified ?? false,
            decision: mappedDecision,
            source: nonEmpty(decoded.source) ?? "hub_memory_v1_grpc",
            denyCode: nonEmpty(decoded.denyCode),
            challengeId: nonEmpty(decoded.challengeId) ?? normalizedChallengeId,
            transcriptHash: nonEmpty(decoded.transcriptHash),
            semanticMatchScore: decoded.semanticMatchScore ?? 0,
            challengeMatch: decoded.challengeMatch ?? false,
            deviceBindingOK: decoded.deviceBindingOk ?? false,
            mobileConfirmed: decoded.mobileConfirmed ?? false,
            reasonCode: reasonCode?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }
}
