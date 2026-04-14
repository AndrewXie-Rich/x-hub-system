import Foundation

extension ProcessInfo {
    var isRunningUnderAutomatedTests: Bool {
        let env = environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil {
            return true
        }

        let lowercasedArguments = arguments.map { $0.lowercased() }
        if lowercasedArguments.contains("--testing-library") || lowercasedArguments.contains("swift-testing") {
            return true
        }

        let processName = processName.lowercased()
        if processName.contains("xctest") || processName.contains("swiftpm-testing-helper") {
            return true
        }

        let bundlePath = Bundle.main.bundleURL.path.lowercased()
        if bundlePath.contains(".xctest") || bundlePath.contains("/swift/pm") {
            return true
        }

        return false
    }
}
