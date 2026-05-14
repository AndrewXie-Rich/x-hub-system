import Foundation

struct XTDockSlashSuggestion: Identifiable, Equatable {
    var id: String { insertion }
    let title: String
    let subtitle: String
    let insertion: String
}

enum XTDockSlashSuggestionSupport {
    static func suggestions(
        for draft: String,
        models: [HubModel]
    ) -> [XTDockSlashSuggestion] {
        let lower = draft.lowercased()

        if lower == "/hub" || lower.hasPrefix("/hub ") {
            return filtered(
                [
                    XTDockSlashSuggestion(
                        title: "/hub route",
                        subtitle: "查看 Hub 传输模式",
                        insertion: "/hub route"
                    )
                ],
                matching: lower
            )
        }

        if lower == "/network" || lower.hasPrefix("/network ") {
            return filtered(
                [
                    XTDockSlashSuggestion(
                        title: "/network 30m",
                        subtitle: "申请网络访问",
                        insertion: "/network 30m"
                    )
                ],
                matching: lower
            )
        }

        if lower == "/model" || lower.hasPrefix("/model ") {
            let query = String(lower.dropFirst("/model".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var items = models
                .filter { $0.state == .loaded }
                .map { model in
                    XTDockSlashSuggestion(
                        title: "/model \(model.id)",
                        subtitle: model.backend,
                        insertion: "/model \(model.id)"
                    )
                }

            if query.isEmpty || "auto".hasPrefix(query) {
                items.insert(
                    XTDockSlashSuggestion(
                        title: "/model auto",
                        subtitle: "使用默认模型",
                        insertion: "/model auto"
                    ),
                    at: 0
                )
            }

            if !query.isEmpty {
                items = items.filter { suggestion in
                    suggestion.insertion.lowercased().contains(query)
                }
            }

            return items
        }

        let base: [XTDockSlashSuggestion] = [
            XTDockSlashSuggestion(title: "/models", subtitle: "查看当前可用模型", insertion: "/models"),
            XTDockSlashSuggestion(title: "/model <id>", subtitle: "切换当前项目模型", insertion: "/model "),
            XTDockSlashSuggestion(title: "/route diagnose", subtitle: "解释当前模型路由", insertion: "/route diagnose"),
            XTDockSlashSuggestion(title: "/tools", subtitle: "查看工具策略", insertion: "/tools"),
            XTDockSlashSuggestion(title: "/clear", subtitle: "清空当前聊天", insertion: "/clear"),
            XTDockSlashSuggestion(title: "/help", subtitle: "查看可用命令", insertion: "/help")
        ]

        if lower == "/" {
            return base
        }

        guard lower.hasPrefix("/") else { return [] }
        let query = String(lower.dropFirst())
        return base.filter { suggestion in
            suggestion.insertion.lowercased().contains(query)
                || suggestion.title.lowercased().contains(query)
        }
    }

    private static func filtered(
        _ suggestions: [XTDockSlashSuggestion],
        matching lower: String
    ) -> [XTDockSlashSuggestion] {
        let query = String(lower.dropFirst())
        guard !query.isEmpty else { return suggestions }
        return suggestions.filter { suggestion in
            suggestion.insertion.lowercased().contains(query)
                || suggestion.title.lowercased().contains(query)
        }
    }
}
