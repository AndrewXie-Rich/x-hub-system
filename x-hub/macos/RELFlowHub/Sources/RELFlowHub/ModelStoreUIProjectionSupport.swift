import Foundation
import RELFlowHubCore

struct OptionalRuntimePresentationCacheEntry {
    let value: LocalModelRuntimePresentation?
}

struct OptionalStringCacheEntry {
    let value: String?
}

struct LocalRuntimeSupportInputs {
    let providerID: String
    let probeLaunchConfig: LocalRuntimePythonProbeLaunchConfig?
    let pythonPath: String?
}

extension ModelStore {
}
