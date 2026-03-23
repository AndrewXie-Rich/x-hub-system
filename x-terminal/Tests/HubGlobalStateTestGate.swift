import Foundation

actor HubGlobalStateTestGate {
    static let shared = HubGlobalStateTestGate()

    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !locked {
            locked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            locked = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }

    func run<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    func runOnMainActor<T>(_ operation: @MainActor @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
}
