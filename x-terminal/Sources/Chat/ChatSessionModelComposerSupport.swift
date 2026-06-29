import Foundation

@MainActor
final class ChatComposerState: ObservableObject {
    @Published var draft: String = ""
    @Published var draftAttachments: [AXChatAttachment] = []
    @Published var importContinuation: AXChatImportContinuationSuggestion? = nil
    @Published var autoRunTools: Bool = false
}

enum ChatStreamingUIFlushCadence {
    static let shortIntervalNanoseconds: UInt64 = 50_000_000
    static let mediumIntervalNanoseconds: UInt64 = 100_000_000
    static let longIntervalNanoseconds: UInt64 = 160_000_000
    static let mediumByteThreshold = 12_000
    static let longByteThreshold = 48_000

    static func delayNanoseconds(forContentByteCount byteCount: Int) -> UInt64 {
        if byteCount > longByteThreshold {
            return longIntervalNanoseconds
        }
        if byteCount > mediumByteThreshold {
            return mediumIntervalNanoseconds
        }
        return shortIntervalNanoseconds
    }
}

extension ChatSessionModel {
    func normalizedUserPayload(
        draft: String,
        attachments: [AXChatAttachment]
    ) -> String? {
        AXChatAttachmentSupport.normalizedUserPrompt(
            draft: draft,
            attachments: attachments
        )
    }

    func activeConversationAttachments() -> [AXChatAttachment] {
        AXChatAttachmentSupport.merge(
            existing: [],
            resolved: messages.flatMap(\.attachments)
        )
    }

    func activeAttachmentReadableRoots() -> [URL] {
        AXChatAttachmentSupport.readableRoots(for: activeConversationAttachments())
    }

    func attachmentPromptSummary(
        currentTurnAttachments: [AXChatAttachment],
        projectRoot: URL
    ) async -> String {
        let previewOverrides = await AXChatAttachmentLocalModelPreview.previewOverrides(
            for: currentTurnAttachments
        )
        let summary = AXChatAttachmentSupport.promptSummary(
            currentTurnAttachments: currentTurnAttachments,
            activeAttachments: activeConversationAttachments(),
            projectRoot: projectRoot,
            previewOverrides: previewOverrides
        )
        let heading = "Attachment Context:\n"
        if summary.hasPrefix(heading) {
            return String(summary.dropFirst(heading.count))
        }
        return summary
    }

    func currentTurnMultimodalInputSummary(
        userText: String,
        currentTurnAttachments: [AXChatAttachment]
    ) async -> String {
        await AXChatTurnMultimodalInput.summary(
            userText: userText,
            attachments: currentTurnAttachments
        ) ?? ""
    }

    func handleDroppedFiles(_ urls: [URL], ctx: AXProjectContext) {
        let resolved = AXChatAttachmentSupport.resolveDroppedURLs(
            urls,
            projectRoot: ctx.root
        )
        guard !resolved.isEmpty else { return }
        draftAttachments = AXChatAttachmentSupport.merge(
            existing: draftAttachments,
            resolved: resolved
        )
        lastError = nil
    }

    func removeDraftAttachment(_ attachment: AXChatAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        refreshImportContinuation()
    }

    func importDroppedFilesToProject(_ urls: [URL], ctx: AXProjectContext) {
        let resolved = AXChatAttachmentSupport.resolveDroppedURLs(
            urls,
            projectRoot: ctx.root
        )
        guard !resolved.isEmpty else { return }

        let workspaceAttachments = resolved.filter { !$0.isReadOnlyExternal }
        if !workspaceAttachments.isEmpty {
            draftAttachments = AXChatAttachmentSupport.merge(
                existing: draftAttachments,
                resolved: workspaceAttachments
            )
        }

        let externalAttachments = resolved.filter(\.isReadOnlyExternal)
        guard !externalAttachments.isEmpty else {
            lastError = nil
            return
        }

        _ = importAttachmentsToProject(externalAttachments, ctx: ctx)
    }

    func importAttachmentToProject(
        _ attachment: AXChatAttachment,
        ctx: AXProjectContext
    ) {
        _ = importAttachmentsToProject([attachment], ctx: ctx)
    }

    func importAllExternalDraftAttachments(ctx: AXProjectContext) {
        let pending = draftAttachments.filter(\.isReadOnlyExternal)
        guard !pending.isEmpty else { return }
        _ = importAttachmentsToProject(pending, ctx: ctx)
    }

    func applyImportContinuationToDraft() {
        guard let importContinuation else { return }
        draft = AXChatAttachmentSupport.draftApplyingImportContinuation(
            importContinuation,
            existingDraft: draft
        )
        self.importContinuation = nil
    }

    func dismissImportContinuation() {
        importContinuation = nil
    }

    @discardableResult
    func importAttachmentsToProject(
        _ attachments: [AXChatAttachment],
        ctx: AXProjectContext
    ) -> [AXChatAttachmentImportResult] {
        var importedResults: [AXChatAttachmentImportResult] = []
        var failures: [String] = []

        for attachment in attachments {
            do {
                let result = try AXChatAttachmentSupport.importAttachment(attachment, into: ctx.root)
                draftAttachments.removeAll {
                    PathGuard.resolve(URL(fileURLWithPath: $0.path)).path ==
                        PathGuard.resolve(URL(fileURLWithPath: attachment.path)).path
                }
                draftAttachments = AXChatAttachmentSupport.merge(
                    existing: draftAttachments,
                    resolved: [result.importedAttachment]
                )
                AXProjectStore.appendRawLog(
                    [
                        "type": "attachment_import",
                        "created_at": Date().timeIntervalSince1970,
                        "source_path": result.sourceAttachment.path,
                        "destination_path": result.destinationURL.path,
                        "kind": result.sourceAttachment.kind.rawValue,
                        "scope": result.sourceAttachment.scope.rawValue,
                    ],
                    for: ctx
                )
                importedResults.append(result)
            } catch {
                failures.append("\(attachment.displayName)：\(error.localizedDescription)")
            }
        }

        if let notice = AXChatAttachmentSupport.importSuccessNotice(results: importedResults) {
            _ = appendLocalAssistantNotice(
                notice,
                ctx: ctx
            )
        }

        importContinuation = AXChatAttachmentSupport.importContinuationSuggestion(
            results: importedResults,
            projectRoot: ctx.root
        )

        if let firstFailure = failures.first {
            lastError = firstFailure
        } else {
            lastError = nil
        }

        return importedResults
    }

    func refreshImportContinuation() {
        guard let importContinuation else { return }
        guard importContinuation.isRelevant(to: draftAttachments) else {
            self.importContinuation = nil
            return
        }
    }
}
