import SwiftUI

/// 待审批工具调用的浮动卡片
struct PendingToolApprovalView: View {
    @ObservedObject var session: ChatSessionModel
    let hubConnected: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头部
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending Approval")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)

                    Text("\(session.pendingToolCalls.count) tool call(s) require your approval")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 8) {
                    Button {
                        onReject()
                    } label: {
                        Text("Reject")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onApprove()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Approve & Run")
                        }
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .green.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hubConnected)
                }
            }

            Divider()

            // 工具列表
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(session.pendingToolCalls) { call in
                        PendingToolCallChip(toolCall: call)
                    }
                }
            }

            // 连接状态提示
            if !hubConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.red)
                    Text("Hub not connected. Please connect to approve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

/// 单个待审批工具的芯片
struct PendingToolCallChip: View {
    let toolCall: ToolCall
    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: toolIcon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(toolCall.tool.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)

                    if let summary = toolSummary {
                        Text(summary)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails) {
            ToolCallDetailsPopover(toolCall: toolCall)
        }
    }

    private var toolIcon: String {
        switch toolCall.tool {
        case .read_file:
            return "doc.text"
        case .write_file:
            return "pencil"
        case .list_dir:
            return "folder"
        case .search:
            return "magnifyingglass"
        case .skills_search:
            return "magnifyingglass"
        case .summarize:
            return "text.alignleft"
        case .run_command:
            return "terminal"
        case .git_status, .git_diff, .git_apply_check, .git_apply:
            return "arrow.triangle.branch"
        case .session_list:
            return "list.bullet.rectangle"
        case .session_resume:
            return "play.circle"
        case .session_compact:
            return "archivebox"
        case .agentImportRecord:
            return "checklist"
        case .memory_snapshot:
            return "memorychip"
        case .project_snapshot:
            return "folder.badge.gearshape"
        case .deviceUIObserve:
            return "eye"
        case .deviceUIAct:
            return "hand.tap"
        case .deviceUIStep:
            return "point.3.connected.trianglepath.dotted"
        case .deviceClipboardRead, .deviceClipboardWrite:
            return "list.clipboard"
        case .deviceScreenCapture:
            return "camera.viewfinder"
        case .deviceBrowserControl:
            return "safari"
        case .deviceAppleScript:
            return "apple.logo"
        case .need_network, .bridge_status, .web_fetch, .web_search, .browser_read:
            return "network"

        }
    }

    private var toolSummary: String? {
        switch toolCall.tool {
        case .read_file, .write_file:
            if case .string(let path)? = toolCall.args["path"] {
                return path.split(separator: "/").last.map(String.init)
            }
        case .run_command:
            if case .string(let cmd)? = toolCall.args["command"] {
                return String(cmd.prefix(30))
            }
        case .search:
            if case .string(let pattern)? = toolCall.args["pattern"] {
                return pattern
            }
        case .session_resume, .session_compact:
            if case .string(let sessionID)? = toolCall.args["session_id"] {
                return sessionID
            }
        case .agentImportRecord:
            if case .string(let stagingID)? = toolCall.args["staging_id"] {
                return stagingID
            }
        case .memory_snapshot:
            if case .string(let mode)? = toolCall.args["mode"] {
                return mode
            }
        case .skills_search:
            if case .string(let query)? = toolCall.args["query"] {
                return query
            }
        case .web_search:
            if case .string(let query)? = toolCall.args["query"] {
                return query
            }
        case .summarize:
            if case .string(let url)? = toolCall.args["url"] {
                return url
            }
            if case .string(let path)? = toolCall.args["path"] {
                return path
            }
            if case .string(let text)? = toolCall.args["text"] {
                return String(text.prefix(72))
            }
        case .browser_read, .web_fetch:
            if case .string(let url)? = toolCall.args["url"] {
                return url
            }
        default:
            break
        }
        return nil
    }
}

/// 工具调用详情弹窗
struct ToolCallDetailsPopover: View {
    let toolCall: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: toolIcon)
                    .foregroundColor(.accentColor)
                Text(toolCall.tool.rawValue)
                    .font(.system(.headline, design: .monospaced))
            }

            Divider()

            // 参数
            if !toolCall.args.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Arguments:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(toolCall.args.keys.sorted()), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text(formatArgValue(toolCall.args[key]))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    private var toolIcon: String {
        switch toolCall.tool {
        case .read_file:
            return "doc.text"
        case .write_file:
            return "pencil"
        case .list_dir:
            return "folder"
        case .search:
            return "magnifyingglass"
        case .skills_search:
            return "magnifyingglass"
        case .summarize:
            return "text.alignleft"
        case .run_command:
            return "terminal"
        case .git_status, .git_diff, .git_apply_check, .git_apply:
            return "arrow.triangle.branch"
        case .session_list:
            return "list.bullet.rectangle"
        case .session_resume:
            return "play.circle"
        case .session_compact:
            return "archivebox"
        case .agentImportRecord:
            return "checklist"
        case .memory_snapshot:
            return "memorychip"
        case .project_snapshot:
            return "folder.badge.gearshape"
        case .deviceUIObserve:
            return "eye"
        case .deviceUIAct:
            return "hand.tap"
        case .deviceUIStep:
            return "point.3.connected.trianglepath.dotted"
        case .deviceClipboardRead, .deviceClipboardWrite:
            return "list.clipboard"
        case .deviceScreenCapture:
            return "camera.viewfinder"
        case .deviceBrowserControl:
            return "safari"
        case .deviceAppleScript:
            return "apple.logo"
        case .need_network, .bridge_status, .web_fetch, .web_search, .browser_read:
            return "network"

        }
    }

    private func formatArgValue(_ value: JSONValue?) -> String {
        guard let value = value else { return "null" }

        switch value {
        case .string(let s):
            return s
        case .number(let n):
            return String(n)
        case .bool(let b):
            return String(b)
        case .null:
            return "null"
        case .array(let arr):
            return arr.map { formatArgValue($0) }.joined(separator: ", ")
        case .object(let obj):
            return obj.map { "\($0.key): \(formatArgValue($0.value))" }.joined(separator: "\n")
        }
    }
}
