import Combine
import Foundation

struct XTGlobalHomeSkillsSnapshot: Equatable {
    var builtinGovernedSkills: [AXBuiltinGovernedSkillSummary]
    var installedSkillCount: Int
    var statusKind: AXSkillsCompatibilityStatusKind
    var statusLine: String

    static let empty = XTGlobalHomeSkillsSnapshot(
        builtinGovernedSkills: [],
        installedSkillCount: 0,
        statusKind: .unavailable,
        statusLine: "skills?"
    )

    init(
        builtinGovernedSkills: [AXBuiltinGovernedSkillSummary],
        installedSkillCount: Int,
        statusKind: AXSkillsCompatibilityStatusKind,
        statusLine: String
    ) {
        self.builtinGovernedSkills = builtinGovernedSkills
        self.installedSkillCount = installedSkillCount
        self.statusKind = statusKind
        self.statusLine = statusLine
    }

    init(skillsSnapshot: AXSkillsDoctorSnapshot) {
        self.init(
            builtinGovernedSkills: skillsSnapshot.builtinGovernedSkills,
            installedSkillCount: skillsSnapshot.installedSkillCount,
            statusKind: skillsSnapshot.statusKind,
            statusLine: skillsSnapshot.statusLine
        )
    }

    var builtinGovernedSkillCount: Int {
        builtinGovernedSkills.count
    }
}

struct XTGlobalHomeSnapshot: Equatable {
    var latestResumeReminder: AXResumeReminderProjectPresentation?
    var preferredResumeProject: AXResumeReminderProjectPresentation?
    var remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot?
    var skills: XTGlobalHomeSkillsSnapshot

    static let empty = XTGlobalHomeSnapshot(
        latestResumeReminder: nil,
        preferredResumeProject: nil,
        remotePaidAccessSnapshot: nil,
        skills: .empty
    )
}

@MainActor
final class XTGlobalHomeStore: ObservableObject {
    @Published private(set) var snapshot: XTGlobalHomeSnapshot

    init(snapshot: XTGlobalHomeSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTGlobalHomeSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
