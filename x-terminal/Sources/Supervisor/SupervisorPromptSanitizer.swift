import Foundation

func sanitizeSupervisorOutboundPrompt(_ text: String) -> String {
    sanitizeSupervisorPromptIdentifiers(text)
}

func sanitizeSupervisorPromptIdentifiers(_ text: String) -> String {
    var output = text
    output = replaceSupervisorPromptPattern(
        output,
        pattern: #"(?i)\b([0-9a-f]{8})-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
        template: "id:$1"
    )
    output = replaceSupervisorPromptPattern(
        output,
        pattern: #"(?i)\b([0-9a-f]{8})[0-9a-f]{24,120}\b"#,
        template: "hex:$1"
    )
    return output
}

private func replaceSupervisorPromptPattern(
    _ text: String,
    pattern: String,
    template: String
) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return text
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
}
