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
    var hubRuntimeLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeIssueLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeDetailLine: SupervisorXTReadyIncidentLinePresentation?
    var hubRuntimeNextLine: SupervisorXTReadyIncidentLinePresentation?
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
        let hubRuntimeDetailText = hubRuntimeDiagnosis?.detailLines
            .prefix(2)
            .joined(separator: " || ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hubRuntimeText = hubRuntimeDiagnosis.map { diagnosis in
            let suffix = diagnosis.failureCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.isEmpty {
                return "Hub 运行时：\(localizedHubOverallState(diagnosis.overallState))"
            }
            return "Hub 运行时：\(localizedHubOverallState(diagnosis.overallState)) · \(suffix)"
        }
        let hubRuntimeTone = hubRuntimeTone(hubRuntimeDiagnosis)

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
        let hubTone = hubRuntimeTone(snapshot.hubRuntimeDiagnosis)
        if hubTone == .danger {
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
        if hubTone == .warning {
            return .warning
        }
        if hubTone == .accent {
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
