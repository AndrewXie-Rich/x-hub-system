import Foundation

enum AXChatAttachmentLocalModelPreview {
    typealias SnapshotLoaderForTesting = @Sendable () -> ModelStateSnapshot?
    typealias LocalTaskExecutorForTesting = @Sendable (
        String,
        String,
        [String: JSONValue],
        Double
    ) -> HubIPCClient.LocalTaskResult

    private struct CacheEntry {
        var preview: String?
        var storedAt: TimeInterval
    }

    private enum CacheLookupResult {
        case hit(String?)
        case miss
    }

    private struct TaskPreviewOutput {
        var taskKind: String
        var text: String
        var language: String?
    }

    private static let previewCacheTTL: TimeInterval = 30.0
    private static let previewLimit = 2
    private static let visionTimeoutSec = 2.0
    private static let ocrTimeoutSec = 1.5
    private static let previewLock = NSLock()
    private static var previewCache: [String: CacheEntry] = [:]
    private static var snapshotLoaderOverrideForTesting: SnapshotLoaderForTesting?
    private static var localTaskExecutorOverrideForTesting: LocalTaskExecutorForTesting?

    private static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "webp", "heic", "bmp", "tif", "tiff"
    ]

    private static let ocrFirstHints = [
        "receipt", "invoice", "scan", "screenshot", "screen", "capture", "page",
        "doc", "document", "form", "slide", "menu", "poster", "ocr"
    ]

    private static let visionPreviewPrompt =
        "Summarize this image attachment for coding chat context. Mention UI, layout, objects, and any clearly readable text briefly."

    static func previewOverrides(
        for attachments: [AXChatAttachment],
        limit: Int = previewLimit
    ) async -> [String: String] {
        guard limit > 0 else { return [:] }

        var overrides: [String: String] = [:]
        var remaining = limit

        for attachment in attachments {
            guard remaining > 0 else { break }
            guard canUseLocalPreview(for: attachment) else { continue }
            remaining -= 1

            if let preview = await previewSummary(for: attachment) {
                overrides[attachmentKey(for: attachment)] = preview
            }
        }

        return overrides
    }

    static func previewSummary(for attachment: AXChatAttachment) async -> String? {
        guard canUseLocalPreview(for: attachment) else { return nil }
        return await Task.detached(priority: .utility) {
            previewSummarySync(for: attachment)
        }.value
    }

    static func installTestingOverrides(
        snapshotLoader: SnapshotLoaderForTesting? = nil,
        localTaskExecutor: LocalTaskExecutorForTesting? = nil
    ) {
        previewLock.lock()
        snapshotLoaderOverrideForTesting = snapshotLoader
        localTaskExecutorOverrideForTesting = localTaskExecutor
        previewCache.removeAll()
        previewLock.unlock()
    }

    static func resetTestingOverrides() {
        installTestingOverrides()
    }

    static func canUseLocalPreview(for attachment: AXChatAttachment) -> Bool {
        guard attachment.kind == .file else { return false }
        let resolvedPath = PathGuard.resolve(URL(fileURLWithPath: attachment.path)).path
        let url = URL(fileURLWithPath: resolvedPath)
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard supportedImageExtensions.contains(ext) else { return false }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private static func previewSummarySync(for attachment: AXChatAttachment) -> String? {
        guard let cacheKey = previewCacheKey(for: attachment) else { return nil }
        switch cachedPreview(for: cacheKey) {
        case .hit(let cached):
            return cached
        case .miss:
            break
        }

        let imagePath = resolvedPath(for: attachment)
        let snapshot = loadSnapshot()
        let visionModel = selectModel(for: "vision_understand", in: snapshot)
        let ocrModel = selectModel(for: "ocr", in: snapshot)

        guard visionModel != nil || ocrModel != nil else {
            storePreview(nil, for: cacheKey)
            return nil
        }

        var outputs: [TaskPreviewOutput] = []
        for taskKind in orderedTaskKinds(
            for: attachment,
            visionModelAvailable: visionModel != nil,
            ocrModelAvailable: ocrModel != nil
        ) {
            let selectedModel = taskKind == "ocr" ? ocrModel : visionModel
            guard let model = selectedModel else { continue }

            let result = executeLocalTask(
                taskKind: taskKind,
                modelID: model.id,
                parameters: parameters(
                    for: taskKind,
                    imagePath: imagePath
                ),
                timeoutSec: timeoutSec(for: taskKind)
            )
            guard result.ok,
                  let output = previewOutput(from: result, taskKind: taskKind) else {
                continue
            }
            outputs.append(output)
        }

        let preview = renderedPreview(from: outputs)
        storePreview(preview, for: cacheKey)
        return preview
    }

    private static func loadSnapshot() -> ModelStateSnapshot {
        if let override = snapshotLoaderForTesting() {
            return override() ?? .empty()
        }

        let url = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return .empty()
        }
        return snapshot
    }

    private static func selectModel(
        for taskKind: String,
        in snapshot: ModelStateSnapshot
    ) -> HubModel? {
        snapshot.models
            .filter { model in
                model.isLocalModel
                    && supportsImageInput(model)
                    && supportsTaskKind(taskKind, model: model)
            }
            .sorted { lhs, rhs in
                selectionRank(for: lhs, taskKind: taskKind) < selectionRank(for: rhs, taskKind: taskKind)
            }
            .first
    }

    private static func supportsTaskKind(_ taskKind: String, model: HubModel) -> Bool {
        let normalizedTaskKind = normalize(taskKind)
        return model.taskKinds.contains { normalize($0) == normalizedTaskKind }
    }

    private static func supportsImageInput(_ model: HubModel) -> Bool {
        let inputs = Set(model.inputModalities.map(normalize(_:)))
        if inputs.contains("image") {
            return true
        }
        return supportsTaskKind("vision_understand", model: model)
            || supportsTaskKind("ocr", model: model)
    }

    private static func selectionRank(
        for model: HubModel,
        taskKind: String
    ) -> (Int, Int, Int, Int, String) {
        let stateRank: Int
        switch model.state {
        case .loaded:
            stateRank = 0
        case .available:
            stateRank = 1
        case .sleeping:
            stateRank = 2
        }

        let outputs = Set(model.outputModalities.map(normalize(_:)))
        let outputRank: Int = {
            if taskKind == "ocr" {
                return outputs.contains("spans") ? 0 : 1
            }
            return outputs.contains("text") ? 0 : 1
        }()

        let specializationRank = model.taskKinds.count <= 1 ? 0 : 1
        let offlineRank = model.offlineReady ? 0 : 1

        return (stateRank, outputRank, specializationRank, offlineRank, model.id.lowercased())
    }

    private static func orderedTaskKinds(
        for attachment: AXChatAttachment,
        visionModelAvailable: Bool,
        ocrModelAvailable: Bool
    ) -> [String] {
        let haystack = (attachment.displayName + " " + attachment.path).lowercased()
        let prefersOCRFirst = ocrFirstHints.contains(where: { haystack.contains($0) })

        var ordered: [String] = []
        if prefersOCRFirst, ocrModelAvailable {
            ordered.append("ocr")
        }
        if visionModelAvailable {
            ordered.append("vision_understand")
        }
        if ocrModelAvailable && !ordered.contains("ocr") {
            ordered.append("ocr")
        }
        return ordered
    }

    private static func parameters(
        for taskKind: String,
        imagePath: String
    ) -> [String: JSONValue] {
        var parameters: [String: JSONValue] = [
            "image_path": .string(imagePath)
        ]
        if taskKind == "vision_understand" {
            parameters["prompt"] = .string(visionPreviewPrompt)
        } else if taskKind == "ocr" {
            parameters["options"] = .object([
                "language": .string("auto")
            ])
        }
        return parameters
    }

    private static func timeoutSec(for taskKind: String) -> Double {
        taskKind == "ocr" ? ocrTimeoutSec : visionTimeoutSec
    }

    private static func executeLocalTask(
        taskKind: String,
        modelID: String,
        parameters: [String: JSONValue],
        timeoutSec: Double
    ) -> HubIPCClient.LocalTaskResult {
        if let override = localTaskExecutorForTesting() {
            return override(taskKind, modelID, parameters, timeoutSec)
        }

        return HubIPCClient.executeLocalTaskViaLocalHub(
            taskKind: taskKind,
            modelID: modelID,
            parameters: parameters,
            timeoutSec: timeoutSec
        )
    }

    private static func previewOutput(
        from result: HubIPCClient.LocalTaskResult,
        taskKind: String
    ) -> TaskPreviewOutput? {
        let normalizedTaskKind = normalize(result.taskKind ?? taskKind)
        let primaryText = normalizedPreviewText(
            result.payload["text"]?.stringValue
        )
        let spanText = normalizedPreviewText(
            collectedSpanTexts(from: result.payload["spans"]).joined(separator: " | ")
        )
        guard let resolvedText = primaryText ?? spanText else { return nil }

        return TaskPreviewOutput(
            taskKind: normalizedTaskKind,
            text: resolvedText,
            language: normalizedPreviewText(result.payload["language"]?.stringValue)
        )
    }

    private static func collectedSpanTexts(from value: JSONValue?) -> [String] {
        guard let spans = value?.arrayValue else { return [] }

        var seen = Set<String>()
        var collected: [String] = []

        for span in spans {
            guard let object = span.objectValue,
                  let text = normalizedPreviewText(object["text"]?.stringValue) else {
                continue
            }
            let dedupeKey = text.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            collected.append(text)
            if collected.count >= 3 {
                break
            }
        }

        return collected
    }

    private static func renderedPreview(from outputs: [TaskPreviewOutput]) -> String? {
        guard !outputs.isEmpty else { return nil }

        let vision = outputs.first { $0.taskKind == "vision_understand" }
        let ocr = outputs.first { $0.taskKind == "ocr" }

        var lines: [String] = []
        let visionText = truncatedPreviewText(vision?.text, limit: 260)
        if let visionText {
            lines.append("image summary: \(visionText)")
        }

        if let ocr {
            let ocrText = truncatedPreviewText(ocr.text, limit: 260)
            let shouldAppendOCR = ocrText != nil
                && normalize(ocrText) != normalize(visionText)
            if shouldAppendOCR, let ocrText {
                let label: String
                if let language = normalizedPreviewText(ocr.language) {
                    label = "ocr text (\(language))"
                } else {
                    label = "ocr text"
                }
                lines.append("\(label): \(ocrText)")
            }
        }

        let rendered = lines.joined(separator: "\n")
        return rendered.isEmpty ? nil : rendered
    }

    private static func truncatedPreviewText(_ raw: String?, limit: Int) -> String? {
        guard let text = normalizedPreviewText(raw) else { return nil }
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "..."
    }

    private static func normalizedPreviewText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func resolvedPath(for attachment: AXChatAttachment) -> String {
        PathGuard.resolve(URL(fileURLWithPath: attachment.path)).path
    }

    private static func attachmentKey(for attachment: AXChatAttachment) -> String {
        resolvedPath(for: attachment).lowercased()
    }

    private static func previewCacheKey(for attachment: AXChatAttachment) -> String? {
        let resolvedPath = resolvedPath(for: attachment)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath) else {
            return nil
        }

        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(resolvedPath.lowercased())::\(fileSize)::\(Int(modifiedAt))"
    }

    private static func cachedPreview(for cacheKey: String) -> CacheLookupResult {
        previewLock.lock()
        defer { previewLock.unlock() }

        guard let entry = previewCache[cacheKey] else { return .miss }
        let age = Date().timeIntervalSince1970 - entry.storedAt
        guard age <= previewCacheTTL else {
            previewCache.removeValue(forKey: cacheKey)
            return .miss
        }
        return .hit(entry.preview)
    }

    private static func storePreview(_ preview: String?, for cacheKey: String) {
        previewLock.lock()
        previewCache[cacheKey] = CacheEntry(
            preview: preview,
            storedAt: Date().timeIntervalSince1970
        )
        previewLock.unlock()
    }

    private static func snapshotLoaderForTesting() -> SnapshotLoaderForTesting? {
        previewLock.lock()
        defer { previewLock.unlock() }
        return snapshotLoaderOverrideForTesting
    }

    private static func localTaskExecutorForTesting() -> LocalTaskExecutorForTesting? {
        previewLock.lock()
        defer { previewLock.unlock() }
        return localTaskExecutorOverrideForTesting
    }

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
