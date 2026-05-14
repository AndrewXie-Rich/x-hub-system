import Foundation

struct XTPathScopeViolation: Error, Equatable {
    var denyCode: String
    var policyReason: String
    var targetPath: String
    var allowedRoots: [String]
    var detail: String
}

enum PathGuard {
    static func resolve(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func resolveAgainstScopedRoots(target: URL, roots: [URL]) -> URL {
        let resolvedTarget = resolve(target)
        let resolvedRoots = roots.map(resolve)

        if resolvedRoots.contains(where: { isInside(root: $0, target: resolvedTarget) }) {
            return resolvedTarget
        }

        for root in resolvedRoots {
            if let aliasedTarget = aliasResolvedTarget(target: resolvedTarget, root: root) {
                return aliasedTarget
            }
        }
        return resolvedTarget
    }

    static func isInside(root: URL, target: URL) -> Bool {
        let r = resolve(root)
        let t = resolve(target)
        if t.path == r.path { return true }
        let rp = r.path.hasSuffix("/") ? r.path : (r.path + "/")
        return t.path.hasPrefix(rp)
    }

    static func requireInside(root: URL, target: URL) throws {
        try requireInsideAny(
            roots: [root],
            target: target,
            denyCode: "path_outside_project_root",
            policyReason: "project_root_only",
            detail: "Path is outside project root"
        )
    }

    static func requireInsideAny(
        roots: [URL],
        target: URL,
        denyCode: String,
        policyReason: String,
        detail: String
    ) throws {
        let resolvedTarget = resolve(target)
        let resolvedRoots = Array(
            Set(
                roots.map { resolve($0).path }
            )
        ).sorted()

        guard resolvedRoots.contains(where: { isInside(root: URL(fileURLWithPath: $0), target: resolvedTarget) }) else {
            throw XTPathScopeViolation(
                denyCode: denyCode,
                policyReason: policyReason,
                targetPath: resolvedTarget.path,
                allowedRoots: resolvedRoots,
                detail: detail
            )
        }
    }

    private static func aliasResolvedTarget(target: URL, root: URL) -> URL? {
        let targetComponents = target.pathComponents
        let rootComponents = root.pathComponents
        guard targetComponents.count >= rootComponents.count else { return nil }

        for index in rootComponents.indices {
            guard scopedPathComponentsMatchAlias(
                rootComponents[index],
                targetComponents[index]
            ) else {
                return nil
            }
        }

        var rewritten = root
        for component in targetComponents.dropFirst(rootComponents.count) {
            rewritten.appendPathComponent(component, isDirectory: false)
        }
        return rewritten
    }

    private static func scopedPathComponentsMatchAlias(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        return normalizedScopedPathComponent(lhs) == normalizedScopedPathComponent(rhs)
    }

    private static func normalizedScopedPathComponent(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty, out != "/" else { return out }

        let wrappers: [(String, String)] = [
            ("**", "**"),
            ("《", "》"),
            ("[", "]"), ("【", "】"),
            ("(", ")"), ("（", "）"),
            ("“", "”"), ("\"", "\""),
            ("'", "'"), ("`", "`")
        ]

        var changed = true
        while changed {
            changed = false
            for (head, tail) in wrappers {
                if out.hasPrefix(head), out.hasSuffix(tail), out.count > (head.count + tail.count) {
                    out.removeFirst(head.count)
                    out.removeLast(tail.count)
                    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }
        return out
    }
}
