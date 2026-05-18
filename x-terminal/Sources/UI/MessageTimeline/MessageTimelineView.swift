import AppKit
import SwiftUI

enum MessageTimelineWindowingSupport {
    static func initialVisibleRange(
        totalCount: Int,
        pageSize: Int
    ) -> Range<Int> {
        guard totalCount > 0 else { return 0..<0 }
        let clampedPageSize = max(1, pageSize)
        let end = totalCount
        let start = max(0, end - clampedPageSize)
        return start..<end
    }

    static func prependedVisibleRange(
        currentRange: Range<Int>,
        totalCount: Int,
        pageSize: Int,
        maxWindowSize: Int? = nil
    ) -> Range<Int> {
        guard totalCount > 0 else { return 0..<0 }
        guard !currentRange.isEmpty else {
            return initialVisibleRange(totalCount: totalCount, pageSize: pageSize)
        }
        let clampedUpper = min(totalCount, max(currentRange.upperBound, 0))
        let newStart = max(0, currentRange.lowerBound - max(1, pageSize))
        return clampedVisibleRange(
            currentRange: newStart..<clampedUpper,
            totalCount: totalCount,
            maxWindowSize: maxWindowSize
        )
    }

    static func latestVisibleRange(
        from currentRange: Range<Int>,
        totalCount: Int,
        pageSize: Int,
        maxWindowSize: Int? = nil,
        stickToBottom: Bool
    ) -> Range<Int> {
        guard totalCount > 0 else { return 0..<0 }
        guard !currentRange.isEmpty else {
            return initialVisibleRange(totalCount: totalCount, pageSize: pageSize)
        }
        if currentRange.lowerBound >= totalCount {
            return initialVisibleRange(totalCount: totalCount, pageSize: pageSize)
        }
        if stickToBottom {
            let preservedWindow = max(currentRange.count, max(1, pageSize))
            let clampedWindow = maxWindowSize.map { min(preservedWindow, max(1, $0)) } ?? preservedWindow
            let end = totalCount
            let start = max(0, end - clampedWindow)
            return start..<end
        }
        return clampedVisibleRange(
            currentRange: currentRange,
            totalCount: totalCount,
            maxWindowSize: maxWindowSize
        )
    }

    static func clampedVisibleRange(
        currentRange: Range<Int>,
        totalCount: Int,
        maxWindowSize: Int? = nil
    ) -> Range<Int> {
        guard totalCount > 0 else { return 0..<0 }
        guard !currentRange.isEmpty else { return 0..<0 }

        let lowerBound = max(0, min(currentRange.lowerBound, totalCount - 1))
        let upperBound = max(lowerBound, min(totalCount, currentRange.upperBound))
        guard let maxWindowSize else {
            return lowerBound..<upperBound
        }

        let clampedMaxWindowSize = max(1, maxWindowSize)
        if upperBound - lowerBound <= clampedMaxWindowSize {
            return lowerBound..<upperBound
        }
        return lowerBound..<min(totalCount, lowerBound + clampedMaxWindowSize)
    }

    static func shouldStickToBottom(
        bottomAnchorMaxY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat = 72
    ) -> Bool {
        guard viewportHeight > 0 else { return true }
        guard bottomAnchorMaxY.isFinite else { return true }
        return bottomAnchorMaxY <= viewportHeight + threshold
    }

    static func updatedStickToBottomState(
        currentValue: Bool,
        bottomAnchorMaxY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat = 72
    ) -> Bool? {
        let nextValue = shouldStickToBottom(
            bottomAnchorMaxY: bottomAnchorMaxY,
            viewportHeight: viewportHeight,
            threshold: threshold
        )
        return nextValue == currentValue ? nil : nextValue
    }
}

private enum MessageTimelineFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private enum MessageTimelineRenderCache {
    private static let parsedContentLock = NSLock()
    private static var parsedContentByKey: [String: ParsedContent] = [:]
    private static var parsedContentOrder: [String] = []
    private static let maxParsedContentEntries = 256

    static func parsedContent(for message: AXChatMessage) -> ParsedContent {
        guard ToolCallParser.mightContainToolCalls(message.content) else {
            return .plainText(message.content)
        }

        let key = "\(message.id)|\(XTMessageTimelineContentFingerprint.make(from: message.content))"
        parsedContentLock.lock()
        if let cached = parsedContentByKey[key] {
            parsedContentLock.unlock()
            return cached
        }
        parsedContentLock.unlock()

        let parsed = ToolCallParser.parse(message.content)

        parsedContentLock.lock()
        parsedContentByKey[key] = parsed
        parsedContentOrder.append(key)
        if parsedContentOrder.count > maxParsedContentEntries,
           let evictedKey = parsedContentOrder.first {
            parsedContentOrder.removeFirst()
            parsedContentByKey.removeValue(forKey: evictedKey)
        }
        parsedContentLock.unlock()
        return parsed
    }
}

private struct MessageTimelineStickToBottomObserver: NSViewRepresentable {
    var threshold: CGFloat
    var onStateChange: (Bool) -> Void

    final class Coordinator: NSObject {
        var threshold: CGFloat
        var onStateChange: (Bool) -> Void
        private weak var observedClipView: NSClipView?
        private weak var observedScrollView: NSScrollView?
        private var lastValue: Bool?

        init(
            threshold: CGFloat,
            onStateChange: @escaping (Bool) -> Void
        ) {
            self.threshold = threshold
            self.onStateChange = onStateChange
        }

        deinit {
            detach()
        }

        func attachIfNeeded(from hostView: NSView) {
            var ancestor: NSView? = hostView.superview
            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    attach(to: scrollView)
                    return
                }
                ancestor = view.superview
            }
        }

        func refreshCurrentState() {
            guard let scrollView = observedScrollView,
                  let documentView = scrollView.documentView else {
                return
            }
            let viewportHeight = scrollView.contentView.bounds.height
            let bottomAnchorMaxY = documentView.bounds.height - scrollView.contentView.bounds.minY
            let nextValue = MessageTimelineWindowingSupport.shouldStickToBottom(
                bottomAnchorMaxY: bottomAnchorMaxY,
                viewportHeight: viewportHeight,
                threshold: threshold
            )
            guard lastValue != nextValue else { return }
            lastValue = nextValue
            onStateChange(nextValue)
        }

        private func attach(to scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else {
                refreshCurrentState()
                return
            }

            detach()
            observedScrollView = scrollView

            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            observedClipView = clipView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )

            DispatchQueue.main.async { [weak self] in
                self?.refreshCurrentState()
            }
        }

        private func detach() {
            if let clipView = observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
            }
            observedClipView = nil
            observedScrollView = nil
        }

        @objc
        private func boundsDidChange() {
            refreshCurrentState()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            threshold: threshold,
            onStateChange: onStateChange
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.threshold = threshold
        context.coordinator.onStateChange = onStateChange
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: nsView)
            context.coordinator.refreshCurrentState()
        }
    }
}

/// 现代化的消息时间线视图，替代原来的 TranscriptTextView
struct MessageTimelineView: View {
    let ctx: AXProjectContext
    let config: AXProjectConfig?
    let session: ChatSessionModel
    let hubConnected: Bool
    let onApproveSkillActivity: (String) -> Void
    let onRetrySkillActivity: (ProjectSkillActivityItem) -> Void
    let onApprovePendingTools: () -> Void
    let onRejectPendingTools: () -> Void
    let onOpenGovernance: (XTProjectGovernanceDestination, XTSectionFocusContext?) -> Void
    var onStartWorkPrompt: ((String) -> Void)? = nil
    var onResumeProject: (() -> Void)? = nil
    var onRouteDiagnose: (() -> Void)? = nil
    var focusedSkillActivityRequestId: String? = nil
    var focusedSkillActivityNonce: Int? = nil
    var bottomPadding: CGFloat = 24
    var scrollToBottomNonce: Int = 0
    @Namespace private var bottomID
    @StateObject private var timelineSessionStore = XTMessageTimelineSessionStore(
        minimumUpdateIntervalNanoseconds: 16_000_000
    )
    @State private var recentSkillActivities: [ProjectSkillActivityItem] = []
    @State private var selectedSkillRecord: ProjectSkillRecordSheetState?
    @State private var pendingFocusedSkillActivityNonce: Int?
    @State private var timelineMessages: [AXChatMessage] = []
    @State private var timelineRowSnapshots: [MessageRowSnapshot] = []
    @State private var timelineSourceMessageCount = 0
    @State private var visibleMessageRange: Range<Int> = 0..<0
    @State private var isLoadingPreviousMessages = false
    @State private var shouldStickToBottomState = true

    private let recentSkillActivityLimit = 8
    private let initialMessagePageSize = 48
    private let prependMessagePageSize = 24
    private let maxVisibleMessageWindow = 96

    private var visibleMessages: ArraySlice<AXChatMessage> {
        let range = visibleMessageRange.clamped(to: 0..<timelineMessages.count)
        guard !range.isEmpty else { return [] }
        return timelineMessages[range]
    }

    private var visibleRowSnapshots: ArraySlice<MessageRowSnapshot> {
        let range = visibleMessageRange.clamped(to: 0..<timelineRowSnapshots.count)
        guard !range.isEmpty else { return [] }
        return timelineRowSnapshots[range]
    }

