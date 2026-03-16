import SwiftUI

struct SupervisorSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var supervisorManager = SupervisorManager.shared
    @State private var selectedProjectId: String?
    @State private var selectedRole: AXRole = .coder
    @State private var showProjectModelPicker = false
    @State private var wakeTriggerWordsDraft: String = ""
    @State private var supervisorPromptDraft: SupervisorPromptPreferences = .default()
    @State private var voiceDiagnosticsExpanded: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                promptPersonalitySection
                heartbeatPolicySection
                voiceRuntimeSection

                Divider()

                if appModel.sortedProjects.isEmpty {
                    Text("没有项目。请先创建或打开一个项目。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    modelAssignmentArea
                        .frame(minHeight: 420)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            modelManager.setAppModel(appModel)
            syncWakeTriggerWordsDraft()
            syncSupervisorPromptDraft()
            Task {
                await modelManager.fetchModels()
            }
        }
        .onChange(of: appModel.settingsStore.settings.supervisorPrompt) { _ in
            syncSupervisorPromptDraft()
        }
        .onChange(of: supervisorManager.voiceWakeProfileSnapshot.generatedAtMs) { _ in
            if wakeTriggerWordsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                syncWakeTriggerWordsDraft()
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Supervisor 设置")
                    .font(.title2)
                Spacer()
                
                Button("刷新模型列表") {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Text("在这里可以为各个项目分配不同的 AI 模型。Supervisor 可以根据项目需求为不同角色（编程助手、代码审查等）指定合适的模型。")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("如果某台 paired Terminal 需要更大的或更小的本地 context length，请在 Hub 的设备编辑页调整该设备的 local model override；这里显示的是 Hub catalog 默认值。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var modelAssignmentArea: some View {
        HSplitView {
            projectList
            
            Divider()
            
            modelAssignmentPanel
        }
    }

    private var heartbeatPolicySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heartbeat 升级策略")
                .font(.headline)

            Stepper(
                value: Binding(
                    get: { supervisorManager.blockerEscalationThreshold },
                    set: { supervisorManager.setBlockerEscalationThreshold($0) }
                ),
                in: 1...20
            ) {
                Text("阻塞连续 N 次升级提醒：\(supervisorManager.blockerEscalationThreshold)")
            }

            Stepper(
                value: Binding(
                    get: { supervisorManager.blockerEscalationCooldownMinutes },
                    set: { supervisorManager.setBlockerEscalationCooldownMinutes($0) }
                ),
                in: 1...240
            ) {
                Text("升级提醒冷却：\(supervisorManager.blockerEscalationCooldownMinutes) 分钟")
            }

            HStack {
                Text("默认值：3 次 / 15 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") {
                    supervisorManager.resetBlockerEscalationPolicyToDefaults()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var promptPersonalitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prompt Personality")
                    .font(.headline)
                Spacer()
                Button("保存人格设置") {
                    saveSupervisorPromptDraft()
                }
                .buttonStyle(.borderedProminent)

                Button("恢复默认") {
                    resetSupervisorPromptDefaults()
                }
                .buttonStyle(.bordered)
            }

            Text("这里控制 Supervisor 的身份名、角色描述、语气补充和附加 system prompt。身份名会影响本地直答；语气补充和附加 prompt 会进入远端推理系统提示词。不要在这里写入密钥或敏感信息。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Identity Name")
                        .font(.caption.weight(.semibold))
                    TextField("Supervisor", text: $supervisorPromptDraft.identityName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Role Summary")
                        .font(.caption.weight(.semibold))
                    TextField(
                        "Supervisor AI for project orchestration, model routing, and execution coordination.",
                        text: $supervisorPromptDraft.roleSummary
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tone Directives")
                    .font(.caption.weight(.semibold))
                Text("每行一条，补充你希望 Supervisor 保持的说话风格，例如“直接回答，不绕弯”“必要时指出风险，不要太像客服”。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextEditor(text: $supervisorPromptDraft.toneDirectives)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 76)
                    .padding(6)
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Extra System Prompt")
                    .font(.caption.weight(.semibold))
                Text("附加到 system prompt 末尾，适合放高层行为约束或团队内部风格要求。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextEditor(text: $supervisorPromptDraft.extraSystemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var voiceRuntimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Voice Runtime")
                    .font(.headline)
                Spacer()
                Button("Refresh Voice Runtime") {
                    supervisorManager.refreshVoiceRuntimeStatus()
                }
                .buttonStyle(.bordered)
            }

            Text("Configure the local voice route, FunASR sidecar endpoint, and current runtime readiness. High-risk authorization still remains fail-closed on the Hub path.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Picker("Preferred Route", selection: voicePreferredRouteBinding) {
                    ForEach(VoicePreferredRoute.allCases) { route in
                        Text(route.id).tag(route)
                    }
                }
                .pickerStyle(.menu)

                Picker("Wake Mode", selection: voiceWakeModeBinding) {
                    ForEach(VoiceWakeMode.allCases) { mode in
                        Text(mode.id).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("Auto Report", selection: voiceAutoReportModeBinding) {
                    ForEach(VoiceAutoReportMode.allCases) { mode in
                        Text(mode.id).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                Picker("Voice Persona", selection: voicePersonaBinding) {
                    ForEach(VoicePersonaPreset.allCases) { persona in
                        Text(persona.displayName).tag(persona)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Interrupt On Speech", isOn: voiceInterruptOnSpeechBinding)
                    .toggleStyle(.switch)
            }

            Toggle("Enable FunASR Sidecar", isOn: funASREnabledBinding)
                .toggleStyle(.switch)

            HStack(spacing: 12) {
                TextField("FunASR WebSocket URL", text: funASRWebSocketURLBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("Healthcheck URL (optional)", text: funASRHealthcheckURLBinding)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Toggle("Wake Events Enabled", isOn: funASRWakeEnabledBinding)
                    .toggleStyle(.switch)
                Toggle("Partial Transcript Enabled", isOn: funASRPartialsEnabledBinding)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Wake Trigger Words")
                    .font(.caption.weight(.semibold))
                Text("Hub owns one normalized trigger list for paired devices, while local enable/disable and permissions stay device-specific. XT can edit a local override, then push or resync against the Hub pair-sync truth source.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("x hub, supervisor", text: $wakeTriggerWordsDraft)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 10) {
                    Button("Apply Local Override") {
                        supervisorManager.updateVoiceWakeTriggerWords(wakeTriggerWordsDraft)
                        syncWakeTriggerWordsDraft()
                    }
                    .buttonStyle(.bordered)

                    Button("Restore Defaults") {
                        supervisorManager.restoreDefaultVoiceWakeTriggerWords()
                        syncWakeTriggerWordsDraft()
                    }
                    .buttonStyle(.bordered)

                    Button("Push To Hub") {
                        supervisorManager.pushVoiceWakeProfileToHub()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Resync From Hub") {
                        supervisorManager.resyncVoiceWakeProfile()
                    }
                    .buttonStyle(.bordered)
                }
                Text("Normalization: trim + dedupe, empty falls back to defaults, max \(VoiceWakeProfile.maxTriggerCount) triggers, max \(VoiceWakeProfile.maxTriggerLength) chars each.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    supervisorManager.voiceReadinessSnapshot.overallSummary,
                    systemImage: supervisorManager.voiceReadinessSnapshot.overallState.iconName
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(supervisorManager.voiceReadinessSnapshot.overallState.tint)
                Text("Readiness State: \(supervisorManager.voiceReadinessSnapshot.overallState.rawValue)")
                    .font(.caption)
                if !supervisorManager.voiceReadinessSnapshot.primaryReasonCode.isEmpty {
                    Text("Primary Reason: \(supervisorManager.voiceReadinessSnapshot.primaryReasonCode)")
                        .font(.caption)
                }
                Text("Current Route: \(supervisorManager.voiceRouteDecision.route.rawValue)")
                    .font(.caption)
                Text("Voice Persona: \(appModel.settingsStore.settings.voice.persona.displayName)")
                    .font(.caption)
                Text("Reason: \(supervisorManager.voiceRouteDecision.reasonCode)")
                    .font(.caption)
                Text("Authorization: \(supervisorManager.voiceAuthorizationStatus.rawValue)")
                    .font(.caption)
                Text("Session State: \(supervisorManager.voiceRuntimeState.state.rawValue)")
                    .font(.caption)
                Text("Interrupt On Speech: \(appModel.settingsStore.settings.voice.interruptOnSpeech ? "enabled" : "disabled")")
                    .font(.caption)
                Text("Wake Profile Sync: \(supervisorManager.voiceWakeProfileSnapshot.syncState.rawValue)")
                    .font(.caption)
                Text("Desired Wake Mode: \(supervisorManager.voiceWakeProfileSnapshot.desiredWakeMode.rawValue)")
                    .font(.caption)
                Text("Effective Wake Mode: \(supervisorManager.voiceWakeProfileSnapshot.effectiveWakeMode.rawValue)")
                    .font(.caption)
                Text("Wake Profile Source: \(supervisorManager.voiceWakeProfileSnapshot.profileSource?.rawValue ?? "none")")
                    .font(.caption)
                Text("Wake Profile Reason: \(supervisorManager.voiceWakeProfileSnapshot.reasonCode)")
                    .font(.caption)
                if !supervisorManager.voiceWakeProfileSnapshot.triggerWords.isEmpty {
                    Text("Wake Trigger Words: \(supervisorManager.voiceWakeProfileSnapshot.triggerWords.joined(separator: ", "))")
                        .font(.caption)
                }
                if let remoteReason = supervisorManager.voiceWakeProfileSnapshot.lastRemoteReasonCode, !remoteReason.isEmpty {
                    Text("Wake Sync Remote Reason: \(remoteReason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Wake Capability: \(supervisorManager.voiceRouteDecision.wakeCapability)")
                    .font(.caption)
                Text("Engine Health: funasr=\(supervisorManager.voiceRouteDecision.funasrHealth.rawValue), whisperkit=\(supervisorManager.voiceRouteDecision.whisperKitHealth.rawValue), system=\(supervisorManager.voiceRouteDecision.systemSpeechHealth.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !supervisorManager.voiceActiveHealthReasonCode.isEmpty {
                    Text("Engine Reason: \(supervisorManager.voiceActiveHealthReasonCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)

            DisclosureGroup(isExpanded: $voiceDiagnosticsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if !supervisorManager.voiceReadinessSnapshot.orderedFixes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ordered Fixes")
                                .font(.caption.weight(.semibold))
                            ForEach(supervisorManager.voiceReadinessSnapshot.orderedFixes, id: \.self) { fix in
                                Text("• \(fix)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }

                    if !supervisorManager.voiceReadinessSnapshot.checks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Voice Readiness Checks")
                                .font(.caption.weight(.semibold))
                            ForEach(supervisorManager.voiceReadinessSnapshot.checks) { check in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(check.kind.title)
                                            .font(.caption.weight(.semibold))
                                        Spacer()
                                        Text(check.state.rawValue)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(check.state.tint)
                                    }
                                    Text(check.headline)
                                        .font(.caption)
                                    Text("reason=\(check.reasonCode)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }

                    if let snapshot = supervisorManager.voiceFunASRSidecarHealth {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FunASR Sidecar")
                                .font(.caption.weight(.semibold))
                            Text("Status: \(snapshot.status.rawValue)")
                                .font(.caption)
                            Text("Endpoint: \(snapshot.endpoint)")
                                .font(.caption)
                            Text("Capabilities: vad=\(readinessToken(snapshot.vadReady)), wake=\(readinessToken(snapshot.wakeReady)), partial=\(readinessToken(snapshot.partialReady))")
                                .font(.caption)
                            if let lastError = snapshot.lastError, !lastError.isEmpty {
                                Text("Last Error: \(lastError)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Next Action: \(voiceRuntimeOperatorGuidance(snapshot: snapshot))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("Detailed Voice Diagnostics")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(voiceDiagnosticsExpanded ? "展开中" : "已折叠")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func readinessToken(_ ready: Bool) -> String {
        ready ? "ready" : "blocked"
    }

    private func voiceRuntimeOperatorGuidance(
        snapshot: VoiceSidecarHealthSnapshot
    ) -> String {
        if supervisorManager.voiceAuthorizationStatus == .denied ||
            supervisorManager.voiceAuthorizationStatus == .restricted {
            return "Grant microphone and speech-recognition permission in macOS Settings before retrying voice capture."
        }

        switch snapshot.status {
        case .ready:
            if supervisorManager.voiceRouteDecision.route == .funasrStreaming {
                return "FunASR streaming is healthy. You can verify push-to-talk now."
            }
            return "FunASR is healthy, but another route is currently preferred. Check the preferred route setting if that is unexpected."
        case .disabled:
            return "Enable the local FunASR sidecar only if you want streaming / wake support. Otherwise the runtime will keep using safer fallbacks."
        case .degraded:
            if snapshot.lastError == "funasr_healthcheck_not_configured" {
                return "Configure a local healthcheck URL or disable FunASR until the sidecar is fully wired."
            }
            return "The sidecar answered partially. Inspect the last error and re-run Refresh Voice Runtime after fixing the local sidecar."
        case .unreachable:
            return "Keep FunASR on a local endpoint only, start the sidecar, then refresh runtime readiness."
        }
    }
    
    private var projectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("项目列表")
                .font(.headline)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(appModel.sortedProjects) { project in
                        projectRow(project)
                    }
                }
            }
        }
        .frame(minWidth: 250)
        .padding(8)
    }
    
    private func projectRow(_ project: AXProjectEntry) -> some View {
        Button(action: {
            selectedProjectId = project.projectId
            showProjectModelPicker = false
        }) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("ID: \(project.projectId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if selectedProjectId == project.projectId {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(selectedProjectId == project.projectId ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var modelAssignmentPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let projectId = selectedProjectId {
                roleSelector
                
                Divider()
                
                modelRoutingPanel(for: projectId)
            } else {
                Text("请从左侧选择一个项目")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 400)
        .padding(8)
    }
    
    private var roleSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择角色")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach([AXRole.coder, .coarse, .refine, .reviewer, .advisor, .supervisor], id: \.self) { role in
                        roleButton(role)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func roleButton(_ role: AXRole) -> some View {
        Button(action: {
            selectedRole = role
            showProjectModelPicker = false
        }) {
            HStack(spacing: 8) {
                roleIcon(role)
                Text(role.displayName)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedRole == role ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundStyle(selectedRole == role ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func roleIcon(_ role: AXRole) -> some View {
        Image(systemName: iconName(for: role))
            .font(.system(size: 16))
    }
    
    private func iconName(for role: AXRole) -> String {
        switch role {
        case .coder:
            return "hammer.fill"
        case .coarse:
            return "doc.text.fill"
        case .refine:
            return "sparkles"
        case .reviewer:
            return "checkmark.circle.fill"
        case .advisor:
            return "lightbulb.fill"
        case .supervisor:
            return "person.3.fill"
        }
    }
    
    private func modelRoutingPanel(for projectId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("为 \(selectedRole.displayName) 选择模型")
                    .font(.headline)
                Spacer()
                if let modelId = currentProjectModelOverrideId(for: projectId, role: selectedRole), !modelId.isEmpty {
                    Button("应用到全部项目") {
                        assignModelToAllProjects(role: selectedRole, modelId: modelId)
                    }
                    .buttonStyle(.bordered)
                    .help("将当前角色模型批量应用到所有项目")
                }
            }
            
            if sortedAvailableHubModels.isEmpty {
                Text("没有可用的模型。请确保 X-Hub 已启动并加载了模型。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                if let selectedProject = appModel.sortedProjects.first(where: { $0.projectId == projectId }) {
                    Text("当前项目：\(selectedProject.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let warning = modelAvailabilityWarningText(for: projectId, role: selectedRole) {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HubModelRoutingButton(
                    title: selectedModelButtonTitle(for: projectId, role: selectedRole),
                    identifier: selectedModelIdentifier(for: projectId, role: selectedRole),
                    sourceLabel: selectedModelPresentationSourceLabel(for: projectId, role: selectedRole),
                    presentation: selectedModelPresentation(for: projectId, role: selectedRole),
                    disabled: !appModel.hubInteractive || sortedAvailableHubModels.isEmpty
                ) {
                    showProjectModelPicker = true
                }
                .frame(maxWidth: 480, alignment: .leading)
                .popover(isPresented: $showProjectModelPicker, arrowEdge: .bottom) {
                    let recommendation = projectModelSelectionRecommendation(
                        for: projectId,
                        role: selectedRole
                    )
                    HubModelPickerPopover(
                        title: "为 \(selectedRole.displayName) 选择模型",
                        selectedModelId: currentProjectModelOverrideId(for: projectId, role: selectedRole),
                        inheritedModelId: globalModelId(selectedRole),
                        inheritedModelPresentation: globalModelPresentation(for: selectedRole),
                        models: sortedAvailableHubModels,
                        recommendedModelId: recommendation?.modelId,
                        recommendationMessage: recommendation?.message,
                        onSelect: { modelId in
                            appModel.setProjectRoleModelOverride(projectId: projectId, role: selectedRole, modelId: modelId)
                            showProjectModelPicker = false
                        }
                    )
                    .frame(width: 460, height: 420)
                }

                if let globalHint = inheritedGlobalModelHint(for: projectId, role: selectedRole) {
                    Text(globalHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func currentProjectModelOverrideId(for projectId: String, role: AXRole) -> String? {
        guard let ctx = appModel.projectContext(for: projectId),
              let cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
            return nil
        }
        let raw = cfg.modelOverride(for: role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func availableHubModels() -> [HubModel] {
        modelManager.availableModels.isEmpty ? appModel.modelsState.models : modelManager.availableModels
    }

    private var sortedAvailableHubModels: [HubModel] {
        var dedup: [String: HubModel] = [:]
        for model in availableHubModels() {
            dedup[model.id] = model
        }
        return dedup.values.sorted { a, b in
            let sa = stateRank(a.state)
            let sb = stateRank(b.state)
            if sa != sb { return sa < sb }
            let an = (a.name.isEmpty ? a.id : a.name).lowercased()
            let bn = (b.name.isEmpty ? b.id : b.name).lowercased()
            if an != bn { return an < bn }
            return a.id.lowercased() < b.id.lowercased()
        }
    }

    private func globalModelId(_ role: AXRole) -> String? {
        appModel.settingsStore.settings.assignment(for: role).model
    }

    private func selectedModelPresentation(for projectId: String, role: AXRole) -> ModelInfo? {
        if let projectModelId = currentProjectModelOverrideId(for: projectId, role: role) {
            return availableHubModels().first(where: { $0.id == projectModelId })?.capabilityPresentationModel
                ?? XTModelCatalog.modelInfo(for: projectModelId)
        }

        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !inheritedModelId.isEmpty else { return nil }
        return availableHubModels().first(where: { $0.id == inheritedModelId })?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: inheritedModelId)
    }

    private func globalModelPresentation(for role: AXRole) -> ModelInfo? {
        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !inheritedModelId.isEmpty else { return nil }
        return availableHubModels().first(where: { $0.id == inheritedModelId })?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: inheritedModelId)
    }

    private func selectedModelPresentationSourceLabel(for projectId: String, role: AXRole) -> String {
        currentProjectModelOverrideId(for: projectId, role: role) == nil ? "继承全局" : "项目覆盖"
    }

    private func selectedModelButtonTitle(for projectId: String, role: AXRole) -> String {
        if let presentation = selectedModelPresentation(for: projectId, role: role) {
            return presentation.displayName
        }
        return "使用全局设置"
    }

    private func selectedModelIdentifier(for projectId: String, role: AXRole) -> String? {
        if let projectModelId = currentProjectModelOverrideId(for: projectId, role: role) {
            return projectModelId
        }
        let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return inheritedModelId.isEmpty ? nil : inheritedModelId
    }

    private func inheritedGlobalModelHint(for projectId: String, role: AXRole) -> String? {
        guard currentProjectModelOverrideId(for: projectId, role: role) != nil else { return nil }
        if let global = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines), !global.isEmpty {
            return "当前不选项目覆盖时，会回到全局模型 `\(global)`。"
        }
        return "当前不选项目覆盖时，会回到全局自动路由。"
    }

    private func modelInventorySnapshot() -> ModelStateSnapshot {
        ModelStateSnapshot(
            models: availableHubModels(),
            updatedAt: appModel.modelsState.updatedAt
        )
    }

    private func projectModelSelectionRecommendation(
        for projectId: String,
        role: AXRole
    ) -> (modelId: String, message: String)? {
        let configured = selectedModelIdentifier(for: projectId, role: role)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty else { return nil }

        if let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: configured,
            role: role,
            ctx: appModel.projectContext(for: projectId),
            snapshot: modelInventorySnapshot()
        ),
           let recommendedModelId = guidance.recommendedModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommendedModelId.isEmpty {
            let message = guidance.recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                recommendedModelId,
                (message?.isEmpty == false ? message! : guidance.warningText)
            )
        }

        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configured,
            snapshot: modelInventorySnapshot()
        )
        guard let assessment,
              assessment.isExactMatchLoaded != true,
              let rawCandidate = assessment.loadedCandidates.first?.id else {
            return nil
        }
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.caseInsensitiveCompare(configured) != .orderedSame else {
            return nil
        }

        if let exact = assessment.exactMatch {
            return (
                candidate,
                "`\(exact.id)` 当前是 \(HubModelSelectionAdvisor.stateLabel(exact.state))；如果你现在就要继续，先切到已加载的 `\(candidate)` 更稳。"
            )
        }

        return (
            candidate,
            "`\(configured)` 当前不在可直接执行的 inventory 里；先切到已加载的 `\(candidate)`，可以避免这轮继续掉本地。"
        )
    }

    private func modelAvailabilityWarningText(for projectId: String, role: AXRole) -> String? {
        guard let configuredBinding = warningConfiguredModelBinding(for: projectId, role: role) else {
            return nil
        }
        let configured = configuredBinding.modelId
        if let routeWarning = AXProjectModelRouteMemoryStore.selectionWarningText(
            configuredModelId: configured,
            role: role,
            ctx: configuredBinding.ctx,
            snapshot: modelInventorySnapshot()
        ) {
            return routeWarning
        }
        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configured,
            snapshot: modelInventorySnapshot()
        )
        guard assessment?.isExactMatchLoaded != true else { return nil }

        if let assessment, let exact = assessment.exactMatch {
            let candidates = suggestedModelIDs(from: assessment)
            if let first = candidates.first {
                return "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。若你现在执行，这一路可能会回退到本地；可先切到 `\(first)`。"
            }
            return "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。若你现在执行，这一路可能会回退到本地。"
        }

        if let assessment {
            let candidates = suggestedModelIDs(from: assessment)
            if !candidates.isEmpty {
                return "\(configuredBinding.subject) `\(configured)`，但 inventory 里没有精确匹配。可先试 `\(candidates.joined(separator: "`, `"))`。"
            }
        }
        return "\(configuredBinding.subject) `\(configured)`，但现在无法确认它可执行。"
    }

    private func warningConfiguredModelBinding(
        for projectId: String,
        role: AXRole
    ) -> (modelId: String, subject: String, ctx: AXProjectContext?)? {
        if let projectModelId = currentProjectModelOverrideId(for: projectId, role: role)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !projectModelId.isEmpty {
            return (
                projectModelId,
                "当前 project 为 \(role.displayName) 配的是",
                appModel.projectContext(for: projectId)
            )
        }

        if let inheritedModelId = globalModelId(role)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inheritedModelId.isEmpty {
            return (
                inheritedModelId,
                "\(role.displayName) 当前继承的全局模型是",
                appModel.projectContext(for: projectId)
            )
        }

        return nil
    }

    private func suggestedModelIDs(from assessment: HubModelAvailabilityAssessment) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        return source.prefix(3).map(\.id)
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available: return 1
        case .sleeping: return 2
        }
    }

    private func assignModelToProject(projectId: String, role: AXRole, modelId: String) {
        appModel.setProjectRoleModelOverride(projectId: projectId, role: role, modelId: modelId)
    }

    private func assignModelToAllProjects(role: AXRole, modelId: String) {
        for project in appModel.sortedProjects {
            appModel.setProjectRoleModelOverride(projectId: project.projectId, role: role, modelId: modelId)
        }
    }

    private var voicePreferredRouteBinding: Binding<VoicePreferredRoute> {
        Binding(
            get: { appModel.settingsStore.settings.voice.preferredRoute },
            set: { value in
                updateVoiceSettings { $0.preferredRoute = value }
            }
        )
    }

    private var voiceWakeModeBinding: Binding<VoiceWakeMode> {
        Binding(
            get: { appModel.settingsStore.settings.voice.wakeMode },
            set: { value in
                updateVoiceSettings { $0.wakeMode = value }
            }
        )
    }

    private var voiceAutoReportModeBinding: Binding<VoiceAutoReportMode> {
        Binding(
            get: { appModel.settingsStore.settings.voice.autoReportMode },
            set: { value in
                updateVoiceSettings { $0.autoReportMode = value }
            }
        )
    }

    private var voicePersonaBinding: Binding<VoicePersonaPreset> {
        Binding(
            get: { appModel.settingsStore.settings.voice.persona },
            set: { value in
                updateVoiceSettings { $0.persona = value }
            }
        )
    }

    private var voiceInterruptOnSpeechBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.interruptOnSpeech },
            set: { value in
                updateVoiceSettings { $0.interruptOnSpeech = value }
            }
        )
    }

    private var funASREnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.enabled },
            set: { value in
                updateVoiceSettings { $0.funASR.enabled = value }
            }
        )
    }

    private var funASRWebSocketURLBinding: Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.webSocketURL },
            set: { value in
                updateVoiceSettings { $0.funASR.webSocketURL = value.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        )
    }

    private var funASRHealthcheckURLBinding: Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.healthcheckURL ?? "" },
            set: { value in
                updateVoiceSettings {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.funASR.healthcheckURL = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    private var funASRWakeEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.wakeEnabled },
            set: { value in
                updateVoiceSettings { $0.funASR.wakeEnabled = value }
            }
        )
    }

    private var funASRPartialsEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.partialsEnabled },
            set: { value in
                updateVoiceSettings { $0.funASR.partialsEnabled = value }
            }
        )
    }

    private func updateVoiceSettings(
        _ mutate: (inout VoiceRuntimePreferences) -> Void
    ) {
        var voice = appModel.settingsStore.settings.voice
        mutate(&voice)
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(voice: voice)
        appModel.settingsStore.save()
    }

    private func syncWakeTriggerWordsDraft() {
        let triggers = supervisorManager.voiceWakeProfileSnapshot.triggerWords
        wakeTriggerWordsDraft = VoiceWakeProfile.formatTriggerWords(
            triggers.isEmpty ? VoiceWakeProfile.defaultTriggerWords : triggers
        )
    }

    private func syncSupervisorPromptDraft() {
        supervisorPromptDraft = appModel.settingsStore.settings.supervisorPrompt.normalized()
    }

    private func saveSupervisorPromptDraft() {
        let normalized = supervisorPromptDraft.normalized()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(supervisorPrompt: normalized)
        appModel.settingsStore.save()
        supervisorPromptDraft = normalized
    }

    private func resetSupervisorPromptDefaults() {
        supervisorPromptDraft = .default()
        saveSupervisorPromptDraft()
    }
}
