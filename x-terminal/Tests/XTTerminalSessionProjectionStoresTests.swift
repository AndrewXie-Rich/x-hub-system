import Foundation
import Testing
@testable import XTerminal

struct XTTerminalSessionProjectionStoresTests {
    @Test
    @MainActor
    func statusStoreTracksTerminalStatusWithoutOutputContentChurn() async {
        let session = TerminalSessionModel(root: URL(fileURLWithPath: "/tmp/xt-terminal-status-store"))
        let store = XTTerminalStatusStore()
        store.bind(to: session)

        session.isRunning = true
        session.output = "first line"
        await Task.yield()

        #expect(store.snapshot.isRunning == true)
        #expect(store.snapshot.outputIsEmpty == false)

        let stableSnapshot = store.snapshot
        session.output = "first line\nsecond streamed line"
        await Task.yield()

        #expect(store.snapshot == stableSnapshot)
    }

    @Test
    @MainActor
    func statusStoreTracksExitAndError() async {
        let session = TerminalSessionModel(root: URL(fileURLWithPath: "/tmp/xt-terminal-error-store"))
        let store = XTTerminalStatusStore()
        store.bind(to: session)

        session.isRunning = false
        session.lastExitCode = 127
        session.lastError = "command not found"
        await Task.yield()

        #expect(store.snapshot.lastExitCode == 127)
        #expect(store.snapshot.lastError == "command not found")
    }

    @Test
    @MainActor
    func outputStoreTracksOutputContent() async {
        let session = TerminalSessionModel(root: URL(fileURLWithPath: "/tmp/xt-terminal-output-store"))
        let store = XTTerminalOutputStore()
        store.bind(to: session)

        session.output = "first line"
        session.output = "first line\nsecond streamed line"
        await Task.yield()

        #expect(store.snapshot.output == "first line\nsecond streamed line")
    }

    @Test
    @MainActor
    func outputStorePublishesBoundedVisibleTailForLargeOutput() async {
        let session = TerminalSessionModel(root: URL(fileURLWithPath: "/tmp/xt-terminal-output-tail-store"))
        let store = XTTerminalOutputStore()
        store.bind(to: session)

        let largeOutput = String(
            repeating: "a",
            count: XTTerminalOutputPresentation.visibleOutputByteLimit + 64
        )
        session.output = largeOutput
        await Task.yield()

        #expect(store.snapshot.output.hasPrefix("[x-terminal] showing last"))
        #expect(store.snapshot.output.utf8.count < largeOutput.utf8.count)
        #expect(store.snapshot.output.hasSuffix(String(repeating: "a", count: 64)))
    }
}
