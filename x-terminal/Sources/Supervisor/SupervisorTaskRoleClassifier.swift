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
            let resolvedRole = resolveSingleMatchedRole(only.role, input: input)
            return Output(
                role: resolvedRole,
                normalizedTaskTags: normalizedTaskTags,
                matchedSignals: matchedSignals,
                reasons: singleMatchReasons(for: only, resolvedRole: resolvedRole, input: input)
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

        if input.sideEffect.requiresSupervisorRoute {
            role = .supervisor
            reason = "no_explicit_task_tag_match; mutating_external_side_effect routes to supervisor"
        } else if input.codeExecution || input.sideEffect.requiresCoderRoute {
            role = .coder
            reason = "no_explicit_task_tag_match; execution_path routes to coder"
        } else if input.risk.requiresHubPolicy {
            role = .supervisor
            reason = "no_explicit_task_tag_match; high_risk escalates grant policy but stays on supervisor until explicit review intent"
        } else {
            role = .supervisor
            reason = "no_explicit_task_tag_match; fail_closed defaults to supervisor"
        }

        return Output(
            role: role,
            normalizedTaskTags: normalizedTaskTags,
            matchedSignals: [],
            reasons: [reason]
        )
    }

    private func resolveSingleMatchedRole(_ role: SupervisorTaskRole, input: Input) -> SupervisorTaskRole {
        guard role == .reviewer else { return role }

        if input.sideEffect.requiresSupervisorRoute {
            return .supervisor
        }
        if input.codeExecution || input.sideEffect.requiresCoderRoute {
            return .coder
        }
        return .reviewer
    }

    private func singleMatchReasons(
        for signal: MatchedRoleSignal,
        resolvedRole: SupervisorTaskRole,
        input: Input
    ) -> [String] {
        var reasons = [
            "matched_explicit_role_tags:\(signal.role.rawValue)"
        ]

        if signal.role == resolvedRole {
            reasons.append("role:\(signal.role.rawValue) selected from task_tags \(signal.taskTags.joined(separator: ","))")
            return reasons
        }

        reasons.append("explicit_review_role_clamped_to:\(resolvedRole.rawValue)")
        if input.sideEffect.requiresSupervisorRoute {
            reasons.append("reviewer_reserved_for_read_only_review_regression_gate; mutating_external_side_effect keeps the task on supervisor")
        } else if input.codeExecution || input.sideEffect.requiresCoderRoute {
            reasons.append("reviewer_reserved_for_read_only_review_regression_gate; execution_path keeps the task on coder")
        }
        return reasons
    }

    private func resolveConflict(for signals: [MatchedRoleSignal], input: Input) -> SupervisorTaskRole {
        let matchedRoles = Set(signals.map(\.role))

        if matchedRoles.contains(.supervisor), input.sideEffect.requiresSupervisorRoute {
            return .supervisor
        }
        if matchedRoles.contains(.coder), (input.codeExecution || input.sideEffect.requiresCoderRoute) {
            return .coder
        }

        let conservativeOrder: [SupervisorTaskRole] = [.supervisor, .coder, .reviewer]
        return conservativeOrder.first(where: matchedRoles.contains) ?? .supervisor
    }

    private func conflictReason(for role: SupervisorTaskRole, input: Input) -> String {
        if role == .supervisor, input.sideEffect.requiresSupervisorRoute {
            return "supervisor_preferred_due_to_mutating_external_side_effect"
        }
        if role == .coder, (input.codeExecution || input.sideEffect.requiresCoderRoute) {
            return "coder_preferred_due_to_execution_path"
        }
        if role == .supervisor, input.risk.requiresHubPolicy {
            return "high_risk_kept_on_supervisor_until_explicit_review_intent"
        }
        if role == .reviewer {
            return "reviewer_retained_only_after_non_execution_conflict_resolution"
        }
        return "conservative_role_precedence_applied"
    }
}
