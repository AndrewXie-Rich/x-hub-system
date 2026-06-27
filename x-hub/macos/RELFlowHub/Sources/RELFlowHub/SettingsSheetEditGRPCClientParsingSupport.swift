import SwiftUI
import AppKit
import RELFlowHubCore

extension EditGRPCClientSheet {
func parseList(_ text: String) -> [String] {
        let raw = text
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if raw.isEmpty { return [] }

        // De-dup while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            if seen.contains(s) { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }
}
