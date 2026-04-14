import Testing
@testable import XTerminal

struct MessageTimelineWindowingSupportTests {

    @Test
    func initialVisibleRangeStartsFromLatestPage() {
        let range = MessageTimelineWindowingSupport.initialVisibleRange(
            totalCount: 180,
            pageSize: 80
        )

        #expect(range == 100..<180)
    }

    @Test
    func prependedVisibleRangeKeepsLoadedTail() {
        let range = MessageTimelineWindowingSupport.prependedVisibleRange(
            currentRange: 100..<180,
            totalCount: 180,
            pageSize: 80
        )

        #expect(range == 20..<180)
    }

    @Test
    func latestVisibleRangeTracksBottomWithoutGrowingUnbounded() {
        let range = MessageTimelineWindowingSupport.latestVisibleRange(
            from: 20..<180,
            totalCount: 196,
            pageSize: 80,
            maxWindowSize: 120,
            stickToBottom: true
        )

        #expect(range == 76..<196)
    }

    @Test
    func latestVisibleRangeKeepsHistoryWindowStableWhenUserIsReadingOlderMessages() {
        let range = MessageTimelineWindowingSupport.latestVisibleRange(
            from: 20..<100,
            totalCount: 196,
            pageSize: 80,
            maxWindowSize: 120,
            stickToBottom: false
        )

        #expect(range == 20..<100)
    }

    @Test
    func prependedVisibleRangeCapsMaximumWindowSize() {
        let range = MessageTimelineWindowingSupport.prependedVisibleRange(
            currentRange: 80..<200,
            totalCount: 200,
            pageSize: 30,
            maxWindowSize: 120
        )

        #expect(range == 50..<170)
    }

    @Test
    func shouldStickToBottomOnlyWhenBottomAnchorIsNearViewport() {
        #expect(
            MessageTimelineWindowingSupport.shouldStickToBottom(
                bottomAnchorMaxY: 620,
                viewportHeight: 600,
                threshold: 32
            )
        )

        #expect(
            !MessageTimelineWindowingSupport.shouldStickToBottom(
                bottomAnchorMaxY: 680,
                viewportHeight: 600,
                threshold: 32
            )
        )
    }
}
