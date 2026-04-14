import SwiftUI

struct XTChatAttachmentStrip: View {
    let attachments: [AXChatAttachment]
    var showsPath: Bool = false
    var onRemove: ((AXChatAttachment) -> Void)? = nil
    var onImport: ((AXChatAttachment) -> Void)? = nil

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        XTChatAttachmentCapsule(
                            attachment: attachment,
                            showsPath: showsPath,
                            onRemove: onRemove.map { action in { action(attachment) } },
                            onImport: onImport.map { action in { action(attachment) } }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct XTChatContextDock: View {
    var activeIntent: XTChatComposerDropIntent? = nil
    var importEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Context Dock")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
                Text("拖到左侧先理解，拖到右侧进入项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                XTChatContextDockCard(
                    title: "问 AI",
                    subtitle: "只读理解，不改项目边界",
                    icon: "bubble.left.and.text.bubble.right.fill",
                    tint: .accentColor,
                    isActive: activeIntent == .attachReadOnly
                )

                XTChatContextDockCard(
                    title: "导入项目",
                    subtitle: importEnabled
                        ? "复制到工作区，之后可直接开发"
                        : "当前未选中项目，暂不可导入",
                    icon: "tray.and.arrow.down.fill",
                    tint: importEnabled ? Color.green : Color.secondary,
                    isActive: activeIntent == .importToProject && importEnabled,
                    isDisabled: !importEnabled
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
    }
}

struct XTChatProjectInboxPanel: View {
    let attachments: [AXChatAttachment]
    var title: String = "Project Inbox"
    var projectImportEnabled: Bool = true
    var continuation: AXChatImportContinuationSuggestion? = nil
    var onRemove: ((AXChatAttachment) -> Void)? = nil
    var onImport: ((AXChatAttachment) -> Void)? = nil
    var onImportAll: (() -> Void)? = nil
    var onContinue: (() -> Void)? = nil
    var onContinueAndSend: (() -> Void)? = nil
    var canContinueAndSend: Bool = false
    var onDismissContinuation: (() -> Void)? = nil

    private var externalAttachments: [AXChatAttachment] {
        attachments.filter(\.isReadOnlyExternal)
    }

    private var projectAttachments: [AXChatAttachment] {
        attachments.filter { !$0.isReadOnlyExternal }
    }

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(Color.green)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline.weight(.semibold))

                        Text(inboxSummaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if !externalAttachments.isEmpty {
                        Button("全部导入") {
                            onImportAll?()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!projectImportEnabled || onImportAll == nil)
                    }
                }

                if !externalAttachments.isEmpty {
                    XTChatInboxSectionLabel(
                        title: "待导入",
                        count: externalAttachments.count,
                        tint: .orange
                    )
                    XTChatAttachmentStrip(
                        attachments: externalAttachments,
                        showsPath: true,
                        onRemove: onRemove,
                        onImport: projectImportEnabled ? onImport : nil
                    )
                }

                if !projectAttachments.isEmpty {
                    XTChatInboxSectionLabel(
                        title: "已在项目内",
                        count: projectAttachments.count,
                        tint: .accentColor
                    )
                    XTChatAttachmentStrip(
                        attachments: projectAttachments,
                        showsPath: true,
                        onRemove: onRemove
                    )
                }

                if let continuation {
                    XTChatImportContinuationCard(
                        continuation: continuation,
                        onContinue: onContinue,
                        onContinueAndSend: onContinueAndSend,
                        canContinueAndSend: canContinueAndSend,
                        onDismiss: onDismissContinuation
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var inboxSummaryLine: String {
        if !externalAttachments.isEmpty {
            if projectImportEnabled {
                return "右侧拖入会直接复制到项目；左侧仍保留只读理解。"
            }
            return "当前项目不可导入，外部文件会先以只读附件保留。"
        }
        return "当前上下文中的文件已经进入项目工作区，可继续开发。"
    }
}

private struct XTChatContextDockCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var isActive: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(cardTint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardTint.opacity(isActive ? 0.18 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardTint.opacity(isActive ? 0.8 : 0.18), lineWidth: isActive ? 2 : 1)
        )
        .opacity(isDisabled ? 0.62 : 1)
    }

    private var cardTint: Color {
        isDisabled ? .secondary : tint
    }
}

private struct XTChatInboxSectionLabel: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.12))
                )

            Spacer(minLength: 0)
        }
    }
}

private struct XTChatImportContinuationCard: View {
    let continuation: AXChatImportContinuationSuggestion
    var onContinue: (() -> Void)? = nil
    var onContinueAndSend: (() -> Void)? = nil
    var canContinueAndSend: Bool = false
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(continuation.headline)
                        .font(.subheadline.weight(.semibold))
                    Text(continuation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 3) {
                    Text("下一步")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("请直接输入你希望 AI 基于这些已导入文件做什么；系统不会自动替你生成一条“阅读/梳理”请求。")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.82))
            )

            VStack(alignment: .leading, spacing: 8) {
                XTChatContinuationHintRow(
                    icon: "shippingbox.fill",
                    title: "建议落位",
                    text: continuation.placementHint
                )
                XTChatContinuationHintRow(
                    icon: "link.circle.fill",
                    title: "可能联动",
                    text: continuation.linkedFilesHint
                )
            }

            HStack(spacing: 8) {
                if let onContinueAndSend, canContinueAndSend {
                    Button("发送当前输入") {
                        onContinueAndSend()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if let onContinue {
                    Button("继续输入需求") {
                        onContinue()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(
                    canContinueAndSend
                        ? "只会发送你已经输入的内容，不会自动补一段请求。"
                        : "先在输入框里写明你的目标，再发送给 AI。"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct XTChatContinuationHintRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct XTChatAttachmentCapsule: View {
    let attachment: AXChatAttachment
    let showsPath: Bool
    let onRemove: (() -> Void)?
    let onImport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: attachment.kind == .directory ? "folder.fill" : "doc.text.fill")
                    .foregroundStyle(attachment.isReadOnlyExternal ? Color.orange : Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(attachment.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if showsPath {
                        Text(attachment.displayPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(attachment.scopeBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(attachment.isReadOnlyExternal ? Color.orange : Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((attachment.isReadOnlyExternal ? Color.orange : Color.accentColor).opacity(0.12))
                    )

                if let onImport, attachment.isReadOnlyExternal {
                    Button("导入项目") {
                        onImport()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let sizeBytes = attachment.sizeBytes, sizeBytes > 0, showsPath == false {
                Text("\(sizeBytes) bytes")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((attachment.isReadOnlyExternal ? Color.orange : Color.accentColor).opacity(0.18), lineWidth: 1)
        )
        .help(attachment.path)
    }
}
