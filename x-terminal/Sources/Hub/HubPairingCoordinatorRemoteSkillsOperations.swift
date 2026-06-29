import Foundation

extension HubPairingCoordinator {
    func searchRemoteSkills(
        options rawOptions: HubRemoteConnectOptions,
        query: String,
        sourceFilter: String?,
        projectId: String?,
        limit: Int
    ) -> HubRemoteSkillsSearchResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let boundedLimit = max(1, min(100, limit))

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillsSearchResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                results: [],
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                officialChannelStatus: nil,
                logLines: ["hub env or client kit missing for remote skills search"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillsSearchResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                results: [],
                reasonCode: "node_missing",
                officialChannelStatus: nil,
                logLines: ["missing node runtime for remote skills search"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SKILLS_QUERY"] = query.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_SKILLS_SOURCE_FILTER"] = sourceFilter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SKILLS_LIMIT"] = String(boundedLimit)
        scriptEnv["XTERMINAL_SKILLS_PROJECT_ID"] = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillsSearchScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteSkillsSearchScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skills_search_failed")
            return HubRemoteSkillsSearchResult(
                ok: false,
                source: "hub_runtime_grpc",
                updatedAtMs: 0,
                results: [],
                reasonCode: fallback,
                officialChannelStatus: nil,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skills_search_failed")
        let results = (decoded.results ?? []).compactMap { row -> HubRemoteSkillCatalogEntry? in
            let skillID = nonEmpty(row.skillID) ?? ""
            guard !skillID.isEmpty else { return nil }
            return HubRemoteSkillCatalogEntry(
                skillID: skillID,
                name: nonEmpty(row.name) ?? skillID,
                version: nonEmpty(row.version) ?? "",
                description: nonEmpty(row.description) ?? "",
                publisherID: nonEmpty(row.publisherID) ?? "",
                capabilitiesRequired: row.capabilitiesRequired ?? [],
                sourceID: nonEmpty(row.sourceID) ?? "",
                packageSHA256: nonEmpty(row.packageSHA256) ?? "",
                installHint: nonEmpty(row.installHint) ?? "",
                riskLevel: nonEmpty(row.riskLevel) ?? "low",
                requiresGrant: row.requiresGrant ?? false,
                sideEffectClass: nonEmpty(row.sideEffectClass) ?? ""
            )
        }
        let officialChannelStatus = decoded.officialChannelStatus.map { row in
            HubRemoteOfficialSkillChannelStatus(
                channelID: nonEmpty(row.channelID) ?? "official-stable",
                status: nonEmpty(row.status) ?? "",
                updatedAtMs: max(0, row.updatedAtMs ?? 0),
                lastAttemptAtMs: max(0, row.lastAttemptAtMs ?? 0),
                lastSuccessAtMs: max(0, row.lastSuccessAtMs ?? 0),
                skillCount: max(0, row.skillCount ?? 0),
                errorCode: nonEmpty(row.errorCode) ?? "",
                maintenanceEnabled: row.maintenanceEnabled ?? false,
                maintenanceIntervalMs: max(0, row.maintenanceIntervalMs ?? 0),
                maintenanceLastRunAtMs: max(0, row.maintenanceLastRunAtMs ?? 0),
                maintenanceSourceKind: nonEmpty(row.maintenanceSourceKind) ?? "",
                lastTransitionAtMs: max(0, row.lastTransitionAtMs ?? 0),
                lastTransitionKind: nonEmpty(row.lastTransitionKind) ?? "",
                lastTransitionSummary: nonEmpty(row.lastTransitionSummary) ?? ""
            )
        }

        return HubRemoteSkillsSearchResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            results: results,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            officialChannelStatus: officialChannelStatus,
            logLines: logs
        )
    }

