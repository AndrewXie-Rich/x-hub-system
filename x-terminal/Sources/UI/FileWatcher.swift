import Foundation

final class FileWatcher {
    private let url: URL
    private let handler: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init(url: URL, handler: @escaping () -> Void) {
        self.url = url
        self.handler = handler
    }

    func start() {
        stop()

        fd = open((url.path as NSString).fileSystemRepresentation, O_EVTONLY)
        if fd < 0 {
            return
        }

        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        s.setEventHandler { [weak self] in
            guard let self else { return }
            // If file was replaced (atomic write), re-arm the watcher.
            let flags = s.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.start()
            }
            self.handler()
        }

        s.setCancelHandler { [fd] in
            if fd >= 0 { close(fd) }
        }

        source = s
        s.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }

    deinit {
        stop()
    }
}
