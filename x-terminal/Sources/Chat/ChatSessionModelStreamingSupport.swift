import Foundation

extension ChatSessionModel {
    func startToolStream(_ call: ToolCall) -> String? {
        guard shouldSurfaceSuccessfulToolResult(
            call: call,
            result: ToolResult(id: call.id, tool: call.tool, ok: true, output: "")
        ) else {
            return nil
        }
        let header = "[tool:\(call.tool.rawValue)] running..."
        let msg = AXChatMessage(role: .tool, content: header)
        messages.append(msg)
        toolStreamStates[msg.id] = ToolStreamState(header: header, display: "", truncated: false)
        return msg.id
    }

    func appendToolStream(id: String, chunk: String) {
        guard var st = toolStreamStates[id] else { return }
        st.display += chunk
        if st.display.count > toolStreamMaxChars {
            st.display = String(st.display.suffix(toolStreamMaxChars))
            st.truncated = true
        }
        toolStreamStates[id] = st
        pendingToolStreamContentByMessageID[id] = streamContent(for: st)
        scheduleToolStreamFlush(messageID: id)
    }

    func finishToolStream(id: String, result: ToolResult) {
        cancelPendingToolStreamFlush(messageID: id)
        let header = "[tool:\(result.tool.rawValue)] ok=\(result.ok)"
        let body = truncateOutput(result.output)
        updateMessage(id: id, content: header + "\n" + body)
        toolStreamStates[id] = nil
    }

    func finishToolStreamWithError(id: String, error: String) {
        cancelPendingToolStreamFlush(messageID: id)
        let header = "[tool:run_command] ok=false"
        updateMessage(id: id, content: header + "\n" + error)
        toolStreamStates[id] = nil
    }

    func updateMessage(id: String, content: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        guard messages[idx].content != content else { return }
        messages[idx].content = content
    }

    func appendAssistantProgress(assistantIndex: Int, line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard assistantIndex < messages.count else { return }

        let messageID = messages[assistantIndex].id
        guard !assistantVisibleStreamingMessageIDs.contains(messageID) else { return }
        var lines = pendingAssistantProgressLinesByMessageID[messageID]
            ?? assistantProgressLinesByMessageID[messageID]
            ?? []
        if lines.last != trimmed {
            lines.append(trimmed)
        }
        if lines.count > assistantProgressMaxLines {
            lines = Array(lines.suffix(assistantProgressMaxLines))
        }
        if assistantProgressLinesByMessageID[messageID] == nil,
           pendingAssistantProgressLinesByMessageID[messageID] == nil {
            applyAssistantProgressLines(lines, messageID: messageID)
            return
        }
        pendingAssistantProgressLinesByMessageID[messageID] = lines
        scheduleAssistantProgressFlush(messageID: messageID)
    }

    func clearAssistantProgress(assistantIndex: Int) {
        guard assistantIndex < messages.count else { return }
        clearAssistantProgress(messageID: messages[assistantIndex].id)
    }

    func streamVisibleAssistantText(assistantIndex: Int, content: String) {
        guard assistantIndex < messages.count else { return }
        let messageID = messages[assistantIndex].id
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty else { return }

        let hadProgressLines = assistantProgressLinesByMessageID[messageID] != nil
        let wasVisibleStreaming = assistantVisibleStreamingMessageIDs.contains(messageID)
        assistantProgressLinesByMessageID[messageID] = nil
        cancelPendingAssistantProgressFlush(messageID: messageID)
        assistantVisibleStreamingMessageIDs.insert(messageID)
        if hadProgressLines || !wasVisibleStreaming {
            bumpMessageTimelinePresentationVersion()
        }
        pendingAssistantStreamTextByMessageID[messageID] = normalized
        scheduleAssistantStreamFlush(messageID: messageID)
    }

    func scheduleAssistantProgressFlush(messageID: String) {
        guard assistantProgressFlushTasksByMessageID[messageID] == nil else { return }
        let delay = assistantProgressFlushIntervalNanos
        assistantProgressFlushTasksByMessageID[messageID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            self?.flushPendingAssistantProgress(messageID: messageID)
        }
    }

    func flushPendingAssistantProgress(messageID: String) {
        assistantProgressFlushTasksByMessageID[messageID] = nil
        guard let lines = pendingAssistantProgressLinesByMessageID.removeValue(forKey: messageID) else {
            return
        }
        XTPerformanceTrace.event(
            "chat_progress_flush",
            "lines=\(lines.count)"
        )
        applyAssistantProgressLines(lines, messageID: messageID)
    }

