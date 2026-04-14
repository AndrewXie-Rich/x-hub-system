import Foundation

enum AXChatTurnMultimodalInput {
    typealias SnapshotLoaderForTesting = @Sendable () -> ModelStateSnapshot?
    typealias LocalTaskExecutorForTesting = @Sendable (
        String,
        String,
        [String: JSONValue],
        Double
    ) -> HubIPCClient.LocalTaskResult

    private struct CacheEntry {
        var summary: String?
        var storedAt: TimeInterval
    }

    private enum CacheLookupResult {
        case hit(String?)
        case miss
    }

    private struct TaskSelection {
        var taskKind: String
        var selectionReason: String
        var model: HubModel
    }

    private struct OCRSpan {
        var fileName: String?
        var pageIndex: Int?
        var pageCount: Int?
        var text: String
    }

    private static let cacheTTL: TimeInterval = 30.0
    private static let timeoutSecVision = 4.0
    private static let timeoutSecOCR = 4.0
    private static let maxImagesPerTurn = 4
    private static let lock = NSLock()
    private static var cache: [String: CacheEntry] = [:]
    private static var snapshotLoaderOverrideForTesting: SnapshotLoaderForTesting?
    private static var localTaskExecutorOverrideForTesting: LocalTaskExecutorForTesting?

    private static let genericAttachmentPrompts: Set<String> = [
        "请先阅读并理解我附带的文件。",
        "请先阅读并理解我附带的这些文件。",
        "请先阅读并处理我附带的文件。",
        "请先阅读并处理我附带的这些文件。"
    ]

    private static let ocrPromptHints = [
        "ocr", "extract text", "read text", "read the text", "transcribe",
        "receipt", "invoice", "scan", "subtitle", "document", "screenshot text",
        "识别", "提取", "文字", "文本", "转写", "收据", "发票", "截图", "扫描", "文档"
    ]

    static func summary(
        userText: String,
        attachments: [AXChatAttachment]
    ) async -> String? {
        let imageAttachments = imageAttachments(from: attachments)
        guard !imageAttachments.isEmpty else { return nil }

        return await Task.detached(priority: .utility) {
            summarySync(
                userText: userText,
                attachments: imageAttachments
            )
        }.value
    }

    static func installTestingOverrides(
        snapshotLoader: SnapshotLoaderForTesting? = nil,
        localTaskExecutor: LocalTaskExecutorForTesting? = nil
    ) {
        lock.lock()
        snapshotLoaderOverrideForTesting = snapshotLoader
        localTaskExecutorOverrideForTesting = localTaskExecutor
        cache.removeAll()
        lock.unlock()
    }

    static func resetTestingOverrides() {
        installTestingOverrides()
    }

    private static func summarySync(
        userText: String,
        attachments: [AXChatAttachment]
    ) -> String? {
        guard let cacheKey = cacheKey(userText: userText, attachments: attachments) else {
            return nil
        }
        switch cachedSummary(for: cacheKey) {
        case .hit(let cached):
            return cached
        case .miss:
            break
        }

        let snapshot = loadSnapshot()
        let visionModel = selectModel(for: "vision_understand", in: snapshot)
        let ocrModel = selectModel(for: "ocr", in: snapshot)
        guard let selection = selectedTask(
            userText: userText,
            visionModel: visionModel,
            ocrModel: ocrModel
        ) else {
            storeSummary(nil, for: cacheKey)
            return nil
        }

        let resolvedImages = attachments.map(resolvedPath(for:))
        let promptText = normalizedPromptText(
            userText,
            taskKind: selection.taskKind,
            imageCount: resolvedImages.count
        )
        let parameters = requestParameters(
            taskKind: selection.taskKind,
            promptText: promptText,
            imagePaths: resolvedImages
        )
        let result = executeLocalTask(
            taskKind: selection.taskKind,
            modelID: selection.model.id,
            parameters: parameters,
            timeoutSec: selection.taskKind == "ocr" ? timeoutSecOCR : timeoutSecVision
        )

        guard result.ok else {
            storeSummary(nil, for: cacheKey)
            return nil
        }

        let summary = renderedSummary(
            from: result,
            selection: selection,
            promptText: promptText,
            imageAttachments: attachments
        )
        storeSummary(summary, for: cacheKey)
        return summary
    }

