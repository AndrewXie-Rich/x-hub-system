import Foundation

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
        if !isInside(root: root, target: target) {
            throw NSError(domain: "xterminal", code: 401, userInfo: [NSLocalizedDescriptionKey: "Path is outside project root"])
        }
    }
}
