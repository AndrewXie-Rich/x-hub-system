import Foundation

extension SupervisorManager {
    func supervisorActionURL(
        projectId: String?,
        focusTarget: XTDeepLinkFocusTarget? = nil,
        requestId: String? = nil,
        grantRequestId: String? = nil,
        capability: String? = nil
    ) -> String? {
        let normalizedRequestId = requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let grantId = grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let capabilityToken = capability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedFocusTarget: XTDeepLinkFocusTarget? = {
            if let focusTarget {
                return focusTarget
            }
            if !grantId.isEmpty || !capabilityToken.isEmpty {
                return .grant
            }
            if !normalizedRequestId.isEmpty {
                return .approval
            }
            return nil
        }()
        if let raw = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return XTDeepLinkURLBuilder.projectURL(
                projectId: raw,
                pane: .chat,
                openTarget: .supervisor,
                focusTarget: resolvedFocusTarget,
                requestId: normalizedRequestId.isEmpty ? nil : normalizedRequestId,
                grantRequestId: grantId.isEmpty ? nil : grantId,
                grantCapability: capabilityToken.isEmpty ? nil : capabilityToken
            )?.absoluteString
        }
        if resolvedFocusTarget != nil {
            return XTDeepLinkURLBuilder.supervisorURL(
                focusTarget: resolvedFocusTarget,
                requestId: normalizedRequestId.isEmpty ? nil : normalizedRequestId,
                grantRequestId: grantId.isEmpty ? nil : grantId,
                grantCapability: capabilityToken.isEmpty ? nil : capabilityToken
            )?.absoluteString
        }
        return XTDeepLinkURLBuilder.supervisorURL()?.absoluteString
    }

    func resumeProjectActionURL(
        projectId: String?,
        openTarget: XTDeepLinkOpenTarget? = nil
    ) -> String? {
        guard let raw = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return XTDeepLinkURLBuilder.supervisorURL()?.absoluteString
        }
        return XTDeepLinkURLBuilder.projectURL(
            projectId: raw,
            pane: .chat,
            openTarget: openTarget,
            resumeRequested: true
        )?.absoluteString
    }

    func toolApprovalActionURL(
        projectId: String?,
        requestId: String? = nil
    ) -> String? {
        guard let raw = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let normalizedRequestId = requestId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return XTDeepLinkURLBuilder.projectURL(
            projectId: raw,
            pane: .chat,
            focusTarget: .toolApproval,
            requestId: normalizedRequestId?.isEmpty == false ? normalizedRequestId : nil
        )?.absoluteString
    }

    func routeDiagnoseActionURL(
        projectId: String?
    ) -> String? {
        guard let raw = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return XTDeepLinkURLBuilder.projectURL(
            projectId: raw,
            pane: .chat,
            focusTarget: .routeDiagnose
        )?.absoluteString
    }

    func projectGovernanceActionURL(
        projectId: String?,
        destination: XTProjectGovernanceDestination
    ) -> String? {
        guard let raw = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return XTDeepLinkURLBuilder.projectURL(
            projectId: raw,
            pane: .chat,
            governanceDestination: destination
        )?.absoluteString
    }

    func governanceRepairHint(
        for record: SupervisorSkillCallRecord
    ) -> XTGuardrailRepairHint? {
        switch record.status {
        case .blocked, .failed:
            return XTGuardrailMessagePresentation.repairHint(
                denyCode: record.denyCode,
                policySource: record.policySource ?? "",
                policyReason: record.policyReason ?? ""
            )
        case .queued, .running, .awaitingAuthorization, .completed, .canceled:
            return nil
        }
    }

    func supervisorSkillActivityActionURL(
        projectId: String,
        record: SupervisorSkillCallRecord,
        ctx: AXProjectContext
    ) -> String? {
        let capability = record.requiredCapability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let grantRequestId = record.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if record.status == .awaitingAuthorization {
            if !capability.isEmpty || !grantRequestId.isEmpty {
                return supervisorActionURL(
                    projectId: projectId,
                    grantRequestId: grantRequestId.isEmpty ? nil : grantRequestId,
                    capability: capability.isEmpty ? nil : capability
                )
            }
            return supervisorActionURL(
                projectId: projectId,
                requestId: record.requestId
            )
        }
        if supervisorShouldRouteToUIReview(
            requestId: record.requestId,
            ctx: ctx
        ) {
            return projectGovernanceActionURL(
                projectId: projectId,
                destination: .uiReview
            )
        }
        if let repairHint = governanceRepairHint(for: record) {
            return projectGovernanceActionURL(
                projectId: projectId,
                destination: repairHint.destination
            )
        }
        return resumeProjectActionURL(projectId: projectId)
    }
}
