import Foundation

struct SupervisorBigTaskCandidate: Equatable {
    var goal: String
    var fingerprint: String
}

enum SupervisorBigTaskAssist {
    static func detect(
        inputText: String,
        latestUserMessage: String?,
        dismissedFingerprint: String?
    ) -> SupervisorBigTaskCandidate? {
        let candidate = candidate(from: inputText)
            ?? candidate(from: latestUserMessage ?? "")
        guard let candidate else { return nil }
        if dismissedFingerprint == candidate.fingerprint {
            return nil
        }
        return candidate
    }

    static func candidate(from raw: String) -> SupervisorBigTaskCandidate? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16, !trimmed.hasPrefix("/") else { return nil }
        guard !trimmed.contains("job + initial plan"),
              !trimmed.contains("建成一个大任务") else { return nil }

        let normalized = trimmed.lowercased()
        let taskKeywords = [
            "做", "开发", "构建", "实现", "设计", "重构", "建立", "搭建",
            "系统", "平台", "网站", "应用", "app", "agent", "workflow",
            "自动化", "机器人", "功能", "项目", "架构"
        ]
        guard taskKeywords.contains(where: { keyword in
            trimmed.contains(keyword) || normalized.contains(keyword)
        }) else {
            return nil
        }

        let intentSignals = ["帮我", "请", "需要", "想要", "希望", "做一个", "实现一个", "搭一个", "做个"]
        guard intentSignals.contains(where: { signal in
            trimmed.contains(signal) || normalized.contains(signal)
        }) || trimmed.count >= 28 else {
            return nil
        }

        let fingerprint = normalized
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SupervisorBigTaskCandidate(goal: trimmed, fingerprint: fingerprint)
    }

    static func prompt(for candidate: SupervisorBigTaskCandidate) -> String {
        """
请把下面这件事建成一个大任务，并先给出 job + initial plan；如果还缺关键约束，只问我一个最关键的问题。

\(candidate.goal)
"""
    }
}
