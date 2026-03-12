import Foundation

struct SupervisorTaskRoleClassifier {
    struct Input: Equatable, Sendable {
        var taskTags: [String]
        var risk: SupervisorTaskRisk
        var sideEffect: SupervisorTaskSideEffect
        var codeExecution: Bool

        init(
            taskTags: [String],
            risk: SupervisorTaskRisk = .low,
            sideEffect: SupervisorTaskSideEffect = .none,
            codeExecution: Bool = false
        ) {
            self.taskTags = taskTags
            self.risk = risk
            self.sideEffect = sideEffect
            self.codeExecution = codeExecution
        }
    }

    struct MatchedRoleSignal: Equatable, Sendable {
        var role: SupervisorTaskRole
        var taskTags: [String]
    }

    struct Output: Equatable, Sendable {
        var role: SupervisorTaskRole
        var normalizedTaskTags: [String]
        var matchedSignals: [MatchedRoleSignal]
        var reasons: [String]

        var matchedRouteTags: [String] {
            matchedSignals.first(where: { $0.role == role })?.taskTags ?? []
        }

        var matchedRoles: [SupervisorTaskRole] {
            matchedSignals.map(\.role)
        }
    }

    func classify(_ input: Input) -> Output {
        let normalizedTaskTags = Self.normalizeTaskTags(input.taskTags)
        let matchedSignals = SupervisorTaskRole.allCases.compactMap { role -> MatchedRoleSignal? in
            let matches = role.canonicalTaskTags.filter { normalizedTaskTags.contains($0) }
            guard !matches.isEmpty else { return nil }
            return MatchedRoleSignal(role: role, taskTags: matches)
        }

        if matchedSignals.isEmpty {
            return fallbackOutput(for: input, normalizedTaskTags: normalizedTaskTags)
        }

        if matchedSignals.count == 1, let only = matchedSignals.first {
            return Output(
                role: only.role,
                normalizedTaskTags: normalizedTaskTags,
                matchedSignals: matchedSignals,
                reasons: [
                    "matched_explicit_role_tags:\(only.role.rawValue)",
                    "role:\(only.role.rawValue) selected from task_tags \(only.taskTags.joined(separator: ","))"
                ]
            )
        }

        let resolvedRole = resolveConflict(for: matchedSignals, input: input)
        let candidateLabels = matchedSignals.map(\.role.rawValue).joined(separator: ",")
        return Output(
            role: resolvedRole,
            normalizedTaskTags: normalizedTaskTags,
            matchedSignals: matchedSignals,
            reasons: [
                "multiple_role_matches:\(candidateLabels)",
                "conflict_resolved_to:\(resolvedRole.rawValue)",
                conflictReason(for: resolvedRole, input: input)
            ]
        )
    }

    static func normalizeTaskTags(_ taskTags: [String]) -> [String] {
        var seen = Set<String>()
        return taskTags.compactMap { raw in
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return nil }
            guard seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private func fallbackOutput(for input: Input, normalizedTaskTags: [String]) -> Output {
        let role: SupervisorTaskRole
        let reason: String

        if input.sideEffect.hasOperationalSideEffect {
            role = .ops
            reason = "no_explicit_task_tag_match; operational_side_effect routes to ops"
        } else if input.codeExecution {
            role = .coder
            reason = "no_explicit_task_tag_match; code_execution routes to coder"
        } else if input.risk.requiresHubPolicy {
            role = .reviewer
            reason = "no_explicit_task_tag_match; high_risk routes to reviewer"
        } else {
            role = .planner
            reason = "no_explicit_task_tag_match; fail_closed defaults to planner"
        }

        return Output(
            role: role,
            normalizedTaskTags: normalizedTaskTags,
            matchedSignals: [],
            reasons: [reason]
        )
    }

    private func resolveConflict(for signals: [MatchedRoleSignal], input: Input) -> SupervisorTaskRole {
        let matchedRoles = Set(signals.map(\.role))

        if matchedRoles.contains(.ops), input.sideEffect.hasOperationalSideEffect {
            return .ops
        }
        if matchedRoles.contains(.reviewer), input.risk.requiresHubPolicy {
            return .reviewer
        }
        if matchedRoles.contains(.coder), input.codeExecution {
            return .coder
        }

        let conservativeOrder: [SupervisorTaskRole] = [.ops, .reviewer, .coder, .doc, .planner]
        return conservativeOrder.first(where: matchedRoles.contains) ?? .planner
    }

    private func conflictReason(for role: SupervisorTaskRole, input: Input) -> String {
        if role == .ops, input.sideEffect.hasOperationalSideEffect {
            return "ops_preferred_due_to_side_effect"
        }
        if role == .reviewer, input.risk.requiresHubPolicy {
            return "reviewer_preferred_due_to_high_risk"
        }
        if role == .coder, input.codeExecution {
            return "coder_preferred_due_to_code_execution"
        }
        return "conservative_role_precedence_applied"
    }
}
