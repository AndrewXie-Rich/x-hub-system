import SwiftUI

struct SupervisorSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var supervisorManager = SupervisorManager.shared
    @State private var selectedProjectId: String?
    @State private var selectedRole: AXRole = .coder
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            heartbeatPolicySection
            
            Divider()
            
            if appModel.sortedProjects.isEmpty {
                Text("没有项目。请先创建或打开一个项目。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                modelAssignmentArea
            }
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            modelManager.setAppModel(appModel)
            Task {
                await modelManager.fetchModels()
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
                
                modelList(for: projectId)
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
    
    private func modelList(for projectId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("为 \(selectedRole.displayName) 选择模型")
                    .font(.headline)
                Spacer()
                if let modelId = getCurrentModel(for: projectId, role: selectedRole), !modelId.isEmpty {
                    Button("应用到全部项目") {
                        assignModelToAllProjects(role: selectedRole, modelId: modelId)
                    }
                    .buttonStyle(.bordered)
                    .help("将当前角色模型批量应用到所有项目")
                }
            }
            
            if modelManager.availableModels.isEmpty {
                Text("没有可用的模型。请确保 X-Hub 已启动并加载了模型。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(modelManager.availableModels) { model in
                            modelRow(model, for: projectId)
                        }
                    }
                }
            }
        }
    }
    
    private func modelRow(_ model: HubModel, for projectId: String) -> some View {
        let currentModel = getCurrentModel(for: projectId, role: selectedRole)
        let isSelected = currentModel == model.id
        
        return Button(action: {
            assignModelToProject(projectId: projectId, role: selectedRole, modelId: model.id)
        }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if model.state == .loaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        
                        Text(model.backend)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let note = model.note, !note.isEmpty {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text("上下文长度：\(model.contextLength) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let roles = model.roles, !roles.isEmpty {
                        Text("角色：\(roles.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func getCurrentModel(for projectId: String, role: AXRole) -> String? {
        guard let ctx = appModel.projectContext(for: projectId),
              let cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
            return nil
        }
        return cfg.modelOverride(for: role)
    }
    
    private func assignModelToProject(projectId: String, role: AXRole, modelId: String) {
        guard let ctx = appModel.projectContext(for: projectId) else { return }
        
        guard var cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else { return }
        
        cfg.setModelOverride(role: role, modelId: modelId)
        
        do {
            try AXProjectStore.saveConfig(cfg, for: ctx)
        } catch {
            print("保存项目配置失败：\(error.localizedDescription)")
        }
    }

    private func assignModelToAllProjects(role: AXRole, modelId: String) {
        for project in appModel.sortedProjects {
            guard let ctx = appModel.projectContext(for: project.projectId),
                  var cfg = try? AXProjectStore.loadOrCreateConfig(for: ctx) else {
                continue
            }
            cfg.setModelOverride(role: role, modelId: modelId)
            try? AXProjectStore.saveConfig(cfg, for: ctx)
        }
    }
}
