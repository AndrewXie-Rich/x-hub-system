import Foundation

enum HubPairedSurfaceHeartbeat {
    static let appID = "paired_surface_xt_local"
    static let appName = "X-Terminal"

    private struct Payload: Codable {
        var appId: String
        var appName: String
        var activity: Activity
        var aiEnabled: Bool
        var modelMemoryBytes: Int64?
        var updatedAt: Double

        var surfaceKind: String
        var transportMode: String

        enum Activity: String, Codable {
            case active
            case idle
        }
    }

    static func write(baseDir: URL, active: Bool, aiEnabled: Bool, modelMemoryBytes: Int64? = nil) {
        let dir = baseDir.appendingPathComponent("clients", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let payload = Payload(
            appId: appID,
            appName: appName,
            activity: active ? .active : .idle,
            aiEnabled: aiEnabled,
            modelMemoryBytes: modelMemoryBytes,
            updatedAt: Date().timeIntervalSince1970,
            surfaceKind: "paired_surface",
            transportMode: "local_fileipc"
        )
        let path = dir.appendingPathComponent("\(appID).json")
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: path, options: .atomic)
    }

    static func remove(baseDir: URL?) {
        guard let baseDir else { return }
        let path = baseDir
            .appendingPathComponent("clients", isDirectory: true)
            .appendingPathComponent("\(appID).json")
        try? FileManager.default.removeItem(at: path)
    }
}
