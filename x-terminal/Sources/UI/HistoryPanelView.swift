import SwiftUI
import AppKit
import UserNotifications

struct HistoryPanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedMessage: AXChatMessage?
    @State private var showInsertOptions: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            isSelected: selectedMessage?.id == message.id,
                            onTap: { selectedMessage = message },
                            onCopy: { copyToClipboard(message) },
                            onInsert: {
                                selectedMessage = message
                                showInsertOptions = true
                            }
                        )
                    }
                }
                .padding(12)
            }
            
            if showInsertOptions, let message = selectedMessage {
                insertOptionsSheet(message: message)
            }
        }
        .frame(minWidth: 300, maxWidth: 400)
    }
    
    private var header: some View {
        HStack {
            Text("历史记录")
                .font(.headline)
            Spacer()
            Button("清空") {
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var messages: [AXChatMessage] {
        guard let ctx = appModel.projectContext else {
            return []
        }
        let session = appModel.session(for: ctx)
        return session.messages
    }
    
    private func copyToClipboard(_ message: AXChatMessage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)
        
        showCopiedNotification()
    }
    
    private func showCopiedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "已复制"
        content.body = "内容已复制到剪贴板"
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
    
    @ViewBuilder
    private func insertOptionsSheet(message: AXChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("将内容插入到：")
                .font(.headline)
            
            Button("插入到光标位置") {
                insertAtCursor(message.content)
                showInsertOptions = false
            }
            
            Button("添加到新文件") {
                addToNewFile(message.content)
                showInsertOptions = false
            }
            
            Button("取消") {
                showInsertOptions = false
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .shadow(radius: 10)
    }
    
    private func insertAtCursor(_ content: String) {
        guard let focusedElement = NSApp.keyWindow?.firstResponder else {
            return
        }
        
        if let textView = focusedElement as? NSTextView {
            textView.insertText(content, replacementRange: textView.selectedRange())
        } else if let textField = focusedElement as? NSTextField {
            textField.insertText(content)
        }
    }
    
    private func addToNewFile(_ content: String) {
        let savePanel = NSSavePanel()
        savePanel.title = "保存为新文件"
        savePanel.nameFieldStringValue = "新文件.txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct MessageRow: View {
    let message: AXChatMessage
    let isSelected: Bool
    let onTap: () -> Void
    let onCopy: () -> Void
    let onInsert: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            roleIndicator
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(3)
                
                HStack(spacing: 8) {
                    Button("复制") { onCopy() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    
                    Button("插入") { onInsert() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            onTap()
        }
    }
    
    private var roleIndicator: some View {
        Circle()
            .fill(roleColor)
            .frame(width: 8, height: 8)
    }
    
    private var roleColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .green
        case .tool:
            return .orange
        }
    }
}
