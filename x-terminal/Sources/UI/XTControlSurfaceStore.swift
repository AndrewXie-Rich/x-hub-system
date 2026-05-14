import Combine
import Foundation

struct XTControlSurfaceSnapshot: Equatable {
    var roleAssignmentSummary: String
    var bridgeEnabled: Bool

    static let empty = XTControlSurfaceSnapshot(
        roleAssignmentSummary: "",
        bridgeEnabled: false
    )
}

@MainActor
final class XTControlSurfaceStore: ObservableObject {
    @Published private(set) var snapshot: XTControlSurfaceSnapshot

    init(snapshot: XTControlSurfaceSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTControlSurfaceSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
