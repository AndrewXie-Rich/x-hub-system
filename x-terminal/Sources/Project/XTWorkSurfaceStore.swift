import Combine
import Foundation

struct XTWorkSurfaceSnapshot: Equatable {
    var selectedProjectId: String?
    var projectContext: AXProjectContext?
    var memory: AXMemory?
    var projectConfig: AXProjectConfig?
    var isMultiProjectViewEnabled: Bool
    var selectedPane: AXProjectPane

    static let empty = XTWorkSurfaceSnapshot(
        selectedProjectId: nil,
        projectContext: nil,
        memory: nil,
        projectConfig: nil,
        isMultiProjectViewEnabled: false,
        selectedPane: .chat
    )

    var isGlobalHomeSelected: Bool {
        selectedProjectId == AXProjectRegistry.globalHomeId
    }

    var hasProjectContext: Bool {
        projectContext != nil
    }
}

@MainActor
final class XTWorkSurfaceStore: ObservableObject {
    @Published private(set) var snapshot: XTWorkSurfaceSnapshot

    init(snapshot: XTWorkSurfaceSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTWorkSurfaceSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
