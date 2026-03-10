import SwiftUI

struct ProjectSettingsView: View {
    let ctx: AXProjectContext

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = HubModelManager.shared

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

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            modelManager.setAppModel(appModel)
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

    private struct ModelOption: Identifiable {
        let id: String
        let label: String
    }
}
