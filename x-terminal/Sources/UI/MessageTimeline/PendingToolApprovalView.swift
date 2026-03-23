import SwiftUI

/// 待审批工具调用的浮动卡片
struct PendingToolApprovalView: View {
    @ObservedObject var session: ChatSessionModel
    let hubConnected: Bool
    var isFocused: Bool = false
    var focusedRequestId: String? = nil
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
                    Text("待审批")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)

                    Text("\(session.pendingToolCalls.count) 个工具调用等待你确认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 8) {
                    Button {
                        onReject()
                    } label: {
                        Text("拒绝")
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
                            Text("批准并执行")
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

            Text(XTPendingApprovalPresentation.approvalFooterNote(callCount: session.pendingToolCalls.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            // 工具列表
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(session.pendingToolCalls) { call in
                            PendingToolCallChip(
                                toolCall: call,
                                isFocused: focusedRequestId == call.id
                            )
                            .id(call.id)
                        }
                    }
                }
                .onAppear {
                    scrollToFocusedRequestIfNeeded(using: proxy)
                }
                .onChange(of: focusedRequestId) { _ in
                    scrollToFocusedRequestIfNeeded(using: proxy)
                }
                .onChange(of: session.pendingToolCalls.map(\.id).joined(separator: ",")) { _ in
                    scrollToFocusedRequestIfNeeded(using: proxy)
                }
            }

            // 连接状态提示
            if !hubConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.red)
                    Text("Hub 未连接，连上后才能批准执行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFocused ? Color.orange.opacity(0.14) : Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.orange.opacity(0.65) : Color.orange.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: isFocused ? Color.orange.opacity(0.22) : .black.opacity(0.1), radius: isFocused ? 12 : 8, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func scrollToFocusedRequestIfNeeded(using proxy: ScrollViewProxy) {
        guard let focusedRequestId,
              session.pendingToolCalls.contains(where: { $0.id == focusedRequestId }) else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(focusedRequestId, anchor: .center)
            }
        }
    }
}

/// 单个待审批工具的芯片
struct PendingToolCallChip: View {
    let toolCall: ToolCall
    var isFocused: Bool = false
    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: XTPendingApprovalPresentation.iconName(for: toolCall.tool))
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(XTPendingApprovalPresentation.displayToolName(for: toolCall.tool))
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.medium)

                    Text(XTPendingApprovalPresentation.actionSummary(for: toolCall))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 220, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFocused ? Color.orange.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isFocused ? Color.orange.opacity(0.7) : Color.accentColor.opacity(0.3),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(color: isFocused ? Color.orange.opacity(0.18) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetails) {
            ToolCallDetailsPopover(
                toolCall: toolCall,
                message: XTPendingApprovalPresentation.approvalMessage(for: toolCall)
            )
        }
    }
}

/// 工具调用详情弹窗
struct ToolCallDetailsPopover: View {
    let toolCall: ToolCall
    let message: XTGuardrailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: XTPendingApprovalPresentation.iconName(for: toolCall.tool))
                    .foregroundColor(.accentColor)
                Text(XTPendingApprovalPresentation.displayToolName(for: toolCall.tool))
                    .font(.system(.headline, design: .rounded))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("即将执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(XTPendingApprovalPresentation.actionSummary(for: toolCall))
                    .font(.system(.body, design: .rounded))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("审批说明")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(message.summary)
                    .font(.system(.caption, design: .rounded))

                if let nextStep = message.nextStep,
                   !nextStep.isEmpty {
                    Text(nextStep)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // 参数
            if !toolCall.args.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("参数")
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
