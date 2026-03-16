import SwiftUI

enum XTModelTrait: String, CaseIterable, Hashable {
    case reasoning
    case vision
    case coding

    var iconName: String {
        switch self {
        case .reasoning:
            return "brain.head.profile"
        case .vision:
            return "photo.on.rectangle.angled"
        case .coding:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    var label: String {
        switch self {
        case .reasoning:
            return "推理"
        case .vision:
            return "图像"
        case .coding:
            return "代码"
        }
    }

    var tint: Color {
        switch self {
        case .reasoning:
            return .blue
        case .vision:
            return .pink
        case .coding:
            return .teal
        }
    }
}

struct XTModelCapabilityMarker: Identifiable {
    let id: String
    let iconName: String
    let label: String
    let tint: Color
}

struct XTModelCatalogEntry: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let type: ModelType
    let capability: ModelCapability
    let speed: ModelSpeed
    let costPerMillionTokens: Double?
    let memorySize: String?
    let suitableFor: [String]
    let badge: String?
    let badgeColor: Color?
    let traits: [XTModelTrait]

    var modelInfo: ModelInfo {
        ModelInfo(
            id: id,
            name: id,
            displayName: displayName,
            type: type,
            capability: capability,
            speed: speed,
            costPerMillionTokens: costPerMillionTokens,
            memorySize: memorySize,
            suitableFor: suitableFor,
            badge: badge,
            badgeColor: badgeColor
        )
    }
}

enum XTModelCatalog {
    static let projectCreationEntries: [XTModelCatalogEntry] = [
        XTModelCatalogEntry(
            id: "claude-opus-4.6",
            displayName: "Claude Opus 4.6",
            description: "强推理，支持图像，适合复杂交付",
            type: .hubPaid,
            capability: .expert,
            speed: .medium,
            costPerMillionTokens: 15.0,
            memorySize: nil,
            suitableFor: ["复杂任务", "深度推理", "图像理解", "代码"],
            badge: "最强",
            badgeColor: .purple,
            traits: [.reasoning, .vision, .coding]
        ),
        XTModelCatalogEntry(
            id: "claude-sonnet-4.6",
            displayName: "Claude Sonnet 4.6",
            description: "平衡速度和质量，适合主力开发",
            type: .hubPaid,
            capability: .advanced,
            speed: .fast,
            costPerMillionTokens: 3.0,
            memorySize: nil,
            suitableFor: ["大多数任务", "代码", "图像理解"],
            badge: "推荐",
            badgeColor: .blue,
            traits: [.reasoning, .vision, .coding]
        ),
        XTModelCatalogEntry(
            id: "claude-haiku-4.5",
            displayName: "Claude Haiku 4.5",
            description: "响应快，适合轻量任务和快速试错",
            type: .hubPaid,
            capability: .basic,
            speed: .ultraFast,
            costPerMillionTokens: 0.25,
            memorySize: nil,
            suitableFor: ["快速响应", "轻量推理", "图像理解"],
            badge: "经济",
            badgeColor: .green,
            traits: [.reasoning, .vision]
        ),
        XTModelCatalogEntry(
            id: "llama-3-70b-local",
            displayName: "Llama 3 70B Local",
            description: "本地大模型，代码和通用任务都能扛",
            type: .local,
            capability: .intermediate,
            speed: .medium,
            costPerMillionTokens: nil,
            memorySize: "40GB",
            suitableFor: ["代码生成", "本地执行", "中等任务"],
            badge: nil,
            badgeColor: nil,
            traits: [.reasoning, .coding]
        ),
        XTModelCatalogEntry(
            id: "qwen-2.5-72b-local",
            displayName: "Qwen 2.5 72B Local",
            description: "本地长上下文，适合代码和复杂文本处理",
            type: .local,
            capability: .advanced,
            speed: .medium,
            costPerMillionTokens: nil,
            memorySize: nil,
            suitableFor: ["长上下文", "代码", "本地执行"],
            badge: nil,
            badgeColor: nil,
            traits: [.reasoning, .coding]
        ),
    ]

    static func entry(for modelId: String) -> XTModelCatalogEntry? {
        let normalized = normalizedModelId(modelId)
        return projectCreationEntries.first(where: { normalizedModelId($0.id) == normalized })
    }

