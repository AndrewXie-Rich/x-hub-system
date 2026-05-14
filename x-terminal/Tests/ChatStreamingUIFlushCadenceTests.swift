import Testing
@testable import XTerminal

struct ChatStreamingUIFlushCadenceTests {
    @Test
    func flushCadenceKeepsShortStreamingResponsive() {
        #expect(
            ChatStreamingUIFlushCadence.delayNanoseconds(
                forContentByteCount: ChatStreamingUIFlushCadence.mediumByteThreshold
            ) == ChatStreamingUIFlushCadence.shortIntervalNanoseconds
        )
    }

    @Test
    func flushCadenceSlowsLargeStreamingUpdates() {
        #expect(
            ChatStreamingUIFlushCadence.delayNanoseconds(
                forContentByteCount: ChatStreamingUIFlushCadence.mediumByteThreshold + 1
            ) == ChatStreamingUIFlushCadence.mediumIntervalNanoseconds
        )
        #expect(
            ChatStreamingUIFlushCadence.delayNanoseconds(
                forContentByteCount: ChatStreamingUIFlushCadence.longByteThreshold + 1
            ) == ChatStreamingUIFlushCadence.longIntervalNanoseconds
        )
    }
}