    func applyAssistantProgressLines(
        _ lines: [String],
        messageID: String
    ) {
        let normalized = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if normalized.isEmpty {
            if assistantProgressLinesByMessageID.removeValue(forKey: messageID) != nil {
                bumpMessageTimelinePresentationVersion()
            }
            return
        }
        guard assistantProgressLinesByMessageID[messageID] != normalized else { return }
        assistantProgressLinesByMessageID[messageID] = normalized
        bumpMessageTimelinePresentationVersion()
    }

    func clearAssistantProgress(messageID: String) {
        cancelPendingAssistantProgressFlush(messageID: messageID)
        if assistantProgressLinesByMessageID.removeValue(forKey: messageID) != nil {
            bumpMessageTimelinePresentationVersion()
        }
    }

    func cancelPendingAssistantProgressFlush(messageID: String) {
        assistantProgressFlushTasksByMessageID[messageID]?.cancel()
        assistantProgressFlushTasksByMessageID[messageID] = nil
        pendingAssistantProgressLinesByMessageID[messageID] = nil
    }

    func scheduleAssistantStreamFlush(messageID: String) {
        guard assistantStreamFlushTasksByMessageID[messageID] == nil else { return }
        let byteCount = pendingAssistantStreamTextByMessageID[messageID]?.utf8.count ?? 0
        let delay = ChatStreamingUIFlushCadence.delayNanoseconds(
            forContentByteCount: byteCount
        )
        assistantStreamFlushTasksByMessageID[messageID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            self?.flushPendingAssistantStreamText(messageID: messageID)
        }
    }

    func flushPendingAssistantStreamText(messageID: String) {
        assistantStreamFlushTasksByMessageID[messageID] = nil
        guard let normalized = pendingAssistantStreamTextByMessageID.removeValue(forKey: messageID) else {
            return
        }
        XTPerformanceTrace.event(
            "chat_stream_flush",
            "kind=assistant bytes=\(normalized.utf8.count)"
        )
        updateMessage(id: messageID, content: normalized)
    }

    func cancelPendingAssistantStreamFlush(messageID: String) {
        assistantStreamFlushTasksByMessageID[messageID]?.cancel()
        assistantStreamFlushTasksByMessageID[messageID] = nil
        pendingAssistantStreamTextByMessageID[messageID] = nil
    }

    func scheduleToolStreamFlush(messageID: String) {
        guard toolStreamFlushTasksByMessageID[messageID] == nil else { return }
        let byteCount = pendingToolStreamContentByMessageID[messageID]?.utf8.count ?? 0
        let delay = ChatStreamingUIFlushCadence.delayNanoseconds(
            forContentByteCount: byteCount
        )
        toolStreamFlushTasksByMessageID[messageID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            self?.flushPendingToolStreamContent(messageID: messageID)
        }
    }

    func flushPendingToolStreamContent(messageID: String) {
        toolStreamFlushTasksByMessageID[messageID] = nil
        guard let content = pendingToolStreamContentByMessageID.removeValue(forKey: messageID) else {
            return
        }
        XTPerformanceTrace.event(
            "chat_stream_flush",
            "kind=tool bytes=\(content.utf8.count)"
        )
        updateMessage(id: messageID, content: content)
    }

    func cancelPendingToolStreamFlush(messageID: String) {
        toolStreamFlushTasksByMessageID[messageID]?.cancel()
        toolStreamFlushTasksByMessageID[messageID] = nil
        pendingToolStreamContentByMessageID[messageID] = nil
    }

    func clearStreamingPresentationState() {
        for task in assistantStreamFlushTasksByMessageID.values {
            task.cancel()
        }
        for task in toolStreamFlushTasksByMessageID.values {
            task.cancel()
        }
        for task in assistantProgressFlushTasksByMessageID.values {
            task.cancel()
        }
        assistantStreamFlushTasksByMessageID = [:]
        toolStreamFlushTasksByMessageID = [:]
        assistantProgressFlushTasksByMessageID = [:]
        pendingAssistantStreamTextByMessageID = [:]
        pendingToolStreamContentByMessageID = [:]
        pendingAssistantProgressLinesByMessageID = [:]
        toolStreamStates = [:]
        let shouldBumpPresentationVersion = !assistantProgressLinesByMessageID.isEmpty
            || !assistantVisibleStreamingMessageIDs.isEmpty
        assistantProgressLinesByMessageID = [:]
        assistantVisibleStreamingMessageIDs = []
        if shouldBumpPresentationVersion {
            bumpMessageTimelinePresentationVersion()
        }
    }

