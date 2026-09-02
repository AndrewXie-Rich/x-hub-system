import Foundation

extension SupervisorManager {
    func heartbeatHubLoadSignal(
        baseDir: URL = HubPaths.baseDir()
    ) -> HeartbeatHubLoadSignal? {
        guard let monitor = XHubDoctorOutputStore.loadHubLocalRuntimeMonitorSnapshot(baseDir: baseDir),
              let hostMetrics = monitor.hostMetrics else {
            return nil
        }

        let severity = hostMetrics.resolvedSeverity
        guard severity != .normal else { return nil }

        let summary = heartbeatHubLoadSummary(hostMetrics)
        let nextStep = heartbeatHubLoadNextStep(hostMetrics)
        let detailText = ([summary, nextStep] + hostMetrics.detailLines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return HeartbeatHubLoadSignal(
            severity: severity,
            overallSummary: summary,
            nextStep: nextStep,
            detailLines: hostMetrics.detailLines,
            actionURL: heartbeatHubLoadActionURL(
                severity: severity,
                detail: detailText
            )
        )
    }

    func heartbeatHubLoadSummary(
        _ metrics: XHubLocalRuntimeHostMetricsReport
    ) -> String {
        let severityText: String
        switch metrics.resolvedSeverity {
        case .critical:
            severityText = "Hub 主机负载过高"
        case .high:
            severityText = "Hub 主机负载偏高"
        case .elevated:
            severityText = "Hub 主机负载需要关注"
        case .normal:
            severityText = "Hub 主机负载正常"
        }

        var parts: [String] = [severityText]
        if let cpu = metrics.cpuUsagePercent {
            parts.append(String(format: "CPU %.0f%%", cpu))
        }
        parts.append(
            String(
                format: "load %.2f / %.2f / %.2f",
                metrics.loadAverage1m,
                metrics.loadAverage5m,
                metrics.loadAverage15m
            )
        )
        let memoryPressure = metrics.memoryPressure.trimmingCharacters(in: .whitespacesAndNewlines)
        if !memoryPressure.isEmpty {
            parts.append("内存 \(memoryPressure)")
        }
        let thermalState = metrics.thermalState.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thermalState.isEmpty {
            parts.append("热状态 \(thermalState)")
        }
        return parts.joined(separator: " · ")
    }

    func heartbeatHubLoadNextStep(
        _ metrics: XHubLocalRuntimeHostMetricsReport
    ) -> String {
        switch metrics.resolvedSeverity {
        case .critical:
            return "建议先查看 Hub 诊断，优先降低并发、暂停高负载任务，必要时等待温度和队列回落。"
        case .high:
            return "建议先查看 Hub 诊断，优先检查当前并发、模型加载和排队堆积，再决定是否降模型或降并行度。"
        case .elevated:
            return "建议先查看 Hub 诊断，确认是否只是短时抖动；如果连续几次心跳仍偏高，再收并发或排队。"
        case .normal:
            return "继续观察。"
        }
    }

    func heartbeatHubLoadActionURL(
        severity: XHubLocalRuntimeHostMetricsSeverity,
        detail: String
    ) -> String? {
        let title: String
        switch severity {
        case .critical:
            title = "Hub 负载过高"
        case .high:
            title = "Hub 负载偏高"
        case .elevated:
            title = "Hub 负载需要关注"
        case .normal:
            title = "Hub 负载"
        }

        return XTDeepLinkURLBuilder.hubSetupURL(
            sectionId: "troubleshoot",
            title: title,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail
        )?.absoluteString
    }

    func heartbeatHubLoadContentLine(
        _ signal: HeartbeatHubLoadSignal
    ) -> String {
        let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
        return "• \(capped(signal.overallSummary, maxChars: 120))\(actionSuffix)"
    }

    func heartbeatHubLoadNextStepLine(
        _ signal: HeartbeatHubLoadSignal
    ) -> String {
        let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
        return "Hub 负载：\(capped(signal.overallSummary, maxChars: 72))；建议先查看 Hub 诊断\(actionSuffix)"
    }
}