    static func modelInfo(for modelId: String, preferLocalHint: Bool = false) -> ModelInfo {
        if let entry = entry(for: modelId) {
            return entry.modelInfo
        }

        let normalized = normalizedModelId(modelId)
        let type: ModelType = preferLocalHint || normalized.contains("local") ? .local : .hubPaid
        let capability: ModelCapability
        if normalized.contains("opus") {
            capability = .expert
        } else if normalized.contains("sonnet") || normalized.contains("72b") || normalized.contains("70b") {
            capability = .advanced
        } else if normalized.contains("haiku") || normalized.contains("8b") {
            capability = .basic
        } else {
            capability = .intermediate
        }

        let speed: ModelSpeed
        if normalized.contains("haiku") || normalized.contains("8b") {
            speed = .fast
        } else if normalized.contains("sonnet") {
            speed = .fast
        } else {
            speed = .medium
        }

        return ModelInfo(
            id: modelId,
            name: modelId,
            displayName: prettifiedDisplayName(modelId),
            type: type,
            capability: capability,
            speed: speed,
            costPerMillionTokens: type == .local ? nil : 3.0,
            memorySize: type == .local ? "40GB" : nil,
            suitableFor: fallbackSuitableFor(modelId),
            badge: nil,
            badgeColor: nil
        )
    }

    static func modelInfo(for hubModel: HubModel) -> ModelInfo {
        let base = modelInfo(for: hubModel.id, preferLocalHint: hubModel.isLocalModel)
        let preferredName = hubModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = preferredName.isEmpty ? base.displayName : preferredName
        let modelType: ModelType = hubModel.isLocalModel ? .local : .hubPaid
        var suitableFor = base.suitableFor

        if hubModel.isLocalModel {
            suitableFor.append("本地执行")
        }
        if hubModel.hubDefaultContextLength >= 128_000 {
            suitableFor.append("长上下文")
        }
        suitableFor.append(contentsOf: suitableForHints(from: hubModel))

        return ModelInfo(
            id: hubModel.id,
            name: preferredName.isEmpty ? base.name : preferredName,
            displayName: displayName,
            type: modelType,
            capability: base.capability,
            speed: inferredSpeed(for: hubModel, fallback: base.speed),
            costPerMillionTokens: modelType == .local ? nil : base.costPerMillionTokens,
            memorySize: formattedMemorySize(from: hubModel.memoryBytes) ?? base.memorySize,
            suitableFor: deduplicatedStrings(suitableFor),
            badge: base.badge,
            badgeColor: base.badgeColor
        )
    }

    static func inferredTraits(for model: ModelInfo) -> [XTModelTrait] {
        if let entry = entry(for: model.id) {
            return entry.traits
        }

        let normalized = normalizedModelId(model.id)
        let suitableFor = model.suitableFor.map { $0.lowercased() }
        var traits = Set<XTModelTrait>()

        if model.capability.rawValue >= ModelCapability.advanced.rawValue
            || suitableFor.contains(where: { $0.contains("推理") || $0.contains("reason") || $0.contains("analysis") }) {
            traits.insert(.reasoning)
        }

        if normalized.contains("claude")
            || normalized.contains("vision")
            || normalized.contains("image")
            || normalized.contains("multimodal")
            || normalized.contains("vl")
            || suitableFor.contains(where: { $0.contains("图像") || $0.contains("vision") || $0.contains("image") }) {
            traits.insert(.vision)
        }

        if normalized.contains("code")
            || normalized.contains("coder")
            || normalized.contains("qwen")
            || normalized.contains("llama")
            || normalized.contains("claude")
            || suitableFor.contains(where: { $0.contains("代码") || $0.contains("code") || $0.contains("program") }) {
            traits.insert(.coding)
        }

        return XTModelTrait.allCases.filter { traits.contains($0) }
    }