    private var shouldStickToBottom: Bool {
        shouldStickToBottomState
    }

    private var shouldShowWorkEmptyState: Bool {
        visibleMessages.isEmpty
            && recentSkillActivities.isEmpty
            && !session.shouldShowThinkingIndicator
    }

    var body: some View {
        ScrollViewReader { proxy in
            timelineScrollView(using: proxy)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedSkillRecord) { record in
            ProjectSkillRecordSheet(record: record)
        }
    }

    private func timelineScrollView(using proxy: ScrollViewProxy) -> some View {
        ScrollView {
            timelineStack(using: proxy)
        }
        .background(
            MessageTimelineStickToBottomObserver(threshold: 72) { newValue in
                if shouldStickToBottomState != newValue {
                    shouldStickToBottomState = newValue
                }
            }
            .frame(width: 0, height: 0)
        )
        .onAppear {
            pendingFocusedSkillActivityNonce = focusedSkillActivityNonce
            syncTimelineMessages()
            syncVisibleMessageRangeToLatest()
            refreshRecentSkillActivities(using: proxy)
            DispatchQueue.main.async {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
        .onChange(of: ctx.root.path) { _ in
            timelineSessionStore.bind(to: session)
            syncTimelineMessages()
            visibleMessageRange = MessageTimelineWindowingSupport.initialVisibleRange(
                totalCount: timelineMessages.count,
                pageSize: initialMessagePageSize
            )
            refreshRecentSkillActivities(using: proxy)
            scheduleScrollToBottom(using: proxy)
        }
        .onChange(of: sessionIdentity) { _ in
            timelineSessionStore.bind(to: session)
            syncTimelineMessages()
            syncVisibleMessageRangeToLatest()
            refreshRecentSkillActivities(using: proxy)
            scheduleScrollToBottom(using: proxy)
        }
        .onChange(of: timelineSessionSnapshot.messageCount) { _ in
            syncTimelineMessagesForSourceCountChange()
            syncVisibleMessageRangeToLatest()
            refreshRecentSkillActivities(using: proxy)
            tailSignatureHandledByMessageCountChange = timelineSessionSnapshot.tailSignature
            guard pendingFocusedSkillActivityNonce == nil else { return }
            guard shouldStickToBottom || timelineMessages.last?.role == .user else { return }
            scheduleScrollToBottom(using: proxy, animatedDuration: 0.3)
        }
        .onChange(of: timelineSessionSnapshot.isSending) { sending in
            syncLatestTimelineRowSnapshot()
            guard sending, pendingFocusedSkillActivityNonce == nil, shouldStickToBottom else { return }
            scheduleScrollToBottom(using: proxy, animatedDuration: 0.2)
        }
        .onChange(of: timelineSessionSnapshot.tailSignature) { _ in
            if MessageTimelineChangeCoalescing.shouldSkipTailRefresh(
                handledByMessageCountChange: tailSignatureHandledByMessageCountChange,
                currentTailSignature: timelineSessionSnapshot.tailSignature
            ) {
                tailSignatureHandledByMessageCountChange = nil
                return
            }
            syncTimelineMessagesKeepingTailFresh()
            guard pendingFocusedSkillActivityNonce == nil, shouldStickToBottom else { return }
            scheduleScrollToBottom(using: proxy)
        }
        .onChange(of: timelineSessionSnapshot.presentationVersion) { _ in
            syncTimelinePresentationRowSnapshots()
            guard pendingFocusedSkillActivityNonce == nil,
                  shouldStickToBottom,
                  timelineSessionSnapshot.shouldShowThinkingIndicator else { return }
            scheduleScrollToBottom(using: proxy)
        }
        .onChange(of: timelineSessionSnapshot.pendingToolCallIDSignature) { _ in
            refreshRecentSkillActivities(using: proxy)
        }
        .onChange(of: recentSkillActivities.count) { _ in
            guard pendingFocusedSkillActivityNonce == nil, shouldStickToBottom else { return }
            scheduleScrollToBottom(using: proxy)
        }
        .onChange(of: focusedSkillActivityNonce) { newNonce in
            pendingFocusedSkillActivityNonce = newNonce
            refreshRecentSkillActivities(using: proxy)
        }
    }

    @ViewBuilder
    private func timelineStack(using proxy: ScrollViewProxy) -> some View {
        LazyVStack(spacing: 16) {
            if shouldShowWorkEmptyState {
                workEmptyState
            } else if visibleMessageRange.lowerBound > 0 {
                previousMessagesLoader(using: proxy)
            }

            if !shouldShowWorkEmptyState {
                messageRows
            }

            if !recentSkillActivities.isEmpty {
                skillActivitySection
            }

            if timelineSessionSnapshot.shouldShowThinkingIndicator {
                ThinkingIndicator()
                    .transition(.opacity)
            }

            bottomAnchor
        }
        .padding(20)
        .padding(.bottom, bottomPadding)
    }

    private var workEmptyState: some View {
        let latestSessionSummary = AXSessionSummaryCapsulePresentation.load(for: ctx)
        let actions: [ProjectWorkEmptyStateAction] = {
            var items: [ProjectWorkEmptyStateAction] = [
                ProjectWorkEmptyStateAction(
                    title: "开始：了解项目",
                    subtitle: "快速浏览当前项目结构、风险和建议起点。",
                    style: .prominent
                ) {
                    onStartWorkPrompt?(
                        "先快速浏览这个项目，告诉我当前结构、主要模块、明显风险，以及最合理的起步方式。"
                    )
                },
                ProjectWorkEmptyStateAction(
                    title: "开始：规划下一步",
                    subtitle: "先不要写代码，先给我最合理的下一步和检查项。",
                    style: .secondary
                ) {
                    onStartWorkPrompt?(
                        "先不要写代码。基于这个项目当前状态，给我一个最合理的下一步计划，并说明为什么先做这些。"
                    )
                }
            ]

            if latestSessionSummary != nil {
                items.append(
                    ProjectWorkEmptyStateAction(
                        title: "接上次进度",
                        subtitle: "读取最近交接摘要，从上次边界继续。",
                        style: .secondary
                    ) {
                        onResumeProject?()
                    }
                )
            }

            items.append(
                ProjectWorkEmptyStateAction(
                    title: "解释当前路由",
                    subtitle: "先看这轮为什么会命中当前执行路径。",
                    style: .plain
                ) {
                    onRouteDiagnose?()
                }
            )

            return items
        }()

        return ProjectWorkEmptyStateView(
            title: "开始 \(ctx.projectName())",
            summaryText: "直接说目标即可；如果你想先收敛上下文，也可以用下面的起步动作。",
            detailText: latestSessionSummary.map {
                "检测到最近交接：\($0.reasonLabel) · \($0.relativeText)。如果这就是你要继续的工作，直接恢复会更快。"
            } ?? "当前还没有聊天历史。这里更适合先定目标、看起点，再进入连续执行。",
            actions: actions
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var messageRows: some View {
        ForEach(visibleMessages) { message in
            TimelineMessageRow(
                ctx: ctx,
                config: config,
                session: session,
                message: message,
                thinkingPresentation: session.assistantThinkingPresentation(for: message)
            )
                .equatable()
                .id(message.id)
        }
    }

    private var skillActivitySection: some View {
        ProjectSkillActivitySection(
            items: recentSkillActivities,
            pendingRequestIDs: Set(timelineSessionSnapshot.pendingToolCallIDs),
            focusedRequestID: focusedSkillActivityRequestId,
            isFocused: focusedSkillActivityNonce != nil,
            hubConnected: hubConnected,
            isBusy: timelineSessionSnapshot.isSending,
            onApprove: onApproveSkillActivity,
            onReject: { requestID in
                session.rejectPendingTool(requestID: requestID)
            },
            onRetry: onRetrySkillActivity,
            onOpenGovernance: onOpenGovernance,
            onViewFullRecord: showFullRecord
        )
        .id(MessageTimelineFocusPresentation.projectSkillActivitySectionAnchorID)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var pendingToolApprovalSection: some View {
        PendingToolApprovalView(
            session: session,
            hubConnected: hubConnected,
            isFocused: focusedSkillActivityNonce != nil,
            focusedRequestId: focusedSkillActivityRequestId,
            onApprove: onApprovePendingTools,
            onReject: onRejectPendingTools
        )
        .id(MessageTimelineFocusPresentation.pendingToolApprovalSectionAnchorID)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var bottomAnchor: some View {
        Color.clear
            .frame(height: 1)
            .id(bottomID)
    }

    private func refreshRecentSkillActivities(
        using proxy: ScrollViewProxy? = nil
    ) {
        let items = resolvedRecentSkillActivities()
        recentSkillActivities = items
        if let proxy {
            if scrollToFocusedPendingToolApprovalIfNeeded(using: proxy) {
                return
            }
            scrollToFocusedSkillActivityIfNeeded(using: proxy, items: items)
        }
    }

    @discardableResult
    private func scrollToFocusedPendingToolApprovalIfNeeded(
        using proxy: ScrollViewProxy
    ) -> Bool {
        guard let focusedSkillActivityNonce,
              pendingFocusedSkillActivityNonce == focusedSkillActivityNonce else {
            return false
        }
        guard let anchorID = MessageTimelineFocusPresentation.pendingToolApprovalAnchor(
            requestID: focusedSkillActivityRequestId,
            pendingRequestIDs: timelineSessionSnapshot.pendingToolCallIDs
        ) else {
            return false
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(anchorID, anchor: .center)
            }
            pendingFocusedSkillActivityNonce = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(anchorID, anchor: .center)
            }
        }
        return true
    }

    private func resolvedRecentSkillActivities() -> [ProjectSkillActivityItem] {
        let items = XTProjectUIPresentationReadCache.recentSkillActivities(
            for: ctx,
            limit: recentSkillActivityLimit
        ) {
            ProjectSkillActivityPresentation.loadRecentActivities(
                ctx: ctx,
                limit: recentSkillActivityLimit
            )
        }
        guard let focusedRequestID = MessageTimelineFocusPresentation.normalizedRequestID(
            focusedSkillActivityRequestId
        ) else {
            return items
        }
        let focusedItem = AXProjectSkillActivityStore.loadEvents(
            ctx: ctx,
            requestID: focusedRequestID
        ).last?.item
        return MessageTimelineFocusPresentation.mergedRecentSkillActivities(
            items: items,
            focusedItem: focusedItem
        )
    }

    private func scrollToFocusedSkillActivityIfNeeded(
        using proxy: ScrollViewProxy,
        items: [ProjectSkillActivityItem]
    ) {
        guard let focusedSkillActivityNonce,
              pendingFocusedSkillActivityNonce == focusedSkillActivityNonce else {
            return
        }
        guard let anchorID = MessageTimelineFocusPresentation.projectSkillActivityAnchor(
            requestID: focusedSkillActivityRequestId,
            in: items
        ) else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.24)) {
                proxy.scrollTo(anchorID, anchor: .center)
            }
            pendingFocusedSkillActivityNonce = nil
        }
    }

    private func showFullRecord(for item: ProjectSkillActivityItem) {
        guard let record = ProjectSkillActivityPresentation.fullRecord(
            ctx: ctx,
            requestID: item.requestID
        ) else {
            return
        }
        selectedSkillRecord = ProjectSkillRecordSheetState(record: record)
    }

    @ViewBuilder
    private func previousMessagesLoader(using proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if isLoadingPreviousMessages {
                ProgressView()
                    .controlSize(.small)
            }
            Color.clear
                .frame(height: 12)
                .onAppear {
                    loadPreviousMessages(using: proxy)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func loadPreviousMessages(using proxy: ScrollViewProxy) {
        guard !isLoadingPreviousMessages else { return }
        guard visibleMessageRange.lowerBound > 0 else { return }

        let anchorMessageID = visibleMessages.first?.id
        isLoadingPreviousMessages = true
        visibleMessageRange = MessageTimelineWindowingSupport.prependedVisibleRange(
            currentRange: visibleMessageRange,
            totalCount: timelineMessages.count,
            pageSize: prependMessagePageSize,
            maxWindowSize: maxVisibleMessageWindow
        )

        DispatchQueue.main.async {
            if let anchorMessageID {
                proxy.scrollTo(anchorMessageID, anchor: .top)
            }
            isLoadingPreviousMessages = false
        }
    }

    private func syncVisibleMessageRangeToLatest() {
        visibleMessageRange = MessageTimelineWindowingSupport.latestVisibleRange(
            from: visibleMessageRange,
            totalCount: timelineMessages.count,
            pageSize: initialMessagePageSize,
            maxWindowSize: maxVisibleMessageWindow,
            stickToBottom: shouldStickToBottom
        )
    }

    private func syncTimelineMessages() {
        let sourceMessages = session.messages
        timelineSourceMessageCount = sourceMessages.count
        timelineMessages = MessageTimelineRowProjection.timelineMessages(from: sourceMessages)
        syncTimelineRowSnapshots()
    }

    private func syncTimelineMessagesForSourceCountChange() {
        let sourceMessages = session.messages
        let sourceCount = sourceMessages.count
        guard sourceCount == timelineSourceMessageCount + 1,
              let appendedMessage = sourceMessages.last else {
            syncTimelineMessages()
            return
        }

        let previousLatestMessage = MessageTimelineRowProjection.latestTimelineMessageBeforeSourceTail(
            from: sourceMessages
        )
        if let currentLast = timelineMessages.last {
            guard previousLatestMessage?.id == currentLast.id else {
                syncTimelineMessages()
                return
            }
        } else if previousLatestMessage != nil {
            syncTimelineMessages()
            return
        }

        timelineSourceMessageCount = sourceCount
        guard appendedMessage.role != .tool else { return }

        if let currentLast = timelineMessages.last,
           currentLast.id == appendedMessage.id {
            if currentLast != appendedMessage {
                timelineMessages[timelineMessages.count - 1] = appendedMessage
                syncLatestTimelineRowSnapshot()
            }
            return
        }

        timelineMessages.append(appendedMessage)
        appendLatestTimelineRowSnapshot(for: appendedMessage)
    }

    private func syncTimelineMessagesKeepingTailFresh() {
        guard let latestTimelineMessage = MessageTimelineRowProjection.latestTimelineMessage(
            from: session.messages
        ) else {
            guard !timelineMessages.isEmpty else { return }
            timelineMessages = []
            syncTimelineRowSnapshots()
            return
        }

        guard !timelineMessages.isEmpty,
              let currentLast = timelineMessages.last,
              currentLast.id == latestTimelineMessage.id else {
            syncTimelineMessages()
            return
        }

        if currentLast != latestTimelineMessage {
            timelineMessages[timelineMessages.count - 1] = latestTimelineMessage
            syncLatestTimelineRowSnapshot()
        }
    }

    private func syncTimelineRowSnapshots() {
        let nextSnapshots = MessageTimelineRowProjection.snapshots(
            for: timelineMessages,
            previousSnapshots: timelineRowSnapshots,
            streamingTailMessageID: currentStreamingTailMessageID
        ) { message in
            session.assistantThinkingPresentation(for: message)
        }
        guard timelineRowSnapshots != nextSnapshots else { return }
        timelineRowSnapshots = nextSnapshots
    }

    private var currentStreamingTailMessageID: String? {
        MessageTimelineRowProjection.streamingTailMessageID(
            isSending: timelineSessionSnapshot.isSending,
            timelineMessages: timelineMessages
        )
    }

    private func appendLatestTimelineRowSnapshot(for message: AXChatMessage) {
        guard timelineRowSnapshots.count == timelineMessages.count - 1 else {
            syncTimelineRowSnapshots()
            return
        }

        timelineRowSnapshots.append(
            MessageRowSnapshot(
                message: message,
                thinkingPresentation: session.assistantThinkingPresentation(for: message),
                isStreamingTail: message.id == currentStreamingTailMessageID
            )
        )
    }

    private func syncLatestTimelineRowSnapshot() {
        guard !timelineMessages.isEmpty,
              timelineRowSnapshots.count == timelineMessages.count,
              let latestMessage = timelineMessages.last else {
            syncTimelineRowSnapshots()
            return
        }

        let nextSnapshot = MessageRowSnapshot(
            message: latestMessage,
            thinkingPresentation: session.assistantThinkingPresentation(for: latestMessage),
            isStreamingTail: latestMessage.id == currentStreamingTailMessageID
        )
        let latestIndex = timelineMessages.count - 1
        guard timelineRowSnapshots[latestIndex] != nextSnapshot else { return }
        timelineRowSnapshots[latestIndex] = nextSnapshot
    }

    private func syncTimelinePresentationRowSnapshots() {
        let indexes = MessageTimelineRowProjection.presentationRefreshIndexes(
            timelineMessages: timelineMessages,
            previousSnapshots: timelineRowSnapshots
        )
        guard !indexes.isEmpty else {
            syncTimelineRowSnapshots()
            return
        }

        var nextSnapshots = timelineRowSnapshots
        let streamingTailMessageID = currentStreamingTailMessageID
        var didChange = false
        for index in indexes {
            let message = timelineMessages[index]
            let nextSnapshot = MessageRowSnapshot(
                message: message,
                thinkingPresentation: session.assistantThinkingPresentation(for: message),
                isStreamingTail: message.id == streamingTailMessageID
            )
            guard nextSnapshots[index] != nextSnapshot else { continue }
            nextSnapshots[index] = nextSnapshot
            didChange = true
        }
        guard didChange else { return }
        timelineRowSnapshots = nextSnapshots
    }
}

/// 单个消息卡片
private struct TimelineMessageRow: View, Equatable {
    let ctx: AXProjectContext?
    let config: AXProjectConfig?
    let session: ChatSessionModel?
    let message: AXChatMessage
    let thinkingPresentation: XTStreamingPlaceholderPresentation?

    static func == (lhs: TimelineMessageRow, rhs: TimelineMessageRow) -> Bool {
        lhs.ctx == rhs.ctx &&
        lhs.config == rhs.config &&
        lhs.message == rhs.message &&
        lhs.thinkingPresentation == rhs.thinkingPresentation
    }

    var body: some View {
        MessageCard(
            ctx: ctx,
            config: config,
            session: session,
            message: message,
            thinkingPresentation: thinkingPresentation
        )
    }
}

struct MessageCard: View {
    let ctx: AXProjectContext?
    let config: AXProjectConfig?
    let session: ChatSessionModel?
    let message: AXChatMessage
    let thinkingPresentation: XTStreamingPlaceholderPresentation?

    init(
        ctx: AXProjectContext? = nil,
        config: AXProjectConfig? = nil,
        session: ChatSessionModel? = nil,
        message: AXChatMessage,
        thinkingPresentation: XTStreamingPlaceholderPresentation? = nil
    ) {
        self.ctx = ctx
        self.config = config
        self.session = session
        self.message = message
        self.thinkingPresentation = thinkingPresentation
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUserMessage {
                Spacer(minLength: 56)
            }

            VStack(alignment: bubbleHorizontalAlignment, spacing: 8) {
                headerRow

                MessageContentView(
                    ctx: ctx,
                    config: config,
                    session: session,
                    message: message,
                    thinkingPresentation: thinkingPresentation
                )
            }
            .frame(
                maxWidth: isUserMessage ? 620 : .infinity,
                alignment: bubbleFrameAlignment
            )
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if !isUserMessage {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(roleAccentColor.opacity(0.8))
                        .frame(width: 3)
                        .padding(.vertical, 10)
                        .padding(.leading, 1)
                }
            }

            if !isUserMessage {
                Spacer(minLength: 56)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
    }

    private var roleLabel: String {
        if message.isSupervisorDispatch {
            return "Supervisor"
        }
        switch message.role {
        case .user:
            return "你"
        case .assistant:
            return "助手"
        case .tool:
            return "工具"
        }
    }

    private var isUserMessage: Bool {
        message.role == .user
    }

    private var bubbleHorizontalAlignment: HorizontalAlignment {
        isUserMessage ? .trailing : .leading
    }

    private var bubbleFrameAlignment: Alignment {
        isUserMessage ? .trailing : .leading
    }

    private var roleAccentColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .teal
        case .tool:
            return .secondary
        }
    }

    private var cardBackground: Color {
        if message.isSupervisorDispatch {
            return Color.indigo.opacity(0.06)
        }
        switch message.role {
        case .user:
            return Color.blue.opacity(0.08)
        case .assistant:
            return Color(nsColor: .controlBackgroundColor).opacity(0.95)
        case .tool:
            return Color.secondary.opacity(0.05)
        }
    }

    private var borderColor: Color {
        if message.isSupervisorDispatch {
            return Color.indigo.opacity(0.16)
        }
        switch message.role {
        case .user:
            return Color.blue.opacity(0.18)
        case .assistant:
            return Color.teal.opacity(0.18)
        case .tool:
            return Color.secondary.opacity(0.12)
        }
    }

    private var roleIconName: String? {
        message.isSupervisorDispatch ? "person.2.fill" : nil
    }

    private var timeLabel: String {
        let date = Date(timeIntervalSince1970: message.createdAt)
        return MessageTimelineFormatters.time.string(from: date)
    }

    @ViewBuilder
    private var headerRow: some View {
        if isUserMessage {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                headerMetaRow
                tagView
                MessageRoleBadge(
                    role: message.role,
                    label: roleLabel,
                    accentColor: roleAccentColor
                )
            }
        } else {
            HStack(spacing: 8) {
                MessageRoleBadge(
                    role: message.role,
                    label: roleLabel,
                    accentColor: roleAccentColor
                )
                tagView
                Spacer(minLength: 0)
                headerMetaRow
            }
        }
    }

