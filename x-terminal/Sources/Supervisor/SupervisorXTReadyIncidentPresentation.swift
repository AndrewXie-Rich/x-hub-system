import Foundation

struct SupervisorXTReadyIncidentLinePresentation: Equatable {
    var text: String
    var tone: SupervisorHeaderControlTone
    var isSelectable: Bool = false
    var lineLimit: Int? = nil
}

struct SupervisorXTReadyIncidentPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var summaryLine: String
    var statusLine: SupervisorXTReadyIncidentLinePresentation
    var strictE2ELine: SupervisorXTReadyIncidentLinePresentation
    var missingIncidentLine: SupervisorXTReadyIncidentLinePresentation
    var strictIssueLine: SupervisorXTReadyIncidentLinePresentation
    var connectivityIncidentHistoryLine: SupervisorXTReadyIncidentLinePresentation?
    var connectivityRepairLine: SupervisorXTReadyIncidentLinePresentation?
    var connectivityRepairDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var pairedRouteStatusLine: SupervisorXTReadyIncidentLinePresentation?
    var pairedRouteLine: SupervisorXTReadyIncidentLinePresentation?
    var pairedRemoteEntryLine: SupervisorXTReadyIncidentLinePresentation?
    var freshPairReconnectSmokeLine: SupervisorXTReadyIncidentLinePresentation?
    var freshPairReconnectSmokeDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var firstPairCompletionProofLine: SupervisorXTReadyIncidentLinePresentation?
    var firstPairCompletionProofDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeIssueLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeLoadConfigLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeNextLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeInstallHintLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeRecommendedActionLine: SupervisorXTReadyIncidentLinePresentation?
    var supervisorVoiceLine: SupervisorXTReadyIncidentLinePresentation?
    var supervisorVoiceFreshnessLine: SupervisorXTReadyIncidentLinePresentation?
    var supervisorVoiceDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var supervisorVoiceNextLine: SupervisorXTReadyIncidentLinePresentation?
    var supervisorVoiceActionURL: String?
    var supervisorVoiceActionLabel: String?
    var memoryAssemblyLine: SupervisorXTReadyIncidentLinePresentation
    var memoryAssemblyIssueLine: SupervisorXTReadyIncidentLinePresentation?
    var memoryAssemblyDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var canonicalRetryStatusLine: SupervisorXTReadyIncidentLinePresentation?
    var canonicalRetryMetaLine: SupervisorXTReadyIncidentLinePresentation?
    var canonicalRetryDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var reportPath: String
    var reportLine: SupervisorXTReadyIncidentLinePresentation
    var canOpenReport: Bool
}

