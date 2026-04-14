import Foundation

enum LaunchPresentationPolicy: Equatable {
    case foreground
    case background

    static func from(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        let normalizedArgs = Set(arguments.dropFirst().map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        if normalizedArgs.contains("--background") || normalizedArgs.contains("--hidden") {
            return .background
        }

        if truthy(environment["RELFLOWHUB_LAUNCH_BACKGROUND"]) || truthy(environment["XHUB_LAUNCH_BACKGROUND"]) {
            return .background
        }

        return .foreground
    }

    private static func truthy(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }
}
