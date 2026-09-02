import Foundation

extension SupervisorManager {
    func renderDoctorSummary(_ report: SupervisorDoctorReport) -> String {
        var lines: [String] = []
        prependWorkbenchGovernanceBriefIfAvailable(to: &lines)
        lines.append("🩺 Supervisor Doctor 预检结果")
        lines.append("状态：\(report.ok ? "通过" : "阻断")")
        lines.append("阻断项：\(report.summary.blockingCount) · 告警项：\(report.summary.warningCount)")
        lines.append(
            "memory assembly：阻断 \(report.summary.memoryAssemblyBlockingCount) · 告警 \(report.summary.memoryAssemblyWarningCount)"
        )
        lines.append("配置来源：\(report.configSource)")
        lines.append("Secrets 计划：\(report.secretsPlanSource)")
        lines.append("报告路径：\(doctorReportPath.isEmpty ? "(未落盘)" : doctorReportPath)")
        if let feedback = canonicalMemoryRetryFeedback {
            lines.append(feedback.statusLine)
            if let meta = feedback.metaLine,
               !meta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_meta：\(meta)")
            }
            if let detail = feedback.detailLine,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_detail：\(detail)")
            }
        }
        if let snapshot = supervisorMemoryAssemblySnapshot {
            let continuityLines = Self.prioritizedMemoryAssemblySnapshotDetailLines(snapshot).prefix(2)
            if !continuityLines.isEmpty {
                lines.append("continuity_detail：\(continuityLines.joined(separator: " || "))")
            }
        }

        if report.findings.isEmpty {
            lines.append("未发现风险项。")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append("优先级解释与可操作建议（Top 3）：")
        for (index, finding) in report.findings.prefix(3).enumerated() {
            lines.append("\(index + 1). [\(finding.priority.rawValue.uppercased())] \(finding.title)")
            lines.append("   解释：\(finding.priorityReason)")
            if let first = finding.actions.first {
                lines.append("   建议：\(first)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func renderSecretsDryRunSummary(_ report: SupervisorDoctorReport) -> String {
        let summary = report.summary
        var lines: [String] = []
        prependWorkbenchGovernanceBriefIfAvailable(to: &lines)
        lines.append("🔐 Secrets dry-run 摘要")
        lines.append("目标路径越界：\(summary.secretsPathOutOfScopeCount)")
        lines.append("缺失变量：\(summary.secretsMissingVariableCount)")
        lines.append("权限边界错误：\(summary.secretsPermissionBoundaryCount)")
        lines.append("阻断项总数：\(summary.blockingCount)")

        let secretsFindings = report.findings.filter { $0.area == "secrets_dry_run" }
        if secretsFindings.isEmpty {
            lines.append("当前未发现 secrets dry-run 风险。")
        } else {
            lines.append("")
            lines.append("可执行修复卡片：")
            for finding in secretsFindings.prefix(3) {
                lines.append("- \(finding.title)：\(finding.actions.first ?? "按建议修复后重新 dry-run")")
            }
        }
        return lines.joined(separator: "\n")
    }

    func renderCanonicalMemoryRetryCommandResponse() -> String {
        var lines = ["已触发 canonical memory 重试。"]
        if let feedback = canonicalMemoryRetryFeedback {
            lines.append(feedback.statusLine)
            if let meta = feedback.metaLine,
               !meta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_meta：\(meta)")
            }
            if let detail = feedback.detailLine,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_detail：\(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func renderXTReadyIncidentExportSummary(
        _ result: XTReadyIncidentEventsExportResult
    ) -> String {
        let snapshot = xtReadyIncidentExportSnapshot(limit: 120)
        var lines: [String] = []
        prependWorkbenchGovernanceBriefIfAvailable(to: &lines)
        lines.append("🧾 XT-Ready incident 事件导出")
        lines.append("状态：\(result.ok ? "成功" : "失败")")
        lines.append("导出条数：\(result.exportedEventCount)")
        lines.append("输出路径：\(result.outputPath)")
        lines.append("strict_e2e_ready：\(snapshot.strictE2EReady ? "yes" : "no")")
        lines.append("memory_assembly_ready：\(snapshot.memoryAssemblyReady ? "yes" : "no")")
        lines.append("memory_assembly_status：\(snapshot.memoryAssemblyStatusLine)")
        appendXTReadyIncidentDiagnosticContextLines(snapshot, to: &lines)
        if !result.missingIncidentCodes.isEmpty {
            lines.append("缺失必需 incident_code：\(result.missingIncidentCodes.joined(separator: ","))")
        }
        appendXTReadyIncidentIssueLines(snapshot, to: &lines)
        if let feedback = canonicalMemoryRetryFeedback {
            lines.append(feedback.statusLine)
            if let meta = feedback.metaLine,
               !meta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_meta：\(meta)")
            }
            if let detail = feedback.detailLine,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_detail：\(detail)")
            }
        }
        if result.reason != "ok" {
            lines.append("原因：\(result.reason)")
        }
        lines.append("下一步：node ./scripts/m3_generate_xt_ready_e2e_evidence.js --strict --events-json \(result.outputPath) --out-json ./build/xt_ready_e2e_evidence.runtime.json")
        return lines.joined(separator: "\n")
    }

    func renderXTReadyIncidentEventsStatus() -> String {
        let snapshot = xtReadyIncidentExportSnapshot(limit: 120)

        var lines: [String] = []
        prependWorkbenchGovernanceBriefIfAvailable(to: &lines)
        lines.append("📌 XT-Ready incident 导出状态")
        lines.append("auto_export：\(snapshot.autoExportEnabled ? "enabled" : "disabled")")
        lines.append("ledger incidents：\(snapshot.ledgerIncidentCount)")
        lines.append("exported required incidents：\(snapshot.requiredIncidentEventCount)")
        lines.append("status：\(snapshot.status)")
        lines.append("strict_e2e_ready：\(snapshot.strictE2EReady ? "yes" : "no")")
        lines.append("memory_assembly_ready：\(snapshot.memoryAssemblyReady ? "yes" : "no")")
        lines.append("memory_assembly_status：\(snapshot.memoryAssemblyStatusLine)")
        lines.append("report_path：\(snapshot.reportPath)")
        appendXTReadyIncidentDiagnosticContextLines(snapshot, to: &lines)
        if snapshot.missingIncidentCodes.isEmpty {
            lines.append("missing incident_code：none")
        } else {
            lines.append("missing incident_code：\(snapshot.missingIncidentCodes.joined(separator: ","))")
        }
        appendXTReadyIncidentIssueLines(snapshot, to: &lines)
        if let feedback = canonicalMemoryRetryFeedback {
            lines.append(feedback.statusLine)
            if let meta = feedback.metaLine,
               !meta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_meta：\(meta)")
            }
            if let detail = feedback.detailLine,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("canonical_sync_retry_detail：\(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