    func assistantProgressLine(for call: ToolCall) -> String {
        switch call.tool {
        case .list_dir:
            return "我先看一下项目目录。"
        case .read_file:
            let path = strArgValue(call.args["path"])
            return path.isEmpty ? "我在读取项目文件。" : "我在读取 \(path)。"
        case .write_file:
            let path = strArgValue(call.args["path"])
            return path.isEmpty ? "我在写入文件。" : "我在写入 \(path)。"
        case .delete_path:
            let path = strArgValue(call.args["path"])
            return path.isEmpty ? "我在删除目标路径。" : "我在删除 \(path)。"
        case .move_path:
            let from = strArgValue(call.args["from"])
            let to = strArgValue(call.args["to"])
            if from.isEmpty && to.isEmpty {
                return "我在移动目标路径。"
            }
            if to.isEmpty {
                return "我在移动 \(from)。"
            }
            return "我在把 \(from.isEmpty ? "目标路径" : from) 移动到 \(to)。"
        case .search:
            return "我在搜索相关文件和内容。"
        case .run_command:
            let command = strArgValue(call.args["command"])
            return command.isEmpty
                ? "我在执行命令。"
                : "我在执行 \(truncateProgressToken(command, max: 48))。"
        case .process_start:
            let name = strArgValue(call.args["name"])
            let command = strArgValue(call.args["command"])
            if !name.isEmpty {
                return "我在启动托管进程 \(name)。"
            }
            return command.isEmpty
                ? "我在启动托管进程。"
                : "我在启动托管进程 \(truncateProgressToken(command, max: 48))。"
        case .process_status:
            let processId = strArgValue(call.args["process_id"])
            return processId.isEmpty
                ? "我在检查托管进程状态。"
                : "我在检查托管进程 \(truncateProgressToken(processId, max: 36)) 的状态。"
        case .process_logs:
            let processId = strArgValue(call.args["process_id"])
            return processId.isEmpty
                ? "我在读取托管进程日志。"
                : "我在读取托管进程 \(truncateProgressToken(processId, max: 36)) 的日志。"
        case .process_stop:
            let processId = strArgValue(call.args["process_id"])
            return processId.isEmpty
                ? "我在停止托管进程。"
                : "我在停止托管进程 \(truncateProgressToken(processId, max: 36))。"
        case .git_status:
            return "我在检查当前 Git 状态。"
        case .git_diff:
            return "我在查看当前改动差异。"
        case .git_commit:
            return "我在提交当前改动。"
        case .git_push:
            return "我在推送当前分支。"
        case .git_apply, .git_apply_check:
            return "我在应用代码改动。"
        case .projectDiagnostics, .lspDiagnostics, .checkRun, .buildRun, .testRun:
            return "我在运行项目诊断。"
        case .pr_create:
            return "我在创建 Pull Request。"
        case .ci_read:
            return "我在检查 CI 状态。"
        case .ci_trigger:
            return "我在触发 CI 流程。"
        case .session_list:
            return "我在查看当前会话状态。"
        case .session_resume:
            return "我在恢复当前会话。"
        case .session_compact:
            return "我在压缩会话上下文。"
        case .agentImportRecord:
            let stagingId = strArgValue(call.args["staging_id"])
            return stagingId.isEmpty
                ? "我在读取 Hub 导入审计记录。"
                : "我在读取 Hub 导入审计记录 \(truncateProgressToken(stagingId, max: 36))。"
        case .memory_snapshot:
            return "我在整理记忆快照。"
        case .project_snapshot:
            return "我在整理项目快照。"
        case .deviceUIObserve:
            return "我在查看界面状态。"
        case .deviceUIAct, .deviceUIStep:
            return "我在推进界面操作流程。"
        case .deviceClipboardRead, .deviceClipboardWrite:
            return "我在处理剪贴板内容。"
        case .deviceScreenCapture:
            return "我在抓取当前屏幕。"
        case .deviceBrowserControl:
            if browserControlUsesSecretVault(call) {
                return "我在通过 Secret Vault 填充浏览器字段。"
            }
            return "我在操作浏览器。"
        case .deviceAppleScript:
            return "我在运行 AppleScript 自动化。"
        case .need_network:
            return "我在申请联网能力。"
        case .bridge_status:
            return "我在检查 Bridge 状态。"
        case .skills_search:
            return "我在查询技能目录。"
        case .skills_pin:
            return "我在固定技能依赖。"
        case .skillsExecuteRunner:
            return "我在通过 Hub 审批链执行技能 Runner。"
        case .summarize:
            return "我在整理内容摘要。"
        case .supervisorVoicePlayback:
            return "我在处理 Supervisor 的语音播放。"
        case .run_local_task:
            switch call.args["task_kind"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "embedding":
                return "我在生成向量嵌入。"
            case "speech_to_text":
                return "我在转写音频内容。"
            case "text_to_speech":
                return "我在合成本地语音。"
            case "vision_understand":
                return "我在理解图片内容。"
            case "ocr":
                return "我在提取图片里的文字。"
            default:
                return "我在执行本地模型任务。"
            }
        case .web_fetch, .browser_read:
            return "我在读取远端内容。"
        case .web_search:
            return "我在搜索网络信息。"
        }
    }

