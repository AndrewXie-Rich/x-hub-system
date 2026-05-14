import Combine
import Foundation

struct XTTerminalStatusSnapshot: Equatable {
    var isRunning: Bool
    var lastExitCode: Int32?
    var lastError: String?
    var outputIsEmpty: Bool

    static let empty = XTTerminalStatusSnapshot(
        isRunning: false,
        lastExitCode: nil,
        lastError: nil,
        outputIsEmpty: true
    )
}

@MainActor
final class XTTerminalStatusStore: ObservableObject {
    @Published private(set) var snapshot: XTTerminalStatusSnapshot

    private weak var boundSession: TerminalSessionModel?
    private var cancellables: Set<AnyCancellable> = []

    init(snapshot: XTTerminalStatusSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func bind(to session: TerminalSessionModel) {
        if boundSession === session {
            update(from: session)
            return
        }

        cancellables.removeAll()
        boundSession = session
        update(from: session)

        session.$isRunning
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
        session.$lastExitCode
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
        session.$output
            .map(\.isEmpty)
            .removeDuplicates()
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
    }

    func isBound(to session: TerminalSessionModel) -> Bool {
        boundSession === session
    }

    private func update(from session: TerminalSessionModel) {
        let nextSnapshot = XTTerminalStatusSnapshot(
            isRunning: session.isRunning,
            lastExitCode: session.lastExitCode,
            lastError: session.lastError,
            outputIsEmpty: session.output.isEmpty
        )
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(from session: TerminalSessionModel) {
        Task { @MainActor [weak self, weak session] in
            guard let session else { return }
            self?.update(from: session)
        }
    }
}

struct XTTerminalOutputSnapshot: Equatable {
    var output: String

    static let empty = XTTerminalOutputSnapshot(output: "")
}

enum XTTerminalOutputPresentation {
    static let visibleOutputByteLimit = 80_000

    static func visibleOutput(from output: String) -> String {
        let bytes = output.utf8
        guard bytes.count > visibleOutputByteLimit else { return output }
        return "[x-terminal] showing last \(visibleOutputByteLimit) bytes\n"
            + String(decoding: bytes.suffix(visibleOutputByteLimit), as: UTF8.self)
    }
}

@MainActor
final class XTTerminalOutputStore: ObservableObject {
    @Published private(set) var snapshot: XTTerminalOutputSnapshot

    private weak var boundSession: TerminalSessionModel?
    private var cancellables: Set<AnyCancellable> = []

    init(snapshot: XTTerminalOutputSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func bind(to session: TerminalSessionModel) {
        if boundSession === session {
            update(from: session)
            return
        }

        cancellables.removeAll()
        boundSession = session
        update(from: session)

        session.$output
            .sink { [weak self, weak session] _ in
                guard let session else { return }
                self?.scheduleUpdate(from: session)
            }
            .store(in: &cancellables)
    }

    func isBound(to session: TerminalSessionModel) -> Bool {
        boundSession === session
    }

    private func update(from session: TerminalSessionModel) {
        let nextSnapshot = XTTerminalOutputSnapshot(
            output: XTTerminalOutputPresentation.visibleOutput(from: session.output)
        )
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    private func scheduleUpdate(from session: TerminalSessionModel) {
        Task { @MainActor [weak self, weak session] in
            guard let session else { return }
            self?.update(from: session)
        }
    }
}
