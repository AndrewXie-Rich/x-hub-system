import Foundation

enum AXChatAttachmentKind: String, Codable, Equatable, Sendable {
    case file
    case directory
}

enum AXChatAttachmentScope: String, Codable, Equatable, Sendable {
    case projectWorkspace = "project_workspace"
    case attachmentReadOnly = "attachment_read_only"
}

struct AXChatAttachmentImportResult: Equatable, Sendable {
    var sourceAttachment: AXChatAttachment
    var importedAttachment: AXChatAttachment
    var destinationURL: URL
}

struct AXChatImportContinuationSuggestion: Identifiable, Equatable, Sendable {
    var id: String
    var headline: String
    var detail: String
    var placementHint: String
    var linkedFilesHint: String
    var suggestedPrompt: String
    var importedAttachmentPaths: [String]

    init(
        id: String = UUID().uuidString,
        headline: String,
        detail: String,
        placementHint: String,
        linkedFilesHint: String,
        suggestedPrompt: String,
        importedAttachmentPaths: [String]
    ) {
        self.id = id
        self.headline = headline
        self.detail = detail
        self.placementHint = placementHint
        self.linkedFilesHint = linkedFilesHint
        self.suggestedPrompt = suggestedPrompt
        self.importedAttachmentPaths = importedAttachmentPaths
    }

    func isRelevant(to attachments: [AXChatAttachment]) -> Bool {
        let currentPaths = Set(
            attachments.map { PathGuard.resolve(URL(fileURLWithPath: $0.path)).path }
        )
        return importedAttachmentPaths.contains(where: currentPaths.contains)
    }
}

