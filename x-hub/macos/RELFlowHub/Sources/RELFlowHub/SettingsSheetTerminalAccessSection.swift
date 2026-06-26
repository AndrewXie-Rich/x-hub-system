import SwiftUI

extension SettingsSheetView {
    var terminalAccessSection: some View {
        Section("普通 Terminal Access Key + URL") {
            VStack(alignment: .leading, spacing: 10) {
                terminalAccessOverviewHero

                DisclosureGroup(isExpanded: $terminalAccessIssueExpanded) {
                    terminalAccessIssueCard
                        .padding(.top, 6)
                } label: {
                    settingsInlineDisclosureLabel(
                        systemName: "key.badge.plus",
                        title: "签发新 Terminal Access Key",
                        summary: terminalAccessDraftSummaryText,
                        badge: terminalAccessIssueExpanded ? "编辑中" : "签发面板",
                        tint: .orange,
                        isExpanded: terminalAccessIssueExpanded
                    )
                }

                if let lastSecret = terminalAccessLastSecret {
                    DisclosureGroup(isExpanded: $terminalAccessLastSecretExpanded) {
                        terminalAccessLastSecretCard(lastSecret)
                            .padding(.top, 6)
                    } label: {
                        settingsInlineDisclosureLabel(
                            systemName: "key.radiowaves.forward",
                            title: "最近签发 / 轮换的 Secret",
                            summary: terminalAccessLastSecretSummaryText(lastSecret),
                            badge: terminalAccessLastSecretExpanded ? "已展开" : "待分发",
                            tint: .teal,
                            isExpanded: terminalAccessLastSecretExpanded
                        )
                    }
                }

                if !terminalAccessActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    terminalAccessFeedbackBanner(
                        text: terminalAccessActionText,
                        tint: .blue,
                        systemName: "checkmark.seal"
                    )
                }

                if !terminalAccessErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    terminalAccessFeedbackBanner(
                        text: terminalAccessErrorText,
                        tint: .red,
                        systemName: "exclamationmark.triangle"
                    )
                }

                if terminalAccessSortedKeys.isEmpty {
                    Text("当前还没有给普通 terminal 签发 access key。签发后这里会直接展示 URL、额度、今日用量、轮换次数和导出模板。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(terminalAccessSortedKeys) { accessKey in
                        terminalAccessKeyCard(accessKey)
                    }
                }
            }
            .confirmationDialog(
                "确认撤销普通 terminal access key",
                isPresented: terminalAccessRevokeDialogPresented,
                titleVisibility: .visible
            ) {
                if let accessKey = terminalAccessPendingRevokeAccessKey {
                    Button("撤销", role: .destructive) {
                        Task { await revokeTerminalAccessKey(accessKey) }
                    }
                }
                Button("取消", role: .cancel) {
                    terminalAccessPendingRevokeAccessKeyID = ""
                }
            } message: {
                if let accessKey = terminalAccessPendingRevokeAccessKey {
                    Text("撤销后，现有的 `OPENAI_API_KEY` 会立即失效。目标：\(accessKey.resolvedName)")
                } else {
                    Text("撤销后，这把普通 terminal access key 将不能继续访问 Hub。")
                }
            }
        }
        .id(terminalAccessSectionAnchorID)
    }
}
