import SwiftUI

/// 消息搜索栏
struct MessageSearchBar: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool
    let onSearch: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 搜索图标
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16))

            // 搜索输入框
            TextField("搜索消息…", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    onSearch(searchText)
                }

            // 清除按钮
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    onSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            // 关闭搜索
            Button {
                searchText = ""
                isSearching = false
                isFocused = false
            } label: {
                Text("取消")
                    .font(.body)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1.5)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .onAppear {
            isFocused = true
        }
    }
}

/// 搜索结果高亮视图
struct HighlightedText: View {
    let text: String
    let searchText: String

    var body: some View {
        if searchText.isEmpty {
            Text(text)
        } else {
            highlightedText()
        }
    }

    private func highlightedText() -> Text {
        let parts = highlightedParts()
        return Text(parts.0)
            .foregroundColor(.primary)
        + Text(parts.1)
            .foregroundColor(.primary)
            .fontWeight(.bold)
            .underline()
        + Text(parts.2)
            .foregroundColor(.primary)
    }

    private func highlightedParts() -> (String, String, String) {
        let lowercased = text.lowercased()
        let searchLowercased = searchText.lowercased()

        if let range = lowercased.range(of: searchLowercased) {
            let before = String(text[..<range.lowerBound])
            let match = String(text[range])
            let after = String(text[range.upperBound...])
            return (before, match, after)
        }

        return (text, "", "")
    }
}

/// 消息过滤器
struct MessageFilter {
    enum FilterType {
        case all
        case user
        case assistant
        case tool
        case hasToolCalls
        case hasErrors
    }

    var type: FilterType = .all
    var searchText: String = ""
    var dateRange: ClosedRange<Date>?

    func matches(_ message: AXChatMessage) -> Bool {
        // 角色过滤
        switch type {
        case .all:
            break
        case .user:
            if message.role != .user { return false }
        case .assistant:
            if message.role != .assistant { return false }
        case .tool:
            if message.role != .tool { return false }
        case .hasToolCalls:
            if message.role != .assistant || !message.content.contains("tool_calls") {
                return false
            }
        case .hasErrors:
            if !message.content.lowercased().contains("error") {
                return false
            }
        }

        // 搜索文本过滤
        if !searchText.isEmpty {
            let lowercased = message.content.lowercased()
            let searchLowercased = searchText.lowercased()
            if !lowercased.contains(searchLowercased) {
                return false
            }
        }

        // 日期范围过滤
        if let range = dateRange {
            let messageDate = Date(timeIntervalSince1970: message.createdAt)
            if !range.contains(messageDate) {
                return false
            }
        }

        return true
    }
}

/// 消息过滤器选择器
struct MessageFilterPicker: View {
    @Binding var filter: MessageFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("筛选消息")
                .font(.headline)

            Divider()

            // 类型过滤
            VStack(alignment: .leading, spacing: 8) {
                Text("消息类型")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("类型", selection: $filter.type) {
                    Text("全部").tag(MessageFilter.FilterType.all)
                    Text("用户").tag(MessageFilter.FilterType.user)
                    Text("助手").tag(MessageFilter.FilterType.assistant)
                    Text("工具").tag(MessageFilter.FilterType.tool)
                    Text("含工具调用").tag(MessageFilter.FilterType.hasToolCalls)
                    Text("含错误").tag(MessageFilter.FilterType.hasErrors)
                }
                .pickerStyle(.menu)
            }

            Divider()

            // 重置按钮
            Button {
                filter = MessageFilter()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("重置筛选")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// 带搜索和过滤的消息时间线
struct EnhancedMessageTimelineView: View {
    let ctx: AXProjectContext
    @ObservedObject var session: ChatSessionModel

    @State private var isSearching = false
    @State private var searchText = ""
    @State private var filter = MessageFilter()
    @State private var showFilterPicker = false
    @Namespace private var bottomID

    private var filteredMessages: [AXChatMessage] {
        session.messages.filter { message in
            filter.matches(message)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 12) {
                // 搜索按钮
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isSearching.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(isSearching ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("搜索消息")

                // 过滤按钮
                Button {
                    showFilterPicker.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16))
                        .foregroundColor(filter.type != .all ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("筛选消息")
                .popover(isPresented: $showFilterPicker) {
                    MessageFilterPicker(filter: $filter)
                }

                Spacer()

                // 消息计数
                Text("\(filteredMessages.count) 条消息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            // 搜索栏
            if isSearching {
                MessageSearchBar(
                    searchText: $searchText,
                    isSearching: $isSearching,
                    onSearch: { text in
                        filter.searchText = text
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if filteredMessages.isEmpty {
                            EmptySearchResultView(
                                hasSearch: !searchText.isEmpty,
                                hasFilter: filter.type != .all
                            )
                        } else {
                            ForEach(filteredMessages) { message in
                                MessageCard(message: message)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }

                        // 加载指示器
                        if session.isSending {
                            ThinkingIndicator()
                                .transition(.opacity)
                        }

                        // 底部锚点
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(20)
                    .padding(.bottom, 120)
                }
                .onChange(of: session.messages.count) { _ in
                    if filter.type == .all && searchText.isEmpty {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: session.isSending) { sending in
                    if sending && filter.type == .all && searchText.isEmpty {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 空搜索结果视图
struct EmptySearchResultView: View {
    let hasSearch: Bool
    let hasFilter: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("没有找到消息")
                    .font(.headline)
                if hasSearch {
                    Text("试试别的搜索词")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if hasFilter {
                    Text("试试调整筛选条件")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