    private static func imageAttachments(from attachments: [AXChatAttachment]) -> [AXChatAttachment] {
        var ordered: [AXChatAttachment] = []
        var seen = Set<String>()

        for attachment in attachments where AXChatAttachmentLocalModelPreview.canUseLocalPreview(for: attachment) {
            let resolvedPath = resolvedPath(for: attachment).lowercased()
            guard seen.insert(resolvedPath).inserted else { continue }
            ordered.append(attachment)
            if ordered.count >= maxImagesPerTurn {
                break
            }
        }

        return ordered
    }

    private static func selectedTask(
        userText: String,
        visionModel: HubModel?,
        ocrModel: HubModel?
    ) -> TaskSelection? {
        let prefersOCR = promptLooksLikeOCR(userText)

        if prefersOCR, let ocrModel {
            return TaskSelection(
                taskKind: "ocr",
                selectionReason: "ocr_prompt_heuristic",
                model: ocrModel
            )
        }
        if let visionModel, ocrModel == nil {
            return TaskSelection(
                taskKind: "vision_understand",
                selectionReason: "model_only_vision_understand",
                model: visionModel
            )
        }
        if visionModel == nil, let ocrModel {
            return TaskSelection(
                taskKind: "ocr",
                selectionReason: "model_only_ocr",
                model: ocrModel
            )
        }
        if let visionModel {
            return TaskSelection(
                taskKind: "vision_understand",
                selectionReason: "default_multimodal_attachment_understand",
                model: visionModel
            )
        }
        return nil
    }

    private static func promptLooksLikeOCR(_ userText: String) -> Bool {
        let normalized = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return ocrPromptHints.contains(where: { normalized.contains($0) })
    }

    private static func normalizedPromptText(
        _ raw: String,
        taskKind: String,
        imageCount: Int
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || genericAttachmentPrompts.contains(trimmed) {
            if taskKind == "ocr" {
                return imageCount > 1
                    ? "Extract all readable text from these attached images."
                    : "Extract all readable text from this attached image."
            }
            return imageCount > 1
                ? "Describe the attached images for the current coding turn."
                : "Describe the attached image for the current coding turn."
        }
        return trimmed
    }