    func setRemoteSkillPin(
        options rawOptions: HubRemoteConnectOptions,
        scope: String,
        skillId: String,
        packageSHA256: String,
        projectId: String?,
        note: String?,
        requestId: String?
    ) -> HubRemoteSkillPinResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSkillId = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard normalizedScope == "global" || normalizedScope == "project" else {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "unsupported_skill_pin_scope",
                logLines: ["unsupported skill pin scope: \(normalizedScope)"]
            )
        }
        if normalizedScope == "project", normalizedProjectId.isEmpty {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_project_id",
                logLines: ["project scope skill pin requires project id"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote skill pin"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote skill pin"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SKILLS_PIN_SCOPE"] = normalizedScope
        scriptEnv["XTERMINAL_SKILLS_PIN_SKILL_ID"] = normalizedSkillId
        scriptEnv["XTERMINAL_SKILLS_PIN_PACKAGE_SHA256"] = normalizedPackageSHA256
        scriptEnv["XTERMINAL_SKILLS_PIN_PROJECT_ID"] = normalizedProjectId
        scriptEnv["XTERMINAL_SKILLS_PIN_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_SKILLS_PIN_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillPinScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteSkillPinScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skill_pin_failed")
            return HubRemoteSkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skill_pin_failed")

        return HubRemoteSkillPinResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            scope: nonEmpty(decoded.scope) ?? normalizedScope,
            userId: nonEmpty(decoded.userId) ?? "",
            projectId: nonEmpty(decoded.projectId) ?? normalizedProjectId,
            skillId: nonEmpty(decoded.skillId) ?? normalizedSkillId,
            packageSHA256: nonEmpty(decoded.packageSHA256) ?? normalizedPackageSHA256,
            previousPackageSHA256: nonEmpty(decoded.previousPackageSHA256) ?? "",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteResolvedSkills(
        options rawOptions: HubRemoteConnectOptions,
        projectId: String?
    ) -> HubRemoteResolvedSkillsResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteResolvedSkillsResult(
                ok: false,
                source: "hub_runtime_grpc",
                skills: [],
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote resolved skills request"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteResolvedSkillsResult(
                ok: false,
                source: "hub_runtime_grpc",
                skills: [],
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote resolved skills request"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_RESOLVED_SKILLS_PROJECT_ID"] = normalizedProjectId

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteResolvedSkillsScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteResolvedSkillsScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_resolved_skills_failed")
            return HubRemoteResolvedSkillsResult(
                ok: false,
                source: "hub_runtime_grpc",
                skills: [],
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_resolved_skills_failed")
        let skills = (decoded.skills ?? []).compactMap { row -> HubRemoteResolvedSkillEntry? in
            guard let skillRow = row.skill else { return nil }
            let skillID = nonEmpty(skillRow.skillID) ?? ""
            guard !skillID.isEmpty else { return nil }
            let skill = HubRemoteSkillCatalogEntry(
                skillID: skillID,
                name: nonEmpty(skillRow.name) ?? skillID,
                version: nonEmpty(skillRow.version) ?? "",
                description: nonEmpty(skillRow.description) ?? "",
                publisherID: nonEmpty(skillRow.publisherID) ?? "",
                capabilitiesRequired: skillRow.capabilitiesRequired ?? [],
                sourceID: nonEmpty(skillRow.sourceID) ?? "",
                packageSHA256: nonEmpty(skillRow.packageSHA256) ?? "",
                installHint: nonEmpty(skillRow.installHint) ?? "",
                riskLevel: nonEmpty(skillRow.riskLevel) ?? "low",
                requiresGrant: skillRow.requiresGrant ?? false,
                sideEffectClass: nonEmpty(skillRow.sideEffectClass) ?? ""
            )
            return HubRemoteResolvedSkillEntry(
                scope: nonEmpty(row.scope) ?? "",
                skill: skill
            )
        }

        return HubRemoteResolvedSkillsResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            skills: skills,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteSkillManifest(
        options rawOptions: HubRemoteConnectOptions,
        packageSHA256: String
    ) -> HubRemoteSkillManifestResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedPackageSHA256 = packageSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedPackageSHA256.isEmpty else {
            return HubRemoteSkillManifestResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: "",
                manifestJSON: "",
                reasonCode: "missing_package_sha256",
                logLines: ["remote skill manifest request requires package sha256"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillManifestResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: normalizedPackageSHA256,
                manifestJSON: "",
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote skill manifest request"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillManifestResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: normalizedPackageSHA256,
                manifestJSON: "",
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote skill manifest request"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SKILL_MANIFEST_PACKAGE_SHA256"] = normalizedPackageSHA256

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillManifestScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteSkillManifestScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skill_manifest_failed")
            return HubRemoteSkillManifestResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: normalizedPackageSHA256,
                manifestJSON: "",
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skill_manifest_failed")

        return HubRemoteSkillManifestResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            packageSHA256: nonEmpty(decoded.packageSHA256) ?? normalizedPackageSHA256,
            manifestJSON: decoded.manifestJSON ?? "",
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func downloadRemoteSkillPackage(
        options rawOptions: HubRemoteConnectOptions,
        packageSHA256: String
    ) -> HubRemoteSkillPackageDownloadResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedPackageSHA256 = packageSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedPackageSHA256.isEmpty else {
            return HubRemoteSkillPackageDownloadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: "",
                data: Data(),
                reasonCode: "missing_package_sha256",
                logLines: ["remote skill package download requires package sha256"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillPackageDownloadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: normalizedPackageSHA256,
                data: Data(),
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote skill package download"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillPackageDownloadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: normalizedPackageSHA256,
                data: Data(),
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote skill package download"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_SKILL_PACKAGE_DOWNLOAD_SHA256"] = normalizedPackageSHA256

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillPackageDownloadScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 60.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSkillPackageDownloadScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skill_package_download_failed")
            return HubRemoteSkillPackageDownloadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: normalizedPackageSHA256,
                data: Data(),
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skill_package_download_failed")
        let packageData = Data(base64Encoded: decoded.packageBase64 ?? "") ?? Data()

        return HubRemoteSkillPackageDownloadResult(
            ok: (decoded.ok ?? false) && !packageData.isEmpty,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            packageSHA256: nonEmpty(decoded.packageSHA256) ?? normalizedPackageSHA256,
            data: packageData,
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func evaluateRemoteSkillRunnerGate(
        options rawOptions: HubRemoteConnectOptions,
        request: HubIPCClient.SkillRunnerGateRequestPayload
    ) -> HubRemoteSkillRunnerGateResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedPackageSHA256 = request.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSkillId = request.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToolName = request.toolName.trimmingCharacters(in: .whitespacesAndNewlines)

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                toolName: normalizedToolName,
                decision: "deny",
                toolRequestId: "",
                grantId: "",
                executionId: "",
                denyCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                resultJSON: "",
                executedAtMs: 0,
                logLines: ["hub env or client kit missing for remote skill runner gate"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                toolName: normalizedToolName,
                decision: "deny",
                toolRequestId: "",
                grantId: "",
                executionId: "",
                denyCode: "node_missing",
                resultJSON: "",
                executedAtMs: 0,
                logLines: ["missing node runtime for remote skill runner gate"]
            )
        }

        let execArgvJSON = (try? JSONEncoder().encode(request.execArgv)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"
        var scriptEnv = merged
        scriptEnv["XTERMINAL_SKILL_RUNNER_REQUEST_ID"] = request.requestId
        scriptEnv["XTERMINAL_SKILL_RUNNER_PROJECT_ID"] = request.projectId ?? ""
        scriptEnv["XTERMINAL_SKILL_RUNNER_EXECUTION_ROLE"] = request.executionRole ?? ""
        scriptEnv["XTERMINAL_SKILL_RUNNER_AGENT_MODE"] = request.agentMode ?? ""
        scriptEnv["XTERMINAL_SKILL_RUNNER_LANE_ID"] = request.laneId ?? ""
        scriptEnv["XTERMINAL_SKILL_RUNNER_AUDIT_REF"] = request.auditRef ?? ""
        scriptEnv["XTERMINAL_SKILL_RUNNER_SKILL_ID"] = normalizedSkillId
        scriptEnv["XTERMINAL_SKILL_RUNNER_PACKAGE_SHA256"] = normalizedPackageSHA256
        scriptEnv["XTERMINAL_SKILL_RUNNER_TOOL_NAME"] = normalizedToolName
        scriptEnv["XTERMINAL_SKILL_RUNNER_TOOL_ARGS_HASH"] = request.toolArgsHash
        scriptEnv["XTERMINAL_SKILL_RUNNER_RISK_TIER"] = request.riskTier
        scriptEnv["XTERMINAL_SKILL_RUNNER_REQUIRED_GRANT_SCOPE"] = request.requiredGrantScope
        scriptEnv["XTERMINAL_SKILL_RUNNER_EXEC_ARGV_JSON"] = execArgvJSON
        scriptEnv["XTERMINAL_SKILL_RUNNER_EXEC_CWD"] = request.execCwd

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillRunnerGateScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 30.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSkillRunnerGateScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skill_runner_gate_failed")
            return HubRemoteSkillRunnerGateResult(
                ok: false,
                source: "hub_runtime_grpc",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                toolName: normalizedToolName,
                decision: "deny",
                toolRequestId: "",
                grantId: "",
                executionId: "",
                denyCode: fallback,
                resultJSON: "",
                executedAtMs: 0,
                logLines: logs
            )
        }

        let denyCode = nonEmpty(decoded.denyCode)
            ?? nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
        return HubRemoteSkillRunnerGateResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            skillId: nonEmpty(decoded.skillId) ?? normalizedSkillId,
            packageSHA256: nonEmpty(decoded.packageSHA256) ?? normalizedPackageSHA256,
            toolName: nonEmpty(decoded.toolName) ?? normalizedToolName,
            decision: nonEmpty(decoded.decision) ?? "",
            toolRequestId: nonEmpty(decoded.toolRequestId) ?? "",
            grantId: nonEmpty(decoded.grantId) ?? "",
            executionId: nonEmpty(decoded.executionId) ?? "",
            denyCode: denyCode?.replacingOccurrences(of: " ", with: "_"),
            resultJSON: decoded.resultJSON ?? "",
            executedAtMs: max(0, decoded.executedAtMs ?? 0),
            logLines: logs
        )
    }

    func stageRemoteAgentImport(
        options rawOptions: HubRemoteConnectOptions,
        importManifestJSON: String,
        findingsJSON: String?,
        scanInputJSON: String?,
        requestedBy: String?,
        note: String?,
        requestId: String?
    ) -> HubRemoteAgentImportStageResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []

        let manifestText = importManifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "missing_agent_import_manifest",
                logLines: ["agent import manifest is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)

        guard FileManager.default.fileExists(atPath: hubEnv.path) else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "hub_env_missing",
                logLines: ["missing hub env: \(hubEnv.path)"]
            )
        }
        guard FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "client_kit_missing",
                logLines: ["missing client kit src: \(clientKitSrc.path)"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged)
        guard let nodeBin else {
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import stage"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_MANIFEST_JSON"] = manifestText
        scriptEnv["XTERMINAL_AGENT_IMPORT_FINDINGS_JSON"] = findingsJSON ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_SCAN_INPUT_JSON"] = scanInputJSON ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_REQUESTED_BY"] = requestedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteAgentImportStageScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteAgentImportStageScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_stage_failed")
            return HubRemoteAgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_stage_failed")

        return HubRemoteAgentImportStageResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            preflightStatus: nonEmpty(decoded.preflightStatus),
            skillId: nonEmpty(decoded.skillId),
            policyScope: nonEmpty(decoded.policyScope),
            findingsCount: max(0, decoded.findingsCount ?? 0),
            vetterStatus: nonEmpty(decoded.vetterStatus),
            vetterCriticalCount: max(0, decoded.vetterCriticalCount ?? 0),
            vetterWarnCount: max(0, decoded.vetterWarnCount ?? 0),
            vetterAuditRef: nonEmpty(decoded.vetterAuditRef),
            recordPath: nonEmpty(decoded.recordPath),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteAgentImportRecord(
        options rawOptions: HubRemoteConnectOptions,
        stagingId: String
    ) -> HubRemoteAgentImportRecordResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedStagingId = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStagingId.isEmpty else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "missing_agent_staging_id",
                logLines: ["agent import staging id is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote agent import record"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import record"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_STAGING_ID"] = normalizedStagingId
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteAgentImportRecordScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteAgentImportRecordScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_record_failed")
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_record_failed")

        return HubRemoteAgentImportRecordResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            selector: nonEmpty(decoded.selector),
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            schemaVersion: nonEmpty(decoded.schemaVersion),
            skillId: nonEmpty(decoded.skillId),
            projectId: nonEmpty(decoded.projectId),
            recordJSON: nonEmpty(decoded.recordJSON),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func fetchRemoteResolvedAgentImportRecord(
        options rawOptions: HubRemoteConnectOptions,
        selector: String,
        skillId: String?,
        projectId: String?
    ) -> HubRemoteAgentImportRecordResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSkillId = skillId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedSelector.isEmpty else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: nil,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "missing_agent_import_selector",
                logLines: ["agent import selector is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: normalizedSelector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote agent import resolve"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: normalizedSelector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import resolve"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_SELECTOR"] = normalizedSelector
        if !normalizedSkillId.isEmpty {
            scriptEnv["XTERMINAL_AGENT_IMPORT_SKILL_ID"] = normalizedSkillId
        }
        if !normalizedProjectId.isEmpty {
            scriptEnv["XTERMINAL_AGENT_IMPORT_PROJECT_ID"] = normalizedProjectId
        }
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteResolvedAgentImportRecordScriptSource()
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
              let decoded = try? JSONDecoder().decode(RemoteAgentImportRecordScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_record_resolve_failed")
            return HubRemoteAgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                selector: normalizedSelector,
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                projectId: nil,
                recordJSON: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_record_resolve_failed")

        return HubRemoteAgentImportRecordResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            selector: nonEmpty(decoded.selector) ?? normalizedSelector,
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            schemaVersion: nonEmpty(decoded.schemaVersion),
            skillId: nonEmpty(decoded.skillId),
            projectId: nonEmpty(decoded.projectId),
            recordJSON: nonEmpty(decoded.recordJSON),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func uploadRemoteSkillPackage(
        options rawOptions: HubRemoteConnectOptions,
        packageFileURL: URL,
        manifestJSON: String,
        sourceId: String,
        requestId: String?
    ) -> HubRemoteSkillPackageUploadResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let packagePath = packageFileURL.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: packagePath) else {
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: "skill_package_file_missing",
                logLines: ["missing skill package file: \(packagePath)"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote skill upload"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote skill upload"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_UPLOAD_SKILL_PACKAGE_PATH"] = packagePath
        scriptEnv["XTERMINAL_UPLOAD_SKILL_MANIFEST_JSON"] = manifestJSON
        scriptEnv["XTERMINAL_UPLOAD_SKILL_SOURCE_ID"] = sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptEnv["XTERMINAL_UPLOAD_SKILL_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteSkillPackageUploadScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 60.0,
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
              let decoded = try? JSONDecoder().decode(RemoteSkillPackageUploadScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_skill_package_upload_failed")
            return HubRemoteSkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_skill_package_upload_failed")

        return HubRemoteSkillPackageUploadResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            packageSHA256: nonEmpty(decoded.packageSHA256),
            alreadyPresent: decoded.alreadyPresent ?? false,
            skillId: nonEmpty(decoded.skillId),
            version: nonEmpty(decoded.version),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }

    func promoteRemoteAgentImport(
        options rawOptions: HubRemoteConnectOptions,
        stagingId: String,
        packageSHA256: String,
        note: String?,
        requestId: String?
    ) -> HubRemoteAgentImportPromoteResult {
        let opts = sanitize(rawOptions)
        var logs: [String] = []
        let normalizedStagingId = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedStagingId.isEmpty else {
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "missing_agent_staging_id",
                logLines: ["agent import staging id is empty"]
            )
        }

        let stateDir = opts.stateDir ?? defaultStateDir()
        let hubEnv = stateDir.appendingPathComponent("hub.env")
        let clientKitBase = stateDir.appendingPathComponent("client_kit", isDirectory: true)
        let clientKitHub = clientKitBase.appendingPathComponent("hub_grpc_server", isDirectory: true)
        let clientKitSrc = clientKitHub.appendingPathComponent("src", isDirectory: true)
        guard FileManager.default.fileExists(atPath: hubEnv.path),
              FileManager.default.fileExists(atPath: clientKitSrc.path) else {
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: FileManager.default.fileExists(atPath: hubEnv.path) ? "client_kit_missing" : "hub_env_missing",
                logLines: ["hub env or client kit missing for remote agent import promote"]
            )
        }

        let exported = readEnvExports(from: hubEnv)
        let merged = mergedAxhubEnv(options: opts, extra: exported)
        guard let nodeBin = resolveNodeExecutable(clientKitBaseDir: clientKitBase, env: merged) else {
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "node_missing",
                logLines: ["missing node runtime for remote agent import promote"]
            )
        }

        var scriptEnv = merged
        scriptEnv["XTERMINAL_AGENT_IMPORT_STAGING_ID"] = normalizedStagingId
        scriptEnv["XTERMINAL_AGENT_IMPORT_PACKAGE_SHA256"] = normalizedPackageSHA256
        scriptEnv["XTERMINAL_AGENT_IMPORT_NOTE"] = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptEnv["XTERMINAL_AGENT_IMPORT_REQUEST_ID"] = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let command = [nodeBin, "--input-type=module", "-"].joined(separator: " ")
        func runScript() -> StepOutput {
            do {
                let script = remoteAgentImportPromoteScriptSource()
                let result = try ProcessCapture.run(
                    nodeBin,
                    ["--input-type=module", "-"],
                    cwd: clientKitHub,
                    stdin: script.data(using: .utf8),
                    timeoutSec: 30.0,
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
              let decoded = try? JSONDecoder().decode(RemoteAgentImportPromoteScriptResult.self, from: data) else {
            let fallback = inferFailureCode(from: step.output, fallback: "remote_agent_import_promote_failed")
            return HubRemoteAgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: fallback,
                logLines: logs
            )
        }

        let reason = nonEmpty(decoded.errorCode)
            ?? nonEmpty(decoded.reason)
            ?? nonEmpty(decoded.errorMessage)
            ?? ((decoded.ok ?? false) ? nil : "remote_agent_import_promote_failed")

        return HubRemoteAgentImportPromoteResult(
            ok: decoded.ok ?? false,
            source: nonEmpty(decoded.source) ?? "hub_runtime_grpc",
            stagingId: nonEmpty(decoded.stagingId),
            status: nonEmpty(decoded.status),
            auditRef: nonEmpty(decoded.auditRef),
            packageSHA256: nonEmpty(decoded.packageSHA256),
            scope: nonEmpty(decoded.scope),
            skillId: nonEmpty(decoded.skillId),
            previousPackageSHA256: nonEmpty(decoded.previousPackageSHA256),
            recordPath: nonEmpty(decoded.recordPath),
            reasonCode: reason?.replacingOccurrences(of: " ", with: "_"),
            logLines: logs
        )
    }
}
