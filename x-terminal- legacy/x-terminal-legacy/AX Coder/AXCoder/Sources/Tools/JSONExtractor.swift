import Foundation

enum JSONExtractor {
    // Extract the first top-level JSON object or array from a string.
    // This is intentionally forgiving because some models may prepend extra text.
    static func extractFirstJSON(from text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }

        let open = text[start]
        let close: Character = (open == "{") ? "}" : "]"

        var i = start
        var depth = 0
        var inString = false
        var escape = false

        while i < text.endIndex {
            let ch = text[i]

            if inString {
                if escape {
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == open {
                    depth += 1
                } else if ch == close {
                    depth -= 1
                    if depth == 0 {
                        let end = text.index(after: i)
                        return String(text[start..<end])
                    }
                } else if ch == "{" && open == "[" {
                    // nested objects inside array are fine; tracked by depth on '[' only.
                } else if ch == "[" && open == "{" {
                    // nested arrays inside object are fine; tracked by depth on '{' only.
                }
            }

            i = text.index(after: i)
        }

        return nil
    }
}
