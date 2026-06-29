import Foundation

extension ModelStore {
    nonisolated static func isSystemVoiceTTSAvailable(
        binaryPath: String,
        fileManager: FileManager
    ) -> Bool {
        let trimmed = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("/") || trimmed.hasPrefix(".") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: expanded)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(trimmed)
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return true
            }
        }
        return false
    }
}
