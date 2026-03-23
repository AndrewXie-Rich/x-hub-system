import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct XTTransientUpdateFeedbackStateTests {
    @Test
    func triggerSetsAndClearsHighlightState() async throws {
        let sleeper = ControlledSleeper()
        let state = XTTransientUpdateFeedbackState { nanoseconds in
            await sleeper.sleep(nanoseconds: nanoseconds)
        }

        state.trigger()

        #expect(state.isHighlighted)
        #expect(state.showsBadge)

        await sleeper.resume()
        try await waitUntil {
            state.isHighlighted == false && state.showsBadge == false
        }

        #expect(state.isHighlighted == false)
        #expect(state.showsBadge == false)
    }

    @Test
    func cancelResetClearsStateImmediately() {
        let sleeper = ControlledSleeper()
        let state = XTTransientUpdateFeedbackState { nanoseconds in
            await sleeper.sleep(nanoseconds: nanoseconds)
        }

        state.trigger()
        #expect(state.isHighlighted)
        #expect(state.showsBadge)

        state.cancel(resetState: true)

        #expect(state.isHighlighted == false)
        #expect(state.showsBadge == false)
    }

    private func waitUntil(
        timeoutNs: UInt64 = 1_000_000_000,
        pollIntervalNs: UInt64 = 10_000_000,
        condition: () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            if elapsed >= timeoutNs {
                Issue.record("Timed out waiting for transient update feedback state to settle")
                throw CancellationError()
            }
            try? await Task.sleep(nanoseconds: pollIntervalNs)
        }
    }
}

private actor ControlledSleeper {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasPendingResume = false

    func sleep(nanoseconds: UInt64) async {
        _ = nanoseconds
        if hasPendingResume {
            hasPendingResume = false
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        guard let continuation else {
            hasPendingResume = true
            return
        }
        self.continuation = nil
        continuation.resume()
    }
}
