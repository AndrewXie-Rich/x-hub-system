import Foundation

/// Tool Call 解析器，从 Assistant 消息中提取结构化的 tool calls
enum ToolCallParser {

    /// 从消息内容中解析 tool calls 和文本
    static func parse(_ content: String) -> ParsedContent {
        var parts: [ParsedPart] = []

        // 尝试解析 JSON 格式的 tool_calls
        if let toolCalls = extractToolCalls(from: content) {
            // 如果成功解析到 tool calls，添加它们
            for call in toolCalls {
                parts.append(.toolCall(call))
            }

            // 提取 final 文本（如果有）
            if let finalText = extractFinalText(from: content) {
                parts.append(.text(finalText))
            }
        } else {
            // 没有 tool calls，纯文本
            if !content.isEmpty {
                parts.append(.text(content))
            }
        }

        return ParsedContent(parts: parts)
    }

    /// 从内容中提取 tool calls
    private static func extractToolCalls(from content: String) -> [ToolCall]? {
        // 尝试多种格式

        // 格式 1: JSON 格式的 ToolActionEnvelope
        if let envelope = try? JSONDecoder().decode(ToolActionEnvelope.self, from: content.data(using: .utf8) ?? Data()) {
            return envelope.tool_calls
        }

        // 格式 2: 查找 JSON 块
        if let jsonRange = findJSONBlock(in: content) {
            let jsonString = String(content[jsonRange])
            if let envelope = try? JSONDecoder().decode(ToolActionEnvelope.self, from: jsonString.data(using: .utf8) ?? Data()) {
                return envelope.tool_calls
            }
        }

        // 格式 3: 查找 tool_calls 数组
        if let toolCallsArray = extractToolCallsArray(from: content) {
            return toolCallsArray
        }

        return nil
    }

    /// 从内容中提取 final 文本
    private static func extractFinalText(from content: String) -> String? {
        // 尝试解析 JSON 并提取 final 字段
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let final = json["final"] as? String,
           !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return final
        }

        return nil
    }

    /// 查找 JSON 块
    private static func findJSONBlock(in content: String) -> Range<String.Index>? {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start < end else {
            return nil
        }
        return start..<content.index(after: end)
    }

    /// 提取 tool_calls 数组
    private static func extractToolCallsArray(from content: String) -> [ToolCall]? {
        // 查找 "tool_calls": [...] 模式
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolCallsData = json["tool_calls"],
              let toolCallsJSON = try? JSONSerialization.data(withJSONObject: toolCallsData) else {
            return nil
        }

        return try? JSONDecoder().decode([ToolCall].self, from: toolCallsJSON)
    }
}

/// 解析后的内容
struct ParsedContent {
    let parts: [ParsedPart]

    var isEmpty: Bool {
        parts.isEmpty
    }
}

/// 解析后的部分
enum ParsedPart: Identifiable {
    case text(String)
    case toolCall(ToolCall)
    case thinking(String)

    var id: String {
        switch self {
        case .text(let content):
            return "text_\(content.prefix(50).hashValue)"
        case .toolCall(let call):
            return "tool_\(call.id)"
        case .thinking(let content):
            return "thinking_\(content.prefix(50).hashValue)"
        }
    }
}

/// Tool Result 解析器
enum ToolResultParser {

    /// 从 tool 消息中解析 result
    static func parse(_ content: String) -> ToolResult? {
        // 尝试直接解析 ToolResult JSON
        if let data = content.data(using: .utf8),
           let result = try? JSONDecoder().decode(ToolResult.self, from: data) {
            return result
        }

        // 尝试从 JSON 对象中提取
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            let id = json["id"] as? String ?? UUID().uuidString
            let toolName = json["tool"] as? String ?? "unknown"
            let ok = json["ok"] as? Bool ?? true
            let output = json["output"] as? String ?? content

            if let tool = ToolName(rawValue: toolName) {
                return ToolResult(id: id, tool: tool, ok: ok, output: output)
            }
        }

        return nil
    }
}
