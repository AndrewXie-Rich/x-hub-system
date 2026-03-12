import SwiftUI

struct ProjectSettingsView: View {
    let ctx: AXProjectContext

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = HubModelManager.shared
    @State private var trustedAutomationDeviceIdDraft: String = ""
    @State private var governedReadableRootsDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Project Settings")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }

            Text(ctx.projectName())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            GroupBox("Per-Project Model Routing") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("每个角色可选择不同模型；留空 = 使用全局 Settings。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !appModel.hubInteractive {
                        Text("Hub 未连接，无法读取可用模型列表。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if modelOptions().isEmpty {
                        Text("Hub 暂无可用模型。请在 Hub 中注册/加载模型，或配置付费模型后再试。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(AXRole.allCases) { role in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(roleLabel(role))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 90, alignment: .leading)

                            Picker("", selection: bindingForRole(role)) {
                                Text("使用全局设置").tag("")
                                ForEach(modelOptions()) { opt in
                                    Text(opt.label).tag(opt.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 380, alignment: .leading)
                            .disabled(!appModel.hubInteractive)

                            if let g = globalModelId(role), !g.isEmpty {
                                Text("全局：\(g)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("全局：自动路由")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(8)
            }

            hubMemorySection
            automationSelfIterateSection
            autonomyPolicySection
            trustedAutomationSection

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            modelManager.setAppModel(appModel)
            trustedAutomationDeviceIdDraft = appModel.projectConfig?.trustedAutomationDeviceId ?? ""
            governedReadableRootsDraft = governedReadableRootsText(appModel.projectConfig?.governedReadableRoots ?? [])
            Task {
                await modelManager.fetchModels()
            }
        }
        .onChange(of: appModel.hubInteractive) { connected in
            if connected {
                Task {
                    await modelManager.fetchModels()
                }
            }
        }
        .onChange(of: appModel.projectConfig?.trustedAutomationDeviceId ?? "") { value in
            trustedAutomationDeviceIdDraft = value
        }
        .onChange(of: governedReadableRootsText(appModel.projectConfig?.governedReadableRoots ?? [])) { value in
            governedReadableRootsDraft = value
        }
    }

    private func bindingForRole(_ role: AXRole) -> Binding<String> {
        Binding(
            get: {
                appModel.projectConfig?.modelOverride(for: role) ?? ""
            },
            set: { v in
                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                appModel.setProjectRoleModel(role: role, modelId: trimmed.isEmpty ? nil : trimmed)
            }
        )
    }

    private func globalModelId(_ role: AXRole) -> String? {
        appModel.settingsStore.settings.assignment(for: role).model
    }

    private var hubMemorySection: some View {
        let preferHubMemory = appModel.projectConfig?.preferHubMemory ?? true
        let mode = XTProjectMemoryGovernance.modeLabel(appModel.projectConfig)

        return GroupBox("Hub Memory Governance") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Prefer Hub memory for this project",
                    isOn: Binding(
                        get: { appModel.projectConfig?.preferHubMemory ?? true },
                        set: { appModel.setProjectHubMemoryPreference(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)

                Text("default: on · mode: \(mode)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(preferHubMemory
                     ? "开启后：X-Terminal 会优先用 Hub memory 组装 prompt，并继续保留本地 `.xterminal/AX_MEMORY.md` / `recent_context.json` 作为 continuity/fallback 层。Hub 侧 X-宪章、remote export gate、skills revoked gate、kill-switch 会参与约束。"
                     : "关闭后：当前项目只使用本地 `.xterminal/AX_MEMORY.md` / `recent_context.json` 组装 prompt，不请求 Hub memory context。适合离线或临时隔离场景。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("注意：当前实现仍保留本地 memory 文件用于崩溃恢复与 fallback，所以这还不是单一 Hub 真源；这里只控制 prompt 组装时是否优先走 Hub。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var trustedAutomationSection: some View {
        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let readiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let status = config.trustedAutomationStatus(forProjectRoot: ctx.root, permissionReadiness: readiness)
        let expectedHash = xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        let deviceGroups = status.deviceToolGroups.isEmpty
            ? (status.mode == .trustedAutomation ? xtTrustedAutomationDefaultDeviceToolGroups() : [])
            : status.deviceToolGroups
        let requirementStatuses = readiness.requirementStatuses(
            forDeviceToolGroups: status.mode == .trustedAutomation ? deviceGroups : []
        )
        let repairActions = readiness.suggestedOpenSettingsActions(
            forDeviceToolGroups: status.mode == .trustedAutomation ? deviceGroups : []
        )

        return GroupBox("Trusted Automation") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: trustedAutomationIcon(status.state))
                        .foregroundStyle(trustedAutomationColor(status.state))
                    Text("state: \(status.state.rawValue)")
                        .font(.headline)

                    Spacer()

                    Text("mode: \(status.mode.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("这是一条 project 级绑定，不等于把整个 X-Terminal 永久全开；`Full` 也不等于 `trusted_automation`。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Paired Device ID")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120, alignment: .leading)

                    TextField("device_xt_001", text: $trustedAutomationDeviceIdDraft)
                        .textFieldStyle(.roundedBorder)

                    Button("Arm Current Project") {
                        saveTrustedAutomationBinding(armed: true)
                    }
                    .disabled(trustedAutomationDeviceIdDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Turn Off") {
                        saveTrustedAutomationBinding(armed: false)
                    }
                }

                Text("workspace_binding_hash: \(expectedHash)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("device_tool_groups: \(deviceGroups.isEmpty ? "(none)" : deviceGroups.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                Text("permission_owner: overall=\(readiness.overallState) · install=\(readiness.installState) · can_prompt_user=\(readiness.canPromptUser ? "yes" : "no")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("required_permissions: \(requirementStatuses.isEmpty ? "(none)" : requirementStatuses.map { $0.key.rawValue }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if requirementStatuses.isEmpty {
                    Text("permission_requirements: none")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(requirementStatuses) { requirement in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(requirement.displayName)
                                        .font(.caption.weight(.semibold))
                                    Text(requirement.status.rawValue)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(trustedAutomationPermissionColor(requirement.status))
                                    Spacer()
                                    Text(requirement.requiredByDeviceToolGroups.joined(separator: ", "))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Text(requirement.rationale)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if status.missingPrerequisites.isEmpty {
                    Text("missing_prerequisites: none")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("missing_prerequisites: \(status.missingPrerequisites.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    ForEach(repairActions, id: \.self) { action in
                        Button(XTSystemSettingsLinks.label(forOpenSettingsAction: action)) {
                            XTSystemSettingsLinks.openPrivacyAction(action)
                        }
                    }

                    Button("Open System Settings") {
                        XTSystemSettingsLinks.openSystemSettings()
                    }

                    Spacer()
                }
            }
            .padding(8)
        }
    }

    private var autonomyPolicySection: some View {
        let config = appModel.projectConfig ?? .default(forProjectRoot: ctx.root)
        let effective = appModel.resolvedProjectAutonomyPolicy(config: config)
        let selectedMode = config.autonomyMode
        let configuredDeviceAuthority = config.automationMode == .trustedAutomation
            && config.autonomyMode == .trustedOpenClawMode
            && config.autonomyAllowDeviceTools
        let effectiveDeviceAuthority = effective.effectiveMode == .trustedOpenClawMode
            && effective.allowDeviceTools
            && config.automationMode == .trustedAutomation
            && !config.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && config.workspaceBindingHash == xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        let configuredSurfaceText = configuredAutonomySurfaceText(config)
        let effectiveSurfaceText = effective.allowedSurfaceLabels.isEmpty ? "(none)" : effective.allowedSurfaceLabels.joined(separator: ", ")
        let updatedAtText = config.autonomyUpdatedAtDate.map { autonomyTimestampFormatter.string(from: $0) } ?? "(never armed)"
        let hubOverrideUpdatedAtText: String = {
            guard effective.remoteOverrideUpdatedAtMs > 0 else { return "(none)" }
            let date = Date(timeIntervalSince1970: TimeInterval(effective.remoteOverrideUpdatedAtMs) / 1000.0)
            return autonomyTimestampFormatter.string(from: date)
        }()

        return GroupBox("Autonomy Policy") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Enable governed device authority for this project",
                    isOn: Binding(
                        get: { configuredDeviceAuthority },
                        set: { setGovernedDeviceAuthority(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)

                Text(configuredDeviceAuthority
                     ? "开启后：当前 project 会进入 trusted_openclaw_mode，并尝试 arm trusted automation。Supervisor 会继承同一个 project 的 governed device authority。"
                     : "关闭后：当前 project 会回到 manual，并停用 trusted automation 绑定；浏览器/device/connector/extension 四类自治面全部回收。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("device_authority: configured=\(configuredDeviceAuthority ? "on" : "off") · effective=\(effectiveDeviceAuthority ? "on" : "off") · paired_device=\(trustedAutomationDeviceIdDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(missing)" : trustedAutomationDeviceIdDraft)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Preset")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.projectConfig?.autonomyMode ?? .manual },
                            set: { appModel.setProjectAutonomyPolicy(mode: $0) }
                        )
                    ) {
                        ForEach(AXProjectAutonomyMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260, alignment: .leading)

                    Spacer()

                    Text("effective: \(effective.effectiveMode.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(alignment: .top, spacing: 16) {
                    Toggle(
                        "Allow browser runtime",
                        isOn: Binding(
                            get: { appModel.projectConfig?.autonomyAllowBrowserRuntime ?? false },
                            set: { appModel.setProjectAutonomyPolicy(allowBrowserRuntime: $0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(selectedMode == .manual)

                    Toggle(
                        "Allow device tools",
                        isOn: Binding(
                            get: { appModel.projectConfig?.autonomyAllowDeviceTools ?? false },
                            set: { appModel.setProjectAutonomyPolicy(allowDeviceTools: $0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(selectedMode != .trustedOpenClawMode)
                }

                HStack(alignment: .top, spacing: 16) {
                    Toggle(
                        "Allow connector actions",
                        isOn: Binding(
                            get: { appModel.projectConfig?.autonomyAllowConnectorActions ?? false },
                            set: { appModel.setProjectAutonomyPolicy(allowConnectorActions: $0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(selectedMode != .trustedOpenClawMode)

                    Toggle(
                        "Allow extensions",
                        isOn: Binding(
                            get: { appModel.projectConfig?.autonomyAllowExtensions ?? false },
                            set: { appModel.setProjectAutonomyPolicy(allowExtensions: $0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(selectedMode != .trustedOpenClawMode)
                }

                Stepper(
                    value: Binding(
                        get: { max(5, (appModel.projectConfig?.autonomyTTLSeconds ?? 3600) / 60) },
                        set: { appModel.setProjectAutonomyPolicy(ttlSeconds: max(5, $0) * 60) }
                    ),
                    in: 5...1440,
                    step: 5
                ) {
                    Text("Autonomy TTL: \((config.autonomyTTLSeconds / 60)) min")
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Terminal Clamp")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120, alignment: .leading)

                    Picker(
                        "",
                        selection: Binding(
                            get: { appModel.projectConfig?.autonomyHubOverrideMode ?? AXProjectAutonomyHubOverrideMode.none },
                            set: { appModel.setProjectAutonomyPolicy(hubOverrideMode: $0) }
                        )
                    ) {
                        ForEach(AXProjectAutonomyHubOverrideMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260, alignment: .leading)

                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Hub Clamp")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120, alignment: .leading)

                    Text(effective.remoteOverrideMode.displayName)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()
                }

                Text("configured_surfaces: \(configuredSurfaceText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("effective_surfaces: \(effectiveSurfaceText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("ttl_remaining: \(autonomyRemainingText(config: config, effective: effective)) · updated_at: \(updatedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("hub_override_source: \(effective.remoteOverrideSource.isEmpty ? "(none)" : effective.remoteOverrideSource) · hub_override_updated_at: \(hubOverrideUpdatedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Governed Extra Read Roots")
                        .font(.caption.weight(.semibold))

                    TextEditor(text: $governedReadableRootsDraft)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )

                    HStack(spacing: 8) {
                        Button("Save Read Roots") {
                            saveGovernedReadableRoots()
                        }

                        Button("Add Parent Folder") {
                            appendGovernedReadableRootSuggestion(ctx.root.deletingLastPathComponent())
                        }

                        Button("Add Grandparent Folder") {
                            appendGovernedReadableRootSuggestion(ctx.root.deletingLastPathComponent().deletingLastPathComponent())
                        }

                        Button("Clear") {
                            governedReadableRootsDraft = ""
                            saveGovernedReadableRoots()
                        }

                        Spacer()
                    }

                    Text("每行一个路径；支持绝对路径，也支持相对当前 project root 的路径。这里只扩展 `read_file` / `list_dir` / `search(path=...)`，不会放开 project 外的 `write_file` / `run_command`。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("effective_read_roots: \(effectiveGovernedReadableRootsText(config: config, effective: effective))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("Terminal Clamp 和 Hub Clamp 会按更严格的一侧合并，最终执行面始终 fail-closed。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(autonomyExplanation(config: config, effective: effective))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var automationSelfIterateSection: some View {
        let enabled = appModel.projectConfig?.automationSelfIterateEnabled ?? false
        let maxDepth = appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2
        let recipeRef = appModel.projectConfig?.activeAutomationRecipeRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return GroupBox("Automation Self-Iteration") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Enable bounded self-iterate auto retry",
                    isOn: Binding(
                        get: { appModel.projectConfig?.automationSelfIterateEnabled ?? false },
                        set: { appModel.setProjectAutomationSelfIteration(enabled: $0) }
                    )
                )
                .toggleStyle(.switch)

                Stepper(
                    value: Binding(
                        get: { appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2 },
                        set: { appModel.setProjectAutomationSelfIteration(maxAutoRetryDepth: $0) }
                    ),
                    in: 1...8
                ) {
                    Text("Max Auto Retry Depth: \(maxDepth)")
                }

                Text("current_mode: \(enabled ? "enabled" : "disabled") · active_recipe: \(recipeRef.isEmpty ? "(none)" : recipeRef)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("当前实现是受控的证据驱动自动重试，不会自动改 recipe、patch 或 planner。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func roleLabel(_ role: AXRole) -> String {
        switch role {
        case .coder: return "coder"
        case .coarse: return "coarse"
        case .refine: return "refine"
        case .reviewer: return "reviewer"
        case .advisor: return "advisor"
        case .supervisor: return "supervisor"
        }
    }

    private func modelOptions() -> [ModelOption] {
        var dedup: [String: HubModel] = [:]
        let source = modelManager.availableModels.isEmpty ? appModel.modelsState.models : modelManager.availableModels
        for model in source {
            dedup[model.id] = model
        }
        let models = Array(dedup.values)
        if models.isEmpty { return [] }
        let sorted = models.sorted { a, b in
            let sa = stateRank(a.state)
            let sb = stateRank(b.state)
            if sa != sb { return sa < sb }
            let na = (a.name.isEmpty ? a.id : a.name).lowercased()
            let nb = (b.name.isEmpty ? b.id : b.name).lowercased()
            if na != nb { return na < nb }
            return a.id.lowercased() < b.id.lowercased()
        }
        return sorted.map { m in
            let name = m.name.isEmpty ? m.id : m.name
            let st = stateText(m.state)
            let backend = m.backend.isEmpty ? "" : " · \(m.backend)"
            let remote = isRemote(m)
            let origin = remote ? "Remote" : "Local"
            return ModelOption(id: m.id, label: "\(name) · \(origin) · \(m.id) · \(st)\(backend)")
        }
    }

    private func isRemote(_ m: HubModel) -> Bool {
        let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !mp.isEmpty { return false }
        return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available: return 1
        case .sleeping: return 2
        }
    }

    private func stateText(_ s: HubModelState) -> String {
        switch s {
        case .loaded: return "已加载"
        case .available: return "可用"
        case .sleeping: return "休眠"
        }
    }

    private func saveTrustedAutomationBinding(armed: Bool) {
        let deviceId = trustedAutomationDeviceIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode: AXProjectAutomationMode = armed ? .trustedAutomation : .standard
        appModel.setProjectTrustedAutomationBinding(
            mode: mode,
            deviceId: deviceId,
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        )
    }

    private func setGovernedDeviceAuthority(enabled: Bool) {
        if enabled {
            if (appModel.projectConfig?.governedReadableRoots ?? []).isEmpty {
                let bootstrapRoots = bootstrapGovernedReadableRoots()
                if !bootstrapRoots.isEmpty {
                    appModel.setProjectGovernedReadableRoots(paths: bootstrapRoots)
                    governedReadableRootsDraft = governedReadableRootsText(bootstrapRoots)
                }
            }
            appModel.setProjectAutonomyPolicy(mode: .trustedOpenClawMode)
            saveTrustedAutomationBinding(armed: true)
        } else {
            appModel.setProjectAutonomyPolicy(mode: .manual)
            saveTrustedAutomationBinding(armed: false)
        }
    }

    private func saveGovernedReadableRoots() {
        let roots = governedReadableRootsDraft
            .split(whereSeparator: { $0.isNewline })
            .map { String($0) }
        appModel.setProjectGovernedReadableRoots(paths: roots)
    }

    private func appendGovernedReadableRootSuggestion(_ url: URL) {
        let path = PathGuard.resolve(url).path
        guard path != PathGuard.resolve(ctx.root).path else { return }
        guard path != "/" else { return }

        var lines = governedReadableRootsDraft
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !lines.contains(path) {
            lines.append(path)
            governedReadableRootsDraft = governedReadableRootsText(lines)
        }
    }

    private func bootstrapGovernedReadableRoots() -> [String] {
        var roots: [String] = []
        appendBootstrapRoot(ctx.root.deletingLastPathComponent(), into: &roots)
        appendBootstrapRoot(ctx.root.deletingLastPathComponent().deletingLastPathComponent(), into: &roots)
        return roots
    }

    private func appendBootstrapRoot(_ url: URL, into roots: inout [String]) {
        let path = PathGuard.resolve(url).path
        guard path != PathGuard.resolve(ctx.root).path else { return }
        guard path != "/" else { return }
        guard !roots.contains(path) else { return }
        roots.append(path)
    }

    private func trustedAutomationIcon(_ state: AXTrustedAutomationProjectState) -> String {
        switch state {
        case .off:
            return "bolt.slash.circle"
        case .armed:
            return "bolt.badge.clock"
        case .active:
            return "bolt.shield.fill"
        case .blocked:
            return "exclamationmark.shield.fill"
        }
    }

    private func trustedAutomationColor(_ state: AXTrustedAutomationProjectState) -> Color {
        switch state {
        case .off:
            return .secondary
        case .armed:
            return .orange
        case .active:
            return .green
        case .blocked:
            return .red
        }
    }

    private func trustedAutomationPermissionColor(_ status: AXTrustedAutomationPermissionStatus) -> Color {
        switch status {
        case .granted:
            return .green
        case .missing:
            return .orange
        case .denied:
            return .red
        case .managed:
            return .blue
        }
    }

    private func configuredAutonomySurfaceText(_ config: AXProjectConfig) -> String {
        let labels = config.configuredAutonomySurfaceLabels
        return labels.isEmpty ? "(none)" : labels.joined(separator: ", ")
    }

    private func governedReadableRootsText(_ roots: [String]) -> String {
        roots.joined(separator: "\n")
    }

    private func effectiveGovernedReadableRootsText(
        config: AXProjectConfig,
        effective: AXProjectAutonomyEffectivePolicy
    ) -> String {
        let authorityOn = effective.effectiveMode == .trustedOpenClawMode
            && effective.allowDeviceTools
            && config.automationMode == .trustedAutomation
            && !config.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && config.workspaceBindingHash == xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        var roots = [PathGuard.resolve(ctx.root).path]
        if authorityOn {
            roots.append(contentsOf: config.governedReadableRoots)
        }
        return roots.joined(separator: ", ")
    }

    private func autonomyRemainingText(
        config: AXProjectConfig,
        effective: AXProjectAutonomyEffectivePolicy
    ) -> String {
        if effective.killSwitchEngaged {
            return "kill_switch"
        }
        if effective.expired {
            return "expired"
        }
        if config.autonomyMode == .manual {
            return "n/a"
        }
        let minutes = max(1, (effective.remainingSeconds + 59) / 60)
        return "\(minutes)m"
    }

    private func autonomyExplanation(
        config: AXProjectConfig,
        effective: AXProjectAutonomyEffectivePolicy
    ) -> String {
        if effective.killSwitchEngaged {
            if effective.remoteOverrideMode == .killSwitch {
                return "当前 Hub kill-switch 已生效：device/browser/connector/extension 四类执行面全部 fail-closed。"
            }
            return "当前 kill-switch 已生效：device/browser/connector/extension 四类执行面全部 fail-closed。"
        }
        if effective.expired {
            return "当前自治 TTL 已过期，项目已自动回收到 manual；如需继续放开，需要重新显式授权。"
        }
        if effective.hubOverrideMode == .clampManual {
            if effective.remoteOverrideMode == .clampManual {
                return "当前 Hub clamp_manual 已把项目压回 manual。项目里的自治偏好仍会保留，但执行面不会放行。"
            }
            return "当前 clamp_manual 已把项目压回 manual。项目里的自治偏好仍会保留，但执行面不会放行。"
        }
        if effective.hubOverrideMode == .clampGuided,
           config.autonomyMode == .trustedOpenClawMode,
           effective.effectiveMode == .guided {
            if effective.remoteOverrideMode == .clampGuided {
                return "当前 Hub clamp_guided 已把 trusted_openclaw_mode 压回 guided，只保留浏览器 runtime 这条受控面。"
            }
            return "当前 clamp_guided 已把 trusted_openclaw_mode 压回 guided，只保留浏览器 runtime 这条受控面。"
        }
        switch effective.effectiveMode {
        case .manual:
            return "manual 是最保守档位：device/browser runtime/connector/extension 四类自治面全部关闭。"
        case .guided:
            return "guided 是中间档位：当前只允许浏览器 runtime，设备级动作、connector side effect 和扩展继续 fail-closed。"
        case .trustedOpenClawMode:
            return "trusted_openclaw_mode 会按上面的 surface 开关放行，但仍继续受 trusted automation、tool policy、Hub memory 治理、Hub 宪章和 kill-switch 共同约束。"
        }
    }

    private struct ModelOption: Identifiable {
        let id: String
        let label: String
    }

    private var autonomyTimestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
