import Foundation

extension SupervisorManager {
    func addAssistantMessage(_ text: String) {
        _ = appendSupervisorAssistantMessage(text)
    }

    func shouldPreserveConversationStreamingMessage(
        id: String,
        replacingWith content: String
    ) -> Bool {
        guard let message = messages.first(where: { $0.id == id }) else { return false }
        let existing = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return !existing.isEmpty && !replacement.isEmpty && existing != replacement
    }

    func updateSupervisorMessage(
        id: String,
        content: String,
        projectId: String? = nil,
        projectName: String? = nil,
        requiresKnownProjectMatch: Bool? = nil
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        if let projectId {
            messages[index].projectId = projectId
        }
        if let projectName {
            messages[index].projectName = projectName
        }
        if let requiresKnownProjectMatch {
            messages[index].requiresKnownProjectMatch = requiresKnownProjectMatch
        }
    }

    func removeSupervisorMessage(id: String) {
        messages.removeAll { $0.id == id }
    }

    @discardableResult
    func appendSupervisorAssistantMessage(
        _ text: String,
        timestamp: Date = Date(),
        projectId: String? = nil,
        projectName: String? = nil,
        requiresKnownProjectMatch: Bool = false
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: trimmed,
                isVoice: false,
                timestamp: timestamp.timeIntervalSince1970,
                projectId: projectId,
                projectName: projectName,
                requiresKnownProjectMatch: requiresKnownProjectMatch
            )
        )
        return trimmed
    }

    @discardableResult
    func appendLocalAssistantNotice(
        _ text: String,
        timestamp: Date = Date()
    ) -> String? {
        appendSupervisorAssistantMessage(text, timestamp: timestamp)
    }

    func idleDurationText(_ seconds: TimeInterval) -> String {
        if seconds < 90 { return "刚刚无更新" }
        let mins = Int(seconds / 60)
        if mins < 60 { return "\(mins) 分钟无更新" }
        let hours = Int(round(Double(mins) / 60.0))
        if hours < 48 { return "\(hours) 小时无更新" }
        let days = Int(round(Double(hours) / 24.0))
        return "\(days) 天无更新"
    }

    func conversationStreamingPlaceholder(for message: SupervisorMessage) -> XTStreamingPlaceholderPresentation? {
        guard message.role == .assistant else { return nil }
        guard message.id == activeConversationStreamingMessageID else { return nil }
        guard message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard isProcessing else { return nil }

        return XTStreamingPlaceholderSupport.presentation(
            from: processingStatusText ?? conversationPlaceholderStatusText,
            fallbackTitle: "准备回复"
        )
    }

    func addSystemMessage(
        _ text: String,
        projectId: String? = nil,
        projectName: String? = nil,
        requiresKnownProjectMatch: Bool = false
    ) {
        recordRuntimeActivity(
            text,
            projectId: projectId,
            projectName: projectName,
            requiresKnownProjectMatch: requiresKnownProjectMatch
        )
        let message = SupervisorMessage(
            id: UUID().uuidString,
            role: .system,
            content: text,
            isVoice: false,
            timestamp: Date().timeIntervalSince1970,
            projectId: projectId,
            projectName: projectName,
            requiresKnownProjectMatch: requiresKnownProjectMatch
        )
        messages.append(message)
    }

    func addSystemMessage(
        _ text: String,
        project: AXProjectEntry,
        requiresKnownProjectMatch: Bool = true
    ) {
        addSystemMessage(
            text,
            projectId: project.projectId,
            projectName: project.displayName,
            requiresKnownProjectMatch: requiresKnownProjectMatch
        )
    }
}
