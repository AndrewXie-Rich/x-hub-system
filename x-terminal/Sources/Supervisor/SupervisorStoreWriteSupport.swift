import Foundation

enum SupervisorStoreWriteSupport {
    typealias WriteAttemptOverride = @Sendable (Data, URL, Data.WritingOptions) throws -> Void

    private static let testingLock = NSLock()
    private static let testingOverrideSemaphore = DispatchSemaphore(value: 1)
    private static var writeAttemptOverrideForTesting: WriteAttemptOverride?
    private static var testingOverrideLeaseHeld = false

    static func writeSnapshotData(_ data: Data, to target: URL) throws {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let hadExistingTarget = FileManager.default.fileExists(atPath: target.path)

        if existingSnapshotMatches(data, target: target) {
            return
        }

        let temp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try writeData(data, to: temp, options: .atomic)
            if FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: temp, to: target)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            guard hadExistingTarget, looksLikeDiskSpaceExhaustion(error) else {
                throw error
            }
            try writeData(data, to: target, options: [])
        }
    }

    static func installWriteAttemptOverrideForTesting(_ override: WriteAttemptOverride?) {
        testingOverrideSemaphore.wait()
        withTestingLock {
            writeAttemptOverrideForTesting = override
            testingOverrideLeaseHeld = true
        }
    }

    static func resetWriteBehaviorForTesting() {
        var shouldSignal = false
        withTestingLock {
            writeAttemptOverrideForTesting = nil
            if testingOverrideLeaseHeld {
                testingOverrideLeaseHeld = false
                shouldSignal = true
            }
        }
        if shouldSignal {
            testingOverrideSemaphore.signal()
        }
    }

    private static func existingSnapshotMatches(_ data: Data, target: URL) -> Bool {
        guard let existing = try? Data(contentsOf: target) else { return false }
        return existing == data
    }

    private static func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        if let override = withTestingLock({ writeAttemptOverrideForTesting }) {
            try override(data, url, options)
            return
        }
        try data.write(to: url, options: options)
    }

    private static func looksLikeDiskSpaceExhaustion(_ error: Error) -> Bool {
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

    @discardableResult
    private static func withTestingLock<T>(_ body: () -> T) -> T {
        testingLock.lock()
        defer { testingLock.unlock() }
        return body()
    }
}