    func strArgValue(_ value: JSONValue?) -> String {
        guard case .string(let s)? = value else { return "" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func browserControlUsesSecretVault(_ call: ToolCall) -> Bool {
        guard call.tool == .deviceBrowserControl else { return false }
        let action = strArgValue(call.args["action"]).lowercased()
        guard action == "type" else { return false }
        let secretTokens = [
            strArgValue(call.args["secret_item_id"]),
            strArgValue(call.args["secret_scope"]),
            strArgValue(call.args["secret_name"])
        ]
        return secretTokens.contains { !$0.isEmpty }
    }

    func truncateProgressToken(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max)
        return String(trimmed[..<end]) + "..."
    }

    func streamContent(for st: ToolStreamState) -> String {
        let notice = st.truncated ? "[output truncated]\n" : ""
        if st.display.isEmpty {
            return st.header + "\n" + notice
        }
        return st.header + "\n" + notice + st.display
    }

    func truncateOutput(_ s: String) -> String {
        if s.count <= toolStreamMaxChars { return s }
        let suffix = String(s.suffix(toolStreamMaxChars))
        return "[output truncated]\n" + suffix
    }

    func visibleAssistantTextCandidate(
        from raw: String,
        mode: VisibleLLMStreamMode
    ) -> String? {
        guard mode != .none else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch mode {
        case .none:
            return nil
        case .finalOrPlainText:
            if let first = firstNonWhitespaceCharacter(in: raw), first == "{" || first == "[" {
                if let final = partialJSONStringValue(forKey: "final", in: raw) {
                    return final
                }
                return nil
            }
            return raw
        }
    }

    func firstNonWhitespaceCharacter(in text: String) -> Character? {
        text.first { !$0.isWhitespace }
    }

    func partialJSONStringValue(forKey key: String, in raw: String) -> String? {
        guard let keyRange = raw.range(of: "\"\(key)\"") else { return nil }
        var index = keyRange.upperBound

        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        guard index < raw.endIndex, raw[index] == ":" else { return nil }
        index = raw.index(after: index)

        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        guard index < raw.endIndex, raw[index] == "\"" else { return nil }
        index = raw.index(after: index)

        var output = ""
        while index < raw.endIndex {
            let ch = raw[index]
            if ch == "\"" {
                return output
            }
            if ch == "\\" {
                let next = raw.index(after: index)
                guard next < raw.endIndex else { break }
                let escaped = raw[next]
                var consumedIndex = next
                switch escaped {
                case "\"":
                    output.append("\"")
                case "\\":
                    output.append("\\")
                case "/":
                    output.append("/")
                case "b":
                    output.append("\u{08}")
                case "f":
                    output.append("\u{0C}")
                case "n":
                    output.append("\n")
                case "r":
                    output.append("\r")
                case "t":
                    output.append("\t")
                case "u":
                    let hexStart = raw.index(after: next)
                    guard let hexEnd = raw.index(hexStart, offsetBy: 4, limitedBy: raw.endIndex),
                          raw.distance(from: hexStart, to: hexEnd) == 4 else {
                        return output
                    }
                    let hex = String(raw[hexStart..<hexEnd])
                    if let scalarValue = UInt32(hex, radix: 16),
                       let scalar = UnicodeScalar(scalarValue) {
                        output.unicodeScalars.append(scalar)
                    }
                    consumedIndex = raw.index(before: hexEnd)
                default:
                    output.append(escaped)
                }
                index = raw.index(after: consumedIndex)
                continue
            }

            output.append(ch)
            index = raw.index(after: index)
        }

        return output
    }
}
