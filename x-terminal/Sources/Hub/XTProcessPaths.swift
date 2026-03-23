import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum XTProcessPaths {
    static func realHomeDirectory(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["AXHUBCTL_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }

        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }

        return fileManager.homeDirectoryForCurrentUser
    }

    static func defaultAxhubStateDir(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["AXHUBCTL_STATE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }

        return realHomeDirectory(fileManager: fileManager)
            .appendingPathComponent(".axhub", isDirectory: true)
    }
}
