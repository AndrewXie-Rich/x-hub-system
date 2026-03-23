import Foundation

enum XTStoreWriteSupport {
    typealias WriteAttemptOverride = SupervisorStoreWriteSupport.WriteAttemptOverride

    static func writeSnapshotData(_ data: Data, to target: URL) throws {
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: target)
    }

    static func writeUTF8Text(_ text: String, to target: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw NSError(
                domain: "xterminal",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode text as UTF-8"]
            )
        }
        try writeSnapshotData(data, to: target)
    }

    static func looksLikeDiskSpaceExhaustion(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 28 {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return looksLikeDiskSpaceExhaustion(underlying)
        }
        return false
    }

    static func installWriteAttemptOverrideForTesting(_ override: WriteAttemptOverride?) {
        SupervisorStoreWriteSupport.installWriteAttemptOverrideForTesting(override)
    }

    static func resetWriteBehaviorForTesting() {
        SupervisorStoreWriteSupport.resetWriteBehaviorForTesting()
    }
}