    private static func requestParameters(
        taskKind: String,
        promptText: String,
        imagePaths: [String]
    ) -> [String: JSONValue] {
        let multimodalContent: [JSONValue] =
            [.object(["type": .string("text"), "text": .string(promptText)])]
            + imagePaths.map { imagePath in
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("file://\(imagePath)")
                    ])
                ])
            }

        var parameters: [String: JSONValue] = [
            "prompt": .string(promptText),
            "image_path": .string(imagePaths.first ?? ""),
            "image_paths": .array(imagePaths.map(JSONValue.string)),
            "multimodal_messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .array(multimodalContent)
                ])
            ])
        ]

        if taskKind == "ocr" {
            parameters["options"] = .object([
                "language": .string("auto")
            ])
        }

        return parameters
    }

    private static func renderedSummary(
        from result: HubIPCClient.LocalTaskResult,
        selection: TaskSelection,
        promptText: String,
        imageAttachments: [AXChatAttachment]
    ) -> String? {
        let payload = result.payload
        let routeTrace = payload["routeTrace"]?.objectValue ?? payload["route_trace"]?.objectValue
        let selectionReason = normalizedText(
            routeTrace?["selectionReason"]?.stringValue
                ?? routeTrace?["selection_reason"]?.stringValue
        ) ?? selection.selectionReason
        let runtimeTaskKind = normalizedText(
            result.taskKind
                ?? payload["taskKind"]?.stringValue
                ?? payload["task_kind"]?.stringValue
        ) ?? selection.taskKind
        let modelID = normalizedText(
            result.modelId
                ?? payload["modelId"]?.stringValue
                ?? payload["model_id"]?.stringValue
        ) ?? selection.model.id

        let summaryText = normalizedText(payload["text"]?.stringValue)
        let spans = ocrSpans(from: payload["spans"])
        guard summaryText != nil || !spans.isEmpty else { return nil }

        var lines: [String] = [
            "Current-turn multimodal inputs:",
            "- The current-turn image attachments were routed through Hub local multimodal task IPC. Treat this as attachment-derived evidence, not user-authored text.",
            "- task_kind=\(runtimeTaskKind) model_id=\(modelID) image_count=\(imageAttachments.count) selection_reason=\(selectionReason)"
        ]

        let fileList = imageAttachments.map { $0.displayName }
        if !fileList.isEmpty {
            lines.append("- image_files=\(fileList.joined(separator: ", "))")
        }

        if !promptText.isEmpty {
            lines.append("- turn_prompt=\(promptText)")
        }

        if let summaryText {
            let heading = runtimeTaskKind == "ocr" ? "- extracted_text:" : "- image_understanding:"
            lines.append(heading)
            lines.append(indent(truncated(summaryText, limit: 1_000), prefix: "  "))
        }

        if !spans.isEmpty {
            lines.append("- page_spans:")
            for span in spans.prefix(6) {
                var row = "- "
                if let fileName = span.fileName {
                    row += "file=\(fileName) "
                }
                if let pageIndex = span.pageIndex {
                    let pageCount = max(1, span.pageCount ?? 1)
                    row += "page=\(pageIndex + 1)/\(pageCount) "
                }
                row += "text=\(truncated(span.text, limit: 180))"
                lines.append("  " + row)
            }
            if spans.count > 6 {
                lines.append("  - ... \(spans.count - 6) more span(s) omitted.")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func ocrSpans(from value: JSONValue?) -> [OCRSpan] {
        guard let rows = value?.arrayValue else { return [] }
        var spans: [OCRSpan] = []

        for row in rows {
            guard let object = row.objectValue,
                  let text = normalizedText(object["text"]?.stringValue) else {
                continue
            }

            spans.append(
                OCRSpan(
                    fileName: normalizedText(object["fileName"]?.stringValue ?? object["file_name"]?.stringValue),
                    pageIndex: object["pageIndex"]?.intValue ?? object["page_index"]?.intValue,
                    pageCount: object["pageCount"]?.intValue ?? object["page_count"]?.intValue,
                    text: text
                )
            )
        }

        return spans
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

    private static func loadSnapshot() -> ModelStateSnapshot {
        if let override = snapshotLoaderOverride() {
            return override() ?? .empty()
        }

        let url = HubPaths.modelsStateURL()
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ModelStateSnapshot.self, from: data) else {
            return .empty()
        }
        return snapshot
    }

    private static func executeLocalTask(
        taskKind: String,
        modelID: String,
        parameters: [String: JSONValue],
        timeoutSec: Double
    ) -> HubIPCClient.LocalTaskResult {
        if let override = localTaskExecutorOverride() {
            return override(taskKind, modelID, parameters, timeoutSec)
        }

        return HubIPCClient.executeLocalTaskViaLocalHub(
            taskKind: taskKind,
            modelID: modelID,
            parameters: parameters,
            timeoutSec: timeoutSec
        )
    }

    private static func cacheKey(
        userText: String,
        attachments: [AXChatAttachment]
    ) -> String? {
        let normalizedPrompt = normalizedText(userText) ?? ""
        let imageKeys = attachments.compactMap(imageCacheToken(for:))
        guard !imageKeys.isEmpty else { return nil }
        return imageKeys.joined(separator: "::") + "::" + normalizedPrompt.lowercased()
    }

    private static func imageCacheToken(for attachment: AXChatAttachment) -> String? {
        let resolvedPath = resolvedPath(for: attachment)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath) else {
            return nil
        }
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(resolvedPath.lowercased())::\(fileSize)::\(Int(modifiedAt))"
    }

    private static func cachedSummary(for key: String) -> CacheLookupResult {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else { return .miss }
        let age = Date().timeIntervalSince1970 - entry.storedAt
        guard age <= cacheTTL else {
            cache.removeValue(forKey: key)
            return .miss
        }
        return .hit(entry.summary)
    }

    private static func storeSummary(_ summary: String?, for key: String) {
        lock.lock()
        cache[key] = CacheEntry(summary: summary, storedAt: Date().timeIntervalSince1970)
        lock.unlock()
    }

    private static func snapshotLoaderOverride() -> SnapshotLoaderForTesting? {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLoaderOverrideForTesting
    }

    private static func localTaskExecutorOverride() -> LocalTaskExecutorForTesting? {
        lock.lock()
        defer { lock.unlock() }
        return localTaskExecutorOverrideForTesting
    }

    private static func resolvedPath(for attachment: AXChatAttachment) -> String {
        PathGuard.resolve(URL(fileURLWithPath: attachment.path)).path
    }

    private static func normalizedText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func truncated(_ raw: String, limit: Int) -> String {
        guard raw.count > limit else { return raw }
        let end = raw.index(raw.startIndex, offsetBy: limit)
        return String(raw[..<end]) + "..."
    }

    private static func indent(_ text: String, prefix: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
