import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
enum GRPCClientExecutionState {
        case remoteCompleted
        case localCompleted
        case downgradedToLocal
        case denied
        case failed
        case canceled
        case unknown
    }

    func grpcClientExecutionState(_ st: GRPCDeviceStatusEntry) -> GRPCClientExecutionState {
        guard let activity = st.lastActivity else { return .unknown }
        let eventType = activity.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        switch eventType {
        case "ai.generate.downgraded_to_local":
            return .downgradedToLocal
        case "ai.generate.completed":
            return activity.networkAllowed ? .remoteCompleted : .localCompleted
        case "ai.generate.denied":
            return .denied
        case "ai.generate.failed":
            return .failed
        case "ai.generate.canceled":
            return .canceled
        default:
            return .unknown
        }
    }

    func grpcClientExecutionPillTitle(_ st: GRPCDeviceStatusEntry) -> String {
        switch grpcClientExecutionState(st) {
        case .remoteCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.executionRemote
        case .localCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.executionLocal
        case .downgradedToLocal:
            return HubUIStrings.Settings.GRPC.DeviceList.executionDowngraded
        case .denied:
            return HubUIStrings.Settings.GRPC.DeviceList.executionDenied
        case .failed:
            return HubUIStrings.Settings.GRPC.DeviceList.executionFailed
        case .canceled:
            return HubUIStrings.Settings.GRPC.DeviceList.executionCanceled
        case .unknown:
            return HubUIStrings.Settings.GRPC.DeviceList.executionUnknown
        }
    }

    func grpcClientExecutionPillColor(_ st: GRPCDeviceStatusEntry) -> Color {
        switch grpcClientExecutionState(st) {
        case .remoteCompleted:
            return .green
        case .localCompleted:
            return .secondary
        case .downgradedToLocal:
            return .orange
        case .denied, .failed:
            return .red
        case .canceled:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    func grpcClientActualExecutionSummary(_ st: GRPCDeviceStatusEntry) -> String {
        guard let activity = st.lastActivity else {
            let topModel = st.topModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !topModel.isEmpty {
                return HubUIStrings.Settings.GRPC.DeviceList.executionSummaryWithTopModel(topModel)
            }
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionNoDetail
        }

        let model = activity.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = activity.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = activity.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.isEmpty ? HubUIStrings.Settings.GRPC.DeviceList.noReportedModel : model

        switch grpcClientExecutionState(st) {
        case .remoteCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionRemote(resolvedModel)
        case .localCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionLocal(resolvedModel)
        case .downgradedToLocal:
            let reason = !code.isEmpty ? code : (!message.isEmpty ? message : HubUIStrings.Settings.GRPC.DeviceList.downgradedFallback)
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionDowngraded(model: resolvedModel, reason: reason)
        case .denied:
            let reason = !code.isEmpty ? code : (!message.isEmpty ? message : HubUIStrings.Settings.GRPC.DeviceList.deniedFallback)
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionDenied(reason)
        case .failed:
            let reason = !code.isEmpty ? code : (!message.isEmpty ? message : HubUIStrings.Settings.GRPC.DeviceList.failedFallback)
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionFailed(reason)
        case .canceled:
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionCanceled
        case .unknown:
            let eventType = activity.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
            if eventType.isEmpty {
                return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionIncomplete
            }
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionUnknown(eventType: eventType, model: resolvedModel)
        }
    }

    func grpcClientLastBlockedSummary(_ st: GRPCDeviceStatusEntry) -> String {
        let reason = st.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = st.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty && code.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlockedNone }
        if reason.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(code) }
        if code.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(reason) }
        return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(reason: reason, code: code)
    }

    func grpcClientModelBreakdownSummary(_ row: GRPCDeviceModelBreakdownEntry) -> String {
        var parts: [String] = [row.modelId]
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.tokenUsage(row.totalTokens))
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.requests(row.requestCount))
        if row.blockedCount > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.blocked(row.blockedCount)) }
        if row.lastUsedAtMs > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.recent(formatMs(row.lastUsedAtMs))) }
        if row.lastBlockedAtMs > 0 {
            let code = row.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(code.isEmpty ? HubUIStrings.Settings.GRPC.DeviceList.denyRecorded : HubUIStrings.Settings.GRPC.DeviceList.denyCode(code))
        }
        return HubUIStrings.Settings.GRPC.DeviceList.summary(parts)
    }

    func paidPolicyModeLabel(_ raw: String) -> String {
        HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel(raw)
    }

    func grpcClientLastActivitySummary(_ a: GRPCDeviceLastActivity) -> String {
        let model = a.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = a.capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let at = a.createdAtMs > 0 ? formatMs(a.createdAtMs) : ""
        let eventType = a.eventType.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !eventType.isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.audit(eventType))
        } else if !model.isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.audit(model))
        } else {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.auditUnknown)
        }

        if !model.isEmpty { parts.append(HubUIStrings.Settings.GRPC.DeviceList.model(model)) }
        if !cap.isEmpty { parts.append(cap) }
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.network(a.networkAllowed))
        if a.totalTokens > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.tokenUsage(a.totalTokens)) }
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.ok(a.ok))
        if !at.isEmpty { parts.append(at) }
        if !a.ok {
            let code = a.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { parts.append(code) }
        }
        return HubUIStrings.Settings.GRPC.DeviceList.summary(parts)
    }

    func formatMs(_ ms: Int64) -> String {
        let secs = Double(ms) / 1000.0
        let d = Date(timeIntervalSince1970: secs)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.dateTimeWithSeconds
        return f.string(from: d)
    }

    static let remoteModeGuideText = HubUIStrings.Settings.GRPC.remoteAccessGuideChecklist
}
