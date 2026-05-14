import Combine
import Foundation

struct SupervisorConversationMessageRowSnapshot: Identifiable, Equatable {
    var message: SupervisorMessage
    var thinkingPresentation: XTStreamingPlaceholderPresentation?

    var id: String { message.id }
}

struct SupervisorConversationTimelineSnapshot: Equatable {
    var rows: [SupervisorConversationMessageRowSnapshot]
    var processingStatusText: String
    var placeholderStatusText: String

    static let empty = SupervisorConversationTimelineSnapshot(
        rows: [],
        processingStatusText: "",
        placeholderStatusText: ""
    )

    var lastMessageID: String {
        rows.last?.message.id ?? ""
    }

    var lastMessageContent: String {
        rows.last?.message.content ?? ""
    }

    var messageCount: Int {
        rows.count
    }

    @MainActor
    static func make(from supervisor: SupervisorManager) -> SupervisorConversationTimelineSnapshot {
        let processingStatusText = supervisor.processingStatusText ?? ""
        let placeholderStatusText = supervisor.conversationPlaceholderStatusText ?? ""
        let activeStreamingMessageID = supervisor.activeConversationStreamingMessageID
        let isProcessing = supervisor.isProcessing
        let streamingStatusText = processingStatusText.isEmpty ? placeholderStatusText : processingStatusText
        let rows = supervisor.chatTimelineMessages.map { message in
            SupervisorConversationMessageRowSnapshot(
                message: message,
                thinkingPresentation: thinkingPresentation(
                    for: message,
                    activeStreamingMessageID: activeStreamingMessageID,
                    isProcessing: isProcessing,
                    statusText: streamingStatusText
                )
            )
        }

        return SupervisorConversationTimelineSnapshot(
            rows: rows,
            processingStatusText: processingStatusText,
            placeholderStatusText: placeholderStatusText
        )
    }

    private static func thinkingPresentation(
        for message: SupervisorMessage,
        activeStreamingMessageID: String?,
        isProcessing: Bool,
        statusText: String
    ) -> XTStreamingPlaceholderPresentation? {
        guard message.role == .assistant else { return nil }
        guard message.id == activeStreamingMessageID else { return nil }
        guard isProcessing else { return nil }
        guard message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return XTStreamingPlaceholderSupport.presentation(
            from: statusText,
            fallbackTitle: "准备回复"
        )
    }
}

@MainActor
final class SupervisorConversationTimelineStore: ObservableObject {
    @Published private(set) var snapshot: SupervisorConversationTimelineSnapshot

    private let minimumUpdateIntervalNanoseconds: UInt64
    private weak var boundSupervisor: SupervisorManager?
    private var cancellables: Set<AnyCancellable> = []
    private var updateScheduled = false
    private var lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds

    init(
        snapshot: SupervisorConversationTimelineSnapshot = .empty,
        minimumUpdateIntervalNanoseconds: UInt64 = 0
    ) {
        self.snapshot = snapshot
        self.minimumUpdateIntervalNanoseconds = minimumUpdateIntervalNanoseconds
    }

    func bind(to supervisor: SupervisorManager) {
        if boundSupervisor === supervisor {
            update(from: supervisor)
            return
        }

        cancellables.removeAll()
        boundSupervisor = supervisor
        updateScheduled = false
        update(from: supervisor)

        supervisor.$messages
            .sink { [weak self, weak supervisor] _ in
                guard let supervisor else { return }
                self?.scheduleUpdate(from: supervisor)
            }
            .store(in: &cancellables)
        supervisor.$isProcessing
            .sink { [weak self, weak supervisor] _ in
                guard let supervisor else { return }
                self?.scheduleUpdate(from: supervisor)
            }
            .store(in: &cancellables)
        supervisor.$processingStatusText
            .sink { [weak self, weak supervisor] _ in
                guard let supervisor else { return }
                self?.scheduleUpdate(from: supervisor)
            }
            .store(in: &cancellables)
        supervisor.$conversationPlaceholderStatusText
            .sink { [weak self, weak supervisor] _ in
                guard let supervisor else { return }
                self?.scheduleUpdate(from: supervisor)
            }
            .store(in: &cancellables)
        supervisor.$activeConversationStreamingMessageID
            .sink { [weak self, weak supervisor] _ in
                guard let supervisor else { return }
                self?.scheduleUpdate(from: supervisor)
            }
            .store(in: &cancellables)
    }

    func isBound(to supervisor: SupervisorManager) -> Bool {
        boundSupervisor === supervisor
    }

    private func update(from supervisor: SupervisorManager) {
        let nextSnapshot = SupervisorConversationTimelineSnapshot.make(from: supervisor)
        guard snapshot != nextSnapshot else { return }
        lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(from supervisor: SupervisorManager) {
        guard !updateScheduled else { return }
        updateScheduled = true
        let delayNanoseconds = nextUpdateDelayNanoseconds()
        Task { @MainActor [weak self, weak supervisor] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self else { return }
            self.updateScheduled = false
            guard let supervisor, self.boundSupervisor === supervisor else { return }
            self.update(from: supervisor)
        }
    }

    private func nextUpdateDelayNanoseconds() -> UInt64 {
        guard minimumUpdateIntervalNanoseconds > 0 else { return 0 }
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= lastUpdateNanoseconds ? now - lastUpdateNanoseconds : minimumUpdateIntervalNanoseconds
        guard elapsed < minimumUpdateIntervalNanoseconds else { return 0 }
        return minimumUpdateIntervalNanoseconds - elapsed
    }
}
