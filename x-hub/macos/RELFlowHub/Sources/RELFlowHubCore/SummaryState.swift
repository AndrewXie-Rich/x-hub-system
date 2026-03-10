import Foundation

public struct SummaryState: Codable, Sendable, Equatable {
    public var todayNewUnseenCount: Int
    public var nextMeetingText: String
    public var updatedAt: Double

    public init(todayNewUnseenCount: Int, nextMeetingText: String, updatedAt: Double) {
        self.todayNewUnseenCount = todayNewUnseenCount
        self.nextMeetingText = nextMeetingText
        self.updatedAt = updatedAt
    }

    public static func empty() -> SummaryState {
        SummaryState(todayNewUnseenCount: 0, nextMeetingText: "No events today", updatedAt: Date().timeIntervalSince1970)
    }
}

public enum SummaryStorage {
    // Keep this stable across the app + widget extension.
    public static let appGroupId = "group.rel.flowhub"
    public static let userDefaultsKey = "summary_state_v1"

    public static func load() -> SummaryState {
        // App Group access can trigger repeated TCC prompts for ad-hoc signed dev builds.
        // Only use the shared suite when App Group is available (signed/distributed builds).
        if SharedPaths.appGroupDirectory() != nil, let ud = UserDefaults(suiteName: appGroupId) {
            if let data = ud.data(forKey: userDefaultsKey),
               let obj = try? JSONDecoder().decode(SummaryState.self, from: data) {
                return obj
            }
        }
        // Fallback: local file for dev when App Group isn't configured.
        let url = fallbackURL()
        if let data = try? Data(contentsOf: url), let obj = try? JSONDecoder().decode(SummaryState.self, from: data) {
            return obj
        }
        return .empty()
    }

    public static func save(_ state: SummaryState) {
        if let data = try? JSONEncoder().encode(state) {
            if SharedPaths.appGroupDirectory() != nil, let ud = UserDefaults(suiteName: appGroupId) {
                ud.set(data, forKey: userDefaultsKey)
            }
            // Always write fallback for debugging.
            let url = fallbackURL()
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func fallbackURL() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent("summary_state.json")
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent("summary_state.json")
    }
}
