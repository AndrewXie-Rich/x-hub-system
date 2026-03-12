import Foundation

enum XTProjectMemoryGovernance {
    static let hubPreferredMode = "hub_preferred"
    static let localOnlyMode = "local_only"

    static let hubMemoryContextSource = "hub_memory_context"
    static let hubSnapshotOverlaySource = "hub_snapshot_plus_local_overlay"
    static let localProjectMemorySource = "local_project_memory"
    static let localFallbackSource = "local_fallback"

    static func prefersHubMemory(_ config: AXProjectConfig?) -> Bool {
        config?.preferHubMemory ?? true
    }

    static func modeLabel(_ config: AXProjectConfig?) -> String {
        prefersHubMemory(config) ? hubPreferredMode : localOnlyMode
    }

    static func localSourceLabel(prefersHubMemory: Bool) -> String {
        prefersHubMemory ? localFallbackSource : localProjectMemorySource
    }

    static func normalizedResolvedSource(_ rawSource: String?) -> String {
        let source = (rawSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return hubMemoryContextSource }

        if source == "hub_memory_v1" {
            return hubMemoryContextSource
        }
        if source == "hub_memory_v1_grpc"
            || source == "hub_remote_snapshot"
            || source == hubSnapshotOverlaySource {
            return hubSnapshotOverlaySource
        }
        return source
    }
}