enum SupervisorXTReadyIncidentPresentationMapper {
    static func map(
        snapshot: SupervisorManager.XTReadyIncidentExportSnapshot,
        canonicalRetryFeedback: SupervisorManager.CanonicalMemoryRetryFeedback? = nil
    ) -> SupervisorXTReadyIncidentPresentation {
        let iconTone = statusTone(snapshot)
        let hubRuntimeDiagnosis = snapshot.hubRuntimeDiagnosis
        let strictIssueText: String
        if snapshot.strictE2EIssues.isEmpty {
            strictIssueText = "严格端到端问题：无"
        } else {
            strictIssueText = "严格端到端问题：\(snapshot.strictE2EIssues.prefix(4).joined(separator: ","))"
        }
        let memoryIssueText = snapshot.memoryAssemblyIssues
            .prefix(3)
            .joined(separator: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let memoryDetailText = snapshot.memoryAssemblyDetailLines
            .prefix(2)
            .joined(separator: " || ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReportPath = snapshot.reportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let freshPairReconnectSmoke = snapshot.freshPairReconnectSmokeSnapshot
        let freshPairReconnectSmokeTone = freshPairReconnectSmokeTone(freshPairReconnectSmoke)
        let freshPairReconnectSmokeDetailText = {
            guard let freshPairReconnectSmoke else { return "" }
            let reason = freshPairReconnectSmoke.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary = freshPairReconnectSmoke.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty, !summary.isEmpty, reason != summary {
                return "\(summary) || reason=\(reason)"
            }
            if !summary.isEmpty {
                return summary
            }
            return reason
        }()
        let hubRuntimeLoadConfigText = hubRuntimeDiagnosis?.loadConfigSummaryLine
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hubRuntimeDetailText = hubRuntimeDiagnosis?.renderableDetailLines(limit: 2)
            .joined(separator: " || ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let supervisorVoiceDiagnosis = snapshot.supervisorVoiceDiagnosis
        let supervisorVoiceFreshnessText = supervisorVoiceDiagnosis?.freshnessSummary().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let supervisorVoiceDetailText = {
            let trimmedMessage = supervisorVoiceDiagnosis?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedMessage.isEmpty {
                return trimmedMessage
            }
            return supervisorVoiceDiagnosis?.renderableDetailLines(limit: 2)
                .joined(separator: " || ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }()
        let supervisorVoiceActionURL = fallbackSupervisorVoiceActionURL(supervisorVoiceDiagnosis)
        let hubRuntimeText = hubRuntimeDiagnosis.map { diagnosis in
            let suffix = diagnosis.failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.isEmpty {
                return "Hub 运行时：\(localizedHubOverallState(diagnosis.overallState))"
            }
            return "Hub 运行时：\(localizedHubOverallState(diagnosis.overallState)) · \(suffix)"
        }
        let hubRuntimeTone = hubRuntimeTone(hubRuntimeDiagnosis)
        let supervisorVoiceTone = supervisorVoiceTone(supervisorVoiceDiagnosis)
        let connectivityHistoryText = localizedConnectivityIncidentHistory(snapshot.connectivityIncidentHistory)
        let connectivityHistoryTone = connectivityIncidentHistoryTone(snapshot.connectivityIncidentHistory)
        let connectivityRepairText = localizedConnectivityRepairStatus(snapshot.connectivityRepairLedger)
        let connectivityRepairDetailText = localizedConnectivityRepairDetail(snapshot.connectivityRepairLedger)
        let connectivityRepairTone = connectivityRepairTone(snapshot.connectivityRepairLedger)
        let pairedRouteStatusText = snapshot.pairedRouteSetSnapshot?.summaryLine
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pairedRouteStatusTone = pairedRouteStatusTone(snapshot.pairedRouteSetSnapshot)
        let pairedRouteText = localizedPairedRouteSummary(
            pairedRouteSetSnapshot: snapshot.pairedRouteSetSnapshot,
            routeSnapshot: snapshot.pairedRouteSnapshot
        )
        let pairedRouteLineTone = pairedRouteLineTone(
            pairedRouteSetSnapshot: snapshot.pairedRouteSetSnapshot,
            routeSnapshot: snapshot.pairedRouteSnapshot
        )
        let pairedRemoteEntryText = snapshot.pairedRouteSnapshot?.remoteEntrySummaryLine
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pairedRemoteEntryTone = pairedRemoteEntryTone(snapshot.pairedRouteSnapshot)
        let firstPairCompletionProof = snapshot.firstPairCompletionProofSnapshot
        let firstPairCompletionProofTone = firstPairCompletionProofTone(firstPairCompletionProof)
        let firstPairCompletionProofDetailText = {
            guard let firstPairCompletionProof else { return "" }
            var parts = [firstPairCompletionProof.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)]
            if let summary = firstPairCompletionProof.remoteShadowSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty,
               !parts.contains(summary) {
                parts.append(summary)
            }
            if let route = firstPairCompletionProof.remoteShadowRoute?.trimmingCharacters(in: .whitespacesAndNewlines),
               !route.isEmpty {
                parts.append("route=\(localizedHubRemoteRoute(route))")
            }
            if let source = firstPairCompletionProof.remoteShadowSmokeSource?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                parts.append("source=\(localizedFirstPairRemoteShadowSmokeSource(source))")
            }
            if let reason = firstPairCompletionProof.remoteShadowReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reason.isEmpty {
                parts.append("reason=\(reason)")
            }
            return parts
                .filter { !$0.isEmpty }
                .joined(separator: " || ")
        }()

        return SupervisorXTReadyIncidentPresentation(
            iconName: "waveform.path.ecg.rectangle",
            iconTone: iconTone,
            title: "XT 就绪诊断导出",
            summaryLine: "必需事件=\(snapshot.requiredIncidentEventCount) · 已记录=\(snapshot.ledgerIncidentCount)",
            statusLine: SupervisorXTReadyIncidentLinePresentation(
                text: "状态：\(localizedExportStatus(snapshot.status))",
                tone: iconTone
            ),
            strictE2ELine: SupervisorXTReadyIncidentLinePresentation(
                text: "严格端到端：\(snapshot.strictE2EReady ? "已通过" : "未通过")",
                tone: snapshot.strictE2EReady ? .success : .danger
            ),
            missingIncidentLine: SupervisorXTReadyIncidentLinePresentation(
                text: snapshot.missingIncidentCodes.isEmpty
                    ? "缺少事件编码：无"
                    : "缺少事件编码：\(snapshot.missingIncidentCodes.joined(separator: ","))",
                tone: snapshot.missingIncidentCodes.isEmpty ? .neutral : .warning
            ),
            strictIssueLine: SupervisorXTReadyIncidentLinePresentation(
                text: strictIssueText,
                tone: snapshot.strictE2EIssues.isEmpty ? .neutral : .warning
            ),
            connectivityIncidentHistoryLine: connectivityHistoryText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "最近连接轨迹：\(connectivityHistoryText)",
                    tone: connectivityHistoryTone,
                    isSelectable: true,
                    lineLimit: 3
                ),
            connectivityRepairLine: connectivityRepairText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "连接修复：\(connectivityRepairText)",
                    tone: connectivityRepairTone,
                    lineLimit: 3
                ),
            connectivityRepairDetailLine: connectivityRepairDetailText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "连接修复轨迹：\(connectivityRepairDetailText)",
                    tone: connectivityRepairTone == .danger ? .warning : connectivityRepairTone,
                    isSelectable: true,
                    lineLimit: 3
                ),
            pairedRouteStatusLine: pairedRouteStatusText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "已配对路径：\(pairedRouteStatusText)",
                    tone: pairedRouteStatusTone,
                    lineLimit: 2
                ),
            pairedRouteLine: pairedRouteText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "当前连接路径：\(pairedRouteText)",
                    tone: pairedRouteLineTone,
                    isSelectable: true,
                    lineLimit: 2
                ),
            pairedRemoteEntryLine: pairedRemoteEntryText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "远端入口：\(pairedRemoteEntryText)",
                    tone: pairedRemoteEntryTone,
                    isSelectable: true,
                    lineLimit: 2
                ),
            freshPairReconnectSmokeLine: {
                guard let freshPairReconnectSmoke else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "首配后复连验证：\(localizedFreshPairReconnectSmokeStatus(freshPairReconnectSmoke.status)) · \(localizedFreshPairReconnectSmokeSource(freshPairReconnectSmoke.source)) · 路由 \(localizedHubRemoteRoute(freshPairReconnectSmoke.route))",
                    tone: freshPairReconnectSmokeTone,
                    lineLimit: 2
                )
            }(),
            freshPairReconnectSmokeDetailLine: freshPairReconnectSmokeDetailText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "首配后复连详情：\(freshPairReconnectSmokeDetailText)",
                    tone: freshPairReconnectSmokeTone == .danger ? .warning : freshPairReconnectSmokeTone,
                    isSelectable: true,
                    lineLimit: 3
                ),
            firstPairCompletionProofLine: {
                guard let firstPairCompletionProof else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "首配完成证明：\(localizedFirstPairReadiness(firstPairCompletionProof.readiness)) · 同网\(firstPairCompletionProof.sameLanVerified ? "已验证" : "未验证") · 缓存复连\(firstPairCompletionProof.cachedReconnectSmokePassed ? "已通过" : "未通过") · remote shadow \(localizedFirstPairRemoteShadowSmokeStatus(firstPairCompletionProof.remoteShadowSmokeStatus))",
                    tone: firstPairCompletionProofTone,
                    lineLimit: 2
                )
            }(),
            firstPairCompletionProofDetailLine: firstPairCompletionProofDetailText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "首配完成详情：\(firstPairCompletionProofDetailText)",
                    tone: firstPairCompletionProofTone == .danger ? .warning : firstPairCompletionProofTone,
                    isSelectable: true,
                    lineLimit: 3
                ),
            hubRuntimeLine: hubRuntimeText.map {
                SupervisorXTReadyIncidentLinePresentation(
                    text: $0,
                    tone: hubRuntimeTone
                )
            },
            hubRuntimeIssueLine: {
                guard let diagnosis = hubRuntimeDiagnosis,
                      diagnosis.overallState != XHubDoctorOverallState.ready.rawValue,
                      !diagnosis.headline.isEmpty else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "Hub 运行时问题：\(diagnosis.headline)",
                    tone: hubRuntimeTone,
                    lineLimit: 2
                )
            }(),
            hubRuntimeLoadConfigLine: hubRuntimeLoadConfigText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "Hub 运行时加载配置：\(hubRuntimeLoadConfigText)",
                    tone: hubRuntimeTone == .danger ? .warning : .accent,
                    isSelectable: true,
                    lineLimit: 3
                ),
            hubRuntimeDetailLine: hubRuntimeDetailText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "Hub 运行时详情：\(hubRuntimeDetailText)",
                    tone: hubRuntimeTone == .danger ? .warning : hubRuntimeTone,
                    isSelectable: true,
                    lineLimit: 3
                ),
            hubRuntimeNextLine: {
                guard let diagnosis = hubRuntimeDiagnosis,
                      diagnosis.overallState != XHubDoctorOverallState.ready.rawValue,
                      !diagnosis.nextStep.isEmpty else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "Hub 运行时下一步：\(diagnosis.nextStep)",
                    tone: .accent,
                    lineLimit: 3
                )
            }(),
            hubRuntimeInstallHintLine: {
                guard let diagnosis = hubRuntimeDiagnosis,
                      diagnosis.overallState != XHubDoctorOverallState.ready.rawValue,
                      !diagnosis.installHint.isEmpty else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "Hub 安装提示：\(diagnosis.installHint)",
                    tone: hubRuntimeTone == .danger ? .warning : .accent,
                    lineLimit: 3
                )
            }(),
            hubRuntimeRecommendedActionLine: {
                guard let diagnosis = hubRuntimeDiagnosis,
                      diagnosis.overallState != XHubDoctorOverallState.ready.rawValue,
                      !diagnosis.recommendedAction.isEmpty else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "Hub 建议动作：\(diagnosis.recommendedAction)",
                    tone: .accent,
                    lineLimit: 3
                )
            }(),
            supervisorVoiceLine: {
                guard let diagnosis = supervisorVoiceDiagnosis,
                      !diagnosis.headline.isEmpty else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "Supervisor 语音：\(localizedDoctorCheckStatus(diagnosis.status)) · \(diagnosis.headline)",
                    tone: supervisorVoiceTone,
                    lineLimit: 2
                )
            }(),
            supervisorVoiceFreshnessLine: supervisorVoiceFreshnessText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "Supervisor 语音时效：\(supervisorVoiceFreshnessText)",
                    tone: supervisorVoiceDiagnosis?.isStale() == true ? .warning : .neutral,
                    lineLimit: 2
                ),
            supervisorVoiceDetailLine: supervisorVoiceDetailText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "Supervisor 语音详情：\(supervisorVoiceDetailText)",
                    tone: supervisorVoiceTone == .danger ? .warning : supervisorVoiceTone,
                    isSelectable: true,
                    lineLimit: 3
                ),
            supervisorVoiceNextLine: {
                guard let diagnosis = supervisorVoiceDiagnosis,
                      !diagnosis.nextStep.isEmpty else {
                    return nil
                }
                return SupervisorXTReadyIncidentLinePresentation(
                    text: "Supervisor 语音下一步：\(diagnosis.nextStep)",
                    tone: .accent,
                    lineLimit: 3
                )
            }(),
            supervisorVoiceActionURL: supervisorVoiceActionURL,
            supervisorVoiceActionLabel: {
                guard let raw = supervisorVoiceDiagnosis?.repairDestinationRef,
                      let destination = UITroubleshootDestination(rawValue: raw) else {
                    return nil
                }
                return SupervisorConversationRepairActionPlanner.plan(for: destination).buttonTitle
            }(),
            memoryAssemblyLine: SupervisorXTReadyIncidentLinePresentation(
                text: "记忆装配：就绪=\(snapshot.memoryAssemblyReady ? "是" : "否") · 问题=\(snapshot.memoryAssemblyIssues.count) · 状态=\(snapshot.memoryAssemblyStatusLine)",
                tone: snapshot.memoryAssemblyReady ? .success : .warning,
                lineLimit: 2
            ),
            memoryAssemblyIssueLine: memoryIssueText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "记忆装配问题：\(memoryIssueText)",
                    tone: .warning,
                    lineLimit: 2
                ),
            memoryAssemblyDetailLine: memoryDetailText.isEmpty
                ? nil
                : SupervisorXTReadyIncidentLinePresentation(
                    text: "记忆装配详情：\(memoryDetailText)",
                    tone: .warning,
                    isSelectable: true,
                    lineLimit: 3
                ),
            canonicalRetryStatusLine: canonicalRetryFeedback.map {
                SupervisorXTReadyIncidentLinePresentation(
                    text: $0.statusLine,
                    tone: $0.tone,
                    lineLimit: 2
                )
            },
            canonicalRetryMetaLine: canonicalRetryFeedback?.metaLine.map {
                SupervisorXTReadyIncidentLinePresentation(
                    text: $0,
                    tone: .neutral,
                    lineLimit: 2
                )
            },
            canonicalRetryDetailLine: canonicalRetryFeedback?.detailLine.map {
                SupervisorXTReadyIncidentLinePresentation(
                    text: $0,
                    tone: .secondaryRetryTone(canonicalRetryFeedback?.tone ?? .neutral),
                    isSelectable: true,
                    lineLimit: 3
                )
            },
            reportPath: trimmedReportPath,
            reportLine: SupervisorXTReadyIncidentLinePresentation(
                text: "报告：\(trimmedReportPath.isEmpty ? "无" : trimmedReportPath)",
                tone: .neutral,
                isSelectable: true,
                lineLimit: 2
            ),
            canOpenReport: !trimmedReportPath.isEmpty
        )
    }

    static func statusTone(
        _ snapshot: SupervisorManager.XTReadyIncidentExportSnapshot
    ) -> SupervisorHeaderControlTone {
        let pairedRouteTone = pairedRouteStatusTone(snapshot.pairedRouteSetSnapshot)
        let hubTone = hubRuntimeTone(snapshot.hubRuntimeDiagnosis)
        let freshPairTone = freshPairReconnectSmokeTone(snapshot.freshPairReconnectSmokeSnapshot)
        let firstPairProofTone = firstPairCompletionProofTone(snapshot.firstPairCompletionProofSnapshot)
        let voiceTone = supervisorVoiceTone(snapshot.supervisorVoiceDiagnosis)
        let connectivityHistoryTone = connectivityIncidentHistoryTone(snapshot.connectivityIncidentHistory)
        let voiceStale = snapshot.supervisorVoiceDiagnosis?.isStale() == true
        if pairedRouteTone == .danger {
            return .danger
        }
        if hubTone == .danger {
            return .danger
        }
        if voiceTone == .danger {
            return .danger
        }
        if connectivityHistoryTone == .danger {
            return .danger
        }
        if firstPairProofTone == .danger {
            return .danger
        }
        if connectivityRepairTone(snapshot.connectivityRepairLedger) == .danger {
            return .danger
        }
        if snapshot.status.hasPrefix("failed") {
            return .danger
        }
        if !snapshot.strictE2EReady {
            return .danger
        }
        if !snapshot.missingIncidentCodes.isEmpty {
            return .warning
        }
        if pairedRouteTone == .warning {
            return .warning
        }
        if hubTone == .warning {
            return .warning
        }
        if freshPairTone == .warning {
            return .warning
        }
        if connectivityHistoryTone == .warning {
            return .warning
        }
        if firstPairProofTone == .warning {
            return .warning
        }
        if connectivityRepairTone(snapshot.connectivityRepairLedger) == .warning {
            return .warning
        }
        if voiceTone == .warning || voiceStale {
            return .warning
        }
        if hubTone == .accent || freshPairTone == .accent || firstPairProofTone == .accent {
            return .accent
        }
        if snapshot.status == "ok" {
            return .success
        }
        if snapshot.status == "disabled" {
            return .neutral
        }
        return .accent
    }

    static func hubRuntimeTone(
        _ diagnosis: SupervisorManager.XTHubRuntimeDiagnosisSnapshot?
    ) -> SupervisorHeaderControlTone {
        guard let diagnosis else { return .neutral }
        switch diagnosis.overallState {
        case XHubDoctorOverallState.ready.rawValue:
            return .success
        case XHubDoctorOverallState.blocked.rawValue:
            return .danger
        case XHubDoctorOverallState.degraded.rawValue:
            return .warning
        case XHubDoctorOverallState.inProgress.rawValue:
            return .accent
        default:
            return .neutral
        }
    }

    static func freshPairReconnectSmokeTone(
        _ diagnosis: SupervisorManager.XTFreshPairReconnectSmokeDiagnosisSnapshot?
    ) -> SupervisorHeaderControlTone {
        guard let diagnosis else { return .neutral }
        switch diagnosis.status {
        case XTFreshPairReconnectSmokeStatus.failed.rawValue:
            return .warning
        case XTFreshPairReconnectSmokeStatus.running.rawValue:
            return .accent
        case XTFreshPairReconnectSmokeStatus.succeeded.rawValue:
            return .success
        default:
            return .neutral
        }
    }

    static func firstPairCompletionProofTone(
        _ diagnosis: SupervisorManager.XTFirstPairCompletionProofDiagnosisSnapshot?
    ) -> SupervisorHeaderControlTone {
        guard let diagnosis else { return .neutral }

        switch diagnosis.readiness {
        case XTPairedRouteReadiness.remoteBlocked.rawValue:
            return .danger
        case XTPairedRouteReadiness.remoteDegraded.rawValue:
            return .warning
        case XTPairedRouteReadiness.localReady.rawValue:
            if diagnosis.remoteShadowSmokeStatus == XTFirstPairRemoteShadowSmokeStatus.running.rawValue {
                return .accent
            }
            return diagnosis.stableRemoteRoutePresent ? .warning : .neutral
        case XTPairedRouteReadiness.remoteReady.rawValue:
            switch diagnosis.remoteShadowSmokeStatus {
            case XTFirstPairRemoteShadowSmokeStatus.running.rawValue:
                return .accent
            case XTFirstPairRemoteShadowSmokeStatus.passed.rawValue:
                return .success
            case XTFirstPairRemoteShadowSmokeStatus.failed.rawValue:
                return .warning
            default:
                return .success
            }
        default:
            return .neutral
        }
    }

    static func supervisorVoiceTone(
        _ diagnosis: SupervisorManager.XTSupervisorVoiceDiagnosisSnapshot?
    ) -> SupervisorHeaderControlTone {
        guard let diagnosis else { return .neutral }
        switch diagnosis.status {
        case XHubDoctorCheckStatus.fail.rawValue:
            return .danger
        case XHubDoctorCheckStatus.warn.rawValue:
            return .warning
        case XHubDoctorCheckStatus.pass.rawValue:
            return .success
        case XHubDoctorCheckStatus.skip.rawValue:
            return .neutral
        default:
            return .neutral
        }
    }

    static func connectivityIncidentHistoryTone(
        _ history: XHubDoctorOutputConnectivityIncidentHistoryReport?
    ) -> SupervisorHeaderControlTone {
        guard let last = history?.entries.last else { return .neutral }
        switch last.incidentState {
        case XTHubConnectivityIncidentState.blocked.rawValue:
            return .danger
        case XTHubConnectivityIncidentState.retrying.rawValue,
             XTHubConnectivityIncidentState.waiting.rawValue:
            return .warning
        case XTHubConnectivityIncidentState.none.rawValue:
            return history?.entries.count ?? 0 > 1 ? .success : .neutral
        default:
            return .neutral
        }
    }

    static func connectivityRepairTone(
        _ ledger: XTConnectivityRepairLedgerSnapshot?
    ) -> SupervisorHeaderControlTone {
        guard let latest = ledger?.entries.last else { return .neutral }
        switch latest.result {
        case .failed:
            return .danger
        case .deferred:
            return .warning
        case .succeeded:
            return .success
        }
    }

    static func pairedRouteStatusTone(
        _ snapshot: XHubDoctorOutputPairedRouteSetSnapshot?
    ) -> SupervisorHeaderControlTone {
        guard let snapshot else { return .neutral }
        switch snapshot.readiness {
        case XTPairedRouteReadiness.remoteReady.rawValue:
            return .success
        case XTPairedRouteReadiness.remoteBlocked.rawValue:
            return .danger
        case XTPairedRouteReadiness.localReady.rawValue,
             XTPairedRouteReadiness.remoteDegraded.rawValue:
            return .warning
        default:
            return .neutral
        }
    }

    static func pairedRouteLineTone(
        pairedRouteSetSnapshot: XHubDoctorOutputPairedRouteSetSnapshot?,
        routeSnapshot: XHubDoctorOutputRouteSnapshot?
    ) -> SupervisorHeaderControlTone {
        let readinessTone = pairedRouteStatusTone(pairedRouteSetSnapshot)
        if readinessTone != .neutral {
            return readinessTone
        }
        return pairedRemoteEntryTone(routeSnapshot)
    }

    static func pairedRemoteEntryTone(
        _ snapshot: XHubDoctorOutputRouteSnapshot?
    ) -> SupervisorHeaderControlTone {
        guard let posture = snapshot?.remoteEntryPosture.trimmingCharacters(in: .whitespacesAndNewlines),
              !posture.isEmpty else {
            return .neutral
        }
        switch posture {
        case "stable_named_entry":
            return .success
        case "missing_formal_remote_entry",
             "lan_only_entry",
             "temporary_raw_ip_entry":
            return .warning
        default:
            return .neutral
        }
    }

    private static func localizedConnectivityIncidentHistory(
        _ history: XHubDoctorOutputConnectivityIncidentHistoryReport?
    ) -> String {
        guard let history else { return "" }
        let recentEntries = Array(history.entries.suffix(3))
        guard !recentEntries.isEmpty else { return "" }
        let trail = recentEntries.map { entry in
            let state = localizedConnectivityIncidentState(entry.incidentState)
            let reason = entry.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else { return state }
            return "\(state)(\(reason))"
        }.joined(separator: " -> ")
        guard !trail.isEmpty else { return "" }
        return "最近 \(history.entries.count) 次 · \(trail)"
    }

    private static func localizedConnectivityRepairStatus(
        _ ledger: XTConnectivityRepairLedgerSnapshot?
    ) -> String {
        guard let ledger,
              let latest = ledger.entries.last else { return "" }
        return [
            "最近 \(ledger.entries.count) 次",
            localizedConnectivityRepairOwner(latest.owner),
            localizedConnectivityRepairAction(latest.action),
            localizedConnectivityRepairResult(latest.result),
            "验证 \(latest.verifyResult)",
            "路由 \(localizedHubRemoteRoute(latest.finalRoute))"
        ].joined(separator: " · ")
    }

    private static func localizedConnectivityRepairDetail(
        _ ledger: XTConnectivityRepairLedgerSnapshot?
    ) -> String {
        guard let ledger else { return "" }
        return ledger.entries.suffix(3).map { entry in
            "\(localizedConnectivityRepairAction(entry.action)) \(localizedConnectivityRepairResult(entry.result))"
        }.joined(separator: " -> ")
    }

    private static func localizedPairedRouteSummary(
        pairedRouteSetSnapshot: XHubDoctorOutputPairedRouteSetSnapshot?,
        routeSnapshot: XHubDoctorOutputRouteSnapshot?
    ) -> String {
        if let activeRoute = pairedRouteSetSnapshot?.activeRoute {
            var parts = [localizedPairedRouteKind(activeRoute.routeKind)]
            if let routeSnapshot {
                let transportLabel = localizedTransportMode(routeSnapshot.transportMode)
                if !transportLabel.isEmpty,
                   !parts.contains(transportLabel) {
                    parts.append(transportLabel)
                }
            }
            let host = activeRoute.host.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.isEmpty {
                parts.append("host=\(host)")
            }
            return parts.joined(separator: " · ")
        }

        guard let routeSnapshot else { return "" }
        let routeLabel = routeSnapshot.routeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let transportLabel = localizedTransportMode(routeSnapshot.transportMode)
        var parts: [String] = []
        if !routeLabel.isEmpty {
            parts.append(routeLabel)
        }
        if !transportLabel.isEmpty,
           !routeLabel.lowercased().contains(transportLabel.lowercased()) {
            parts.append(transportLabel)
        }
        if let host = routeSnapshot.normalizedInternetHost {
            parts.append("host=\(host)")
        }
        return parts.joined(separator: " · ")
    }

    private static func localizedPairedRouteKind(_ raw: String) -> String {
        switch raw {
        case XTPairedRouteTargetKind.localFileIPC.rawValue:
            return "本机直连"
        case XTPairedRouteTargetKind.lan.rawValue:
            return "局域网"
        case XTPairedRouteTargetKind.internet.rawValue:
            return "互联网直连"
        case XTPairedRouteTargetKind.internetTunnel.rawValue:
            return "互联网隧道"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func localizedConnectivityRepairOwner(
        _ owner: XTConnectivityRepairOwner
    ) -> String {
        switch owner {
        case .xtRuntime:
            return "XT 自动修复"
        case .user:
            return "用户触发"
        }
    }

    private static func localizedConnectivityRepairAction(
        _ action: XTConnectivityRepairAction
    ) -> String {
        switch action {
        case .remoteReconnect:
            return "远端重连"
        case .bootstrapReconnect:
            return "bootstrap 重连"
        case .waitForNetwork:
            return "等待网络恢复"
        case .waitForPairingRepair:
            return "等待配对修复"
        case .waitForRouteReady:
            return "等待正式路由"
        }
    }

    private static func localizedConnectivityRepairResult(
        _ result: XTConnectivityRepairResult
    ) -> String {
        switch result {
        case .deferred:
            return "待处理"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        }
    }

    private static func localizedConnectivityIncidentState(_ raw: String) -> String {
        switch raw {
        case XTHubConnectivityIncidentState.none.rawValue:
            return "已恢复"
        case XTHubConnectivityIncidentState.retrying.rawValue:
            return "重试中"
        case XTHubConnectivityIncidentState.waiting.rawValue:
            return "等待中"
        case XTHubConnectivityIncidentState.blocked.rawValue:
            return "已阻塞"
        default:
            return raw
        }
    }

    private static func localizedFreshPairReconnectSmokeStatus(_ raw: String) -> String {
        switch raw {
        case XTFreshPairReconnectSmokeStatus.running.rawValue:
            return "验证中"
        case XTFreshPairReconnectSmokeStatus.succeeded.rawValue:
            return "已通过"
        case XTFreshPairReconnectSmokeStatus.failed.rawValue:
            return "失败"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func localizedFreshPairReconnectSmokeSource(_ raw: String) -> String {
        switch raw {
        case XTFreshPairReconnectSmokeSource.startupAutomaticFirstPair.rawValue:
            return XTFreshPairReconnectSmokeSource.startupAutomaticFirstPair.doctorLabel
        case XTFreshPairReconnectSmokeSource.manualOneClickSetup.rawValue:
            return XTFreshPairReconnectSmokeSource.manualOneClickSetup.doctorLabel
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func localizedFirstPairReadiness(_ raw: String) -> String {
        switch raw {
        case XTPairedRouteReadiness.localReady.rawValue:
            return "本地就绪"
        case XTPairedRouteReadiness.remoteReady.rawValue:
            return "异网就绪"
        case XTPairedRouteReadiness.remoteDegraded.rawValue:
            return "异网降级"
        case XTPairedRouteReadiness.remoteBlocked.rawValue:
            return "异网阻塞"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func localizedFirstPairRemoteShadowSmokeStatus(_ raw: String) -> String {
        switch raw {
        case XTFirstPairRemoteShadowSmokeStatus.notRun.rawValue:
            return "未验证"
        case XTFirstPairRemoteShadowSmokeStatus.running.rawValue:
            return "验证中"
        case XTFirstPairRemoteShadowSmokeStatus.passed.rawValue:
            return "已通过"
        case XTFirstPairRemoteShadowSmokeStatus.failed.rawValue:
            return "失败"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func localizedFirstPairRemoteShadowSmokeSource(_ raw: String) -> String {
        switch raw {
        case XTRemoteShadowReconnectSmokeSource.cachedRemoteReconnectEvidence.rawValue:
            return XTRemoteShadowReconnectSmokeSource.cachedRemoteReconnectEvidence.doctorLabel
        case XTRemoteShadowReconnectSmokeSource.liveRemoteRoute.rawValue:
            return XTRemoteShadowReconnectSmokeSource.liveRemoteRoute.doctorLabel
        case XTRemoteShadowReconnectSmokeSource.dedicatedStableRemoteProbe.rawValue:
            return XTRemoteShadowReconnectSmokeSource.dedicatedStableRemoteProbe.doctorLabel
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func localizedHubRemoteRoute(_ raw: String) -> String {
        switch raw {
        case HubRemoteRoute.lan.rawValue:
            return "局域网"
        case HubRemoteRoute.internet.rawValue:
            return "互联网直连"
        case HubRemoteRoute.internetTunnel.rawValue:
            return "互联网隧道"
        case HubRemoteRoute.none.rawValue:
            return "未建立"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func localizedTransportMode(_ raw: String) -> String {
        switch raw {
        case "grpc",
             "remote_grpc",
             "remote_grpc_lan",
             "remote_grpc_internet",
             "remote_grpc_tunnel":
            return "gRPC"
        case "local_fileipc", "local:fileipc":
            return "fileIPC"
        case "local":
            return "本机直连"
        case "pairing_bootstrap":
            return "配对引导"
        case "disconnected":
            return "未连接"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func fallbackSupervisorVoiceActionURL(
        _ diagnosis: SupervisorManager.XTSupervisorVoiceDiagnosisSnapshot?
    ) -> String? {
        let existing = diagnosis?.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !existing.isEmpty {
            return existing
        }
        guard let diagnosis,
              let destination = UITroubleshootDestination(
                rawValue: diagnosis.repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return nil
        }
        let detail = [
            diagnosis.message.trimmingCharacters(in: .whitespacesAndNewlines),
            diagnosis.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let title = diagnosis.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? nil : title
        let resolvedDetail = detail.isEmpty ? nil : detail

        switch destination {
        case .xtPairHub:
            return XTDeepLinkURLBuilder.settingsURL(
                sectionId: "pair_hub",
                title: resolvedTitle,
                detail: resolvedDetail
            )?.absoluteString
        case .xtChooseModel:
            return XTDeepLinkURLBuilder.supervisorModelSettingsURL(
                title: resolvedTitle,
                detail: resolvedDetail
            )?.absoluteString
        case .xtDiagnostics:
            return XTDeepLinkURLBuilder.settingsURL(
                sectionId: "diagnostics",
                title: resolvedTitle,
                detail: resolvedDetail
            )?.absoluteString
        case .hubPairing, .hubLAN:
            return XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "pair_progress",
                title: resolvedTitle,
                detail: resolvedDetail
            )?.absoluteString
        case .hubModels:
            return XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "choose_model",
                title: resolvedTitle,
                detail: resolvedDetail
            )?.absoluteString
        case .hubGrants, .hubSecurity, .hubDiagnostics:
            return XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "troubleshoot",
                title: resolvedTitle,
                detail: resolvedDetail
            )?.absoluteString
        case .systemPermissions, .homeSupervisor:
            return XTDeepLinkURLBuilder.supervisorSettingsURL()?.absoluteString
        }
    }

    private static func localizedExportStatus(_ raw: String) -> String {
        switch raw {
        case "ok":
            return "正常"
        case "disabled":
            return "已停用"
        case "warming":
            return "收敛中"
        case "failed_export":
            return "导出失败"
        default:
            if raw.hasPrefix("failed") {
                return "失败"
            }
            return raw
        }
    }

    private static func localizedHubOverallState(_ raw: String) -> String {
        switch raw {
        case XHubDoctorOverallState.ready.rawValue:
            return "正常"
        case XHubDoctorOverallState.blocked.rawValue:
            return "阻塞"
        case XHubDoctorOverallState.degraded.rawValue:
            return "降级"
        case XHubDoctorOverallState.inProgress.rawValue:
            return "处理中"
        default:
            return raw
        }
    }

    private static func localizedDoctorCheckStatus(_ raw: String) -> String {
        switch raw {
        case XHubDoctorCheckStatus.fail.rawValue:
            return "失败"
        case XHubDoctorCheckStatus.warn.rawValue:
            return "告警"
        case XHubDoctorCheckStatus.pass.rawValue:
            return "通过"
        case XHubDoctorCheckStatus.skip.rawValue:
            return "跳过"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未知" : raw
        }
    }
}

private extension SupervisorHeaderControlTone {
    static func secondaryRetryTone(_ tone: SupervisorHeaderControlTone) -> SupervisorHeaderControlTone {
        switch tone {
        case .danger:
            return .warning
        default:
            return tone
        }
    }
}
