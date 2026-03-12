import Foundation

struct SupervisorModelRoutePolicy: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_model_route_policy.v1"

    struct RoleRoute: Codable, Equatable, Sendable {
        var role: SupervisorTaskRole
        var taskTags: [String]
        var preferredModelClasses: [SupervisorPreferredModelClass]
        var fallbackOrder: [SupervisorPreferredModelClass]
        var grantPolicy: SupervisorRouteGrantPolicy

        init(
            role: SupervisorTaskRole,
            taskTags: [String],
            preferredModelClasses: [SupervisorPreferredModelClass],
            fallbackOrder: [SupervisorPreferredModelClass],
            grantPolicy: SupervisorRouteGrantPolicy
        ) {
            self.role = role
            self.taskTags = SupervisorTaskRoleClassifier.normalizeTaskTags(taskTags)
            self.preferredModelClasses = Self.uniqueModelClasses(preferredModelClasses)
            self.fallbackOrder = Self.uniqueModelClasses(fallbackOrder)
            self.grantPolicy = grantPolicy
        }

        private static func uniqueModelClasses(_ values: [SupervisorPreferredModelClass]) -> [SupervisorPreferredModelClass] {
            var seen = Set<SupervisorPreferredModelClass>()
            return values.filter { seen.insert($0).inserted }
        }
    }

    var schemaVersion: String
    var projectID: String
    var roleRoutes: [RoleRoute]

    init(
        schemaVersion: String = SupervisorModelRoutePolicy.currentSchemaVersion,
        projectID: String,
        roleRoutes: [RoleRoute] = SupervisorModelRoutePolicy.defaultRoleRoutes
    ) {
        self.schemaVersion = schemaVersion
        self.projectID = projectID
        self.roleRoutes = roleRoutes
    }

    static func `default`(projectID: String) -> SupervisorModelRoutePolicy {
        SupervisorModelRoutePolicy(projectID: projectID)
    }

    static let defaultRoleRoutes: [RoleRoute] = [
        RoleRoute(
            role: .planner,
            taskTags: SupervisorTaskRole.planner.canonicalTaskTags,
            preferredModelClasses: [.localReasoner, .paidPlanner],
            fallbackOrder: [.localReasoner, .paidGeneral],
            grantPolicy: .lowRiskOK
        ),
        RoleRoute(
            role: .coder,
            taskTags: SupervisorTaskRole.coder.canonicalTaskTags,
            preferredModelClasses: [.paidCoder, .localCodegen],
            fallbackOrder: [.paidCoder, .localReasoner],
            grantPolicy: .projectPolicyRequired
        ),
        RoleRoute(
            role: .reviewer,
            taskTags: SupervisorTaskRole.reviewer.canonicalTaskTags,
            preferredModelClasses: [.paidReviewer, .localReasoner],
            fallbackOrder: [.localReasoner, .paidGeneral],
            grantPolicy: .projectPolicyRequired
        ),
        RoleRoute(
            role: .doc,
            taskTags: SupervisorTaskRole.doc.canonicalTaskTags,
            preferredModelClasses: [.localWriter, .paidWriter],
            fallbackOrder: [.localReasoner, .paidGeneral],
            grantPolicy: .lowRiskOK
        ),
        RoleRoute(
            role: .ops,
            taskTags: SupervisorTaskRole.ops.canonicalTaskTags,
            preferredModelClasses: [.localReasoner, .paidOps],
            fallbackOrder: [.localReasoner, .paidGeneral],
            grantPolicy: .projectPolicyRequired
        ),
    ]

    func routeDecision(
        for input: SupervisorTaskRoleClassifier.Input,
        projectConfig: AXProjectConfig? = nil,
        classifier: SupervisorTaskRoleClassifier = SupervisorTaskRoleClassifier()
    ) -> SupervisorModelRouteDecision {
        let classification = classifier.classify(input)
        let roleRoute = route(for: classification.role) ?? Self.failClosedRoute(for: classification.role)
        let projectModelHints = projectConfig?.modelOverrideCandidates(for: classification.role.preferredConfigRoles) ?? []

        var grantPolicy = roleRoute.grantPolicy
        if input.codeExecution {
            grantPolicy = .max(grantPolicy, .projectPolicyRequired)
        }
        grantPolicy = .max(grantPolicy, input.sideEffect.minimumGrantPolicy)
        if input.risk.requiresHubPolicy {
            grantPolicy = .max(grantPolicy, .hubPolicyRequired)
        }

        let matchedSignals = buildMatchedSignals(classification: classification, input: input)
        let explainability = SupervisorModelRouteExplainability(
            whyRole: buildRoleExplanation(classification: classification, input: input),
            whyPreferredModelClasses: buildModelClassExplanation(
                roleRoute: roleRoute,
                projectModelHints: projectModelHints
            ),
            whyHubStillDecides: buildHubExplanation(
                grantPolicy: grantPolicy,
                projectModelHints: projectModelHints
            ),
            matchedSignals: matchedSignals,
            classifierReasons: classification.reasons
        )

        return SupervisorModelRouteDecision(
            projectID: projectID,
            role: classification.role,
            taskTags: classification.normalizedTaskTags,
            risk: input.risk,
            sideEffect: input.sideEffect,
            codeExecution: input.codeExecution,
            preferredModelClasses: roleRoute.preferredModelClasses,
            fallbackOrder: roleRoute.fallbackOrder,
            grantPolicy: grantPolicy,
            hubPolicyRequired: grantPolicy == .hubPolicyRequired,
            matchedRouteTags: classification.matchedRouteTags,
            projectModelHints: projectModelHints,
            explainability: explainability
        )
    }

    func route(for role: SupervisorTaskRole) -> RoleRoute? {
        roleRoutes.first(where: { $0.role == role })
    }

    private static func failClosedRoute(for role: SupervisorTaskRole) -> RoleRoute {
        defaultRoleRoutes.first(where: { $0.role == role })
            ?? RoleRoute(
                role: .planner,
                taskTags: SupervisorTaskRole.planner.canonicalTaskTags,
                preferredModelClasses: [.localReasoner, .paidPlanner],
                fallbackOrder: [.localReasoner, .paidGeneral],
                grantPolicy: .lowRiskOK
            )
    }

    private func buildMatchedSignals(
        classification: SupervisorTaskRoleClassifier.Output,
        input: SupervisorTaskRoleClassifier.Input
    ) -> [String] {
        var signals: [String] = classification.matchedRouteTags.map { "task_tag:\($0)" }
        if input.codeExecution {
            signals.append("code_exec:true")
        }
        if input.sideEffect != .none {
            signals.append("side_effect:\(input.sideEffect.rawValue)")
        }
        if input.risk != .low {
            signals.append("risk:\(input.risk.rawValue)")
        }
        if signals.isEmpty {
            signals.append("fail_closed_default:\(classification.role.rawValue)")
        }
        return signals
    }

    private func buildRoleExplanation(
        classification: SupervisorTaskRoleClassifier.Output,
        input: SupervisorTaskRoleClassifier.Input
    ) -> String {
        var parts: [String] = []
        if !classification.matchedRouteTags.isEmpty {
            parts.append("Matched task_tags \(classification.matchedRouteTags.joined(separator: ", ")) to the \(classification.role.rawValue) role.")
        } else {
            parts.append("No explicit task_tag mapped cleanly, so fail-closed routing chose \(classification.role.rawValue).")
        }
        if input.codeExecution {
            parts.append("`code_exec=true` kept the decision on an execution-capable route instead of collapsing to a project-wide default model.")
        }
        if input.sideEffect != .none {
            parts.append("`side_effect=\(input.sideEffect.rawValue)` was considered during routing so operator-facing work stays distinguishable from pure drafting.")
        }
        if input.risk.requiresHubPolicy {
            parts.append("`risk=\(input.risk.rawValue)` keeps the role explainable while escalating the downstream grant policy.")
        }
        return parts.joined(separator: " ")
    }

    private func buildModelClassExplanation(
        roleRoute: RoleRoute,
        projectModelHints: [String]
    ) -> String {
        let preferred = roleRoute.preferredModelClasses.map(\.rawValue).joined(separator: ", ")
        let fallback = roleRoute.fallbackOrder.map(\.rawValue).joined(separator: ", ")
        var parts = [
            "Preferred model classes for \(roleRoute.role.rawValue) are [\(preferred)] with fallback [\(fallback)] so XT routes by role intent instead of hardcoding one project-wide model."
        ]
        if !projectModelHints.isEmpty {
            parts.append("Existing AXProjectConfig overrides contribute role-scoped model hints \(projectModelHints.joined(separator: ", ")), but they are advisory inputs, not a universal forced choice.")
        }
        return parts.joined(separator: " ")
    }

    private func buildHubExplanation(
        grantPolicy: SupervisorRouteGrantPolicy,
        projectModelHints: [String]
    ) -> String {
        var parts = [
            "XT only emits role intent plus preferred model classes; Hub must still resolve the concrete model after AI registry, grant, budget, and trust checks."
        ]
        parts.append("This decision resolved `grant_policy=\(grantPolicy.rawValue)`, so XT cannot bypass Hub gating even when project hints exist.")
        if !projectModelHints.isEmpty {
            parts.append("Project-configured model hints stay scoped to the chosen role and still pass through Hub arbitration.")
        }
        return parts.joined(separator: " ")
    }
}
