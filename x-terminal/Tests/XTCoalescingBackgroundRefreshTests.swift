import Foundation
import Testing
@testable import XTerminal

@Suite(.timeLimit(.minutes(1)))
struct XTCoalescingBackgroundRefreshTests {
    @Test @MainActor
    func burstCapturesOnlyLatestStateAfterCoalescing() async {
        let refresh = XTCoalescingBackgroundRefresh<Int>(delayNanoseconds: 1_000_000)
        var selection = 0
        var preparations = 0
        var published: [Int] = []
        for project in 1...50 {
            selection = project
            refresh.request(prepare: {
                preparations += 1
                let selected = selection
                return { selected }
            }, publish: { published.append($0) })
        }
        await refresh.waitForIdle()
        #expect(preparations == 1)
        #expect(published == [50])
    }

    @Test @MainActor
    func slowReadLeavesMainActorResponsiveAndLatestRequestWins() async {
        let refresh = XTCoalescingBackgroundRefresh<Int>(delayNanoseconds: 0)
        let slowRead = BlockingRead()
        var started = slowRead.started.makeAsyncIterator()
        var published: [Int] = []
        var prepared: [Int] = []
        refresh.request(prepare: {
            prepared.append(1)
            return { slowRead.read() }
        }, publish: { published.append($0) })

        // The background read stays blocked until this main-actor continuation
        // runs. If the work moves onto the UI executor, the bounded wait times
        // out and the assertions fail instead of hanging the test process.
        _ = await started.next()
        #expect(!slowRead.finished)
        for project in [2, 3] {
            refresh.request(prepare: {
                prepared.append(project)
                return { project }
            }, publish: { published.append($0) })
        }
        #expect(prepared == [1])
        slowRead.release.signal()
        await refresh.waitForIdle()

        #expect(slowRead.ranOffMainThread)
        #expect(!slowRead.timedOut)
        #expect(prepared == [1, 3])
        #expect(published == [3])
    }

    @Test @MainActor
    func manualUpdateInvalidatesInFlightReadWithoutStartingOverlap() async {
        let refresh = XTCoalescingBackgroundRefresh<Int>(delayNanoseconds: 0)
        let slowRead = BlockingRead()
        var started = slowRead.started.makeAsyncIterator()
        var displayed = 0
        refresh.request(prepare: { { slowRead.read() } }, publish: { displayed = $0 })
        _ = await started.next()
        refresh.invalidate()
        displayed = 99
        slowRead.release.signal()
        await refresh.waitForIdle()
        #expect(displayed == 99)

        refresh.request(prepare: { { 100 } }, publish: { displayed = $0 })
        await refresh.waitForIdle()
        #expect(displayed == 100)
    }

    @Test @MainActor
    func invalidatingQueuedRefreshPreventsAnyRead() async {
        let refresh = XTCoalescingBackgroundRefresh<Int>(delayNanoseconds: 1_000_000)
        var preparations = 0
        var published: [Int] = []
        refresh.request(prepare: {
            preparations += 1
            return { 1 }
        }, publish: { published.append($0) })
        refresh.invalidate()
        await refresh.waitForIdle()
        #expect(preparations == 0)
        #expect(published.isEmpty)
    }
}

private final class BlockingRead: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    let started: AsyncStream<Void>
    private let start: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var didFinish = false
    private var wasOffMainThread = false
    private var didTimeOut = false

    init() {
        var continuation: AsyncStream<Void>.Continuation!
        started = AsyncStream { continuation = $0 }
        start = continuation
    }

    var finished: Bool { lock.withLock { didFinish } }
    var ranOffMainThread: Bool { lock.withLock { wasOffMainThread } }
    var timedOut: Bool { lock.withLock { didTimeOut } }

    func read() -> Int {
        let offMain = !Thread.isMainThread
        start.yield(())
        let timeout = release.wait(timeout: .now() + 3) == .timedOut
        lock.withLock {
            wasOffMainThread = offMain
            didTimeOut = timeout
            didFinish = true
        }
        start.finish()
        return 1
    }
}
