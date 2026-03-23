import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct FileToolWriteSupportTests {
    @Test
    func writeTextFallsBackToDirectOverwriteWhenAtomicWriteRunsOutOfSpaceForExistingFile() throws {
        let root = try makeTempDirectory("existing_file")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let target = root.appendingPathComponent("Sources/hello.txt")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old value\n".utf8).write(to: target)

        let capture = FileToolWriteCapture()
        installScopedExistingFileOutOfSpaceOverride(root: root, capture: capture)

        try FileTool.writeText(
            path: "Sources/hello.txt",
            content: "new value\n",
            projectRoot: root
        )

        let data = try Data(contentsOf: target)
        let options = capture.writeOptionsSnapshot()
        #expect(String(decoding: data, as: UTF8.self) == "new value\n")
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
    }

    @Test
    func writeTextThrowsWithoutCreatingTargetWhenAtomicWriteRunsOutOfSpaceForNewFile() throws {
        let root = try makeTempDirectory("new_file")
        defer {
            XTStoreWriteSupport.resetWriteBehaviorForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let target = root.appendingPathComponent("Sources/new.txt")
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            if !Self.normalizedPath(url).hasPrefix(Self.normalizedPath(root)) {
                try data.write(to: url, options: options)
                return
            }
            if options.contains(.atomic) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }

        #expect(throws: Error.self) {
            try FileTool.writeText(
                path: "Sources/new.txt",
                content: "new file\n",
                projectRoot: root
            )
        }

        let sourceDir = root.appendingPathComponent("Sources", isDirectory: true)
        let remainingEntries = (try? FileManager.default.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: nil
        )) ?? []
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(remainingEntries.isEmpty)
    }

    private func makeTempDirectory(_ suffix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_file_tool_write_\(suffix)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func installScopedExistingFileOutOfSpaceOverride(root: URL, capture: FileToolWriteCapture) {
        XTStoreWriteSupport.installWriteAttemptOverrideForTesting { data, url, options in
            if !Self.normalizedPath(url).hasPrefix(Self.normalizedPath(root)) {
                try data.write(to: url, options: options)
                return
            }
            capture.appendWriteOption(options)
            if options.contains(.atomic),
               let existingTarget = Self.existingTargetForAtomicTemp(url),
               FileManager.default.fileExists(atPath: existingTarget.path) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
    }

    private static func existingTargetForAtomicTemp(_ url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."),
              let tempRange = name.range(of: ".tmp-") else {
            return nil
        }
        let targetName = String(name[name.index(after: name.startIndex)..<tempRange.lowerBound])
        guard !targetName.isEmpty else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(targetName)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path.replacingOccurrences(
            of: "/private",
            with: "",
            options: [.anchored]
        )
    }
}

private final class FileToolWriteCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }
}
