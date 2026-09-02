import Foundation

extension SupervisorManager {
    func mapSupervisorSkillToToolCall(
        skillId: String,
        payload: [String: JSONValue],
        requestId: String,
        projectId: String? = nil,
        projectName: String? = nil,
        projectRoot: URL? = nil,
        registryItem: SupervisorSkillRegistryItem? = nil
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        let canonicalSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(skillId)
        let effectiveSkillId = effectiveSupervisorSkillID(
            requestedSkillId: canonicalSkillId,
            projectId: projectId,
            projectName: projectName,
            projectRoot: projectRoot,
            registryItem: registryItem
        )
        let effectivePayload = normalizedSupervisorSkillPayload(
            requestedSkillId: canonicalSkillId,
            effectiveSkillId: effectiveSkillId,
            payload: payload
        )
        let effectiveRegistryItem: SupervisorSkillRegistryItem? = {
            let canonicalRegistryItemId = AXSkillsLibrary.canonicalSupervisorSkillID(registryItem?.skillId ?? "")
            if canonicalRegistryItemId == effectiveSkillId {
                return registryItem
            }
            return resolvedSupervisorRegistryItem(
                skillId: effectiveSkillId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot
            ) ?? registryItem
        }()

        switch effectiveSkillId.lowercased() {
        case "repo.git.status":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .git_status, args: [:]),
                toolName: ToolName.git_status.rawValue
            ))
        case "repo.git.diff":
            var args: [String: JSONValue] = [:]
            if let cached = effectivePayload["cached"] {
                args["cached"] = cached
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .git_diff, args: args),
                toolName: ToolName.git_diff.rawValue
            ))
        case "repo.git.commit":
            return mappedSupervisorGitCommitDispatch(
                payload: payload,
                requestId: requestId
            )
        case "repo.git.push":
            return mappedSupervisorGitPushDispatch(
                payload: payload,
                requestId: requestId
            )
        case "repo.git.apply", "repo.patch.apply", "repo.git.patch.apply":
            guard let patch = payload["patch"]?.stringValue,
                  !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.patch_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .git_apply, args: ["patch": .string(patch)]),
                toolName: ToolName.git_apply.rawValue
            ))
        case "repo.search", "repo.grep":
            guard let pattern = payload["pattern"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pattern.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.pattern_missing"))
            }
            var args: [String: JSONValue] = ["pattern": .string(pattern)]
            if let path = effectivePayload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                args["path"] = .string(path)
            }
            if let glob = effectivePayload["glob"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !glob.isEmpty {
                args["glob"] = .string(glob)
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .search, args: args),
                toolName: ToolName.search.rawValue
            ))
        case "repo.write.file", "repo.write", "repo.file.write":
            return mappedSupervisorRepoWriteFileDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "repo.delete.path", "repo.delete.file", "repo.delete":
            return mappedSupervisorRepoDeletePathDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "repo.move.path", "repo.rename.path", "repo.move", "repo.rename":
            return mappedSupervisorRepoMovePathDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "repo.read.file", "repo.read", "repo.file.read":
            guard let path = effectivePayload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.path_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .read_file, args: ["path": .string(path)]),
                toolName: ToolName.read_file.rawValue
            ))
        case "repo.list.dir", "repo.list", "repo.dir.list":
            let path = effectivePayload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "."
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .list_dir, args: ["path": .string(path.isEmpty ? "." : path)]),
                toolName: ToolName.list_dir.rawValue
            ))
        case "project.snapshot", "project_snapshot":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .project_snapshot, args: [:]),
                toolName: ToolName.project_snapshot.rawValue
            ))
        case "memory.snapshot", "memory_snapshot":
            var args: [String: JSONValue] = [:]
            if let mode = payload["mode"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !mode.isEmpty {
                args["mode"] = .string(mode)
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .memory_snapshot, args: args),
                toolName: ToolName.memory_snapshot.rawValue
            ))
        case "bridge.status", "bridge_status":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .bridge_status, args: [:]),
                toolName: ToolName.bridge_status.rawValue
            ))
        case "find-skills", "skills.search", "skills_search":
            if let registryDriven = mappedSupervisorGovernedDispatch(
                skillId: effectiveSkillId,
                payload: effectivePayload,
                requestId: requestId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot,
                registryItem: effectiveRegistryItem
            ) {
                return registryDriven
            }
            guard let query = effectivePayload["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !query.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.query_missing"))
            }
            var args: [String: JSONValue] = ["query": .string(query)]
            if let sourceFilter = firstNonEmptyString(
                effectivePayload["source_filter"]?.stringValue,
                effectivePayload["source"]?.stringValue
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sourceFilter.isEmpty {
                args["source_filter"] = .string(sourceFilter)
            }
            if let projectId = effectivePayload["project_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !projectId.isEmpty {
                args["project_id"] = .string(projectId)
            }
            if let limit = effectivePayload["limit"] ?? effectivePayload["max_results"] {
                args["limit"] = limit
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .skills_search, args: args),
                toolName: ToolName.skills_search.rawValue
            ))
        case "agent-browser", "agent_browser", "agent.browser":
            if let registryDriven = mappedSupervisorGovernedDispatch(
                skillId: effectiveSkillId,
                payload: effectivePayload,
                requestId: requestId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot,
                registryItem: effectiveRegistryItem
            ) {
                return registryDriven
            }
            return mappedSupervisorAgentBrowserDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "self-improving-agent", "self_improving_agent", "agent.retrospective", "agent_retrospective":
            if let registryDriven = mappedSupervisorGovernedDispatch(
                skillId: effectiveSkillId,
                payload: effectivePayload,
                requestId: requestId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot,
                registryItem: effectiveRegistryItem
            ) {
                return registryDriven
            }
            return mappedSupervisorSelfImprovingAgentDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "browser.open", "browser.navigate", "browser_open", "browser_navigate":
            guard let url = effectivePayload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string(url)
                    ]
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "browser.runtime.inspect", "browser_runtime.inspect":
            var args: [String: JSONValue] = ["action": .string("snapshot")]
            if let url = effectivePayload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                args["url"] = .string(url)
            }
            if let sessionId = effectivePayload["session_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sessionId.isEmpty {
                args["session_id"] = .string(sessionId)
            }
            guard args["url"] != nil || args["session_id"] != nil else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_or_session_id_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .deviceBrowserControl, args: args),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "browser.runtime.smoke", "browser_runtime.smoke":
            let url = effectivePayload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "https://example.com"
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string(url)
                    ]
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "web.fetch", "web_fetch":
            guard let url = effectivePayload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            var args: [String: JSONValue] = ["url": .string(url)]
            for key in ["grant_id", "timeout_sec", "max_bytes"] {
                if let value = effectivePayload[key] {
                    args[key] = value
                }
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .web_fetch, args: args),
                toolName: ToolName.web_fetch.rawValue
            ))
        case "web.search", "web_search":
            guard let query = effectivePayload["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !query.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.query_missing"))
            }
            var args: [String: JSONValue] = ["query": .string(query)]
            for key in ["grant_id", "timeout_sec", "max_results", "max_bytes"] {
                if let value = effectivePayload[key] {
                    args[key] = value
                }
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .web_search, args: args),
                toolName: ToolName.web_search.rawValue
            ))
        case "browser.read", "browser_read":
            guard let url = effectivePayload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            var args: [String: JSONValue] = ["url": .string(url)]
            for key in ["grant_id", "timeout_sec", "max_bytes"] {
                if let value = effectivePayload[key] {
                    args[key] = value
                }
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .browser_read, args: args),
                toolName: ToolName.browser_read.rawValue
            ))
        case "summarize", "document.summarize", "document_summarize":
            if let registryDriven = mappedSupervisorGovernedDispatch(
                skillId: effectiveSkillId,
                payload: effectivePayload,
                requestId: requestId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot,
                registryItem: effectiveRegistryItem
            ) {
                return registryDriven
            }
            return mappedSupervisorSummarizeDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "supervisor-voice", "supervisor.voice", "supervisor_voice":
            if let registryDriven = mappedSupervisorGovernedDispatch(
                skillId: "supervisor-voice",
                payload: effectivePayload,
                requestId: requestId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot,
                registryItem: effectiveRegistryItem
            ) {
                return registryDriven
            }
            return mappedSupervisorVoicePlaybackDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "repo.test.run", "repo.test", "repo.verify.run":
            return mappedSupervisorRepoCommandDispatch(
                payload: effectivePayload,
                requestId: requestId,
                profile: .test
            )
        case "repo.build.run", "repo.build":
            return mappedSupervisorRepoCommandDispatch(
                payload: effectivePayload,
                requestId: requestId,
                profile: .build
            )
        case "repo.pr.create", "repo.pull_request.create", "repo.pull-request.create":
            return mappedSupervisorPRCreateDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "repo.ci.read", "ci.read":
            return mappedSupervisorCIReadDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "repo.ci.trigger", "ci.trigger":
            return mappedSupervisorCITriggerDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "process.start":
            return mappedSupervisorProcessStartDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "process.status":
            return mappedSupervisorProcessStatusDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "process.logs":
            return mappedSupervisorProcessLogsDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "process.stop":
            return mappedSupervisorProcessStopDispatch(
                payload: effectivePayload,
                requestId: requestId
            )
        case "coder.run.command", "coder.run", "coder_run.command", "coder_run":
            guard let command = effectivePayload["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.command_missing"))
            }
            var args: [String: JSONValue] = ["command": .string(command)]
            if let timeout = effectivePayload["timeout_sec"] {
                args["timeout_sec"] = timeout
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .run_command, args: args),
                toolName: ToolName.run_command.rawValue
            ))
        default:
            if let registryDriven = mappedSupervisorGovernedDispatch(
                skillId: effectiveSkillId,
                payload: effectivePayload,
                requestId: requestId,
                projectId: projectId,
                projectName: projectName,
                projectRoot: projectRoot,
                registryItem: effectiveRegistryItem
            ) {
                return registryDriven
            }
            return .failure(SupervisorSkillMappingFailure(reasonCode: "unsupported_skill_id"))
        }
    }

    private func mappedSupervisorGovernedDispatch(
        skillId: String,
        payload: [String: JSONValue],
        requestId: String,
        projectId: String?,
        projectName: String?,
        projectRoot: URL? = nil,
        registryItem: SupervisorSkillRegistryItem?
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure>? {
        let normalizedSkillId = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSkillId.isEmpty else { return nil }
        let item = registryItem ?? resolvedSupervisorRegistryItem(
            skillId: normalizedSkillId,
            projectId: projectId,
            projectName: projectName,
            projectRoot: projectRoot
        )
        if let variantResult = mappedSupervisorGovernedDispatchVariant(
            item: item,
            payload: payload,
            requestId: requestId
        ) {
            return variantResult
        }
        guard let dispatch = item?.governedDispatch else { return nil }
        return mappedSupervisorGovernedDispatch(
            dispatch: dispatch,
            item: item,
            payload: payload,
            requestId: requestId,
            actionOverride: nil
        )
    }

    private func mappedSupervisorGovernedDispatchVariant(
        item: SupervisorSkillRegistryItem?,
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure>? {
        guard let item, !item.governedDispatchVariants.isEmpty else { return nil }
        let requestedAction = firstNonEmptyString(
            payload["action"]?.stringValue,
            payload["operation"]?.stringValue,
            payload["mode"]?.stringValue
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
        guard !requestedAction.isEmpty else { return nil }

        guard let variant = item.governedDispatchVariants.first(where: { variant in
            variant.actions.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == requestedAction
            }
        }) else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.action_unsupported"))
        }

        let actionOverride: (key: String, value: String)? = {
            let cleanedKey = variant.actionArg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedKey.isEmpty else { return nil }
            let mapped = variant.actionMap.first(where: {
                $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == requestedAction
            })?.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = {
                let token = mapped ?? ""
                return token.isEmpty ? requestedAction : token
            }()
            guard !resolved.isEmpty else { return nil }
            return (cleanedKey, resolved)
        }()

        return mappedSupervisorGovernedDispatch(
            dispatch: variant.dispatch,
            item: item,
            payload: payload,
            requestId: requestId,
            actionOverride: actionOverride
        )
    }

    private func mappedSupervisorGovernedDispatch(
        dispatch: SupervisorGovernedSkillDispatch,
        item: SupervisorSkillRegistryItem?,
        payload: [String: JSONValue],
        requestId: String,
        actionOverride: (key: String, value: String)?
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {

        let toolToken = dispatch.tool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolToken.isEmpty,
              let toolName = ToolName.allCases.first(where: { $0.rawValue == toolToken }) else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "governed_dispatch_tool_invalid"))
        }

        var args = dispatch.fixedArgs
        if let actionOverride {
            args[actionOverride.key] = .string(actionOverride.value)
        }
        let canonicalKeys = Set(dispatch.passthroughArgs).union(dispatch.argAliases.keys)
        for canonicalKey in canonicalKeys.sorted() {
            if let value = resolvedGovernedDispatchPayloadValue(
                payload: payload,
                canonicalKey: canonicalKey,
                aliases: dispatch.argAliases[canonicalKey] ?? []
            ) {
                args[canonicalKey] = value
            }
        }

        enrichSupervisorSkillRunnerBindingArgsIfNeeded(
            toolName: toolName,
            item: item,
            args: &args
        )

        for group in dispatch.requiredAny {
            let presentCount = group.filter { governedDispatchHasValue(args[$0]) }.count
            guard presentCount > 0 else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: governedDispatchMissingReasonCode(for: group)))
            }
        }

        for group in dispatch.exactlyOneOf {
            let presentCount = group.filter { governedDispatchHasValue(args[$0]) }.count
            guard presentCount == 1 else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: governedDispatchExclusiveReasonCode(for: group, presentCount: presentCount)))
            }
        }

        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: toolName, args: args),
            toolName: toolName.rawValue
        ))
    }

    func resolvedSupervisorRegistryItem(
        skillId: String,
        projectId: String?,
        projectName: String?,
        projectRoot: URL? = nil
    ) -> SupervisorSkillRegistryItem? {
        guard let projectId = firstNonEmptyString(projectId) else { return nil }
        let canonicalSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(skillId)
        guard !canonicalSkillId.isEmpty else { return nil }
        let persistedFallbackItem: SupervisorSkillRegistryItem? = {
            guard let projectRoot else { return nil }
            return persistedRemoteRegistryFallbackItem(
                skillId: canonicalSkillId,
                projectId: projectId,
                projectName: firstNonEmptyString(projectName),
                ctx: AXProjectContext(root: projectRoot)
            )
        }()
        let snapshot: SupervisorSkillRegistrySnapshot?
        if let projectRoot {
            snapshot = AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                projectId: projectId,
                projectName: firstNonEmptyString(projectName),
                projectRoot: projectRoot,
                hubBaseDir: HubPaths.baseDir()
            )
        } else {
            snapshot = AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: projectId,
                projectName: firstNonEmptyString(projectName),
                hubBaseDir: HubPaths.baseDir()
            )
        }
        return snapshot?.items.first {
            AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId) == canonicalSkillId
        } ?? persistedFallbackItem
    }

    func effectiveSupervisorSkillID(
        requestedSkillId: String,
        projectId: String?,
        projectName: String?,
        projectRoot: URL? = nil,
        registrySnapshot: SupervisorSkillRegistrySnapshot? = nil,
        registryItem: SupervisorSkillRegistryItem? = nil
    ) -> String {
        let canonicalSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(requestedSkillId)
        guard !canonicalSkillId.isEmpty else { return "" }
        return preferredSupervisorBuiltinSkillID(
            requestedSkillId: canonicalSkillId,
            projectId: projectId,
            projectName: projectName,
            projectRoot: projectRoot,
            registrySnapshot: registrySnapshot,
            registryItem: registryItem
        ) ?? canonicalSkillId
    }

    func normalizedSupervisorSkillPayload(
        requestedSkillId: String,
        effectiveSkillId: String,
        payload: [String: JSONValue]
    ) -> [String: JSONValue] {
        guard AXSkillsLibrary.canonicalSupervisorSkillID(effectiveSkillId) == "guarded-automation" else {
            return payload
        }
        guard firstNonEmptyString(
            payload["action"]?.stringValue,
            payload["operation"]?.stringValue,
            payload["mode"]?.stringValue
        ) == nil else {
            return payload
        }
        guard let inferredAction = inferredGuardedAutomationAction(for: requestedSkillId) else {
            return payload
        }
        var normalized = payload
        normalized["action"] = .string(inferredAction)
        return normalized
    }

    private func inferredGuardedAutomationAction(for requestedSkillId: String) -> String? {
        switch AXSkillsLibrary.canonicalSupervisorSkillID(requestedSkillId).lowercased() {
        case "browser.open", "browser_open":
            return "open"
        case "browser.navigate", "browser_navigate":
            return "navigate"
        case "browser.runtime.inspect", "browser_runtime.inspect":
            return "snapshot"
        default:
            return nil
        }
    }

    private func preferredSupervisorBuiltinSkillID(
        requestedSkillId: String,
        projectId: String?,
        projectName: String?,
        projectRoot: URL? = nil,
        registrySnapshot: SupervisorSkillRegistrySnapshot? = nil,
        registryItem: SupervisorSkillRegistryItem? = nil
    ) -> String? {
        let canonicalSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(requestedSkillId)
        guard preferredBuiltinSkillCompatibilityToken(for: canonicalSkillId) == "governed_browser_automation" else {
            return nil
        }

        let snapshot: SupervisorSkillRegistrySnapshot? = {
            if let registrySnapshot {
                return registrySnapshot
            }
            if let projectRoot,
               let projectId = firstNonEmptyString(projectId) {
                return AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                    projectId: projectId,
                    projectName: firstNonEmptyString(projectName),
                    projectRoot: projectRoot,
                    hubBaseDir: HubPaths.baseDir()
                )
            }
            return AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                projectId: projectId ?? "",
                projectName: firstNonEmptyString(projectName),
                hubBaseDir: HubPaths.baseDir()
            )
        }()
        let preferredBuiltinId = "guarded-automation"
        let canonicalRegistryItemId = AXSkillsLibrary.canonicalSupervisorSkillID(registryItem?.skillId ?? "")
        if canonicalRegistryItemId == preferredBuiltinId {
            return preferredBuiltinId
        }
        guard snapshot?.items.contains(where: {
            AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId) == preferredBuiltinId
        }) == true else {
            return nil
        }
        return preferredBuiltinId
    }

    func supervisorWorkflowSkillIDsAreCompatible(
        expectedSkillId: String,
        requestedSkillId: String
    ) -> Bool {
        let canonicalExpected = AXSkillsLibrary.canonicalSupervisorSkillID(expectedSkillId)
        let canonicalRequested = AXSkillsLibrary.canonicalSupervisorSkillID(requestedSkillId)
        guard !canonicalExpected.isEmpty, !canonicalRequested.isEmpty else { return false }
        if canonicalExpected == canonicalRequested {
            return true
        }
        return supervisorWorkflowSkillCompatibilityToken(canonicalExpected)
            == supervisorWorkflowSkillCompatibilityToken(canonicalRequested)
    }

    private func supervisorWorkflowSkillCompatibilityToken(_ canonicalSkillId: String) -> String {
        preferredBuiltinSkillCompatibilityToken(for: canonicalSkillId)
    }

    private func preferredBuiltinSkillCompatibilityToken(for canonicalSkillId: String) -> String {
        switch canonicalSkillId {
        case "agent-browser", "guarded-automation", "browser.open", "browser_open", "browser.navigate", "browser_navigate", "browser.runtime.inspect", "browser_runtime.inspect":
            return "governed_browser_automation"
        default:
            return canonicalSkillId
        }
    }

    private func resolvedGovernedDispatchPayloadValue(
        payload: [String: JSONValue],
        canonicalKey: String,
        aliases: [String]
    ) -> JSONValue? {
        let candidates = [canonicalKey] + aliases
        for candidate in candidates {
            let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            guard let value = payload[key], governedDispatchHasValue(value) else { continue }
            return value
        }
        return nil
    }

    private func enrichSupervisorSkillRunnerBindingArgsIfNeeded(
        toolName: ToolName,
        item: SupervisorSkillRegistryItem?,
        args: inout [String: JSONValue]
    ) {
        guard toolName == .skillsExecuteRunner,
              let item else {
            return
        }
        if !governedDispatchHasValue(args["skill_id"]) {
            let skillId = item.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !skillId.isEmpty {
                args["skill_id"] = .string(skillId)
            }
        }
        if !governedDispatchHasValue(args["package_sha256"]) {
            let packageSHA256 = item.packageSHA256
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !packageSHA256.isEmpty {
                args["package_sha256"] = .string(packageSHA256)
            }
        }
    }

    private func governedDispatchHasValue(_ value: JSONValue?) -> Bool {
        guard let value else { return false }
        switch value {
        case .null:
            return false
        case .string(let string):
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let array):
            return !array.isEmpty
        case .object(let object):
            return !object.isEmpty
        case .number, .bool:
            return true
        }
    }

    private func governedDispatchMissingReasonCode(for group: [String]) -> String {
        let normalized = group
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if normalized.count == 1, let first = normalized.first {
            return "payload.\(first)_missing"
        }
        return "payload.required_args_missing"
    }

    private func governedDispatchExclusiveReasonCode(for group: [String], presentCount: Int) -> String {
        let normalized = group
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let sourceGroup = Set(["url", "path", "text"])
        if Set(normalized) == sourceGroup {
            return presentCount == 0 ? "payload.source_missing" : "payload.multiple_sources"
        }
        if normalized.count == 1, let first = normalized.first {
            return "payload.\(first)_missing"
        }
        return presentCount == 0 ? "payload.required_args_missing" : "payload.mutually_exclusive_args"
    }

    private func mappedSupervisorRepoWriteFileDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let path = payload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.path_missing"))
        }
        guard let content = payload["content"]?.stringValue else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.content_missing"))
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(
                id: requestId,
                tool: .write_file,
                args: [
                    "path": .string(path),
                    "content": .string(content)
                ]
            ),
            toolName: ToolName.write_file.rawValue
        ))
    }

    private func mappedSupervisorRepoDeletePathDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let path = firstNonEmptyString(
            payload["path"]?.stringValue,
            payload["target"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !path.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.path_missing"))
        }
        var args: [String: JSONValue] = ["path": .string(path)]
        if let recursive = payload["recursive"] {
            args["recursive"] = recursive
        }
        if let force = payload["force"] {
            args["force"] = force
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .delete_path, args: args),
            toolName: ToolName.delete_path.rawValue
        ))
    }

    private func mappedSupervisorGitCommitDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let message = payload["message"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.message_missing"))
        }
        var args: [String: JSONValue] = ["message": .string(message)]
        if let all = payload["all"] {
            args["all"] = all
        }
        if let allowEmpty = payload["allow_empty"] {
            args["allow_empty"] = allowEmpty
        }
        if let paths = payload["paths"] {
            args["paths"] = paths
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .git_commit, args: args),
            toolName: ToolName.git_commit.rawValue
        ))
    }

    private func mappedSupervisorGitPushDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        var args: [String: JSONValue] = [:]
        if let remote = payload["remote"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remote.isEmpty {
            args["remote"] = .string(remote)
        }
        if let branch = payload["branch"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty {
            args["branch"] = .string(branch)
        }
        if let setUpstream = payload["set_upstream"] {
            args["set_upstream"] = setUpstream
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .git_push, args: args),
            toolName: ToolName.git_push.rawValue
        ))
    }

    private func mappedSupervisorRepoMovePathDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let fromPath = firstNonEmptyString(
            payload["from"]?.stringValue,
            payload["source"]?.stringValue,
            payload["src"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !fromPath.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.from_missing"))
        }
        guard let toPath = firstNonEmptyString(
            payload["to"]?.stringValue,
            payload["destination"]?.stringValue,
            payload["dest"]?.stringValue,
            payload["new_path"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !toPath.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.to_missing"))
        }
        var args: [String: JSONValue] = [
            "from": .string(fromPath),
            "to": .string(toPath),
        ]
        if let overwrite = payload["overwrite"] {
            args["overwrite"] = overwrite
        }
        if let createDirs = payload["create_dirs"] {
            args["create_dirs"] = createDirs
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .move_path, args: args),
            toolName: ToolName.move_path.rawValue
        ))
    }

    private func mappedSupervisorRepoCommandDispatch(
        payload: [String: JSONValue],
        requestId: String,
        profile: XTGovernedRepoCommandProfile
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let rawCommand = payload["command"]?.stringValue else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.command_missing"))
        }
        guard let command = supervisorValidatedRepoCommand(rawCommand, profile: profile) else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.command_not_allowed"))
        }
        var args: [String: JSONValue] = ["command": .string(command)]
        if let timeout = payload["timeout_sec"] {
            args["timeout_sec"] = timeout
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .run_command, args: args),
            toolName: ToolName.run_command.rawValue
        ))
    }

    private func mappedSupervisorProcessStartDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let command = payload["command"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.command_missing"))
        }
        var args: [String: JSONValue] = ["command": .string(command)]
        if let processId = firstNonEmptyString(
            payload["process_id"]?.stringValue,
            payload["id"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !processId.isEmpty {
            args["process_id"] = .string(processId)
        }
        if let name = payload["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            args["name"] = .string(name)
        }
        if let cwd = payload["cwd"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cwd.isEmpty {
            args["cwd"] = .string(cwd)
        }
        if let restartOnExit = payload["restart_on_exit"] {
            args["restart_on_exit"] = restartOnExit
        }
        if let env = payload["env"] {
            args["env"] = env
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .process_start, args: args),
            toolName: ToolName.process_start.rawValue
        ))
    }

    private func mappedSupervisorPRCreateDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        let fill: Bool = {
            guard let value = payload["fill"] else { return false }
            switch value {
            case .bool(let flag):
                return flag
            case .string(let text):
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized == "true" || normalized == "1" || normalized == "yes" || normalized == "on"
            default:
                return false
            }
        }()
        let title = payload["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard fill || !title.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.title_missing"))
        }
        var args: [String: JSONValue] = [:]
        for key in ["title", "body", "base", "head", "draft", "fill", "labels", "reviewers"] {
            if let value = payload[key] {
                args[key] = value
            }
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .pr_create, args: args),
            toolName: ToolName.pr_create.rawValue
        ))
    }

    private func mappedSupervisorCIReadDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        var args: [String: JSONValue] = ["provider": .string("github")]
        for key in ["provider", "workflow", "branch", "commit", "limit"] {
            if let value = payload[key] {
                args[key] = value
            }
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .ci_read, args: args),
            toolName: ToolName.ci_read.rawValue
        ))
    }

    private func mappedSupervisorCITriggerDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let workflow = payload["workflow"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workflow.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.workflow_missing"))
        }
        var args: [String: JSONValue] = [
            "provider": .string("github"),
            "workflow": .string(workflow),
        ]
        if let ref = payload["ref"] {
            args["ref"] = ref
        }
        if let inputs = payload["inputs"] {
            args["inputs"] = inputs
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .ci_trigger, args: args),
            toolName: ToolName.ci_trigger.rawValue
        ))
    }

    private func mappedSupervisorProcessStatusDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        var args: [String: JSONValue] = [:]
        if let processId = firstNonEmptyString(
            payload["process_id"]?.stringValue,
            payload["id"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !processId.isEmpty {
            args["process_id"] = .string(processId)
        }
        if let includeExited = payload["include_exited"] {
            args["include_exited"] = includeExited
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .process_status, args: args),
            toolName: ToolName.process_status.rawValue
        ))
    }

    private func mappedSupervisorProcessLogsDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let processId = firstNonEmptyString(
            payload["process_id"]?.stringValue,
            payload["id"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !processId.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.process_id_missing"))
        }
        var args: [String: JSONValue] = ["process_id": .string(processId)]
        if let tailLines = payload["tail_lines"] {
            args["tail_lines"] = tailLines
        }
        if let maxBytes = payload["max_bytes"] {
            args["max_bytes"] = maxBytes
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .process_logs, args: args),
            toolName: ToolName.process_logs.rawValue
        ))
    }

    private func mappedSupervisorProcessStopDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        guard let processId = firstNonEmptyString(
            payload["process_id"]?.stringValue,
            payload["id"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
        !processId.isEmpty else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.process_id_missing"))
        }
        var args: [String: JSONValue] = ["process_id": .string(processId)]
        if let force = payload["force"] {
            args["force"] = force
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .process_stop, args: args),
            toolName: ToolName.process_stop.rawValue
        ))
    }

    private func mappedSupervisorSummarizeDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        let url = payload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = payload["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = firstNonEmptyString(
            payload["text"]?.stringValue,
            payload["content"]?.stringValue,
            payload["value"]?.stringValue
        ) ?? ""
        let sourceCount = [!url.isEmpty, !path.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty].filter { $0 }.count
        guard sourceCount > 0 else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.source_missing"))
        }
        guard sourceCount == 1 else {
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.multiple_sources"))
        }

        var args: [String: JSONValue] = [:]
        if !url.isEmpty {
            args["url"] = .string(url)
        } else if !path.isEmpty {
            args["path"] = .string(path)
        } else {
            args["text"] = .string(text)
        }

        for key in ["focus", "format", "grant_id", "timeout_sec", "max_bytes", "max_chars"] {
            if let value = payload[key] {
                args[key] = value
            }
        }

        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .summarize, args: args),
            toolName: ToolName.summarize.rawValue
        ))
    }

    private func mappedSupervisorVoicePlaybackDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        var args: [String: JSONValue] = [:]
        if let action = firstNonEmptyString(
            payload["action"]?.stringValue,
            payload["operation"]?.stringValue,
            payload["mode"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !action.isEmpty {
            args["action"] = .string(action)
        }
        if let text = firstNonEmptyString(
            payload["text"]?.stringValue,
            payload["content"]?.stringValue,
            payload["value"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            args["text"] = .string(text)
        }
        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .supervisorVoicePlayback, args: args),
            toolName: ToolName.supervisorVoicePlayback.rawValue
        ))
    }

    private func mappedSupervisorAgentBrowserDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        let requestedAction = firstNonEmptyString(
            payload["action"]?.stringValue,
            payload["operation"]?.stringValue,
            payload["mode"]?.stringValue
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
        let url = payload["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sessionId = payload["session_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let action: String
        if requestedAction.isEmpty {
            if !url.isEmpty {
                action = "open_url"
            } else if !sessionId.isEmpty {
                action = "snapshot"
            } else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.action_missing"))
            }
        } else {
            action = requestedAction
        }

        switch action {
        case "open", "open_url", "navigate", "goto", "visit":
            guard !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            let runtimeAction = action == "navigate" || action == "goto" || action == "visit"
                ? "navigate"
                : "open_url"
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: mappedSupervisorAgentBrowserRuntimeArgs(
                        payload: payload,
                        action: runtimeAction
                    )
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "snapshot", "inspect":
            guard !url.isEmpty || !sessionId.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_or_session_id_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: mappedSupervisorAgentBrowserRuntimeArgs(
                        payload: payload,
                        action: "snapshot"
                    )
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "extract":
            guard !url.isEmpty || !sessionId.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_or_session_id_missing"))
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: mappedSupervisorAgentBrowserRuntimeArgs(
                        payload: payload,
                        action: "extract"
                    )
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "read", "read_page", "read-page", "fetch":
            guard !url.isEmpty else {
                return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.url_missing"))
            }
            var args: [String: JSONValue] = ["url": .string(url)]
            for key in ["grant_id", "timeout_sec", "max_bytes"] {
                if let value = payload[key] {
                    args[key] = value
                }
            }
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(id: requestId, tool: .browser_read, args: args),
                toolName: ToolName.browser_read.rawValue
            ))
        case "click", "tap":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: mappedSupervisorAgentBrowserRuntimeArgs(
                        payload: payload,
                        action: "click"
                    )
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "type", "fill", "input", "enter":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: mappedSupervisorAgentBrowserRuntimeArgs(
                        payload: payload,
                        action: "type"
                    )
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        case "upload", "attach":
            return .success(SupervisorMappedSkillDispatch(
                toolCall: ToolCall(
                    id: requestId,
                    tool: .deviceBrowserControl,
                    args: mappedSupervisorAgentBrowserRuntimeArgs(
                        payload: payload,
                        action: "upload"
                    )
                ),
                toolName: ToolName.deviceBrowserControl.rawValue
            ))
        default:
            return .failure(SupervisorSkillMappingFailure(reasonCode: "payload.action_unsupported"))
        }
    }

    private func mappedSupervisorAgentBrowserRuntimeArgs(
        payload: [String: JSONValue],
        action: String
    ) -> [String: JSONValue] {
        var args: [String: JSONValue] = ["action": .string(action)]
        for key in [
            "url",
            "session_id",
            "selector",
            "field_role",
            "text",
            "content",
            "value",
            "secret_item_id",
            "secret_scope",
            "secret_name",
            "secret_project_id",
            "path",
            "grant_id",
            "timeout_sec",
            "max_bytes",
        ] {
            if let value = payload[key] {
                args[key] = value
            }
        }
        return args
    }

    private func mappedSupervisorSelfImprovingAgentDispatch(
        payload: [String: JSONValue],
        requestId: String
    ) -> Result<SupervisorMappedSkillDispatch, SupervisorSkillMappingFailure> {
        var args: [String: JSONValue] = [
            "mode": .string(XTMemoryUseMode.supervisorOrchestration.rawValue),
            "retrospective": .bool(true)
        ]

        if let focus = firstNonEmptyString(
            payload["focus"]?.stringValue,
            payload["goal"]?.stringValue,
            payload["topic"]?.stringValue
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !focus.isEmpty {
            args["focus"] = .string(focus)
        }

        if let value = payload["limit"] ?? payload["max_results"] ?? payload["top_n"] {
            args["limit"] = value
        }

        for key in [
            "project_id",
            "include_doctor",
            "include_incidents",
            "include_skill_calls",
            "include_plan",
            "include_memory",
        ] {
            if let value = payload[key] {
                args[key] = value
            }
        }

        return .success(SupervisorMappedSkillDispatch(
            toolCall: ToolCall(id: requestId, tool: .memory_snapshot, args: args),
            toolName: ToolName.memory_snapshot.rawValue
        ))
    }

    private func supervisorValidatedRepoCommand(
        _ raw: String,
        profile: XTGovernedRepoCommandProfile
    ) -> String? {
        xtValidateGovernedRepoCommand(raw, profile: profile)
    }

    func firstNonEmptyString(_ values: String?...) -> String? {
        for value in values {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    func supervisorSkillMappingFailureSummary(_ failure: SupervisorSkillMappingFailure) -> String {
        switch failure.reasonCode {
        case "payload.command_not_allowed":
            return "repo command rejected by governed allowlist"
        case "payload.command_missing":
            return "payload.command missing"
        case "payload.action_missing":
            return "payload.action missing"
        case "payload.action_unsupported":
            return "unsupported browser action requested"
        case "payload.content_missing":
            return "payload.content missing"
        case "payload.patch_missing":
            return "payload.patch missing"
        case "payload.path_missing":
            return "payload.path missing"
        case "payload.query_missing":
            return "payload.query missing"
        case "payload.source_missing":
            return "payload source missing"
        case "payload.multiple_sources":
            return "multiple payload sources provided"
        case "payload.url_missing":
            return "payload.url missing"
        case "payload.url_or_session_id_missing":
            return "payload.url or payload.session_id missing"
        default:
            return "skill mapping unavailable"
        }
    }

    func supervisorSkillMappingFailureMessage(
        displaySkill: String,
        failure: SupervisorSkillMappingFailure
    ) -> String {
        switch failure.reasonCode {
        case "unsupported_skill_id":
            return "❌ CALL_SKILL 失败：技能 \(displaySkill) 还没有接到受治理 runtime（skill_mapping_missing）"
        case "payload.command_not_allowed":
            return "❌ CALL_SKILL 失败：技能 \(displaySkill) 请求的命令不在受治理 allowlist 内（payload.command_not_allowed）"
        default:
            return "❌ CALL_SKILL 失败：技能 \(displaySkill) payload 校验失败（\(failure.reasonCode)）"
        }
    }
}