extension AXChatAttachment {
    var toolPath: String {
        let relative = (relativePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return relative.isEmpty ? path : relative
    }

    var displayPath: String {
        let relative = (relativePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return relative.isEmpty ? path : relative
    }

    var isReadOnlyExternal: Bool {
        scope == .attachmentReadOnly
    }

    var scopeBadgeText: String {
        switch scope {
        case .projectWorkspace:
            return "项目内"
        case .attachmentReadOnly:
            return "只读附件"
        }
    }
}

enum AXChatAttachmentSupport {
    private static let previewByteLimit = 16_384
    private static let previewCharLimit = 1_200
    private static let directoryPreviewEntryLimit = 18
    private static let promptAttachmentLimit = 6
    private enum ImportContinuationKind {
        case code
        case config
        case docs
        case asset
        case data
        case directory
        case mixed
        case generic
    }

    static func defaultUserPrompt(for attachments: [AXChatAttachment]) -> String {
        let filtered = orderedUniqueAttachments(attachments)
        guard !filtered.isEmpty else { return "" }
        let allReadOnly = filtered.allSatisfy(\.isReadOnlyExternal)
        if filtered.count == 1 {
            return allReadOnly
                ? "请先阅读并理解我附带的文件。"
                : "请先阅读并处理我附带的文件。"
        }
        return allReadOnly
            ? "请先阅读并理解我附带的这些文件。"
            : "请先阅读并处理我附带的这些文件。"
    }

    static func normalizedUserPrompt(
        draft: String,
        attachments: [AXChatAttachment]
    ) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let attachmentPrompt = defaultUserPrompt(for: attachments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return attachmentPrompt.isEmpty ? nil : attachmentPrompt
    }

    static func hasSubmittableContent(
        draft: String,
        attachments: [AXChatAttachment]
    ) -> Bool {
        normalizedUserPrompt(draft: draft, attachments: attachments) != nil
    }

    static func merge(existing: [AXChatAttachment], resolved: [AXChatAttachment]) -> [AXChatAttachment] {
        orderedUniqueAttachments(existing + resolved)
    }

    static func resolveDroppedURLs(
        _ urls: [URL],
        projectRoot: URL?
    ) -> [AXChatAttachment] {
        orderedUniqueAttachments(
            urls.compactMap { resolveAttachment(url: $0, projectRoot: projectRoot) }
        )
    }

    static func readableRoots(for attachments: [AXChatAttachment]) -> [URL] {
        var ordered: [URL] = []
        var seen = Set<String>()

        for attachment in orderedUniqueAttachments(attachments) where attachment.isReadOnlyExternal {
            let resolved = PathGuard.resolve(URL(fileURLWithPath: attachment.path)).path
            guard seen.insert(resolved).inserted else { continue }
            ordered.append(URL(fileURLWithPath: resolved, isDirectory: attachment.kind == .directory))
        }

        return ordered
    }

    static func promptSummary(
        currentTurnAttachments: [AXChatAttachment],
        activeAttachments: [AXChatAttachment],
        projectRoot: URL?,
        previewOverrides: [String: String] = [:]
    ) -> String {
        let current = orderedUniqueAttachments(currentTurnAttachments)
        let active = orderedUniqueAttachments(activeAttachments)
        guard !active.isEmpty else { return "" }

        let currentKeys = Set(current.map(attachmentKey))
        var lines: [String] = [
            "Attachment Context:",
            "- Attached paths may be read with `read_file`. If an attachment is a directory, you may also use `list_dir` or `search` within that directory.",
            "- External attachments are read-only and exact-path scoped. Do not use `write_file`, `move_path`, or `delete_path` on those external paths.",
            "- If you need to modify an external attachment, ask for it to be imported into the project workspace first or tell the user which project-relative destination you need.",
        ]

        let limited = Array(active.prefix(promptAttachmentLimit))
        for attachment in limited {
            lines.append(promptLine(for: attachment, projectRoot: projectRoot))
            if currentKeys.contains(attachmentKey(attachment)) {
                let overridePreview = normalizedPreviewOverride(
                    previewOverrides[attachmentKey(attachment)]
                )
                let preview = overridePreview ?? previewSummary(for: attachment)
                if !preview.isEmpty {
                    lines.append("  preview:")
                    lines.append(indent(preview, prefix: "    "))
                }
            }
        }

        if active.count > limited.count {
            lines.append("- ... \(active.count - limited.count) more attachment(s) omitted.")
        }

        return lines.joined(separator: "\n")
    }

    static func importAttachment(
        _ attachment: AXChatAttachment,
        into projectRoot: URL
    ) throws -> AXChatAttachmentImportResult {
        let sourceURL = PathGuard.resolve(URL(fileURLWithPath: attachment.path))
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw NSError(
                domain: "xterminal",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Attachment no longer exists: \(sourceURL.path)"]
            )
        }

        let importContainer = projectRoot.appendingPathComponent("Imported Attachments", isDirectory: true)
        try fm.createDirectory(at: importContainer, withIntermediateDirectories: true)

        let destinationURL = uniqueImportDestination(
            preferredName: sanitizedImportName(attachment.displayName),
            in: importContainer,
            isDirectory: isDirectory.boolValue
        )
        try fm.copyItem(at: sourceURL, to: destinationURL)

        guard let importedAttachment = resolveAttachment(url: destinationURL, projectRoot: projectRoot) else {
            throw NSError(
                domain: "xterminal",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to describe imported attachment: \(destinationURL.path)"]
            )
        }

        return AXChatAttachmentImportResult(
            sourceAttachment: attachment,
            importedAttachment: importedAttachment,
            destinationURL: destinationURL
        )
    }

    static func importSuccessNotice(_ result: AXChatAttachmentImportResult) -> String {
        "已将附件 `\(result.sourceAttachment.displayName)` 导入项目工作区：`\(result.importedAttachment.displayPath)`。外部原件仍保持只读，后续请基于项目内副本继续。"
    }

    static func importSuccessNotice(
        results: [AXChatAttachmentImportResult]
    ) -> String? {
        let filtered = results.filter { !$0.importedAttachment.displayPath.isEmpty }
        guard !filtered.isEmpty else { return nil }
        if filtered.count == 1, let first = filtered.first {
            return importSuccessNotice(first)
        }

        let preview = filtered
            .prefix(3)
            .map { "`\($0.importedAttachment.displayPath)`" }
            .joined(separator: "、")
        let suffix = filtered.count > 3 ? " 等 \(filtered.count) 个文件" : ""
        return "已将 \(filtered.count) 个附件导入项目工作区：\(preview)\(suffix)。外部原件仍保持只读；可直接在 Project Inbox 中点 Import & Continue，继续基于项目内副本开发。"
    }

    static func importContinuationSuggestion(
        results: [AXChatAttachmentImportResult],
        projectRoot: URL? = nil
    ) -> AXChatImportContinuationSuggestion? {
        let attachments = results.map(\.importedAttachment)
        guard !attachments.isEmpty else { return nil }

        let kind = continuationKind(for: attachments)
        let workspace = workspaceSnapshot(projectRoot: projectRoot)
        let displayPaths = attachments.map(\.displayPath)
        let attachmentList = summarizedPathList(displayPaths)
        let importedPaths = attachments.map {
            PathGuard.resolve(URL(fileURLWithPath: $0.path)).path
        }

        let headline: String
        let detail: String
        let placementHint: String
        let linkedFilesHint: String
        let prompt: String

        if attachments.count == 1, let attachment = attachments.first {
            switch kind {
            case .code:
                headline = "代码文件已进入项目"
                detail = "它现在已经是项目内副本，可以直接读写并联动当前工程里的其他文件。"
                placementHint = codePlacementHint(workspace: workspace)
                linkedFilesHint = codeLinkedFilesHint(workspace: workspace)
                prompt = "我已把 `\(attachment.displayPath)` 导入项目。请先判断它在当前工程中的角色和影响范围，再继续完成接入或改造。"
            case .config:
                headline = "配置文件已进入项目"
                detail = "后续可以直接基于这个项目内副本调整配置，并同步需要联动的文件。"
                placementHint = configPlacementHint(workspace: workspace)
                linkedFilesHint = configLinkedFilesHint(workspace: workspace)
                prompt = "我已把 `\(attachment.displayPath)` 导入项目。请先说明它在当前项目中的配置用途，再继续完成接入并指出需要联动的文件。"
            case .docs:
                headline = "参考文档已进入项目"
                detail = "现在可以把它当成项目内资料继续消化，并转成可执行的改动或文档。"
                placementHint = docsPlacementHint(workspace: workspace)
                linkedFilesHint = docsLinkedFilesHint(workspace: workspace)
                prompt = "我已把 `\(attachment.displayPath)` 导入项目。请先提炼其中对当前项目最重要的信息，再继续把它转成可执行的改动或文档。"
            case .asset:
                headline = "资源文件已进入项目"
                detail = "现在可以直接把它纳入工作区资源并继续完成落位、引用或配套修改。"
                placementHint = assetPlacementHint(workspace: workspace)
                linkedFilesHint = assetLinkedFilesHint(workspace: workspace)
                prompt = "我已把 `\(attachment.displayPath)` 导入项目。请先判断它适合放在项目里的哪里，再继续完成接入或配套修改。"
            case .data:
                headline = "数据文件已进入项目"
                detail = "它已经变成项目内副本，可以直接分析结构、转换内容并继续接入。"
                placementHint = dataPlacementHint(workspace: workspace)
                linkedFilesHint = dataLinkedFilesHint(workspace: workspace)
                prompt = "我已把 `\(attachment.displayPath)` 导入项目。请先判断它的数据结构和用途，再继续完成接入或转换。"
            case .directory:
                headline = "目录已进入项目"
                detail = "现在可以按项目内目录继续梳理结构、筛选文件并推进接入。"
                placementHint = directoryPlacementHint(workspace: workspace)
                linkedFilesHint = directoryLinkedFilesHint(workspace: workspace)
                prompt = "我已把目录 `\(attachment.displayPath)` 导入项目。请先梳理这个目录的结构和用途，再继续完成接入或整理。"
            case .mixed, .generic:
                headline = "文件已进入项目"
                detail = "现在它已经是项目内副本，可以直接按项目文件继续理解、修改和联动。"
                placementHint = genericPlacementHint(workspace: workspace)
                linkedFilesHint = genericLinkedFilesHint(workspace: workspace)
                prompt = "我已把 `\(attachment.displayPath)` 导入项目。请先判断它在当前项目中的用途，再继续完成需要的处理。"
            }
        } else {
            switch kind {
            case .code:
                headline = "\(attachments.count) 个代码文件已进入项目"
                detail = "这些文件现在都在项目工作区内，适合先梳理关系，再继续批量接入或改造。"
                placementHint = codePlacementHint(workspace: workspace, batch: true)
                linkedFilesHint = codeLinkedFilesHint(workspace: workspace, batch: true)
                prompt = "我已把这些代码文件导入项目：\(attachmentList)。请先梳理它们之间的关系、在当前工程里的落位和影响范围，再继续完成接入或改造。"
            case .config:
                headline = "\(attachments.count) 个配置文件已进入项目"
                detail = "它们已经可以按项目内配置继续联动检查，适合先统一梳理，再继续接入。"
                placementHint = configPlacementHint(workspace: workspace, batch: true)
                linkedFilesHint = configLinkedFilesHint(workspace: workspace, batch: true)
                prompt = "我已把这些配置文件导入项目：\(attachmentList)。请先统一梳理配置含义和依赖关系，再继续完成接入。"
            case .docs:
                headline = "\(attachments.count) 份资料已进入项目"
                detail = "这些文档现在已经纳入项目上下文，适合先抽取关键信息，再继续推进实现。"
                placementHint = docsPlacementHint(workspace: workspace, batch: true)
                linkedFilesHint = docsLinkedFilesHint(workspace: workspace, batch: true)
                prompt = "我已把这些参考资料导入项目：\(attachmentList)。请先提炼对当前项目最重要的信息和约束，再继续把它们转成可执行的改动或文档。"
            case .asset:
                headline = "\(attachments.count) 个资源文件已进入项目"
                detail = "这些资源现在可以直接在工作区里落位、引用，并继续完成相关接入。"
                placementHint = assetPlacementHint(workspace: workspace, batch: true)
                linkedFilesHint = assetLinkedFilesHint(workspace: workspace, batch: true)
                prompt = "我已把这些资源文件导入项目：\(attachmentList)。请先判断它们在项目里的建议落位和引用方式，再继续完成接入或配套修改。"
            case .data:
                headline = "\(attachments.count) 个数据文件已进入项目"
                detail = "它们现在都可按项目内文件继续分析和转换，适合先梳理结构，再继续接入。"
                placementHint = dataPlacementHint(workspace: workspace, batch: true)
                linkedFilesHint = dataLinkedFilesHint(workspace: workspace, batch: true)
                prompt = "我已把这些数据文件导入项目：\(attachmentList)。请先判断它们的数据结构和用途，再继续完成接入或转换。"
            case .directory:
                headline = "\(attachments.count) 个目录已进入项目"
                detail = "这些目录已经变成项目内副本，适合先梳理结构和职责，再继续处理。"
                placementHint = directoryPlacementHint(workspace: workspace, batch: true)
                linkedFilesHint = directoryLinkedFilesHint(workspace: workspace, batch: true)
                prompt = "我已把这些目录导入项目：\(attachmentList)。请先梳理它们的结构和用途，再继续完成接入或整理。"
            case .mixed, .generic:
                headline = "\(attachments.count) 个文件已进入项目"
                detail = "这些文件现在都在工作区里，建议先按代码、配置、文档或资源分类，再继续当前任务。"
                placementHint = genericPlacementHint(workspace: workspace, batch: true)
                linkedFilesHint = genericLinkedFilesHint(workspace: workspace, batch: true)
                prompt = "我已把这些文件导入项目：\(attachmentList)。请先按代码、配置、文档或资源分类，说明建议落位和处理顺序，再继续当前任务。"
            }
        }

        return AXChatImportContinuationSuggestion(
            headline: headline,
            detail: detail,
            placementHint: placementHint,
            linkedFilesHint: linkedFilesHint,
            suggestedPrompt: prompt,
            importedAttachmentPaths: importedPaths
        )
    }

    static func draftApplyingImportContinuation(
        _ continuation: AXChatImportContinuationSuggestion,
        existingDraft: String
    ) -> String {
        return existingDraft
    }

    static func resolveAttachment(
        url: URL,
        projectRoot: URL?
    ) -> AXChatAttachment? {
        let standardized = PathGuard.resolve(url)
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            return nil
        }

        let kind: AXChatAttachmentKind = isDirectory.boolValue ? .directory : .file
        let sizeBytes: Int64?
        if let attributes = try? fm.attributesOfItem(atPath: standardized.path),
           let fileSize = attributes[.size] as? NSNumber {
            sizeBytes = fileSize.int64Value
        } else {
            sizeBytes = nil
        }

        let relativePath = projectRoot.flatMap { projectRelativePath(for: standardized, projectRoot: $0) }
        let scope: AXChatAttachmentScope = relativePath == nil ? .attachmentReadOnly : .projectWorkspace
        let displayName = standardized.lastPathComponent.isEmpty ? standardized.path : standardized.lastPathComponent

        return AXChatAttachment(
            displayName: displayName,
            path: standardized.path,
            relativePath: relativePath,
            kind: kind,
            scope: scope,
            sizeBytes: sizeBytes
        )
    }

