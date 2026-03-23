import Foundation

enum SupervisorVoiceFingerprint {
    static func normalized(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )

        let sanitized = String(
            folded.unicodeScalars.map { scalar in
                if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                    return Character(String(scalar))
                }
                return " "
            }
        )

        return sanitized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    static func normalized(lines: [String]) -> String {
        lines
            .map(normalized)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
