import Foundation
import Darwin

struct LocalExecutionPolicy {
    let workspace: URL
    let readableRoots: [URL]
    let writableRoots: [URL]
    let allowNetwork: Bool

    func shellArguments(command: String) throws -> [String] {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw SandboxError.unsupportedOperation("local_os_sandbox_unavailable")
        }
        return ["-p", try profile(), "/bin/zsh", "-f", "-c", command]
    }

    func profile() throws -> String {
        let systemReadRoots = ["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/share",
                               "/System/Library", "/Library/Apple/System/Library"]
        let readRoots = systemReadRoots + readableRoots.map(\.path) + writableRoots.map(\.path)
        let readFilters = try readRoots.map { "(subpath \(try quotedPath($0)))" }.joined(separator: " ")
        let writeFilters = try writableRoots.map { "(subpath \(try quotedPath($0.path)))" }.joined(separator: " ")
        var rules = [
            "(version 1)",
            "(deny default)",
            "(allow process-exec process-fork)",
            "(allow signal (target same-sandbox))",
            "(allow sysctl-read)",
            "(allow file-read-metadata)",
            "(allow file-read-data (literal \"/\"))",
            "(allow file-read* (literal \"/dev/null\") (literal \"/dev/random\") (literal \"/dev/urandom\") (literal \"/private/etc/localtime\"))",
            "(allow file-write-data (literal \"/dev/null\"))"
        ]
        if !readFilters.isEmpty { rules.append("(allow file-read* \(readFilters))") }
        if !writeFilters.isEmpty { rules.append("(allow file-write* \(writeFilters))") }
        if allowNetwork { rules.append("(allow network*)") }
        return rules.joined(separator: "\n")
    }

    func environment(overrides: [String: String], host: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for key in ["LANG", "LC_ALL", "LC_CTYPE", "TZ"] {
            if let value = host[key] { environment[key] = value }
        }
        environment.merge(overrides) { _, value in value }
        environment["TMPDIR"] = workspace.appendingPathComponent(".tmp", isDirectory: true).path
        environment["ZDOTDIR"] = workspace.path
        return environment
    }

    private func quotedPath(_ path: String) throws -> String {
        guard let resolved = realpath(path, nil) else {
            throw SandboxError.invalidPath("local_execution_root_unresolved")
        }
        defer { free(resolved) }
        let canonical = String(cString: resolved)
        guard canonical != "/", !canonical.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw SandboxError.invalidPath("invalid_local_execution_root")
        }
        return "\"" + canonical.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
