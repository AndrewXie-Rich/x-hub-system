import Foundation

public struct LocalTaskRoutingDescriptor: Equatable, Sendable, Identifiable {
    public var taskKind: String
    public var title: String
    public var shortTitle: String

    public var id: String { taskKind }

    public init(taskKind: String, title: String, shortTitle: String) {
        self.taskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shortTitle = shortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LocalTaskRoutingCatalog {
    public static let descriptors: [LocalTaskRoutingDescriptor] = [
        LocalTaskRoutingDescriptor(taskKind: "text_generate", title: "文本生成", shortTitle: "生成"),
        LocalTaskRoutingDescriptor(taskKind: "embedding", title: "向量", shortTitle: "向量"),
        LocalTaskRoutingDescriptor(taskKind: "speech_to_text", title: "语音转文字", shortTitle: "转写"),
        LocalTaskRoutingDescriptor(taskKind: "text_to_speech", title: "文本转语音", shortTitle: "语音"),
        LocalTaskRoutingDescriptor(taskKind: "vision_understand", title: "视觉理解", shortTitle: "视觉"),
        LocalTaskRoutingDescriptor(taskKind: "ocr", title: "OCR", shortTitle: "OCR"),
    ]

    public static var supportedTaskKinds: [String] {
        descriptors.map(\.taskKind)
    }

    public static func descriptor(for taskKind: String) -> LocalTaskRoutingDescriptor? {
        let normalized = normalizedTaskKind(taskKind)
        return descriptors.first(where: { $0.taskKind == normalized })
    }

    public static func supportedTaskKinds(in rawTaskKinds: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for taskKind in rawTaskKinds {
            let normalized = normalizedTaskKind(taskKind)
            guard supportedTaskKinds.contains(normalized) else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            out.append(normalized)
        }
        return out
    }

    public static func supportedDescriptors(in rawTaskKinds: [String]) -> [LocalTaskRoutingDescriptor] {
        supportedTaskKinds(in: rawTaskKinds).compactMap { descriptor(for: $0) }
    }

    public static func title(for taskKind: String) -> String {
        if let descriptor = descriptor(for: taskKind) {
            return descriptor.title
        }
        return fallbackTitle(for: taskKind)
    }

    public static func shortTitle(for taskKind: String) -> String {
        if let descriptor = descriptor(for: taskKind) {
            return descriptor.shortTitle
        }
        return fallbackTitle(for: taskKind)
    }

    private static func normalizedTaskKind(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func fallbackTitle(for taskKind: String) -> String {
        let normalized = normalizedTaskKind(taskKind)
        guard !normalized.isEmpty else { return "Unknown" }
        return normalized
            .split(separator: "_")
            .map { token in
                let text = String(token)
                guard let first = text.first else { return "" }
                return String(first).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }
}
