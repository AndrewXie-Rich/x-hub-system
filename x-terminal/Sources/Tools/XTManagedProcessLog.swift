import Foundation
import Darwin

final class XTManagedProcessLog: @unchecked Sendable {
    static let defaultSegmentBytes = 1024 * 1024
    static let maximumReadBytes = 256 * 1024

    private let lock = NSLock()
    private let url: URL
    private let segmentBytes: Int
    private var previousURL: URL { url.appendingPathExtension("previous") }

    init(url: URL, segmentBytes: Int = defaultSegmentBytes) {
        self.url = url
        self.segmentBytes = max(1, segmentBytes)
    }

    func append(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var offset = 0
        while offset < data.count {
            let handle = try openFile(url, flags: O_RDWR | O_CREAT)
            let size = try handle.seekToEnd()
            if size >= UInt64(segmentBytes) {
                if size > UInt64(segmentBytes) {
                    try handle.seek(toOffset: size - UInt64(segmentBytes))
                    let retained = try handle.read(upToCount: segmentBytes) ?? Data()
                    try handle.truncate(atOffset: 0)
                    try handle.seek(toOffset: 0)
                    try handle.write(contentsOf: retained)
                }
                try handle.close()
                if rename(url.path, previousURL.path) != 0 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                continue
            }
            do {
                let count = min(segmentBytes - Int(size), data.count - offset)
                try handle.write(contentsOf: data.subdata(in: offset..<(offset + count)))
                offset += count
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
        }
    }

    func tail(maxBytes: Int) throws -> (data: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let limit = max(1, min(maxBytes, Self.maximumReadBytes))
        let current = try readTail(url, limit: limit)
        let previous = try readTail(previousURL, limit: max(0, limit - current.data.count))
        return (previous.data + current.data, previous.size > 0 || current.size > UInt64(limit))
    }

    private func readTail(_ file: URL, limit: Int) throws -> (data: Data, size: UInt64) {
        let handle: FileHandle
        do {
            handle = try openFile(file, flags: O_RDONLY)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return (Data(), 0)
        }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let count = Int(min(UInt64(limit), size))
        try handle.seek(toOffset: size - UInt64(count))
        return (try handle.read(upToCount: count) ?? Data(), size)
    }

    private func openFile(_ file: URL, flags: Int32) throws -> FileHandle {
        let descriptor = Darwin.open(file.path, flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}

enum XTManagedProcessEnvironment {
    static func make(overrides: [String: String], host: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        let allowed = Set(["PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR"])
        var environment = host.filter { allowed.contains($0.key) }
        environment["PATH"] = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TERM"] = "dumb"
        environment.merge(overrides) { _, value in value }
        return environment
    }
}

final class XTManagedProcessLaunch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, Error>?

    init(_ continuation: CheckedContinuation<Int32, Error>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<Int32, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
