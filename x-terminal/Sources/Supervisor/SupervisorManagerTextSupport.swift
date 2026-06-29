import Foundation

extension SupervisorManager {
    func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    func normalizedContainsAny(_ normalized: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            normalized.contains(normalizedLookupKey(needle))
        }
    }

    func capped(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "…"
    }
}
