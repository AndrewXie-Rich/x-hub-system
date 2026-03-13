import SwiftUI

struct ModelSelectorView: View {
    let config: AXProjectConfig?

    @EnvironmentObject private var appModel: AppModel
    @State private var showPopover: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { showPopover.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(selectorTitle)
                    Image(systemName: "chevron.down")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                modelList
            }
        }
    }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hub Loaded Models")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if let selectedModelId, let warning = selectedModelWarningText(modelId: selectedModelId) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前配置提示")
                        .font(.caption.weight(.semibold))
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }

            Divider()

            if appModel.hubInteractive {
                Button(action: {
                    appModel.setProjectRoleModel(role: .coder, modelId: nil)
                    showPopover = false
                }) {
                    HStack {
                        Text("Auto (使用全局/Hub 路由)")
                        Spacer()
                        if selectedModelId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                if loadedModels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hub 当前没有可用模型")
                            .foregroundStyle(.secondary)

                        // 调试信息
                        Text("总模型数: \(appModel.modelsState.models.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if !appModel.modelsState.models.isEmpty {
                            Text("请检查模型状态")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("请在 Hub 中加载模型")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(12)
                } else {
                    ForEach(loadedModels) { model in
                        Button(action: {
                            appModel.setProjectRoleModel(role: .coder, modelId: model.id)
                            showPopover = false
                        }) {
                            HStack {
                                Text(modelDisplayName(model))
                                Spacer()
                                if selectedModelId == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Hub not connected")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(width: 320)
    }

    private var selectedModelId: String? {
        let raw = config?.modelOverride(for: .coder)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var selectorTitle: String {
        if let selectedModelId {
            if let model = loadedModels.first(where: { $0.id == selectedModelId }) {
                return "Coder: \(modelDisplayName(model))"
            }
            if let assessment = selectedModelAssessment {
                if let exact = assessment.exactMatch {
                    return "Coder: \(exact.id) (\(HubModelSelectionAdvisor.stateLabel(exact.state)))"
                }
                return "Coder: \(selectedModelId) (未找到)"
            }
            return "Coder: \(selectedModelId) (待确认)"
        }
        return "Coder: Auto"
    }

    private var loadedModels: [HubModel] {
        let source = appModel.modelsState.models

        // 优先显示 loaded 模型
        let primary = source.filter { $0.state == .loaded }

        // 如果没有 loaded 模型，显示所有模型（而不是空列表）
        let rows = primary.isEmpty ? source : primary

        return rows.sorted { a, b in
            let an = (a.name.isEmpty ? a.id : a.name).lowercased()
            let bn = (b.name.isEmpty ? b.id : b.name).lowercased()
            if an != bn { return an < bn }
            return a.id.lowercased() < b.id.lowercased()
        }
    }

    private var selectedModelAssessment: HubModelAvailabilityAssessment? {
        guard let selectedModelId else { return nil }
        return HubModelSelectionAdvisor.assess(
            requestedId: selectedModelId,
            snapshot: appModel.modelsState
        )
    }

    private func selectedModelWarningText(modelId: String) -> String? {
        guard let assessment = selectedModelAssessment else { return "当前无法确认 `\(modelId)` 是否可用。" }
        guard !assessment.isExactMatchLoaded else { return nil }

        if let exact = assessment.exactMatch {
            let suggestions = suggestedCandidates(from: assessment)
            if let first = suggestions.first {
                return "`\(exact.id)` 当前状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))，这轮请求可能回退到本地。可先改用 `\(first)`。"
            }
            return "`\(exact.id)` 当前状态是 \(HubModelSelectionAdvisor.stateLabel(exact.state))，这轮请求可能回退到本地。"
        }

        let suggestions = suggestedCandidates(from: assessment)
        if !suggestions.isEmpty {
            return "`\(modelId)` 不在当前 inventory 里。可先改用 `\(suggestions.joined(separator: "`, `"))`。"
        }
        return "`\(modelId)` 不在当前 inventory 里，这轮请求可能直接走本地模式。"
    }

    private func suggestedCandidates(from assessment: HubModelAvailabilityAssessment) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        return source.prefix(3).map(\.id)
    }

    private func modelDisplayName(_ model: HubModel) -> String {
        let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return model.id }
        return "\(name) (\(model.id))"
    }
}
