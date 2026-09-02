import Foundation

extension SupervisorManager {
    func supervisorIncidentNotificationDedupeKey(
        _ incident: SupervisorLaneIncident
    ) -> String {
        "x_terminal_supervisor_incident_\(incident.id)"
    }

    func shouldMirrorSupervisorIncidentNotificationToHub(
        _ incident: SupervisorLaneIncident
    ) -> Bool {
        let suppressedCodes = Set([
            LaneBlockedReason.grantPending.rawValue,
            LaneBlockedReason.awaitingInstruction.rawValue,
        ])
        let candidates = [
            incident.incidentCode,
            incident.denyCode,
        ].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return !candidates.contains { suppressedCodes.contains($0) }
    }

    func laneHealthStatusLine(summary: LaneHealthSummary) -> String {
        if summary.total == 0 {
            return "泳道健康：空闲"
        }
        return "泳道健康：总计 \(summary.total) · 运行中 \(summary.running) · 阻塞 \(summary.blocked) · 停滞 \(summary.stalled) · 失败 \(summary.failed)"
    }

    func frontstageLaneHotspotSummary(
        for lane: SupervisorLaneHealthLaneState
    ) -> String {
        let laneLabel = frontstageLaneLabel(for: lane)
        let raw = SplitProposalPanelPresentation.hotspotSummary(for: lane)
            .replacingOccurrences(of: lane.laneID, with: laneLabel)
        let stripped = raw
            .replacingOccurrences(of: #"（[a-z0-9_]+）"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? laneLabel : stripped
    }

    func frontstageLaneLabel(
        for lane: SupervisorLaneHealthLaneState
    ) -> String {
        if let projectID = lane.projectID?.uuidString,
           let project = resolvedSupervisorProjectEntry(projectId: projectID) {
            let projectName = project.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !projectName.isEmpty {
                return projectName
            }
        }

        let profile = lane.agentProfile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !profile.isEmpty {
            let cleaned = profile
                .replacingOccurrences(of: #"[_\-]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return "当前泳道"
    }

    func maybePushLaneHealthNotification(_ snapshot: SupervisorLaneHealthSnapshot) {
        let summary = snapshot.summary
        guard summary.failed > 0 || summary.stalled > 0 else { return }

        let rawHotspots = snapshot.lanes
            .filter { $0.status == .failed || $0.status == .stalled }
            .prefix(3)
            .map { lane in
                "\(lane.laneID):\(lane.status.rawValue)/\(lane.blockedReason?.rawValue ?? "none")"
            }
            .joined(separator: ";")
        let hotspotLines = snapshot.lanes
            .filter { $0.status == .failed || $0.status == .stalled }
            .prefix(3)
            .map { frontstageLaneHotspotSummary(for: $0) }
            .joined(separator: "\n")

        let body = """
\(laneHealthStatusLine(summary: summary))
异常泳道：
\(hotspotLines.isEmpty ? "（无）" : hotspotLines)
"""
        let dedupeKey = "x_terminal_supervisor_lane_health_\(summary.failed)_\(summary.stalled)_\(rawHotspots)"
        let actionURL = supervisorActionURL(projectId: nil)
        guard shouldMirrorNotificationToHub(actionURL: actionURL) else {
            HubIPCClient.removeNotification(dedupeKey: dedupeKey)
            return
        }

        HubIPCClient.pushNotification(
            source: "X-Terminal",
            title: "🫀 泳道健康巡检告警",
            body: body,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            unread: true
        )
    }
}
