import Foundation

enum LocalRuntimeProviderRecoveryAction: Equatable {
    case none
    case start(targetPythonPath: String)
    case restart(targetPythonPath: String)
}

enum LocalRuntimeProviderRecoveryPlanner {
    static func plan(
        runtimeAlive: Bool,
        providerReady: Bool,
        currentPythonPath: String,
        targetPythonPath: String,
        targetSupportsProvider: Bool
    ) -> LocalRuntimeProviderRecoveryAction {
        guard !providerReady else {
            return .none
        }
        guard targetSupportsProvider else {
            return .none
        }

        let normalizedCurrent = normalizedPath(currentPythonPath)
        let normalizedTarget = normalizedPath(targetPythonPath)
        let resolvedTarget = normalizedTarget.isEmpty ? normalizedCurrent : normalizedTarget
        guard !resolvedTarget.isEmpty else {
            return .none
        }

        if runtimeAlive {
            return .restart(targetPythonPath: resolvedTarget)
        }
        return .start(targetPythonPath: resolvedTarget)
    }

    private static func normalizedPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }
}
