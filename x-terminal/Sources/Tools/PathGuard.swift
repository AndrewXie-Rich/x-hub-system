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
}