    private var headerMetaRow: some View {
        HStack(spacing: 6) {
            Text(timeLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if message.role != .tool {
                MessageActionButtons(message: message)
            }
        }
    }

    @ViewBuilder
    private var tagView: some View {
        if let tag = message.tag, !tag.isEmpty {
            Text(tag)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

struct MessageRoleBadge: View {
    let role: AXChatRole
    let label: String
    let accentColor: Color

    var body: some View {
        Label(label, systemImage: iconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentColor.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(0.18), lineWidth: 1)
            )
    }

    private var headerMetaRow: some View {
        HStack(spacing: 6) {
            Text(timeLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if message.role != .tool {
                MessageActionButtons(message: message)
            }
        }
    }

    @ViewBuilder
    private var tagView: some View {
        if let tag = message.tag, !tag.isEmpty {
            Text(tag)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

struct MessageRoleBadge: View {
    let role: AXChatRole
    let label: String
    let accentColor: Color
    var iconName: String? = nil

    var body: some View {
        Label(label, systemImage: resolvedIconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentColor.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(accentColor.opacity(0.18), lineWidth: 1)
            )
    }

    private var resolvedIconName: String {
        if let iconName {
            return iconName
        }
        switch role {
        case .user:
            return "person.fill"
        case .assistant:
            return "sparkles"
        case .tool:
            return "wrench.adjustable"
        }
    }
}

/// 消息操作按钮
struct MessageActionButtons: View {
    let message: AXChatMessage

    var body: some View {
        HStack(spacing: 4) {
            Button {
                copyToClipboard(message.content)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("复制")
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 消息内容视图
struct MessageContentView: View {
    let ctx: AXProjectContext?
    let config: AXProjectConfig?
    let session: ChatSessionModel?
    let message: AXChatMessage
    let thinkingPresentation: XTStreamingPlaceholderPresentation?

    var body: some View {
        switch message.role {
        case .assistant:
            // Assistant 消息：解析并展示结构化内容
            AssistantMessageContent(
                ctx: ctx,
                config: config,
                session: session,
                message: message,
                thinkingPresentation: thinkingPresentation
            )

        case .tool:
            // Tool 消息：展示 tool result
            ToolResultView(ctx: ctx, message: message)

        case .user:
            // User 消息：简单文本
            VStack(alignment: .leading, spacing: 10) {
                MessagePlainTextBody(content: message.content)

                if !message.attachments.isEmpty {
                    XTChatAttachmentStrip(
                        attachments: message.attachments,
                        showsPath: true,
                        onImport: (ctx != nil && session != nil)
                            ? { attachment in
                                guard let ctx, let session else { return }
                                session.importAttachmentToProject(attachment, ctx: ctx)
                            }
                            : nil
                    )
                }
            }
        }
    }
}

struct MessagePlainTextBody: View {
    let content: String
    var isStreamingTail: Bool = false
    @State private var isExpanded = false

    var body: some View {
        if isStreamingTail {
            Text(
                MessageTimelineStreamingTextPresentation.visibleContent(
                    for: content,
                    isStreamingTail: true
                )
            )
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if MessageTimelineLongTextPresentation.shouldCollapse(content) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    isExpanded
                    ? content
                    : MessageTimelineLongTextPresentation.previewContent(for: content)
                )
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isExpanded.toggle()
                } label: {
                    Label(
                        isExpanded ? "收起" : "展开全文",
                        systemImage: isExpanded
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        } else {
            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProjectSkillActivitySection: View {
    let items: [ProjectSkillActivityItem]
    let pendingRequestIDs: Set<String>
    let focusedRequestID: String?
    let isFocused: Bool
    let hubConnected: Bool
    let isBusy: Bool
    let onApprove: (String) -> Void
    let onReject: (String) -> Void
    let onRetry: (ProjectSkillActivityItem) -> Void
    let onOpenGovernance: (XTProjectGovernanceDestination, XTSectionFocusContext?) -> Void
    let onViewFullRecord: (ProjectSkillActivityItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.secondary)
                Text("最近技能动态")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(items.count) 条")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(items) { item in
                ProjectSkillActivityCard(
                    item: item,
                    isPendingApproval: pendingRequestIDs.contains(item.requestID),
                    isFocused: focusedRequestID == item.requestID,
                    hubConnected: hubConnected,
                    isBusy: isBusy,
                    onApprove: {
                        onApprove(item.requestID)
                    },
                    onReject: {
                        onReject(item.requestID)
                    },
                    onRetry: {
                        onRetry(item)
                    },
                    onOpenGovernance: {
                        onOpenGovernance($0, $1)
                    },
                    onViewFullRecord: {
                        onViewFullRecord(item)
                    }
                )
                .id(MessageTimelineFocusPresentation.projectSkillActivityAnchorID(requestID: item.requestID))
            }
        }
        .padding(14)
        .background(isFocused ? Color.orange.opacity(0.06) : Color.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ProjectSkillActivityCard: View {
    let item: ProjectSkillActivityItem
    let isPendingApproval: Bool
    let isFocused: Bool
    let hubConnected: Bool
    let isBusy: Bool
    let onApprove: () -> Void
    let onReject: () -> Void
    let onRetry: () -> Void
    let onOpenGovernance: (XTProjectGovernanceDestination, XTSectionFocusContext?) -> Void
    let onViewFullRecord: () -> Void
    @State private var showGovernanceDetails = false
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: ProjectSkillActivityPresentation.iconName(for: item))
                        .foregroundStyle(iconColor)
                        .font(.system(size: 13, weight: .semibold))

                    Text(ProjectSkillActivityPresentation.title(for: item))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(timeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(ProjectSkillActivityPresentation.statusLabel(for: item))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(iconColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                let skillBadge = ProjectSkillActivityPresentation.skillBadgeText(for: item)
                if !skillBadge.isEmpty {
                    metaBadge(skillBadge)
                }

                let toolBadge = ProjectSkillActivityPresentation.toolBadge(for: item)
                if !toolBadge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metaBadge(toolBadge)
                }

                Spacer()
            }

            Text(ProjectSkillActivityPresentation.timelineBody(for: item))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !governanceDetailLines.isEmpty {
                DisclosureGroup("治理详情", isExpanded: $showGovernanceDetails) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(governanceDetailLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .tint(.secondary)
            }

            HStack(spacing: 8) {
                if ProjectSkillActivityPresentation.isAwaitingApproval(item), isPendingApproval {
                    Button("批准") {
                        onApprove()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !hubConnected)
                    .help(hubConnected ? "批准后继续执行这次受治理的技能调用" : "先连接 Hub，才能批准执行")

                    Button("拒绝") {
                        onReject()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    .help("拒绝这次待审批的技能调用，不继续执行")
                }

                if ProjectSkillActivityPresentation.canRetry(item) {
                    Button("重试") {
                        onRetry()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || isPendingApproval)
                    .help(isPendingApproval ? "这条请求已经在等待审批" : "使用相同的受治理参数重新执行上一次调用")
                }

                if let guardrailRepairHint {
                    Button(guardrailRepairHint.buttonTitle) {
                        onOpenGovernance(
                            guardrailRepairHint.destination,
                            governanceInterception?.repairFocusContext
                        )
                    }
                    .buttonStyle(.bordered)
                    .help(guardrailRepairHint.helpText)
                }

                Button("查看完整记录") {
                    onViewFullRecord()
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if let repairCaption = MessageTimelineGuardrailRepairPresentation.secondaryHintText(
                repairHint: guardrailRepairHint,
                repairActionSummary: governanceInterception?.repairActionSummary
            ) {
                Text(repairCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("详细诊断", isExpanded: $showDiagnostics) {
                ScrollView {
                    Text(ProjectSkillActivityPresentation.diagnostics(for: item))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(.top, 6)
            }
            .font(.caption)
            .tint(.secondary)
        }
        .padding(12)
        .background(isFocused ? Color.orange.opacity(0.1) : Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? Color.orange.opacity(0.52) : iconColor.opacity(0.16), lineWidth: isFocused ? 1.5 : 1)
        )
        .shadow(color: isFocused ? Color.orange.opacity(0.16) : .clear, radius: 8, y: 2)
    }

    private var iconColor: Color {
        switch item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed":
            return .green
        case "failed":
            return .red
        case "blocked":
            return .orange
        case "awaiting_approval":
            return .yellow
        case "resolved":
            return .blue
        default:
            return .secondary
        }
    }

    private var timeLabel: String {
        let date = Date(timeIntervalSince1970: item.createdAt)
        return MessageTimelineFormatters.time.string(from: date)
    }

    private var guardrailRepairHint: XTGuardrailRepairHint? {
        governanceInterception?.repairHint
    }

    private var governanceInterception: ProjectGovernanceInterceptionPresentation? {
        ProjectGovernanceInterceptionPresentation.make(from: item)
    }

    private var governanceDetailLines: [String] {
        var lines = ProjectSkillActivityPresentation.cardGovernedDetailLines(for: item)

        if let governanceTruthLine = ProjectSkillActivityPresentation.displayGovernanceTruthLine(for: item) {
            lines.append(governanceTruthLine)
        }

        if let governanceInterception,
           governanceInterception.shouldShowGovernanceReason {
            lines.append("治理原因：\(governanceInterception.governanceReason)")
        }

        if let policyReason = governanceInterception?.policyReason {
            lines.append("策略原因：\(policyReason)")
        }

        return uniqueNonEmpty(lines)
    }

    private func metaBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08))
            .clipShape(Capsule())
    }

    private func uniqueNonEmpty(_ rawValues: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for rawValue in rawValues {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }

        return result
    }
}

private struct ProjectSkillRecordSheetState: Identifiable {
    let record: ProjectSkillFullRecord

    var id: String { record.id }
}

private struct ProjectSkillRecordSheet: View {
    let record: ProjectSkillRecordSheetState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.record.title)
                        .font(.system(.headline, design: .rounded))
                    HStack(spacing: 8) {
                        Text(record.record.requestID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ProjectSkillRecordStatusBadge(statusLabel: record.record.latestStatusLabel)
                    }
                }

                Spacer()

                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        ProjectSkillActivityPresentation.displayFullRecordText(record.record),
                        forType: .string
                    )
                }
                .buttonStyle(.bordered)

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !record.record.requestMetadata.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "请求信息",
                            fields: record.record.requestMetadata
                        )
                    }

                    if !record.record.approvalFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "审批状态",
                            fields: record.record.approvalFields
                        )
                    }

                    if !record.record.governanceFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "治理上下文",
                            fields: record.record.governanceFields
                        )
                    }

                    if let toolArgs = record.record.toolArgumentsText,
                       !toolArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordCodeSection(
                            title: "工具参数",
                            text: toolArgs,
                            initiallyExpanded: true
                        )
                    }

                    if !record.record.resultFields.isEmpty
                        || !(record.record.rawOutputPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !(record.record.rawOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordResultSection(record: record.record)
                    }

                    if !record.record.evidenceFields.isEmpty {
                        ProjectSkillRecordFieldSection(
                            title: "证据引用",
                            fields: record.record.evidenceFields
                        )
                    }

                    if !record.record.approvalHistory.isEmpty {
                        ProjectSkillRecordTimelineSection(
                            title: "审批记录",
                            entries: record.record.approvalHistory
                        )
                    }

                    if !record.record.timeline.isEmpty {
                        ProjectSkillRecordTimelineSection(
                            title: "事件时间线",
                            entries: record.record.timeline
                        )
                    }

                    if let evidenceJSON = record.record.supervisorEvidenceJSON,
                       !evidenceJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProjectSkillRecordCodeSection(
                            title: "Supervisor 证据 JSON",
                            text: evidenceJSON,
                            initiallyExpanded: false
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

struct ProjectSkillRecordStatusBadge: View {
    let statusLabel: String

    var body: some View {
        if !statusLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           statusLabel != "Unknown",
           statusLabel != "未知" {
            Text(statusLabel)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var color: Color {
        switch statusLabel.lowercased() {
        case "completed", "已完成":
            return .green
        case "failed", "失败":
            return .red
        case "blocked", "受阻":
            return .orange
        case "awaiting approval", "待审批", "待授权":
            return .yellow
        case "resolved", "已路由":
            return .blue
        default:
            return .secondary
        }
    }
}

struct ProjectSkillRecordFieldSection: View {
    let title: String
    let fields: [ProjectSkillRecordField]

    var body: some View {
        let context = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fields) { field in
                    HStack(alignment: .top, spacing: 12) {
                        Text(ProjectSkillActivityPresentation.displayFieldLabel(field.label))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)

                        Text(
                            ProjectSkillActivityPresentation.displayFieldValue(
                                field.label,
                                field.value,
                                context: context
                            )
                        )
                            .font(.system(.subheadline, design: .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }

    private var sectionTitle: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
            Spacer()
            Text("\(fields.count)")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

struct ProjectSkillRecordCodeSection: View {
    let title: String
    let text: String
    let initiallyExpanded: Bool
    @State private var isExpanded: Bool

    init(title: String, text: String, initiallyExpanded: Bool) {
        self.title = title
        self.text = text
        self.initiallyExpanded = initiallyExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $isExpanded) {
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(maxHeight: 220)
            } label: {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .tint(.secondary)
    }
}

private struct ProjectSkillRecordResultSection: View {
    let record: ProjectSkillFullRecord
    @State private var showFullRawOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("执行结果")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                Spacer()
            }

            if !record.resultFields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.resultFields) { field in
                        HStack(alignment: .top, spacing: 12) {
                            Text(ProjectSkillActivityPresentation.displayFieldLabel(field.label))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)

                            Text(ProjectSkillActivityPresentation.displayFieldValue(field.label, field.value))
                                .font(.system(.subheadline, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if let preview = record.rawOutputPreview,
               !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("原始输出预览")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }

            if let rawOutput = record.rawOutput,
               !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("完整原始输出", isExpanded: $showFullRawOutput) {
                    ScrollView {
                        Text(rawOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .frame(maxHeight: 220)
                }
                .font(.caption)
                .tint(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ProjectSkillRecordTimelineSection: View {
    let title: String
    let entries: [ProjectSkillRecordTimelineEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ForEach(entries) { entry in
                ProjectSkillRecordTimelineCard(entry: entry)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ProjectSkillRecordTimelineCard: View {
    let entry: ProjectSkillRecordTimelineEntry
    @State private var showRawJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.statusLabel)
                    .font(.system(.caption2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                Text(entry.timestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(entry.summary)
                .font(.system(.subheadline, design: .default))
                .fixedSize(horizontal: false, vertical: true)

            if let detail = ProjectSkillActivityPresentation.displayTimelineDetail(entry.detail),
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("原始事件 JSON", isExpanded: $showRawJSON) {
                ScrollView {
                    Text(entry.rawJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .frame(maxHeight: 180)
            }
            .font(.caption)
            .tint(.secondary)
        }
        .padding(12)
        .background(statusColor.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.14), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch entry.status.lowercased() {
        case "completed":
            return .green
        case "failed":
            return .red
        case "blocked":
            return .orange
        case "awaiting_approval":
            return .yellow
        case "resolved":
            return .blue
        default:
            return .secondary
        }
    }
}

/// Tool Result 视图
struct ToolResultView: View {
    let ctx: AXProjectContext?
    let message: AXChatMessage
    @Environment(\.xtAppModelReference) private var appModelReference
    @State private var toolResult: ToolResult?
    @State private var showDiagnostics = false

    var body: some View {
        Group {
            if let result = toolResult, !ToolResultPresentation.shouldShowTimelineCard(for: result) {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: resultIcon)
                            .foregroundColor(resultColor)
                            .font(.system(size: 14))

                        Text(summaryTitle)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)

                        Spacer()

                        if let result = toolResult {
                            Text(result.tool.rawValue)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(summaryBody)
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let governanceTruthLine {
                        Text(governanceTruthLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let governanceReason {
                        Text("治理原因：\(governanceReason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let policyReason {
                        Text("策略原因：\(policyReason)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let guardrailRepairHint {
                        Button(guardrailRepairHint.buttonTitle) {
                            openGovernance(guardrailRepairHint.destination)
                        }
                        .buttonStyle(.bordered)
                        .help(guardrailRepairHint.helpText)
                    }

                    if let repairCaption = MessageTimelineGuardrailRepairPresentation.secondaryHintText(
                        repairHint: guardrailRepairHint
                    ) {
                        Text(repairCaption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DisclosureGroup("详细诊断", isExpanded: $showDiagnostics) {
                        ScrollView {
                            Text(diagnosticsText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                        .padding(.top, 6)
                    }
                    .font(.caption)
                    .tint(.secondary)
                }
                .padding(12)
                .background(resultBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(resultBorderColor, lineWidth: 1)
                )
            }
        }
        .onAppear {
            toolResult = ToolResultParser.parse(message.content)
        }
        .onChange(of: message.content) { newContent in
            toolResult = ToolResultParser.parse(newContent)
        }
    }

    private var resultIcon: String {
        guard let result = toolResult else { return "exclamationmark.triangle.fill" }
        return ToolResultPresentation.iconName(for: result)
    }

    private var resultColor: Color {
        guard let result = toolResult else { return .orange }
        return result.ok ? .green : .orange
    }

    private var summaryTitle: String {
        guard let result = toolResult else { return "这条操作需要处理" }
        return ToolResultPresentation.title(for: result)
    }

    private var summaryBody: String {
        guard let result = toolResult else {
            return "这次工具调用返回了诊断信息，可展开“详细诊断”查看原始输出。"
        }
        return ToolResultPresentation.timelineBody(for: result)
    }

    private var governanceTruthLine: String? {
        guard let result = toolResult, !result.ok else { return nil }
        return ToolResultPresentation.governanceTruthLine(for: result)
    }

    private var guardrailRepairHint: XTGuardrailRepairHint? {
        guard let result = toolResult, !result.ok else { return nil }
        return ToolResultPresentation.repairHint(for: result)
    }

    private var governanceReason: String? {
        guard let result = toolResult, !result.ok else { return nil }
        return ToolResultPresentation.governanceReason(for: result)
    }

    private var policyReason: String? {
        guard let result = toolResult, !result.ok else { return nil }
        return ToolResultPresentation.policyReason(for: result)
    }

    private var diagnosticsText: String {
        if let result = toolResult, !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result.output
        }
        return message.content
    }

    private var resultBackground: Color {
        guard let result = toolResult else { return Color.orange.opacity(0.06) }
        return result.ok ? Color.green.opacity(0.06) : Color.orange.opacity(0.06)
    }

    private var resultBorderColor: Color {
        guard let result = toolResult else { return Color.orange.opacity(0.24) }
        return result.ok ? Color.green.opacity(0.24) : Color.orange.opacity(0.24)
    }

    private func openGovernance(_ destination: XTProjectGovernanceDestination) {
        guard let ctx else { return }
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        guard !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appModel.requestProjectSettingsFocus(
            projectId: projectId,
            destination: destination
        )
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ToolResultView requires xtAppModelReference")
        }
        return appModelReference
    }
}

/// Assistant 消息内容（支持 tool calls 展示）
struct AssistantMessageContent: View {
    let ctx: AXProjectContext?
    let config: AXProjectConfig?
    let session: ChatSessionModel?
    let message: AXChatMessage
    let thinkingPresentation: XTStreamingPlaceholderPresentation?

    private var parsedContent: ParsedContent {
        MessageTimelineRenderCache.parsedContent(for: message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thinkingPresentation {
                XTStreamingPlaceholderView(presentation: thinkingPresentation)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !parsedContent.isEmpty {
                // 结构化内容
                ForEach(parsedContent.parts) { part in
                    ParsedPartView(part: part)
                }
            } else {
                messageBody
            }

            if let ctx,
               let session,
               snapshot.showsRouteDiagnoseActions {
                RouteDiagnoseActionRail(
                    ctx: ctx,
                    config: config,
                    session: session,
                    sessionIsSending: sessionIsSending,
                    messageContent: message.content
                )
            }
        }
    }
}

struct RouteDiagnoseActionRail: View {
    private struct RuntimeSnapshot: Equatable {
        var effectiveProjectConfig: AXProjectConfig?
        var recommendation: HubModelPickerRecommendationState?
        var latestRouteEvent: AXModelRouteDiagnosticEvent?
        var supervisorRouteExplainability: RouteDiagnoseMessagePresentation.SupervisorRouteExplainability?

        static let empty = RuntimeSnapshot(
            effectiveProjectConfig: nil,
            recommendation: nil,
            latestRouteEvent: nil,
            supervisorRouteExplainability: nil
        )
    }

    let ctx: AXProjectContext
    let config: AXProjectConfig?
    let session: ChatSessionModel
    let sessionIsSending: Bool
    let messageContent: String
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var showModelPicker = false
    @State private var repairActionInFlight = false
    @State private var actionNotice: XTSettingsChangeNotice?
    @State private var runtimeSnapshot = RuntimeSnapshot.empty

    private var effectiveProjectConfig: AXProjectConfig? {
        runtimeSnapshot.effectiveProjectConfig
            ?? config
            ?? .default(forProjectRoot: ctx.root)
    }

    private var recommendation: HubModelPickerRecommendationState? {
        runtimeSnapshot.recommendation
    }

    private var availableModels: [HubModel] {
        visibleModelSnapshot.models
    }

    private var visibleModelSnapshot: ModelStateSnapshot {
        modelManager.visibleSnapshot(fallback: appModel.modelsState)
    }

    private var interfaceLanguage: XTInterfaceLanguage {
        appModel.settingsStore.settings.interfaceLanguage
    }

    private var recommendationTitle: String? {
        guard let recommendation else { return nil }
        return RouteDiagnoseMessagePresentation.actionTitle(
            for: recommendation,
            models: availableModels,
            language: interfaceLanguage
        )
    }

    private var latestRouteEvent: AXModelRouteDiagnosticEvent? {
        runtimeSnapshot.latestRouteEvent
    }

    private var supervisorRouteExplainability: RouteDiagnoseMessagePresentation.SupervisorRouteExplainability? {
        runtimeSnapshot.supervisorRouteExplainability
    }

    private func recordRouteRepairLog(
        actionId: String,
        outcome: String,
        repairReasonCode: String? = nil,
        note: String? = nil
    ) {
        AXRouteRepairLogStore.record(
            actionId: actionId,
            outcome: outcome,
            latestEvent: latestRouteEvent,
            repairReasonCode: repairReasonCode,
            note: note,
            for: ctx
        )
    }

    private func openRouteDiagnoseModelPicker() {
        recordRouteRepairLog(actionId: "open_model_picker", outcome: "opened")
        showModelPicker = true
        presentRouteActionFeedback(for: .inlineModelPickerOpened)
    }

    private var repairAction: RouteDiagnoseMessagePresentation.RepairAction? {
        RouteDiagnoseMessagePresentation.repairAction(
            latestEvent: latestRouteEvent,
            hubConnected: hubConnectionSnapshot.localConnected,
            hubRemoteConnected: hubConnectionSnapshot.remoteConnected,
            hasRecommendation: recommendation != nil,
            messageContent: messageContent
        )
    }

    private var repairActionTitle: String? {
        guard let repairAction else { return nil }
        return RouteDiagnoseMessagePresentation.title(
            for: repairAction,
            inProgress: repairActionInFlight || hubConnectionSnapshot.remoteLinking,
            language: interfaceLanguage
        )
    }

    private var repairFocusContext: XTSectionFocusContext? {
        guard let repairAction else { return nil }
        return RouteDiagnoseMessagePresentation.focusContext(
            for: repairAction,
            latestEvent: latestRouteEvent,
            recommendation: recommendation,
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            explainability: supervisorRouteExplainability,
            language: interfaceLanguage
        )
    }

    private var repairActionBusy: Bool {
        guard let repairAction else { return false }
        switch repairAction {
        case .connectHubAndDiagnose, .reconnectHubAndDiagnose:
            return repairActionInFlight || hubConnectionSnapshot.remoteLinking
        case .openChooseModel, .openProjectGovernanceOverview, .openHubRecovery, .openHubConnectionLog:
            return false
        }
    }

    var body: some View {
        routeDiagnoseCard
            .popover(isPresented: $showModelPicker) {
                ModelSelectorView(
                    projectContext: ctx,
                    config: effectiveProjectConfig,
                    focusContext: RouteDiagnoseMessagePresentation.focusContext(
                        for: .openChooseModel,
                        latestEvent: latestRouteEvent,
                        recommendation: recommendation,
                        paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
                        language: interfaceLanguage
                    )
                )
                    .frame(width: 420)
            }
            .onDisappear {
                updateFeedback.cancel(resetState: true)
                actionNotice = nil
            }
            .onAppear {
                handleRouteDiagnoseAppear()
            }
            .onChange(of: runtimeRefreshSignature) { _ in
                refreshRuntimeSnapshot()
            }
            .onChange(of: hubConnectionSnapshot.interactive) { connected in
                if connected {
                    fetchVisibleModels()
                }
            }
    }

    private var routeDiagnoseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            modelActionRow
            repairActionRow
            actionNoticeView
            governanceExplainabilityView
            helperMessageView
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: updateFeedback.isHighlighted,
            focusTint: .orange,
            updateTint: .accentColor,
            baseBackground: Color.orange.opacity(0.06),
            baseBorder: Color.orange.opacity(0.18)
        )
    }

    private var modelActionRow: some View {
        HStack(spacing: 8) {
            if let recommendation,
               let recommendationTitle {
                Button(recommendationTitle) {
                    applyRecommendedModel(recommendation)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(sessionIsSending)

                Button(XTL10n.RouteDiagnose.moreModels.resolve(interfaceLanguage)) {
                    openRouteDiagnoseModelPicker()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hubConnectionSnapshot.interactive)
            } else {
                Button(XTL10n.RouteDiagnose.changeModel.resolve(interfaceLanguage)) {
                    openRouteDiagnoseModelPicker()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hubConnectionSnapshot.interactive)
            }

            Button(XTL10n.RouteDiagnose.rediagnose.resolve(interfaceLanguage)) {
                session.presentProjectRouteDiagnosis(
                    ctx: ctx,
                    config: effectiveProjectConfig,
                    router: appModel.llmRouter
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(sessionIsSending)
        }
    }

    private var repairActionRow: some View {
        HStack(spacing: 8) {
            if let repairAction,
               let repairActionTitle {
                Button(repairActionTitle) {
                    runRepairAction(repairAction)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(repairActionBusy)
            }

            Button(XTL10n.RouteDiagnose.modelSettingsButton.resolve(interfaceLanguage)) {
                openModelSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(XTL10n.Common.xtDiagnostics.resolve(interfaceLanguage)) {
                openDiagnostics()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var actionNoticeView: some View {
        if updateFeedback.showsBadge,
           let actionNotice {
            XTSettingsChangeNoticeInlineView(
                notice: actionNotice,
                tint: .accentColor
            )
        }
    }

    @ViewBuilder
    private var helperMessageView: some View {
        if let recommendation {
            Text(recommendation.message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let repairAction {
            Text(
                RouteDiagnoseMessagePresentation.helperText(
                    for: repairAction,
                    explainability: supervisorRouteExplainability,
                    language: interfaceLanguage
                )
            )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var governanceExplainabilityView: some View {
        if let supervisorRouteExplainability,
           supervisorRouteExplainability.hasActionableBlocker
            || supervisorRouteExplainability.runtimeReadinessSummary != nil {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    RouteDiagnoseMessagePresentation.supervisorRouteExplainabilityHeading(
                        language: interfaceLanguage
                    ),
                    systemImage: supervisorRouteExplainability.hasActionableBlocker
                        ? "exclamationmark.triangle"
                        : "checkmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    supervisorRouteExplainability.hasActionableBlocker ? Color.orange : Color.green
                )

                ForEach(
                    RouteDiagnoseMessagePresentation.supervisorRouteExplainabilityLines(
                        supervisorRouteExplainability,
                        language: interfaceLanguage
                    ),
                    id: \.self
                ) { line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func handleRouteDiagnoseAppear() {
        modelManager.setAppModel(appModel)
        refreshRuntimeSnapshot()
        fetchVisibleModels()
    }

    private var runtimeRefreshSignature: String {
        let modelSignature = visibleModelSnapshot.models
            .map { "\($0.id):\(String(describing: $0.state))" }
            .joined(separator: ",")
        return [
            ctx.root.standardizedFileURL.path,
            "\(messageContent.utf8.count)",
            "\(XTMessageTimelineContentFingerprint.make(from: messageContent))",
            "\(visibleModelSnapshot.updatedAt)",
            modelSignature,
            appModel.settingsStore.settings.interfaceLanguage.rawValue,
            appModel.settingsStore.settings.assignment(for: .coder).model ?? "",
            appModel.projectConfig?.modelOverride(for: .coder) ?? ""
        ].joined(separator: "|")
    }

    private func refreshRuntimeSnapshot() {
        let effectiveConfig = resolveEffectiveProjectConfig()
        let recommendation = RouteDiagnoseMessagePresentation.recommendation(
            config: effectiveConfig,
            settings: appModel.settingsStore.settings,
            ctx: ctx,
            modelsState: visibleModelSnapshot
        )
        let latestRouteEvent = XTProjectUIPresentationReadCache.latestRouteEvent(
            for: ctx,
            limit: 1
        ) {
            AXModelRouteDiagnosticsStore.recentEvents(for: ctx, limit: 1).first
        }
        let supervisorRouteExplainability = RouteDiagnoseMessagePresentation
            .supervisorRouteExplainability(from: messageContent)
        let nextSnapshot = RuntimeSnapshot(
            effectiveProjectConfig: effectiveConfig,
            recommendation: recommendation,
            latestRouteEvent: latestRouteEvent,
            supervisorRouteExplainability: supervisorRouteExplainability
        )
        guard runtimeSnapshot != nextSnapshot else { return }
        runtimeSnapshot = nextSnapshot
    }

    private func resolveEffectiveProjectConfig() -> AXProjectConfig? {
        if appModel.projectContext?.root.standardizedFileURL == ctx.root.standardizedFileURL,
           let current = appModel.projectConfig {
            return current
        }
        return XTProjectUIPresentationReadCache.projectConfig(for: ctx) {
            (try? AXProjectStore.loadOrCreateConfig(for: ctx))
                ?? config
                ?? .default(forProjectRoot: ctx.root)
        }
    }

    private func fetchVisibleModels() {
        guard hubConnectionSnapshot.interactive else { return }
        Task {
            await modelManager.fetchModels()
        }
    }

    private func openModelSettings() {
        recordRouteRepairLog(
            actionId: "open_model_settings",
            outcome: "opened"
        )
        let context = RouteDiagnoseMessagePresentation.modelSettingsContext(
            latestEvent: latestRouteEvent,
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            language: interfaceLanguage
        )
        appModel.requestModelSettingsFocus(
            role: .coder,
            title: context.title,
            detail: context.detail
        )
        SupervisorManager.shared.requestSupervisorWindow(
            sheet: .modelSettings,
            reason: "route_diagnose_model_settings",
            focusConversation: false
        )
        presentRouteActionFeedback(for: .modelSettingsOpened)
    }

    private func openDiagnostics() {
        recordRouteRepairLog(
            actionId: "open_xt_diagnostics",
            outcome: "opened"
        )
        let context = RouteDiagnoseMessagePresentation.diagnosticsContext(
            latestEvent: latestRouteEvent,
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            language: interfaceLanguage
        )
        appModel.requestSettingsFocus(
            sectionId: "diagnostics",
            title: context.title,
            detail: context.detail
        )
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        presentRouteActionFeedback(for: .diagnosticsOpened)
    }

    private func runRepairAction(_ action: RouteDiagnoseMessagePresentation.RepairAction) {
        repairActionInFlight = true
        Task { @MainActor in
            switch action {
            case .connectHubAndDiagnose:
                recordRouteRepairLog(
                    actionId: "connect_hub_and_diagnose",
                    outcome: "started"
                )
                let report = await appModel.runHubOneClickSetup(showAlertOnFinish: false)
                if let report {
                    recordRouteRepairLog(
                        actionId: "connect_hub_and_diagnose",
                        outcome: report.ok ? "succeeded" : "failed",
                        repairReasonCode: report.reasonCode,
                        note: report.summary
                    )
                    presentRouteActionFeedback(
                        for: .connectivityRepairFinished(action: action, report: report)
                    )
                    if !report.ok {
                        let context = RouteDiagnoseMessagePresentation.diagnosticsFailureContext(
                            for: action,
                            report: report,
                            latestEvent: latestRouteEvent,
                            language: interfaceLanguage
                        )
                        recordRouteRepairLog(
                            actionId: "open_xt_diagnostics",
                            outcome: "auto_opened",
                            repairReasonCode: report.reasonCode,
                            note: "source=connect_hub_and_diagnose_failed"
                        )
                        appModel.requestSettingsFocus(
                            sectionId: "diagnostics",
                            title: context.title,
                            detail: context.detail
                        )
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                } else {
                    presentRouteActionFeedback(
                        for: .connectivityRepairFinished(action: action, report: nil)
                    )
                }
                session.presentProjectRouteDiagnosis(
                    ctx: ctx,
                    config: effectiveProjectConfig,
                    router: appModel.llmRouter
                )
            case .reconnectHubAndDiagnose:
                recordRouteRepairLog(
                    actionId: "reconnect_hub_and_diagnose",
                    outcome: "started"
                )
                let report = await appModel.runHubReconnectOnly(showAlertOnFinish: false)
                if let report {
                    recordRouteRepairLog(
                        actionId: "reconnect_hub_and_diagnose",
                        outcome: report.ok ? "succeeded" : "failed",
                        repairReasonCode: report.reasonCode,
                        note: report.summary
                    )
                    presentRouteActionFeedback(
                        for: .connectivityRepairFinished(action: action, report: report)
                    )
                    if !report.ok {
                        let context = RouteDiagnoseMessagePresentation.diagnosticsFailureContext(
                            for: action,
                            report: report,
                            latestEvent: latestRouteEvent,
                            language: interfaceLanguage
                        )
                        recordRouteRepairLog(
                            actionId: "open_xt_diagnostics",
                            outcome: "auto_opened",
                            repairReasonCode: report.reasonCode,
                            note: "source=reconnect_hub_and_diagnose_failed"
                        )
                        appModel.requestSettingsFocus(
                            sectionId: "diagnostics",
                            title: context.title,
                            detail: context.detail
                        )
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                } else {
                    presentRouteActionFeedback(
                        for: .connectivityRepairFinished(action: action, report: nil)
                    )
                }
                session.presentProjectRouteDiagnosis(
                    ctx: ctx,
                    config: effectiveProjectConfig,
                    router: appModel.llmRouter
                )
            case .openChooseModel:
                recordRouteRepairLog(
                    actionId: "open_choose_model",
                    outcome: "opened"
                )
                appModel.requestModelSettingsFocus(
                    role: .coder,
                    title: repairFocusContext?.title,
                    detail: repairFocusContext?.detail
                )
                SupervisorManager.shared.requestSupervisorWindow(
                    sheet: .modelSettings,
                    reason: "route_diagnose_open_choose_model",
                    focusConversation: false
                )
                presentRouteActionFeedback(for: .repairSurfaceOpened(action))
            case .openProjectGovernanceOverview:
                recordRouteRepairLog(
                    actionId: "open_project_governance_overview",
                    outcome: "opened"
                )
                let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
                let context = RouteDiagnoseMessagePresentation.projectGovernanceContext(
                    explainability: supervisorRouteExplainability,
                    language: interfaceLanguage
                )
                appModel.requestProjectSettingsFocus(
                    projectId: projectId,
                    destination: .overview,
                    title: context.title,
                    detail: context.detail
                )
                presentRouteActionFeedback(for: .repairSurfaceOpened(action))
            case .openHubRecovery:
                recordRouteRepairLog(
                    actionId: "open_hub_recovery",
                    outcome: "opened"
                )
                appModel.requestHubSetupFocus(
                    sectionId: "troubleshoot",
                    title: repairFocusContext?.title,
                    detail: repairFocusContext?.detail
                )
                openWindow(id: "hub_setup")
                presentRouteActionFeedback(for: .repairSurfaceOpened(action))
            case .openHubConnectionLog:
                recordRouteRepairLog(
                    actionId: "open_hub_connection_log",
                    outcome: "opened"
                )
                appModel.requestHubSetupFocus(
                    sectionId: "connection_log",
                    title: repairFocusContext?.title,
                    detail: repairFocusContext?.detail
                )
                openWindow(id: "hub_setup")
                presentRouteActionFeedback(for: .repairSurfaceOpened(action))
            }
            repairActionInFlight = false
        }
    }

    private func applyRecommendedModel(_ recommendation: HubModelPickerRecommendationState) {
        recordRouteRepairLog(
            actionId: "apply_recommended_model",
            outcome: "selected",
            note: "target_model=\(recommendation.modelId)"
        )
        appModel.setProjectRoleModel(for: ctx, role: .coder, modelId: recommendation.modelId)
        let refreshedConfig = (try? AXProjectStore.loadOrCreateConfig(for: ctx))
            ?? effectiveProjectConfig
        refreshRuntimeSnapshot()
        presentRouteActionNotice(
            XTSettingsChangeNoticeBuilder.projectRoleModel(
                projectName: ctx.displayName(registry: appModel.registry),
                role: .coder,
                modelId: recommendation.modelId,
                inheritedModelId: appModel.settingsStore.settings.assignment(for: .coder).model,
                snapshot: visibleModelSnapshot,
                executionSnapshot: AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[.coder]
                    ?? .empty(role: .coder, source: "message_timeline"),
                transportMode: HubAIClient.transportMode().rawValue
            )
        )
        session.presentProjectRouteDiagnosis(
            ctx: ctx,
            config: refreshedConfig,
            router: appModel.llmRouter
        )
    }

    private func presentRouteActionNotice(_ notice: XTSettingsChangeNotice) {
        actionNotice = notice
        updateFeedback.trigger()
    }

    private func presentRouteActionFeedback(
        for trigger: RouteDiagnoseMessagePresentation.RailFeedbackTrigger
    ) {
        let plan = RouteDiagnoseMessagePresentation.railFeedbackPlan(
            for: trigger,
            language: interfaceLanguage
        )
        guard let notice = plan.notice else { return }
        actionNotice = notice
        if plan.shouldHighlight {
            updateFeedback.trigger()
        }
    }

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("RouteDiagnoseActionRail requires xtAppModelReference")
        }
        return appModelReference
    }
}

/// 解析后的部分视图
struct ParsedPartView: View {
    let part: ParsedPart

    var body: some View {
        switch part {
        case .text(let content):
            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .toolCall(let toolCall):
            ToolCallCard(toolCall: toolCall)

        case .thinking(let content):
            ThinkingCard(content: content)
        }
    }
}

/// Tool Call 卡片
struct ToolCallCard: View {
    let toolCall: ToolCall
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 工具头部（可点击折叠）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: toolIcon)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayToolName)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)

                        if displayToolName != toolCall.tool.rawValue {
                            Text(toolCall.tool.rawValue)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 工具详情（可折叠）
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // 参数
                    if !toolCall.args.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("参数")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(Array(toolCall.args.keys.sorted()), id: \.self) { key in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(key)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Text(formatArgValue(toolCall.args[key]))
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var toolIcon: String {
        switch toolCall.tool {
        case .read_file:
            return "doc.text"
        case .write_file:
            return "pencil"
        case .delete_path:
            return "trash"
        case .move_path:
            return "arrow.right.doc.on.clipboard"
        case .list_dir:
            return "folder"
        case .search:
            return "magnifyingglass"
        case .skills_search:
            return "magnifyingglass"
        case .skills_pin:
            return "pin"
        case .skillsExecuteRunner:
            return "play.rectangle"
        case .summarize:
            return "text.alignleft"
        case .supervisorVoicePlayback:
            return "speaker.wave.2.fill"
        case .run_local_task:
            return "cpu"
        case .run_command:
            return "terminal"
        case .process_start:
            return "play.circle"
        case .process_status:
            return "waveform.path.ecg"
        case .process_logs:
            return "doc.text.magnifyingglass"
        case .process_stop:
            return "stop.circle"
        case .git_status, .git_diff, .git_apply_check, .git_apply:
            return "arrow.triangle.branch"
        case .git_commit:
            return "checkmark.circle"
        case .git_push:
            return "arrow.up.circle"
        case .pr_create:
            return "arrowshape.turn.up.right.circle"
        case .ci_read:
            return "list.bullet.clipboard"
        case .ci_trigger:
            return "bolt.badge.clock"
        case .session_list:
            return "list.bullet.rectangle"
        case .session_resume:
            return "play.circle"
        case .session_compact:
            return "archivebox"
        case .agentImportRecord:
            return "checklist"
        case .memory_snapshot:
            return "memorychip"
        case .project_snapshot:
            return "folder.badge.gearshape"
        case .deviceUIObserve:
            return "eye"
        case .deviceUIAct:
            return "hand.tap"
        case .deviceUIStep:
            return "point.3.connected.trianglepath.dotted"
        case .deviceClipboardRead, .deviceClipboardWrite:
            return "list.clipboard"
        case .deviceScreenCapture:
            return "camera.viewfinder"
        case .deviceBrowserControl:
            return "safari"
        case .deviceAppleScript:
            return "apple.logo"
        case .need_network, .bridge_status, .web_fetch, .web_search, .browser_read:
            return "network"
        }
    }

    private var displayToolName: String {
        XTPendingApprovalPresentation.displayToolName(for: toolCall.tool)
    }

    private func formatArgValue(_ value: JSONValue?) -> String {
        guard let value = value else { return "null" }

        switch value {
        case .string(let s):
            return s.count > 100 ? String(s.prefix(100)) + "..." : s
        case .number(let n):
            return String(n)
        case .bool(let b):
            return String(b)
        case .null:
            return "null"
        case .array(let arr):
            return "[\(arr.count) items]"
        case .object(let obj):
            return "{\(obj.count) keys}"
        }
    }
}

/// Thinking 卡片
struct ThinkingCard: View {
    let content: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "brain")
                        .foregroundColor(.orange)
                    Text("思考过程")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 22)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

/// 思考指示器
struct ThinkingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(scale(for: index))
                }
            }

            Text("准备回复")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.08))
        )
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }

    private func scale(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.33
        let normalizedPhase = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 1.0 + sin(normalizedPhase * .pi * 2) * 0.4
    }
}
