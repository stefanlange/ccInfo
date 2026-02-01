import Foundation

/// Watches a file system path for changes using FSEvents
/// @unchecked Sendable is safe here because all mutable state (stream) is protected by NSLock
final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let path: String
    private let callback: @Sendable () -> Void
    private let lock = NSLock()

    // Strong references to prevent deallocation while stream is active
    // Using NSHashTable with objectPointerPersonality for strong references
    private static var activeWatchers: NSHashTable<FileWatcher> = {
        let hashTable = NSHashTable<FileWatcher>(options: .strongMemory)
        return hashTable
    }()
    private static let watchersLock = NSLock()

    init(path: String, callback: @escaping @Sendable () -> Void) {
        self.path = path
        self.callback = callback
    }

    deinit {
        // Ensure stream is stopped before deallocation to prevent use-after-free
        lock.lock()
        let hasActiveStream = stream != nil
        lock.unlock()

        if hasActiveStream {
            stop()
        }

        // Verify we're not in activeWatchers anymore
        Self.watchersLock.lock()
        assert(!Self.activeWatchers.contains(self), "FileWatcher deallocated while still in activeWatchers")
        Self.watchersLock.unlock()
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
