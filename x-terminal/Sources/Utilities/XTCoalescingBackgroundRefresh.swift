import Foundation

/// Runs at most one expensive refresh at a time. Requests received while it is
/// running replace the pending request, and obsolete results are never published.
@MainActor
final class XTCoalescingBackgroundRefresh<Value: Sendable> {
    private struct Request {
        var revision: UInt64
        var prepare: @MainActor () -> (@Sendable () -> Value)
        var publish: @MainActor (Value) -> Void
    }

    private let delayNanoseconds: UInt64
    private var revision: UInt64 = 0
    private var pending: Request?
    private var task: Task<Void, Never>?

    init(delayNanoseconds: UInt64 = 150_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func request(
        prepare: @escaping @MainActor () -> (@Sendable () -> Value),
        publish: @escaping @MainActor (Value) -> Void
    ) {
        revision &+= 1
        pending = Request(revision: revision, prepare: prepare, publish: publish)
        guard task == nil else { return }

        let delay = delayNanoseconds
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard let request = self?.takePending() else {
                    self?.task = nil
                    return
                }
                // Capture UI state only after coalescing; all I/O and computation
                // in the returned closure run outside the main actor.
                let work = request.prepare()
                let value = await Task.detached(priority: .utility, operation: work).value
                guard !Task.isCancelled else { return }
                if self?.revision == request.revision {
                    request.publish(value)
                }
            }
        }
    }

    /// Also fences off an already running refresh, without starting overlapping
    /// work when the blocking operation cannot be cancelled cooperatively.
    func invalidate() {
        revision &+= 1
        pending = nil
    }

    func waitForIdle() async {
        await task?.value
    }

    private func takePending() -> Request? {
        defer { pending = nil }
        return pending
    }

    deinit {
        task?.cancel()
    }
}