    private static func normalizedModelId(_ modelId: String) -> String {
        modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func prettifiedDisplayName(_ modelId: String) -> String {
        if let entry = entry(for: modelId) {
            return entry.displayName
        }
        return modelId
            .replacingOccurrences(of: "-local", with: " Local")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func suitableForHints(from hubModel: HubModel) -> [String] {
        var hints: [String] = []
        let normalizedTaskKinds = Set(hubModel.taskKinds.map(normalizedToken(_:)))
        let normalizedInputModalities = Set(hubModel.inputModalities.map(normalizedToken(_:)))
        let normalizedOutputModalities = Set(hubModel.outputModalities.map(normalizedToken(_:)))
        let normalizedRoles = Set((hubModel.roles ?? []).map(normalizedToken(_:)))

        if normalizedTaskKinds.contains("text_generate") {
            hints.append("文本生成")
        }
        if normalizedTaskKinds.contains("embedding") || normalizedOutputModalities.contains("embedding") {
            hints.append("向量嵌入")
        }
        if normalizedTaskKinds.contains("speech_to_text") || normalizedInputModalities.contains("audio") {
            hints.append("语音转写")
        }
        if normalizedTaskKinds.contains("vision_understand")
            || normalizedTaskKinds.contains("ocr")
            || normalizedInputModalities.contains("image") {
            hints.append("图像理解")
        }
        if normalizedTaskKinds.contains("ocr") || normalizedOutputModalities.contains("spans") {
            hints.append("OCR")
        }
        if normalizedTaskKinds.contains("classify") || normalizedOutputModalities.contains("labels") {
            hints.append("分类")
        }
        if normalizedTaskKinds.contains("rerank") || normalizedOutputModalities.contains("scores") {
            hints.append("排序")
        }
        if normalizedRoles.contains("coder")
            || normalizedRoles.contains("code")
            || normalizedRoles.contains("coding") {
            hints.append("代码")
        }

        let normalizedNote = normalizedToken(hubModel.note ?? "")
        if hints.isEmpty || !hints.contains("图像理解") {
            if normalizedNote.contains("vision") || normalizedNote.contains("image") || normalizedNote.contains("图像") {
                hints.append("图像理解")
            }
        }
        if !hints.contains("代码") {
            if normalizedNote.contains("code") || normalizedNote.contains("coding") || normalizedNote.contains("代码") {
                hints.append("代码")
            }
        }
        return deduplicatedStrings(hints)
    }

    private static func fallbackSuitableFor(_ modelId: String) -> [String] {
        let normalized = normalizedModelId(modelId)
        if normalized.contains("claude") {
            return ["通用任务", "推理", "代码"]
        }
        if normalized.contains("qwen") || normalized.contains("llama") {
            return ["通用任务", "代码", "本地执行"]
        }
        return ["通用任务"]
    }

    private static func inferredSpeed(for hubModel: HubModel, fallback: ModelSpeed) -> ModelSpeed {
        guard let tokensPerSec = hubModel.tokensPerSec else {
            return fallback
        }
        switch tokensPerSec {
        case 80...:
            return .ultraFast
        case 40..<80:
            return .fast
        case 15..<40:
            return .medium
        default:
            return .slow
        }
    }

    private static func formattedMemorySize(from memoryBytes: Int64?) -> String? {
        guard let memoryBytes, memoryBytes > 0 else {
            return nil
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: memoryBytes)
    }

    private static func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension ModelInfo {
    var capabilityMarkers: [XTModelCapabilityMarker] {
        var markers: [XTModelCapabilityMarker] = [
            XTModelCapabilityMarker(
                id: "type_\(type.rawValue)",
                iconName: isLocal ? "desktopcomputer" : "cloud",
                label: isLocal ? "本地" : "云端",
                tint: isLocal ? .green : .orange
            )
        ]

        markers.append(contentsOf: XTModelCatalog.inferredTraits(for: self).map {
            XTModelCapabilityMarker(
                id: "trait_\($0.rawValue)",
                iconName: $0.iconName,
                label: $0.label,
                tint: $0.tint
            )
        })

        markers.append(
            XTModelCapabilityMarker(
                id: "speed_\(speed.rawValue)",
                iconName: speed.icon,
                label: speed.text,
                tint: .yellow
            )
        )
        return markers
    }
}

extension HubModel {
    var capabilityPresentationModel: ModelInfo {
        XTModelCatalog.modelInfo(for: self)
    }
}
