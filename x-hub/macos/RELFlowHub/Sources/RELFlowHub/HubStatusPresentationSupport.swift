import AppKit
import Foundation
import RELFlowHubCore
import SwiftUI

enum HubStatusPresentationTone: Equatable {
    case ready
    case starting
    case degraded
    case failed
    case unknown
}

struct HubStatusPresentation: Equatable {
    var stateKey: String
    var title: String
    var detail: String
    var tone: HubStatusPresentationTone
    var toolTip: String
    var actionTitle: String
    var actionDetail: String

    var color: NSColor {
        HubStatusPresentationSupport.color(for: tone)
    }

    var colorKey: String {
        HubStatusPresentationSupport.colorKey(color)
    }

    var tint: Color {
        Color(nsColor: color)
    }

    var systemName: String {
        HubStatusPresentationSupport.systemName(for: tone)
    }

    var needsActionHint: Bool {
        tone != .ready
    }
}

enum HubStatusPresentationSupport {
    static let menuBarSymbol = "\u{26A1}\u{FE0E}"

    static func make(
        snapshot: HubLaunchStatusSnapshot?,
        grpcIsRunning: Bool,
        grpcStatusText: String,
        appName: String = "X-Hub"
    ) -> HubStatusPresentation {
        let state = snapshot?.state
        let degraded = snapshot?.degraded.isDegraded == true || !(snapshot?.degraded.blockedCapabilities ?? []).isEmpty
        let rootCause = snapshot?.rootCause

        let tone: HubStatusPresentationTone
        let title: String
        let detail: String
        let stateKey: String

        switch state {
        case .serving where !degraded:
            tone = .ready
            title = "正常"
            let trimmedGRPCStatus = grpcStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
            detail = grpcIsRunning && !trimmedGRPCStatus.isEmpty
                ? trimmedGRPCStatus
                : "Rust kernel serving"
            stateKey = "serving"
        case .serving, .degradedServing:
            tone = .degraded
            title = "降级"
            let blockedCount = snapshot?.degraded.blockedCapabilities.count ?? 0
            detail = blockedCount > 0 ? "\(blockedCount) 个能力被阻止" : "部分服务需要复查"
            stateKey = "degraded"
        case .bootStart, .envValidate, .startGRPCServer, .waitGRPCReady, .startBridge, .waitBridgeReady, .startRuntime, .waitRuntimeReady:
            tone = .starting
            title = "启动中"
            detail = state?.rawValue ?? "BOOT_START"
            stateKey = "starting:\(state?.rawValue ?? "unknown")"
        case .failed:
            tone = .failed
            title = "错误"
            detail = rootCause?.errorCode.isEmpty == false ? rootCause?.errorCode ?? "" : "启动失败"
            stateKey = "failed:\(detail)"
        case nil:
            if grpcIsRunning {
                tone = .ready
                title = "正常"
                detail = grpcStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
                stateKey = "grpc-running"
            } else {
                tone = .unknown
                title = "未知"
                detail = "等待 Hub 状态"
                stateKey = "unknown"
            }
        }

        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolTip = trimmedDetail.isEmpty
            ? "\(appName) • \(title)"
            : "\(appName) • \(title) • \(trimmedDetail)"
        let action = actionHint(for: tone)

        return HubStatusPresentation(
            stateKey: stateKey,
            title: title,
            detail: trimmedDetail,
            tone: tone,
            toolTip: toolTip,
            actionTitle: action.title,
            actionDetail: action.detail
        )
    }

    static func color(for tone: HubStatusPresentationTone) -> NSColor {
        switch tone {
        case .ready:
            return NSColor(calibratedRed: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)
        case .starting:
            return NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
        case .degraded:
            return NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
        case .failed:
            return NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1.0)
        case .unknown:
            return NSColor(calibratedWhite: 0.62, alpha: 1.0)
        }
    }

    static func systemName(for tone: HubStatusPresentationTone) -> String {
        switch tone {
        case .ready:
            return "checkmark.circle.fill"
        case .starting:
            return "arrow.triangle.2.circlepath"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    static func actionHint(for tone: HubStatusPresentationTone) -> (title: String, detail: String) {
        switch tone {
        case .ready:
            return ("继续使用", "Hub 已可接收 XT、本地任务和模型路由请求。")
        case .starting:
            return ("等待启动", "如果长时间停在当前步骤，打开诊断页查看启动链路。")
        case .degraded:
            return ("查看受阻能力", "打开诊断页确认 fail-closed capability、root cause 和恢复动作。")
        case .failed:
            return ("立即修复", "打开诊断页运行修复动作，或导出诊断包保留证据。")
        case .unknown:
            return ("刷新状态", "等待 Hub 写入启动状态；必要时在诊断页重启组件。")
        }
    }

    static func colorKey(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let r = Int((rgb.redComponent * 255.0).rounded())
        let g = Int((rgb.greenComponent * 255.0).rounded())
        let b = Int((rgb.blueComponent * 255.0).rounded())
        let a = Int((rgb.alphaComponent * 255.0).rounded())
        return "\(r)-\(g)-\(b)-\(a)"
    }
}
