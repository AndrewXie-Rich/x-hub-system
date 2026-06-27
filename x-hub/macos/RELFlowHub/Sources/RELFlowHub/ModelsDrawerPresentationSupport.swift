import Foundation
import SwiftUI
import RELFlowHubCore

extension ModelsDrawer {
    var localResourcePoolDetailText: String {
        if localModels.isEmpty {
            return "本地模型会用于隐私任务、离线任务和低延迟任务。"
        }
        if !runtimeAlive {
            return "Runtime 未就绪，本地模型暂时只作为目录展示。"
        }
        if localLoadedCount > 0 {
            return "\(localLoadedCount) 个模型已经常驻，可以直接承接本地任务。"
        }
        return "本地模型已编目，可按任务需要自动加载。"
    }

    func remoteResourcePoolDetailText(
        providerName: String,
        keyPools: [ProviderKeyPoolSnapshot],
        models: [RemoteModelEntry],
        needsSetup: Int
    ) -> String {
        if models.isEmpty && !keyPools.isEmpty {
            return "\(providerName) 账号已接入，但还没有编入可执行模型。"
        }
        if keyPools.isEmpty && !models.isEmpty {
            return "\(providerName) 模型已编目，但缺少可路由账号或 Key。"
        }
        if needsSetup > 0 {
            return "\(needsSetup) 个模型需要补齐 Key、Endpoint 或健康检查。"
        }
        if keyPools.contains(where: { $0.hasQuotaData }) {
            return "额度和 Key 健康已同步，Hub 可按资源池进行路由。"
        }
        return "已编入模型，额度窗口等待 provider 同步。"
    }

    func providerPoolDisplayName(_ pool: ProviderKeyPoolSnapshot) -> String {
        let display = pool.providerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let provider = pool.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isEmpty { return "Remote" }
        switch provider.lowercased() {
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "gemini", "google": return "Gemini"
        default: return provider.uppercased()
        }
    }

    func providerTitle(for model: HubModel) -> String {
        if LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            let backend = model.backend.trimmingCharacters(in: .whitespacesAndNewlines)
            switch backend.lowercased() {
            case "openai": return "OpenAI"
            case "anthropic": return "Anthropic"
            case "gemini", "google": return "Gemini"
            case "remote", "remote_catalog": return model.remoteEndpointHost ?? "Remote"
            default: return backend.isEmpty ? "Remote" : backend.uppercased()
            }
        }
        return "Local"
    }

    func compactModelDetail(_ model: HubModel) -> String {
        let context = model.maxContextLength > model.contextLength
            ? "ctx \(model.contextLength)/\(model.maxContextLength)"
            : "ctx \(model.contextLength)"
        let perf = model.tokensPerSec.map { String(format: "%.1f tok/s", $0) } ?? ""
        let size = model.paramsB > 0 ? String(format: "%.1fB", model.paramsB) : ""
        return [model.backend, model.quant, size, context, perf]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "unknown" }
            .joined(separator: " · ")
    }

    func modelTags(_ model: HubModel) -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: HubTaskRoutingPolicy.capabilityTags(for: model, limit: 3))
        if model.offlineReady { tags.append("本地") }
        if modelSupportsVision(model) { tags.append("视觉") }
        if model.maxContextLength >= 64_000 { tags.append("长上下文") }
        var seen = Set<String>()
        let uniqueTags = tags.filter { !$0.isEmpty && seen.insert($0).inserted }
        return Array(uniqueTags.prefix(4))
    }

    func modelSupportsVision(_ model: HubModel) -> Bool {
        let tokens = model.inputModalities + model.outputModalities + model.taskKinds
        return tokens.contains { token in
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("vision")
                || normalized.contains("image")
                || normalized.contains("ocr")
        }
    }

    func modelStateText(_ state: HubModelState) -> String {
        switch state {
        case .loaded: return "Ready"
        case .available: return "Available"
        case .sleeping: return "Sleep"
        }
    }

    func modelStateColor(_ state: HubModelState) -> Color {
        switch state {
        case .loaded: return .green
        case .available: return .indigo
        case .sleeping: return .orange
        }
    }

    func remoteLibraryDetail(_ entry: RemoteModelEntry) -> String {
        let context = Self.remoteContextSummary(for: entry)
        let host = RemoteModelPresentationSupport.endpointHost(for: entry) ?? ""
        return [entry.effectiveProviderModelID, host, context]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    func remoteModelTags(_ entry: RemoteModelEntry) -> [String] {
        var tags: [String] = []
        let modelID = entry.effectiveProviderModelID.lowercased()
        if modelID.contains("gpt") || modelID.contains("claude") || modelID.contains("gemini") {
            tags.append("推理")
        }
        if modelID.contains("coder") || modelID.contains("code") {
            tags.append("代码")
        }
        if modelID.contains("vision") || modelID.contains("image") {
            tags.append("视觉")
        }
        if max(entry.contextLength, entry.knownContextLength ?? 0) >= 64_000 {
            tags.append("长上下文")
        }
        if tags.isEmpty { tags.append("远程") }
        return Array(tags.prefix(4))
    }

    func remoteModelStateText(_ state: RemoteModelLoadState) -> String {
        switch state {
        case .loaded: return "Ready"
        case .available: return "Available"
        case .needsSetup: return "Setup"
        }
    }

    func remoteModelStateColor(_ state: RemoteModelLoadState) -> Color {
        switch state {
        case .loaded: return .green
        case .available: return .indigo
        case .needsSetup: return .orange
        }
    }
}
