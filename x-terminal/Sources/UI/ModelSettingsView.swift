import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var modelManager = HubModelManager.shared
    @State private var selectedRole: AXRole = .supervisor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            Divider()
            
            if modelManager.isLoading {
                ProgressView("正在加载模型列表...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let error = modelManager.error {
                Text("加载失败：\(error)")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                modelSelectionArea
            }
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 600)
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
                Text("AI 模型设置")
                    .font(.title2)
                Spacer()
                
                Button("刷新模型列表") {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Text("Supervisor 和 Coding 的 AI 都来自于 X-Hub。如果 X-Hub 有默认设置，X-Terminal 没有设置就用 Hub 默认设置。如果没有，可以在 X-Terminal 选择使用哪个模型作为 Supervisor，哪个模型作为主要编程角色。Supervisor 也可以建议或自己指派每个 project 的编程模型。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
    
    private var modelSelectionArea: some View {
        VStack(alignment: .leading, spacing: 20) {
            roleSelector
            
            Divider()
            
            modelList
        }
    }
    
    private var roleSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择要配置的角色")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AXRole.allCases) { role in
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
        case .supervisor:
            return "person.3.fill"
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
        }
    }
    
    private var modelList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("为 \(selectedRole.displayName) 选择模型")
                .font(.headline)

            if let warning = selectedRoleWarningText() {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
                            modelRow(model)
                        }
                    }
                }
            }
        }
    }
    
    private func modelRow(_ model: HubModel) -> some View {
        let isSelected = modelManager.getPreferredModel(for: selectedRole) == model.id
        
        return Button(action: {
            modelManager.setModel(for: selectedRole, modelId: model.id)
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

    private func selectedRoleWarningText() -> String? {
        let configured = (modelManager.getPreferredModel(for: selectedRole) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty else { return nil }
        let snapshot = ModelStateSnapshot(
            models: modelManager.availableModels,
            updatedAt: Date().timeIntervalSince1970
        )
        let assessment = HubModelSelectionAdvisor.assess(requestedId: configured, snapshot: snapshot)
        guard assessment?.isExactMatchLoaded != true else { return nil }

        if let assessment, let exact = assessment.exactMatch {
            let replacements = suggestedModelIDs(from: assessment)
            if let first = replacements.first {
                return "当前 \(selectedRole.displayName) 绑定的是 `\(exact.id)`，但状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。若立刻执行，可能会回退到本地；可先改用 `\(first)`。"
            }
            return "当前 \(selectedRole.displayName) 绑定的是 `\(exact.id)`，但状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))。若立刻执行，可能会回退到本地。"
        }

        if let assessment {
            let replacements = suggestedModelIDs(from: assessment)
            if !replacements.isEmpty {
                return "当前 \(selectedRole.displayName) 绑定的是 `\(configured)`，但 inventory 里没有精确匹配。可先试 `\(replacements.joined(separator: "`, `"))`。"
            }
        }
        return "当前 \(selectedRole.displayName) 绑定的是 `\(configured)`，但现在无法确认它可执行。"
    }

    private func suggestedModelIDs(from assessment: HubModelAvailabilityAssessment) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        return source.prefix(3).map(\.id)
    }
}
