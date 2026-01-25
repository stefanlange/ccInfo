import Foundation

/// Watches a file system path for changes using FSEvents
final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable () -> Void
    private let lock = NSLock()

    // Strong reference to prevent deallocation while stream is active
    private static var activeWatchers = NSHashTable<FileWatcher>.weakObjects()
    private static let watchersLock = NSLock()

    init(path: String, callback: @escaping @Sendable () -> Void) {
        self.path = path
        self.callback = callback
    }

    deinit {
        stop()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard stream == nil else { return }

        Self.watchersLock.lock()
        Self.activeWatchers.add(self)
        Self.watchersLock.unlock()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let streamCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async {
                watcher.callback()
            }
        }

        stream = FSEventStreamCreate(
            nil,
            streamCallback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard let stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil

        Self.watchersLock.lock()
        Self.activeWatchers.remove(self)
        Self.watchersLock.unlock()
    }
}