    private static func promptLine(
        for attachment: AXChatAttachment,
        projectRoot: URL?
    ) -> String {
        let projectRelation: String
        if attachment.scope == .projectWorkspace {
            projectRelation = attachment.relativePath == "." ? "project_root" : "inside_project"
        } else if let projectRoot,
                  let relativePath = projectRelativePath(
                    for: URL(fileURLWithPath: attachment.path),
                    projectRoot: projectRoot
                  ) {
            projectRelation = relativePath == "." ? "project_root" : "inside_project"
        } else {
            projectRelation = "external_attachment"
        }

        let sizeSummary = attachment.sizeBytes.map { " size_bytes=\($0)" } ?? ""
        return "- name=\(attachment.displayName) kind=\(attachment.kind.rawValue) scope=\(attachment.scope.rawValue) project_relation=\(projectRelation) tool_path=\(attachment.toolPath)\(sizeSummary)"
    }

    private static func continuationKind(
        for attachments: [AXChatAttachment]
    ) -> ImportContinuationKind {
        let kinds = Set(attachments.map(continuationKind(for:)))
        guard kinds.count == 1 else { return .mixed }
        return kinds.first ?? .generic
    }

    private struct WorkspaceSnapshot {
        var directories: Set<String> = []
        var files: Set<String> = []

