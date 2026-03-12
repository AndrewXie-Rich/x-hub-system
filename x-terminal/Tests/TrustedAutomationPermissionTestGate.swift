import Foundation
import Testing
@testable import XTerminal

actor TrustedAutomationPermissionTestGate {
    static let shared = TrustedAutomationPermissionTestGate()

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

    func run(_ operation: @MainActor () async throws -> Void) async rethrows {
        await acquire()
        defer { release() }
        try await operation()
    }
}
