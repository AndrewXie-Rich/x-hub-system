import Foundation

enum TokenEstimator {
    // Rough heuristic for mixed English/Chinese. This is *not* model-tokenizer accurate.
    // It's meant for budgeting / trends until the runtime returns real token counts.
    static func estimateTokens(_ text: String) -> Int {
        if text.isEmpty { return 0 }

        var asciiCount = 0
        var nonAsciiCount = 0
        for u in text.unicodeScalars {
            if u.isASCII {
                asciiCount += 1
            } else {
                nonAsciiCount += 1
            }
        }

        // Heuristic: ~4 ASCII chars per token, ~1.5 non-ASCII chars per token.
        let asciiTokens = Int(ceil(Double(asciiCount) / 4.0))
        let nonAsciiTokens = Int(ceil(Double(nonAsciiCount) / 1.5))
        return max(0, asciiTokens + nonAsciiTokens)
    }
}