        func firstDirectory(from candidates: [String]) -> String? {
            candidates.first(where: { directories.contains($0) })
        }

        func firstFile(from candidates: [String]) -> String? {
            candidates.first(where: { files.contains($0) })
        }

        func existingDirectories(from candidates: [String], limit: Int) -> [String] {
            Array(candidates.filter { directories.contains($0) }.prefix(limit))
        }
    }

    private static func workspaceSnapshot(projectRoot: URL?) -> WorkspaceSnapshot {
        guard let projectRoot else { return WorkspaceSnapshot() }
        let fm = FileManager.default

        func directoryExists(_ relativePath: String) -> Bool {
            var isDirectory: ObjCBool = false
            let url = projectRoot.appendingPathComponent(relativePath, isDirectory: true)
            return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }

        func fileExists(_ relativePath: String) -> Bool {
            var isDirectory: ObjCBool = false
            let url = projectRoot.appendingPathComponent(relativePath)
            return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }

        var snapshot = WorkspaceSnapshot()
        let knownDirectories = Set(
            codePlacementCandidates
                + testDirectoryCandidates
                + configDirectoryCandidates
                + docsDirectoryCandidates
                + assetDirectoryCandidates
                + dataDirectoryCandidates
                + ["Imported Attachments"]
        )
        for relativePath in knownDirectories where directoryExists(relativePath) {
            snapshot.directories.insert(relativePath)
        }

        let knownFiles = Set(
            documentationFileCandidates
                + buildFileCandidates
                + configFileCandidates
        )
        for relativePath in knownFiles where fileExists(relativePath) {
            snapshot.files.insert(relativePath)
        }

        return snapshot
    }

