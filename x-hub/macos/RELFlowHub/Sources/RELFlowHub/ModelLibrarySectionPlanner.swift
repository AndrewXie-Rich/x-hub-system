import Foundation
import RELFlowHubCore

struct ModelLibrarySection: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var systemName: String
    var models: [HubModel]
    var loadedCount: Int
}

enum ModelLibrarySectionPlanner {
    private struct SectionDefinition {
        var id: String
        var title: String
        var subtitle: String
        var systemName: String
    }

    private static let sectionDefinitions: [SectionDefinition] = [
        SectionDefinition(
            id: "text",
            title: HubUIStrings.Models.Library.Sections.textTitle,
            subtitle: HubUIStrings.Models.Library.Sections.textSubtitle,
            systemName: "text.bubble"
        ),
        SectionDefinition(
            id: "coding",
            title: HubUIStrings.Models.Library.Sections.codingTitle,
            subtitle: HubUIStrings.Models.Library.Sections.codingSubtitle,
            systemName: "curlybraces"
        ),
        SectionDefinition(
            id: "embedding",
            title: HubUIStrings.Models.Library.Sections.embeddingTitle,
            subtitle: HubUIStrings.Models.Library.Sections.embeddingSubtitle,
            systemName: "point.3.connected.trianglepath.dotted"
        ),
        SectionDefinition(
            id: "voice",
            title: HubUIStrings.Models.Library.Sections.voiceTitle,
            subtitle: HubUIStrings.Models.Library.Sections.voiceSubtitle,
            systemName: "speaker.wave.2.fill"
        ),
        SectionDefinition(
            id: "audio",
            title: HubUIStrings.Models.Library.Sections.audioTitle,
            subtitle: HubUIStrings.Models.Library.Sections.audioSubtitle,
            systemName: "waveform"
        ),
        SectionDefinition(
            id: "vision",
            title: HubUIStrings.Models.Library.Sections.visionTitle,
            subtitle: HubUIStrings.Models.Library.Sections.visionSubtitle,
            systemName: "photo.on.rectangle"
        ),
        SectionDefinition(
            id: "ocr",
            title: HubUIStrings.Models.Library.Sections.ocrTitle,
            subtitle: HubUIStrings.Models.Library.Sections.ocrSubtitle,
            systemName: "doc.text.viewfinder"
        ),
        SectionDefinition(
            id: "remote",
            title: HubUIStrings.Models.Library.Sections.remoteTitle,
            subtitle: HubUIStrings.Models.Library.Sections.remoteSubtitle,
            systemName: "network"
        ),
        SectionDefinition(
            id: "other",
            title: HubUIStrings.Models.Library.Sections.otherTitle,
            subtitle: HubUIStrings.Models.Library.Sections.otherSubtitle,
            systemName: "square.stack.3d.up"
        ),
    ]

    static func sections(from models: [HubModel], preferRemoteSection: Bool = false) -> [ModelLibrarySection] {
        guard !models.isEmpty else { return [] }

        var grouped: [String: [HubModel]] = [:]
        for model in models {
            grouped[sectionID(for: model, preferRemoteSection: preferRemoteSection), default: []].append(model)
        }

        return sectionDefinitions.compactMap { definition in
            guard let sectionModels = grouped[definition.id], !sectionModels.isEmpty else {
                return nil
            }
            return ModelLibrarySection(
                id: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                systemName: definition.systemName,
                models: sectionModels,
                loadedCount: sectionModels.filter { $0.state == .loaded }.count
            )
        }
    }

    static func sectionID(for model: HubModel, preferRemoteSection: Bool = false) -> String {
        if preferRemoteSection && isRemoteModel(model) {
            return "remote"
        }
        if isCodingModel(model) {
            return "coding"
        }
        if isRemoteModel(model) {
            return "remote"
        }

        let taskKinds = Set(LocalModelCapabilityDefaults.normalizedStringList(model.taskKinds, fallback: []))
        let inputModalities = Set(LocalModelCapabilityDefaults.normalizedStringList(model.inputModalities, fallback: []))

        if taskKinds.contains("embedding") {
            return "embedding"
        }
        if taskKinds.contains("text_to_speech") {
            return "voice"
        }
        if taskKinds.contains("speech_to_text") || inputModalities.contains("audio") {
            return "audio"
        }
        if taskKinds.contains("vision_understand") {
            return "vision"
        }
        if taskKinds.contains("ocr") {
            return "ocr"
        }
        if taskKinds.contains("text_generate") || taskKinds.contains("tool_use") {
            return "text"
        }
        return "other"
    }

    private static func isRemoteModel(_ model: HubModel) -> Bool {
        let modelPath = model.modelPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return modelPath.isEmpty
    }

    private static func isCodingModel(_ model: HubModel) -> Bool {
        let normalizedRoles = Set(
            LocalModelCapabilityDefaults.normalizedStringList(model.roles ?? [], fallback: [])
        )
        if !normalizedRoles.isDisjoint(with: ["code", "coder", "coding", "developer", "programming"]) {
            return true
        }

        let tokens = tokenSet([
            model.id,
            model.name,
            model.note ?? "",
        ])
        return !tokens.isDisjoint(with: [
            "code",
            "coder",
            "coding",
            "codegen",
            "developer",
            "programming",
            "deepseek-coder",
            "starcoder",
            "qwen-coder",
        ])
    }

    private static func tokenSet(_ rawValues: [String]) -> Set<String> {
        let joined = rawValues.joined(separator: " ").lowercased()
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted
        return Set(joined.components(separatedBy: separators).filter { !$0.isEmpty })
    }
}

enum ModelLibraryUsageDescriptionBuilder {
    static func description(for model: HubModel) -> String {
        HubUIStrings.Models.Library.Usage.description(
            sectionID: ModelLibrarySectionPlanner.sectionID(for: model),
            isLoaded: model.state == .loaded
        )
    }
}
