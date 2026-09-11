import Foundation

final class ProcessOutputMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (String) -> Void
    private var remainingBytes: Int
    private var pending: [ProcessCapture.OutputStream: Data] = [:]

    init(maxBytes: Int = ProcessCapture.defaultMaxOutputBytes, handler: @escaping @Sendable (String) -> Void) {
        remainingBytes = max(0, maxBytes)
        self.handler = handler
    }

    func append(_ data: Data, stream: ProcessCapture.OutputStream) {
        lock.lock()
        defer { lock.unlock() }
        let accepted = min(remainingBytes, data.count)
        remainingBytes -= accepted
        var buffer = pending[stream] ?? Data()
        buffer.append(data.prefix(accepted))
        let end = completeUTF8Prefix(buffer)
        pending[stream] = Data(buffer.suffix(buffer.count - end))
        if end > 0 { handler(String(decoding: buffer.prefix(end), as: UTF8.self)) }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        for stream in [ProcessCapture.OutputStream.stdout, .stderr] {
            if let data = pending.removeValue(forKey: stream), !data.isEmpty {
                handler(String(decoding: data, as: UTF8.self))
            }
        }
    }

    private func completeUTF8Prefix(_ data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        var start = data.count - 1
        while start > 0 && data[start] & 0xc0 == 0x80 && data.count - start < 4 { start -= 1 }
        let lead = data[start]
        let expected: Int
        switch lead {
        case 0xc2...0xdf: expected = 2
        case 0xe0...0xef: expected = 3
        case 0xf0...0xf4: expected = 4
        default: return data.count
        }
        return data.count - start < expected ? start : data.count
    }
}
