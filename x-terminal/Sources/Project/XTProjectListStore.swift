import Combine
import Foundation

struct XTProjectListSnapshot: Equatable {
    var selectedProjectId: String?
    var projects: [AXProjectEntry]
    var selectedProjectName: String?

    static let empty = XTProjectListSnapshot(
        selectedProjectId: nil,
        projects: [],
        selectedProjectName: nil
    )

    var projectCount: Int {
        projects.count
    }
}

@MainActor
final class XTProjectListStore: ObservableObject {
    @Published private(set) var snapshot: XTProjectListSnapshot

    init(snapshot: XTProjectListSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTProjectListSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
