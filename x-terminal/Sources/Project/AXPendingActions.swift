import Dispatch
import Foundation

// Persisted per-project pending actions so Home/Project views can recover approvals across restart.
// MVP focuses on tool approval (write_file/run_command/git_apply). Network approvals stay in Hub Inbox.

enum AXPendingActionType: String, Codable {
    case toolApproval = "tool_approval"
}

struct AXPendingToolFlowState: Codable, Equatable {
    var step: Int
    var toolResults: [ToolResult]

    var dirtySinceVerify: Bool
    var verifyRunIndex: Int
    var repairAttemptsUsed: Int
    var deferredFinal: String?
    var finalizeOnly: Bool
    var formatRetryUsed: Bool
    var executionRetryUsed: Bool = false

    enum CodingKeys: String, CodingKey {
        case step
        case toolResults
        case dirtySinceVerify
        case verifyRunIndex
        case repairAttemptsUsed
        case deferredFinal
        case finalizeOnly
        case formatRetryUsed
        case executionRetryUsed
    }

    init(
        step: Int,
        toolResults: [ToolResult],
        dirtySinceVerify: Bool,
        verifyRunIndex: Int,
        repairAttemptsUsed: Int,
        deferredFinal: String?,
        finalizeOnly: Bool,
        formatRetryUsed: Bool,
        executionRetryUsed: Bool = false
    ) {
        self.step = step
        self.toolResults = toolResults
        self.dirtySinceVerify = dirtySinceVerify
        self.verifyRunIndex = verifyRunIndex
        self.repairAttemptsUsed = repairAttemptsUsed
        self.deferredFinal = deferredFinal
        self.finalizeOnly = finalizeOnly
        self.formatRetryUsed = formatRetryUsed
        self.executionRetryUsed = executionRetryUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = try container.decode(Int.self, forKey: .step)
        toolResults = try container.decode([ToolResult].self, forKey: .toolResults)
        dirtySinceVerify = try container.decode(Bool.self, forKey: .dirtySinceVerify)
        verifyRunIndex = try container.decode(Int.self, forKey: .verifyRunIndex)
        repairAttemptsUsed = try container.decode(Int.self, forKey: .repairAttemptsUsed)
        deferredFinal = try container.decodeIfPresent(String.self, forKey: .deferredFinal)
        finalizeOnly = try container.decode(Bool.self, forKey: .finalizeOnly)
        formatRetryUsed = try container.decode(Bool.self, forKey: .formatRetryUsed)
        executionRetryUsed = try container.decodeIfPresent(Bool.self, forKey: .executionRetryUsed) ?? false
    }
}

struct AXPendingAction: Identifiable, Codable, Equatable {
    var id: String
    var type: AXPendingActionType
    var createdAt: Double
    var status: String // "pending" | "cleared"

    // Human / debug fields.
    var projectId: String
    var projectName: String
    var reason: String?
    var preview: String?

    // Tool-approval payload (for type == toolApproval).
    var userText: String?
    var assistantStub: String?
    var toolCalls: [ToolCall]?
    var flow: AXPendingToolFlowState?
}

struct AXPendingActionsFile: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var updatedAt: Double
    var actions: [AXPendingAction]

    static func empty() -> AXPendingActionsFile {
        AXPendingActionsFile(schemaVersion: currentSchemaVersion, updatedAt: Date().timeIntervalSince1970, actions: [])
    }
}

enum AXPendingActionsStore {
    private static let queue = DispatchQueue(label: "xterminal.pending_actions_store")

    static func url(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent("pending_actions.json")
    }

    static func load(for ctx: AXProjectContext) -> AXPendingActionsFile {
        queue.sync {
            loadUnlocked(for: ctx)
        }
    }

    static func pendingToolApproval(for ctx: AXProjectContext) -> AXPendingAction? {
        queue.sync {
            let file = loadUnlocked(for: ctx)
            return file.actions.first(where: { $0.type == .toolApproval && $0.status == "pending" })
        }
    }

    static func saveToolApproval(_ action: AXPendingAction, for ctx: AXProjectContext) {
        queue.sync {
            var file = loadUnlocked(for: ctx)
            // Replace any existing tool approval.
            file.actions.removeAll(where: { $0.type == .toolApproval })
            file.actions.append(action)
            file.updatedAt = Date().timeIntervalSince1970
            saveUnlocked(file, for: ctx)
        }
    }

    static func clearToolApproval(for ctx: AXProjectContext) {
        queue.sync {
            var file = loadUnlocked(for: ctx)
            let before = file.actions.count
            file.actions.removeAll(where: { $0.type == .toolApproval })
            if file.actions.count == before {
                return
            }
            file.updatedAt = Date().timeIntervalSince1970
            saveUnlocked(file, for: ctx)
        }
    }

    static func clearAll(for ctx: AXProjectContext) {
        queue.sync {
            saveUnlocked(.empty(), for: ctx)
        }
    }

    // MARK: - IO

    private static func loadUnlocked(for ctx: AXProjectContext) -> AXPendingActionsFile {
        let u = url(for: ctx)
        guard FileManager.default.fileExists(atPath: u.path) else { return .empty() }
        guard let data = try? Data(contentsOf: u) else { return .empty() }
        return (try? JSONDecoder().decode(AXPendingActionsFile.self, from: data)) ?? .empty()
    }

    private static func saveUnlocked(_ file: AXPendingActionsFile, for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        var cur = file
        cur.schemaVersion = AXPendingActionsFile.currentSchemaVersion
        cur.updatedAt = Date().timeIntervalSince1970

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(cur) else { return }
        try? data.write(to: url(for: ctx), options: .atomic)
    }
}
