import Foundation

struct XTAutomationRunLineage: Codable, Equatable, Sendable {
    var lineageID: String
    var rootRunID: String
    var parentRunID: String
    var retryDepth: Int

    init(
        lineageID: String,
        rootRunID: String,
        parentRunID: String = "",
        retryDepth: Int = 0
    ) {
        self.lineageID = lineageID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rootRunID = rootRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.parentRunID = parentRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.retryDepth = max(0, retryDepth)
    }

    func normalized(fallbackRunID: String) -> XTAutomationRunLineage {
        let fallback = fallbackRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedParent = parentRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRoot = rootRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (resolvedParent.isEmpty ? fallback : resolvedParent)
            : rootRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLineageID = lineageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? xtAutomationLineageID(forRootRunID: resolvedRoot)
            : lineageID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRetryDepth = max(0, retryDepth)
        return XTAutomationRunLineage(
            lineageID: resolvedLineageID,
            rootRunID: resolvedRoot,
            parentRunID: resolvedParent,
            retryDepth: resolvedRetryDepth
        )
    }

    func retryChild(parentRunID: String, retryDepth: Int? = nil) -> XTAutomationRunLineage {
        let normalizedParent = parentRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelf = normalized(fallbackRunID: normalizedParent)
        let nextDepth = max(1, retryDepth ?? (normalizedSelf.retryDepth + 1))
        return XTAutomationRunLineage(
            lineageID: normalizedSelf.lineageID,
            rootRunID: normalizedSelf.rootRunID,
            parentRunID: normalizedParent,
            retryDepth: nextDepth
        )
    }

    static func root(runID: String) -> XTAutomationRunLineage {
        let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
        return XTAutomationRunLineage(
            lineageID: xtAutomationLineageID(forRootRunID: normalizedRunID),
            rootRunID: normalizedRunID,
            parentRunID: "",
            retryDepth: 0
        )
    }
}

func xtAutomationResolvedLineage(
    _ lineage: XTAutomationRunLineage?,
    fallbackRunID: String
) -> XTAutomationRunLineage {
    guard let lineage else {
        return XTAutomationRunLineage.root(runID: fallbackRunID)
    }
    return lineage.normalized(fallbackRunID: fallbackRunID)
}

func xtAutomationLineageID(forRootRunID rootRunID: String) -> String {
    let normalizedRootRunID = rootRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    let uuidToken = oneShotDeterministicUUIDString(
        seed: "xt_auto_lineage|\(normalizedRootRunID)"
    )
    return "lineage-\(uuidToken)"
}
