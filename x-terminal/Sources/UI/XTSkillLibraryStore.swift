import Combine
import Foundation

struct XTSkillLibrarySnapshot: Equatable {
    var skillsSnapshot: AXSkillsDoctorSnapshot
    var lastImportedAgentSkillStatusLine: String
    var agentSkillImportBusy: Bool
    var canReviewLastImportedAgentSkill: Bool
    var canEnableLastImportedAgentSkill: Bool
    var skillGovernanceActionStatusLine: String
    var selectedProjectId: String?
    var selectedProjectName: String?

    static let empty = XTSkillLibrarySnapshot(
        skillsSnapshot: .empty,
        lastImportedAgentSkillStatusLine: "",
        agentSkillImportBusy: false,
        canReviewLastImportedAgentSkill: false,
        canEnableLastImportedAgentSkill: false,
        skillGovernanceActionStatusLine: "",
        selectedProjectId: nil,
        selectedProjectName: nil
    )
}

@MainActor
final class XTSkillLibraryStore: ObservableObject {
    @Published private(set) var snapshot: XTSkillLibrarySnapshot

    init(snapshot: XTSkillLibrarySnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTSkillLibrarySnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
