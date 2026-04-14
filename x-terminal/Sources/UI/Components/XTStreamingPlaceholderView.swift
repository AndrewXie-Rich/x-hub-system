import SwiftUI

struct XTStreamingPlaceholderPresentation: Equatable {
    var title: String
    var detail: String?

    init(title: String = "准备回复", detail: String? = nil) {
        self.title = title
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum XTStreamingPlaceholderSupport {
    private enum Stage {
        case preparingReply
        case readingContext
        case executingTools
        case runningVerification
        case waitingForFirstToken
        case waitingForConfirmation

        var title: String {
            switch self {
            case .preparingReply:
                return "准备回复"
            case .readingContext:
                return "读取上下文"
            case .executingTools:
                return "执行工具"
            case .runningVerification:
                return "运行验证"
            case .waitingForFirstToken:
                return "等待首字"
            case .waitingForConfirmation:
                return "等待确认"
            }
        }
    }

    private static let contextHints = [
        "读取", "查看", "搜索", "项目目录", "项目文件", "当前上下文",
        "检查当前 Git 状态", "Git 状态", "改动差异", "会话状态",
        "记忆快照", "项目快照", "导入审计记录", "技能目录",
        "界面状态", "远端内容", "网页内容", "网络信息"
    ]

    private static let confirmationHints = [
        "等待确认", "安全点", "暂停验证", "暂停剩余工具", "申请联网"
    ]

    private static let verificationHints = [
        "跑一遍验证", "验证", "测试", "构建", "CI 状态", "CI 流程", "lint", "smoke"
    ]

    private static let planningHints = [
        "整理这一步的执行方案", "梳理下一步", "压缩会话上下文",
        "整理内容摘要", "索取仅 final 响应", "重规划"
    ]

    static func presentation(
        from raw: String?,
        fallbackTitle: String = Stage.preparingReply.title
    ) -> XTStreamingPlaceholderPresentation {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return XTStreamingPlaceholderPresentation(title: fallbackTitle, detail: nil)
        }

        let compact = compactDetail(from: trimmed)
        guard let stage = inferredStage(from: trimmed) else {
            return XTStreamingPlaceholderPresentation(title: fallbackTitle, detail: compact)
        }

        let detail = stageDetail(for: stage, raw: trimmed, compact: compact)
        return XTStreamingPlaceholderPresentation(
            title: stage.title,
            detail: normalizedDetail(for: stage, detail: detail)
        )
    }

    static func compactDetail(from raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let exactMatches: [String: String] = [
            "我先看一下项目目录。": "查看项目目录",
            "我先梳理下一步。": "梳理上下文",
            "我在读取当前上下文。": "读取当前上下文",
            "我在整理这一步的执行方案。": "整理答复",
            "我在压缩会话上下文。": "整理会话上下文",
            "我在整理内容摘要。": "整理摘要",
            "我在跑一遍验证。": "检查当前改动",
            "我在检查当前 Git 状态。": "查看 Git 状态",
            "我在查看当前改动差异。": "查看改动差异",
            "我在查看当前会话状态。": "查看会话状态",
            "我在检查 CI 状态。": "检查 CI",
            "我在触发 CI 流程。": "触发 CI",
            "我在执行当前工具步骤。": "推进当前步骤",
            "我在执行修正后的工具方案。": "应用修正方案",
            "我在申请联网能力。": "申请联网权限",
            "Supervisor 指导命中工具边界，先暂停剩余工具。": "等待继续指令",
            "Supervisor 指导要求先停机重规划，我先索取仅 final 响应。": "重整回复策略",
            "正在等待 Hub 返回首段输出。": "等待首字"
        ]
        if let exact = exactMatches[trimmed] {
            return exact
        }

        if let verificationCommand = verificationCommandDetail(from: trimmed) {
            return verificationCommand
        }

        if trimmed.contains("等待首段输出") || trimmed.contains("等待首字") {
            return "等待首字"
        }
        if trimmed.contains("准备正文") || trimmed.contains("准备首段输出") {
            return "模型预热中"
        }
        if trimmed.contains("仍在生成") {
            return "持续生成中"
        }
        if trimmed.contains("申请联网") {
            return "申请联网权限"
        }
        if trimmed.contains("暂停剩余工具") {
            return "等待继续指令"
        }

        var compact = trimmed
        if compact.hasPrefix("我在") {
            compact.removeFirst(2)
        } else if compact.hasPrefix("我先") {
            compact.removeFirst(2)
        }
        compact = trimmedSentence(compact)
        return compact.isEmpty ? nil : compact
    }

    private static func inferredStage(from trimmed: String) -> Stage? {
        if containsAny(trimmed, ["等待首段输出", "等待首字", "准备正文", "准备首段输出", "仍在生成"]) {
            return .waitingForFirstToken
        }
        if containsAny(trimmed, confirmationHints) {
            return .waitingForConfirmation
        }
        if containsAny(trimmed, verificationHints) || isLikelyVerificationCommand(trimmed) {
            return .runningVerification
        }
        if containsAny(trimmed, planningHints) {
            return .preparingReply
        }
        if containsAny(trimmed, contextHints) {
            return .readingContext
        }
        if trimmed.hasPrefix("我在") || trimmed.hasPrefix("我先") {
            return .executingTools
        }
        return nil
    }

    private static func stageDetail(
        for stage: Stage,
        raw: String,
        compact: String?
    ) -> String? {
        switch stage {
        case .preparingReply:
            if raw.contains("梳理下一步") {
                return nil
            }
            if raw.contains("压缩会话上下文") {
                return "整理会话上下文"
            }
            if raw.contains("索取仅 final 响应") || raw.contains("重规划") {
                return "重整回复策略"
            }
            return compact
        case .readingContext:
            return compact
        case .executingTools:
            return compact
        case .runningVerification:
            if let verificationCommand = verificationCommandDetail(from: raw) {
                return verificationCommand
            }
            if raw.contains("CI 状态") {
                return "检查 CI"
            }
            if raw.contains("CI 流程") {
                return "触发 CI"
            }
            return compact ?? "检查当前改动"
        case .waitingForFirstToken:
            if raw.contains("Hub 本地模型") {
                return "Hub 模型预热中"
            }
            if raw.contains("本机模型") {
                return "本机模型预热中"
            }
            if raw.contains("远端模型") || raw.contains("Hub 模型") {
                return "模型链路已接通"
            }
            if raw.contains("仍在生成") {
                return "模型仍在准备输出"
            }
            return nil
        case .waitingForConfirmation:
            if raw.contains("安全点") {
                return "到达安全点"
            }
            if raw.contains("暂停剩余工具") {
                return "等待继续指令"
            }
            if raw.contains("申请联网") {
                return "等待联网授权"
            }
            return compact
        }
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func normalizedDetail(for stage: Stage, detail: String?) -> String? {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        switch stage {
        case .preparingReply:
            if ["梳理上下文", "整理答复"].contains(trimmed) {
                return nil
            }
        case .readingContext:
            if trimmed == "读取当前上下文" {
                return nil
            }
        default:
            break
        }

        return trimmed
    }

    private static func trimmedSentence(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = out.last, "。.!！".contains(last) {
            out.removeLast()
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func verificationCommandDetail(from raw: String) -> String? {
        let trimmed = trimmedSentence(raw)
        for prefix in ["我在执行 ", "执行 "] {
            guard trimmed.hasPrefix(prefix) else { continue }
            let command = trimmedSentence(String(trimmed.dropFirst(prefix.count)))
            guard !command.isEmpty, isLikelyVerificationCommand(command) else { continue }
            return "运行 \(command)"
        }
        return nil
    }

    private static func isLikelyVerificationCommand(_ text: String) -> Bool {
        let lowered = " \(text.lowercased()) "
        let hints = [
            " swift test ", " swift build ", " xcodebuild ", " pytest ",
            " cargo test ", " cargo check ", " go test ", " npm test ",
            " npm run test ", " npm run build ", " pnpm test ", " pnpm build ",
            " yarn test ", " yarn build ", " bun test ", " bun run build ",
            " jest ", " vitest ", " rspec ", " phpunit ", " gradle test ",
            " ./gradlew test ", " ./gradlew build ", " mvn test ", " mvn verify ",
            " lint ", " smoke ", " verify ", " build ", " test "
        ]
        return hints.contains { lowered.contains($0) }
    }
}

struct XTStreamingPlaceholderView: View {
    let presentation: XTStreamingPlaceholderPresentation
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(presentation.title)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())

                ThinkingDotsView()

                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    placeholderLine(width: max(120, proxy.size.width * 0.72), delay: 0)
                    placeholderLine(width: max(96, proxy.size.width * 0.49), delay: 0.12)
                    placeholderLine(width: max(144, proxy.size.width * 0.61), delay: 0.24)
                }
            }
            .frame(height: 34)

            if let detail = presentation.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }

    private func placeholderLine(width: CGFloat, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(isAnimating ? 0.18 : 0.08))
            .frame(width: width, height: 8)
            .animation(
                .easeInOut(duration: 0.9)
                    .delay(delay)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
    }
}
