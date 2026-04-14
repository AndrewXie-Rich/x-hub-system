import Foundation

struct XTHubLaunchStatusSnapshot: Codable, Equatable, Sendable {
    struct Degraded: Codable, Equatable, Sendable {
        var blockedCapabilities: [String]
        var isDegraded: Bool

        enum CodingKeys: String, CodingKey {
            case blockedCapabilities = "blocked_capabilities"
            case isDegraded = "is_degraded"
        }
    }

    struct RootCause: Codable, Equatable, Sendable {
        var component: String
        var detail: String
        var errorCode: String

        enum CodingKeys: String, CodingKey {
            case component
            case detail
            case errorCode = "error_code"
        }
    }

    var state: String
    var degraded: Degraded
    var rootCause: RootCause

    enum CodingKeys: String, CodingKey {
        case state
        case degraded
        case rootCause = "root_cause"
    }

    var blockedCapabilities: [String] {
        degraded.blockedCapabilities
    }

    var rootCauseErrorCode: String {
        rootCause.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var rootCauseDetail: String {
        rootCause.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isDegraded: Bool {
        degraded.isDegraded
    }

    var blocksPaidOrWebCapabilities: Bool {
        let normalized = Set(
            blockedCapabilities.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        return normalized.contains("ai.generate.paid") || normalized.contains("web.fetch")
    }

    var blockedCapabilitiesSummary: String {
        let normalized = blockedCapabilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? "none" : normalized.joined(separator: ",")
    }
}

enum XTHubLaunchStatusStore {
    private static let testingLock = NSLock()
    private static var loadOverrideForTesting: (@Sendable (URL) -> XTHubLaunchStatusSnapshot?)?

    static func load(baseDir: URL = HubPaths.baseDir()) -> XTHubLaunchStatusSnapshot? {
        let url = baseDir.appendingPathComponent("hub_launch_status.json")
        if let override = withTestingLock({ loadOverrideForTesting }) {
            return override(url)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XTHubLaunchStatusSnapshot.self, from: data)
    }

    static func installLoadOverrideForTesting(
        _ override: (@Sendable (URL) -> XTHubLaunchStatusSnapshot?)?
    ) {
        withTestingLock {
            loadOverrideForTesting = override
        }
    }

    @discardableResult
    private static func withTestingLock<T>(_ body: () -> T) -> T {
        testingLock.lock()
        defer { testingLock.unlock() }
        return body()
    }
}
