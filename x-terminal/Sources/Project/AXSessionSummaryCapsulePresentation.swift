import Foundation

struct AXResumeReminderProjectPresentation: Equatable {
    let projectId: String
    let projectDisplayName: String
    let summary: AXSessionSummaryCapsulePresentation
}

struct AXSessionSummaryCapsulePresentation: Equatable {
    let reason: String
    let createdAtMs: Int64

    var reasonLabel: String {
        switch reason {
        case "app_exit":
            return "退出 App"
        case "project_switch":
            return "切项目"
        case "ai_switch":
            return "切 AI"
        default:
            return reason
        }
    }

    var relativeText: String {
        let nowMs = Int64((Date().timeIntervalSince1970 * 1_000.0).rounded())
        let deltaSec = max(0, Int((nowMs - createdAtMs) / 1_000))
        if deltaSec < 60 {
            return "刚刚"
        }
        if deltaSec < 3_600 {
            return "\(max(1, deltaSec / 60))m前"
        }
        if deltaSec < 86_400 {
            return "\(max(1, deltaSec / 3_600))h前"
        }
        return "\(max(1, deltaSec / 86_400))d前"
    }

    var absoluteText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(createdAtMs) / 1_000.0))
    }

    var badgeText: String {
        "最近交接：\(reasonLabel) · \(relativeText)"
    }

    var detailText: String {
        "\(reasonLabel) · \(absoluteText)"
    }

    var helpText: String {
        "最新 session_summary_capsule：\(reasonLabel) · \(absoluteText)"
    }

    static func load(for ctx: AXProjectContext) -> AXSessionSummaryCapsulePresentation? {
        guard FileManager.default.fileExists(atPath: ctx.latestSessionSummaryURL.path),
              let data = try? Data(contentsOf: ctx.latestSessionSummaryURL),
              let capsule = try? JSONDecoder().decode(AXSessionSummaryCapsule.self, from: data) else {
            return nil
        }
        return AXSessionSummaryCapsulePresentation(
            reason: capsule.reason,
            createdAtMs: capsule.createdAtMs
        )
    }
}
