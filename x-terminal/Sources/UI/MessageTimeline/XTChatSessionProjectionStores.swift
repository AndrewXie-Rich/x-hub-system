import Combine
import Foundation

struct XTChatStatusSnapshot: Equatable {
    var messageCount: Int
    var isSending: Bool
    var lastError: String?
    var pendingToolCalls: [ToolCall]

    static let empty = XTChatStatusSnapshot(
        messageCount: 0,
        isSending: false,
        lastError: nil,
        pendingToolCalls: []
    )

    var pendingToolCallIDs: [String] {
        pendingToolCalls.map(\.id)
    }

    var pendingToolCallIDSignature: String {
        pendingToolCallIDs.joined(separator: ",")
    }
}

@MainActor
final class XTChatStatusStore: ObservableObject {
    @Published private(set) var snapshot: XTChatStatusSnapshot

    private weak var boundSession: ChatSessionModel?
    private var cancellables: Set<AnyCancellable> = []
    private var updateScheduled = false

    init(snapshot: XTChatStatusSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func bind(to session: ChatSessionModel) {
        if boundSession === session {
            update(from: session)
            return
        }

        cancellables.removeAll()
        boundSession = session
        updateScheduled = false
        update(from: session)

        session.$messages
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
        session.$isSending
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
        session.$lastError
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
        session.$pendingToolCalls
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
    }

    func isBound(to session: ChatSessionModel) -> Bool {
        boundSession === session
    }

    private func update(from session: ChatSessionModel) {
        let nextSnapshot = XTChatStatusSnapshot(
            messageCount: session.messages.count,
            isSending: session.isSending,
            lastError: session.lastError,
            pendingToolCalls: session.pendingToolCalls
        )
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(from session: ChatSessionModel) {
        guard !updateScheduled else { return }
        updateScheduled = true
        Task { @MainActor [weak self, weak session] in
            guard let self else { return }
            self.updateScheduled = false
            guard let session else { return }
            self.update(from: session)
        }
    }
}

struct XTMessageTimelineTailSignature: Equatable {
    var messageCount: Int
    var lastMessageID: String
    var lastMessageRole: AXChatRole?
    var lastMessageTag: String?
    var lastMessageContentByteCount: Int
    var lastMessageContentFingerprint: Int
    var lastAttachmentCount: Int
    var lastAttachmentDisplayPathHash: Int

    static let empty = XTMessageTimelineTailSignature(
        messageCount: 0,
        lastMessageID: "",
        lastMessageRole: nil,
        lastMessageTag: nil,
        lastMessageContentByteCount: 0,
        lastMessageContentFingerprint: 0,
        lastAttachmentCount: 0,
        lastAttachmentDisplayPathHash: 0
    )

    static func make(from messages: [AXChatMessage]) -> XTMessageTimelineTailSignature {
        guard let last = latestTimelineMessage(from: messages) else {
            return XTMessageTimelineTailSignature(
                messageCount: messages.count,
                lastMessageID: "",
                lastMessageRole: nil,
                lastMessageTag: nil,
                lastMessageContentByteCount: 0,
                lastMessageContentFingerprint: 0,
                lastAttachmentCount: 0,
                lastAttachmentDisplayPathHash: 0
            )
        }
        let attachmentDisplayPaths = last.attachments
            .map(\.displayPath)
            .joined(separator: "\u{1F}")
        return XTMessageTimelineTailSignature(
            messageCount: messages.count,
            lastMessageID: last.id,
            lastMessageRole: last.role,
            lastMessageTag: last.tag,
            lastMessageContentByteCount: last.content.utf8.count,
            lastMessageContentFingerprint: XTMessageTimelineContentFingerprint.make(
                from: last.content
            ),
            lastAttachmentCount: last.attachments.count,
            lastAttachmentDisplayPathHash: attachmentDisplayPaths.hashValue
        )
    }

    private static func latestTimelineMessage(from messages: [AXChatMessage]) -> AXChatMessage? {
        messages.reversed().first { $0.role != .tool }
    }
}

enum XTMessageTimelineContentFingerprint {
    private static let edgeByteLimit = 384

    static func make(from content: String) -> Int {
        let bytes = content.utf8
        var hasher = Hasher()
        hasher.combine(bytes.count)
        for byte in bytes.prefix(edgeByteLimit) {
            hasher.combine(byte)
        }
        guard bytes.count > edgeByteLimit else {
            return hasher.finalize()
        }
        hasher.combine(0)
        for byte in bytes.suffix(edgeByteLimit) {
            hasher.combine(byte)
        }
        return hasher.finalize()
    }
}

struct XTMessageTimelineSessionSnapshot: Equatable {
    var tailSignature: XTMessageTimelineTailSignature
    var isSending: Bool
    var pendingToolCalls: [ToolCall]
    var shouldShowThinkingIndicator: Bool
    var presentationVersion: Int

    static let empty = XTMessageTimelineSessionSnapshot(
        tailSignature: .empty,
        isSending: false,
        pendingToolCalls: [],
        shouldShowThinkingIndicator: false,
        presentationVersion: 0
    )

    static func == (
        lhs: XTMessageTimelineSessionSnapshot,
        rhs: XTMessageTimelineSessionSnapshot
    ) -> Bool {
        lhs.tailSignature == rhs.tailSignature &&
            lhs.isSending == rhs.isSending &&
            lhs.pendingToolCalls == rhs.pendingToolCalls &&
            lhs.shouldShowThinkingIndicator == rhs.shouldShowThinkingIndicator &&
            lhs.presentationVersion == rhs.presentationVersion
    }

    var messageCount: Int {
        tailSignature.messageCount
    }

    var pendingToolCallIDs: [String] {
        pendingToolCalls.map(\.id)
    }

    var pendingToolCallIDSignature: String {
        pendingToolCallIDs.joined(separator: ",")
    }

    @MainActor
    static func make(from session: ChatSessionModel) -> XTMessageTimelineSessionSnapshot {
        return XTMessageTimelineSessionSnapshot(
            tailSignature: XTMessageTimelineTailSignature.make(from: session.messages),
            isSending: session.isSending,
            pendingToolCalls: session.pendingToolCalls,
            shouldShowThinkingIndicator: session.shouldShowThinkingIndicator,
            presentationVersion: session.messageTimelinePresentationVersion
        )
    }
}

@MainActor
final class XTMessageTimelineSessionStore: ObservableObject {
    @Published private(set) var snapshot: XTMessageTimelineSessionSnapshot

    private let minimumUpdateIntervalNanoseconds: UInt64
    private weak var boundSession: ChatSessionModel?
    private var cancellables: Set<AnyCancellable> = []
    private var updateScheduled = false
    private var lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds

    init(
        snapshot: XTMessageTimelineSessionSnapshot = .empty,
        minimumUpdateIntervalNanoseconds: UInt64 = 0
    ) {
        self.snapshot = snapshot
        self.minimumUpdateIntervalNanoseconds = minimumUpdateIntervalNanoseconds
    }

    func bind(to session: ChatSessionModel) {
        if boundSession === session {
            update(from: session)
            return
        }

        cancellables.removeAll()
        boundSession = session
        updateScheduled = false
        update(from: session)

        session.$messages
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
        session.$isSending
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
        session.$pendingToolCalls
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
        session.$messageTimelinePresentationVersion
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
    }

    func isBound(to session: ChatSessionModel) -> Bool {
        boundSession === session
    }

    private func update(from session: ChatSessionModel) {
        let nextSnapshot = XTMessageTimelineSessionSnapshot.make(from: session)
        guard snapshot != nextSnapshot else { return }
        lastUpdateNanoseconds = DispatchTime.now().uptimeNanoseconds
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(from session: ChatSessionModel) {
        guard !updateScheduled else { return }
        updateScheduled = true
        let delayNanoseconds = nextUpdateDelayNanoseconds()
        Task { @MainActor [weak self, weak session] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self else { return }
            self.updateScheduled = false
            guard let session, self.boundSession === session else { return }
            self.update(from: session)
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
