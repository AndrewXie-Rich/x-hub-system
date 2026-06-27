import Foundation

struct HubGRPCNodeLaunchConfig: Equatable {
    var exePath: String
    var argsPrefix: [String]
}

@MainActor
extension HubGRPCServerSupport {
    func autoDetectNodeLaunch() -> HubGRPCNodeLaunchConfig? {
        let fm = FileManager.default

        // Prefer a bundled Node runtime (works in App Sandbox; avoids relying on system PATH/Homebrew).
        if let u = Bundle.main.url(forAuxiliaryExecutable: "relflowhub_node") {
            let p = u.path
            if fm.isExecutableFile(atPath: p) {
                return HubGRPCNodeLaunchConfig(exePath: p, argsPrefix: [])
            }
        }
        if let p = Bundle.main.resourceURL?.appendingPathComponent("relflowhub_node").path,
           fm.isExecutableFile(atPath: p) {
            return HubGRPCNodeLaunchConfig(exePath: p, argsPrefix: [])
        }

        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        for c in candidates {
            if fm.isExecutableFile(atPath: c) {
                return HubGRPCNodeLaunchConfig(exePath: c, argsPrefix: [])
            }
        }
        // Fallback: try /usr/bin/env node (may work if PATH is configured for the app).
        if fm.isExecutableFile(atPath: "/usr/bin/env") {
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            probe.arguments = ["node", "--version"]
            let out = Pipe()
            let err = Pipe()
            probe.standardOutput = out
            probe.standardError = err
            do {
                try probe.run()
            } catch {
                return nil
            }
            probe.waitUntilExit()
            if probe.terminationStatus == 0 {
                return HubGRPCNodeLaunchConfig(exePath: "/usr/bin/env", argsPrefix: ["node"])
            }
        }
        return nil
    }

    func bundledServerJSURL() -> URL? {
        // Bundled layout (Resources):
        // - hub_grpc_server/src/server.js
        // - hub_grpc_server/node_modules/...
        // - protocol/hub_protocol_v1.proto (sibling of hub_grpc_server/ under Resources)
        if let r = Bundle.main.resourceURL {
            let cand = r.appendingPathComponent("hub_grpc_server", isDirectory: true)
                .appendingPathComponent("src", isDirectory: true)
                .appendingPathComponent("server.js")
            if FileManager.default.fileExists(atPath: cand.path) {
                return cand
            }
        }

        // Dev fallback: run from repo root.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let dev = cwd.appendingPathComponent("hub_grpc_server", isDirectory: true)
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("server.js")
        if FileManager.default.fileExists(atPath: dev.path) {
            return dev
        }
        return nil
    }

    private static func redactedToken(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 10 { return t }
        let a = t.prefix(4)
        let b = t.suffix(4)
        return "\(a)…\(b)"
    }
}