    private static func codePlacementHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        let destination = workspace.firstDirectory(from: codePlacementCandidates) ?? "Sources"
        let qualifier = batch ? "批量核对" : "做评估"
        return "建议先留在 `Imported Attachments/` \(qualifier)；确认角色后再归位到 `\(destination)/` 或对应 feature 目录。"
    }

    private static func codeLinkedFilesHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        var targets: [String] = []
        if let tests = workspace.firstDirectory(from: testDirectoryCandidates) {
            targets.append("`\(tests)/` 下的同名测试")
        } else {
            targets.append("同名测试")
        }
        if let readme = workspace.firstFile(from: documentationFileCandidates) {
            targets.append("`\(readme)`")
        } else if let docs = workspace.firstDirectory(from: docsDirectoryCandidates) {
            targets.append("`\(docs)/`")
        } else {
            targets.append("相关 README/集成说明")
        }
        if let buildFile = workspace.firstFile(from: buildFileCandidates) {
            targets.append("`\(buildFile)`")
        } else {
            targets.append(batch ? "入口文件和依赖注入" : "入口调用点、依赖注入或路由注册")
        }
        return "优先检查" + targets.joined(separator: "、") + "。"
    }

    private static func configPlacementHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        if let destination = workspace.firstDirectory(from: configDirectoryCandidates) {
            return "建议先留在 `Imported Attachments/` 对比现有配置；稳定后再归位到 `\(destination)/` 或对应环境子目录。"
        }
        return batch
            ? "建议先留在 `Imported Attachments/` 对比现有配置，再归位到 `Config/`、根目录或环境子目录。"
            : "建议先留在 `Imported Attachments/` 对比现有配置；稳定后再归位到 `Config/`、根目录或环境配置目录。"
    }

    private static func configLinkedFilesHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        var targets: [String] = []
        if let buildFile = workspace.firstFile(from: buildFileCandidates) {
            targets.append("`\(buildFile)`")
        } else {
            targets.append("启动代码")
        }
        if let configSample = workspace.firstFile(from: configFileCandidates) {
            targets.append("`\(configSample)`")
        } else {
            targets.append(batch ? "环境装配逻辑" : "环境切换逻辑")
        }
        if let docs = workspace.firstDirectory(from: docsDirectoryCandidates) {
            targets.append("`\(docs)/`")
        } else if let readme = workspace.firstFile(from: documentationFileCandidates) {
            targets.append("`\(readme)`")
        } else {
            targets.append("部署文档")
        }
        return "重点检查读取它的" + targets.joined(separator: "、") + "。"
    }

    private static func docsPlacementHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        if let docs = workspace.firstDirectory(from: docsDirectoryCandidates) {
            return "建议先保留在 `Imported Attachments/` 做整理，确认长期价值后再归位到 `\(docs)/` 或知识目录。"
        }
        if let readme = workspace.firstFile(from: documentationFileCandidates) {
            return "建议先保留在 `Imported Attachments/` 做整理，确认长期价值后再归位到 `\(readme)` 或知识目录。"
        }
        return batch
            ? "建议先保留在 `Imported Attachments/` 汇总，再把长期资料归位到 `docs/`、`README` 或知识目录。"
            : "建议保留在 `Imported Attachments/` 做整理，确认长期价值后再归位到 `docs/`、`README` 或知识目录。"
    }

    private static func docsLinkedFilesHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        var targets: [String] = []
        if let readme = workspace.firstFile(from: documentationFileCandidates) {
            targets.append("`\(readme)`")
        } else {
            targets.append("README")
        }
        if let code = workspace.firstDirectory(from: codePlacementCandidates) {
            targets.append("`\(code)/`")
        } else {
            targets.append("实现文件")
        }
        if let tests = workspace.firstDirectory(from: testDirectoryCandidates) {
            targets.append("`\(tests)/`")
        } else {
            targets.append(batch ? "测试计划" : "测试/验收文档")
        }
        return "重点联动" + targets.joined(separator: "、") + "。"
    }

    private static func assetPlacementHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        let destinations = workspace.existingDirectories(from: assetDirectoryCandidates, limit: 2)
        if !destinations.isEmpty {
            let rendered = destinations.map { "`\($0)/`" }.joined(separator: "、")
            return batch
                ? "建议按资源类型归位到 \(rendered) 或对应模块资源目录，并统一命名。"
                : "建议归位到 \(rendered) 或对应模块资源目录；先确认命名和引用方式。"
        }
        return batch
            ? "建议按资源类型归位到 `Assets/`、`Resources/` 或对应模块资源目录，并统一命名。"
            : "建议归位到 `Assets/`、`Resources/` 或对应模块资源目录；先确认命名和引用方式。"
    }

    private static func assetLinkedFilesHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        var targets: [String] = []
        if let code = workspace.firstDirectory(from: codePlacementCandidates) {
            targets.append("`\(code)/` 里的 UI/渲染代码")
        } else {
            targets.append("引用它的 SwiftUI/View 代码")
        }
        if let assetRoot = workspace.firstDirectory(from: assetDirectoryCandidates) {
            targets.append("`\(assetRoot)/` 的资源注册")
        } else {
            targets.append("资源注册")
        }
        if let readme = workspace.firstFile(from: documentationFileCandidates) {
            targets.append("`\(readme)`")
        } else {
            targets.append(batch ? "配套说明" : "相关说明文档")
        }
        return "重点联动" + targets.joined(separator: "、") + "。"
    }

    private static func dataPlacementHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        let destination = workspace.firstDirectory(from: dataDirectoryCandidates)
            ?? workspace.firstDirectory(from: configDirectoryCandidates)
        if let destination {
            return batch
                ? "建议先在 `Imported Attachments/` 做结构核对，再归位到 `\(destination)/` 或关联目录。"
                : "建议先保留在 `Imported Attachments/` 验证结构，再归位到 `\(destination)/` 或关联目录。"
        }
        return batch
            ? "建议先在 `Imported Attachments/` 做结构核对，再归位到 `Data/`、`Fixtures/` 或 `Config/`。"
            : "建议先保留在 `Imported Attachments/` 验证结构，再归位到 `Data/`、`Fixtures/` 或 `Config/`。"
    }

    private static func dataLinkedFilesHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        var targets: [String] = []
        if let code = workspace.firstDirectory(from: codePlacementCandidates) {
            targets.append("`\(code)/` 里的解析器")
        } else {
            targets.append("解析器")
        }
        if let tests = workspace.firstDirectory(from: testDirectoryCandidates) {
            targets.append("`\(tests)/` 里的 fixture 测试")
        } else {
            targets.append(batch ? "fixture 测试" : "测试 fixture")
        }
        if let config = workspace.firstDirectory(from: configDirectoryCandidates) {
            targets.append("`\(config)/` 里的 schema/转换脚本")
        } else {
            targets.append(batch ? "schema 和转换工具" : "schema 校验")
        }
        return "重点联动" + targets.joined(separator: "、") + "。"
    }

    private static func directoryPlacementHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        let targets = workspace.existingDirectories(
            from: codePlacementCandidates + docsDirectoryCandidates + assetDirectoryCandidates,
            limit: 3
        )
        if !targets.isEmpty {
            let rendered = targets.map { "`\($0)/`" }.joined(separator: "、")
            return batch
                ? "建议先整体保留在 `Imported Attachments/`，确认目录职责后再按模块拆分到 \(rendered)。"
                : "建议先整体保留在 `Imported Attachments/`，确认结构后再拆分归位到 \(rendered)。"
        }
        return batch
            ? "建议先整体保留在 `Imported Attachments/`，确认目录职责后再分批归位。"
            : "建议先整体保留在 `Imported Attachments/`，确认结构后再拆分归位到业务目录。"
    }

    private static func directoryLinkedFilesHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        var targets: [String] = []
        if let buildFile = workspace.firstFile(from: buildFileCandidates) {
            targets.append("`\(buildFile)`")
        } else {
            targets.append("构建脚本")
        }
        if let readme = workspace.firstFile(from: documentationFileCandidates) {
            targets.append("`\(readme)`")
        } else if let docs = workspace.firstDirectory(from: docsDirectoryCandidates) {
            targets.append("`\(docs)/`")
        } else {
            targets.append(batch ? "目录级说明" : "目录级说明文档")
        }
        targets.append(batch ? "入口文件和索引文件" : "目录入口文件、索引文件")
        return "重点联动" + targets.joined(separator: "、") + "。"
    }

    private static func genericPlacementHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        let targets = workspace.existingDirectories(
            from: codePlacementCandidates + configDirectoryCandidates + docsDirectoryCandidates + assetDirectoryCandidates,
            limit: 4
        )
        if !targets.isEmpty {
            let rendered = targets.map { "`\($0)/`" }.joined(separator: "、")
            return batch
                ? "建议先保留在 `Imported Attachments/`，按类型分组后再归位到 \(rendered)。"
                : "建议先留在 `Imported Attachments/`，确认类型和用途后再归位到 \(rendered)。"
        }
        return batch
            ? "建议先保留在 `Imported Attachments/`，按代码、配置、文档和资源分组后再归位。"
            : "建议先留在 `Imported Attachments/`，确认类型和用途后再归位到代码、文档或资源目录。"
    }

    private static func genericLinkedFilesHint(
        workspace: WorkspaceSnapshot,
        batch: Bool = false
    ) -> String {
        var targets: [String] = []
        if let code = workspace.firstDirectory(from: codePlacementCandidates) {
            targets.append("`\(code)/`")
        } else {
            targets.append("实现文件")
        }
        if let config = workspace.firstDirectory(from: configDirectoryCandidates) {
            targets.append("`\(config)/`")
        } else {
            targets.append("配置")
        }
        if let tests = workspace.firstDirectory(from: testDirectoryCandidates) {
            targets.append("`\(tests)/`")
        } else {
            targets.append("测试")
        }
        if let readme = workspace.firstFile(from: documentationFileCandidates) {
            targets.append("`\(readme)`")
        } else {
            targets.append(batch ? "README 和资源引用" : "说明文档")
        }
        return "通常会联动" + targets.joined(separator: "、") + "。"
    }

    private static func continuationKind(
        for attachment: AXChatAttachment
    ) -> ImportContinuationKind {
        if attachment.kind == .directory {
            return .directory
        }

        let ext = URL(fileURLWithPath: attachment.path)
            .pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if Self.codeExtensions.contains(ext) {
            return .code
        }
        if Self.configExtensions.contains(ext) {
            return .config
        }
        if Self.docsExtensions.contains(ext) {
            return .docs
        }
        if Self.assetExtensions.contains(ext) {
            return .asset
        }
        if Self.dataExtensions.contains(ext) {
            return .data
        }
        return .generic
    }

    private static func summarizedPathList(_ paths: [String]) -> String {
        let filtered = paths.map { "`\($0)`" }
        guard filtered.count > 3 else {
            return filtered.joined(separator: "、")
        }
        return filtered.prefix(3).joined(separator: "、") + " 等 \(filtered.count) 个文件"
    }

    private static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "js", "jsx", "cjs", "mjs",
        "ts", "tsx", "py", "rb", "go", "rs", "java", "kt", "kts", "scala", "php",
        "cs", "html", "css", "scss", "sass", "less", "vue", "svelte", "sql", "sh",
        "bash", "zsh"
    ]

    private static let codePlacementCandidates = [
        "Sources", "src", "App", "app", "lib"
    ]

    private static let testDirectoryCandidates = [
        "Tests", "test", "tests", "__tests__", "spec"
    ]

    private static let configDirectoryCandidates = [
        "Config", "Configs", "config"
    ]

    private static let docsDirectoryCandidates = [
        "docs", "Docs"
    ]

    private static let assetDirectoryCandidates = [
        "Assets", "Resources", "assets", "public", "static"
    ]

    private static let dataDirectoryCandidates = [
        "Data", "Fixtures", "fixtures", "SampleData", "Samples"
    ]

    private static let documentationFileCandidates = [
        "README.md", "README.MD", "Readme.md"
    ]

    private static let buildFileCandidates = [
        "Package.swift", "package.json", "Podfile", "Cartfile"
    ]

    private static let configFileCandidates = [
        ".env", ".env.example", "app.json", "tsconfig.json"
    ]

    private static let configExtensions: Set<String> = [
        "json", "yaml", "yml", "toml", "plist", "ini", "cfg", "conf", "env", "xcconfig"
    ]

    private static let docsExtensions: Set<String> = [
        "md", "txt", "rtf", "pdf", "doc", "docx"
    ]

    private static let assetExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "icns", "mp3", "wav",
        "m4a", "aac", "mp4", "mov"
    ]

    private static let dataExtensions: Set<String> = [
        "csv", "tsv", "xml"
    ]

    private static func previewSummary(for attachment: AXChatAttachment) -> String {
        let url = URL(fileURLWithPath: attachment.path)
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "(currently unavailable on disk)"
        }

        if isDirectory.boolValue {
            let items = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? [])
                .sorted()
            if items.isEmpty {
                return "(empty directory)"
            }
            let limited = Array(items.prefix(directoryPreviewEntryLimit))
            var lines = limited.map { "- \($0)" }
            if items.count > limited.count {
                lines.append("- ... \(items.count - limited.count) more item(s)")
            }
            return lines.joined(separator: "\n")
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "(preview unavailable)"
        }
        defer { try? handle.close() }

        let prefixData = (try? handle.read(upToCount: previewByteLimit)) ?? Data()
        if prefixData.isEmpty {
            return "(empty file)"
        }

        guard isProbablyText(prefixData) else {
            let ext = url.pathExtension.isEmpty ? "(none)" : url.pathExtension
            return "(binary file preview unavailable; extension=\(ext))"
        }

        let decoded = String(decoding: prefixData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty else {
            return "(empty file)"
        }

        if decoded.count <= previewCharLimit {
            return decoded
        }

        let end = decoded.index(decoded.startIndex, offsetBy: previewCharLimit)
        return String(decoded[..<end]) + "\n...[preview truncated]"
    }

    private static func isProbablyText(_ data: Data) -> Bool {
        if data.contains(0) {
            return false
        }

        let printable = data.reduce(into: 0) { count, byte in
            switch byte {
            case 0x09, 0x0A, 0x0D:
                count += 1
            case 0x20...0x7E:
                count += 1
            default:
                break
            }
        }

        return Double(printable) / Double(max(1, data.count)) > 0.82
    }

    private static func uniqueImportDestination(
        preferredName: String,
        in directory: URL,
        isDirectory: Bool
    ) -> URL {
        let fm = FileManager.default
        let ext = URL(fileURLWithPath: preferredName).pathExtension
        let baseName: String
        if !ext.isEmpty, !isDirectory {
            baseName = URL(fileURLWithPath: preferredName).deletingPathExtension().lastPathComponent
        } else {
            baseName = preferredName
        }

        var candidate = directory.appendingPathComponent(preferredName, isDirectory: isDirectory)
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            let suffix = "-\(index)"
            let nextName: String
            if !ext.isEmpty, !isDirectory {
                nextName = "\(baseName)\(suffix).\(ext)"
            } else {
                nextName = "\(baseName)\(suffix)"
            }
            candidate = directory.appendingPathComponent(nextName, isDirectory: isDirectory)
            index += 1
        }
        return candidate
    }

    private static func projectRelativePath(
        for url: URL,
        projectRoot: URL
    ) -> String? {
        guard PathGuard.isInside(root: projectRoot, target: url) else {
            return nil
        }

        let target = PathGuard.resolve(url).path
        let root = PathGuard.resolve(projectRoot).path
        if target == root {
            return "."
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard target.hasPrefix(prefix) else {
            return nil
        }
        return String(target.dropFirst(prefix.count))
    }

    private static func orderedUniqueAttachments(_ attachments: [AXChatAttachment]) -> [AXChatAttachment] {
        var seen = Set<String>()
        var ordered: [AXChatAttachment] = []

        for attachment in attachments {
            let key = attachmentKey(attachment)
            guard seen.insert(key).inserted else { continue }
            ordered.append(attachment)
        }

        return ordered
    }

    private static func attachmentKey(_ attachment: AXChatAttachment) -> String {
        PathGuard.resolve(URL(fileURLWithPath: attachment.path)).path.lowercased()
    }

    private static func normalizedPreviewOverride(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func indent(_ text: String, prefix: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func sanitizedImportName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}
