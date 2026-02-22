import Foundation

/// Watches a file system path for changes using FSEvents
/// @unchecked Sendable is safe here because all mutable state (stream, retainedSelf) is protected by NSLock
final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var retainedSelf: Unmanaged<FileWatcher>?
    private let path: String
    private let callback: @Sendable () -> Void
    private let lock = NSLock()

    init(path: String, callback: @escaping @Sendable () -> Void) {
        self.path = path
        self.callback = callback
    }

    deinit {
        // stop() is always called explicitly via stopMonitoring() before release.
        // This guard handles unexpected deinit paths without risking a deadlock
        // from DispatchQueue.main.sync during app termination.
        if Thread.isMainThread {
            stop()
        }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard stream == nil else { return }

        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained

        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let streamCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.callback()
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

        guard let stream else {
            retained.release()
            retainedSelf = nil
            return
        }

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

        if let retained = retainedSelf {
            retained.release()
            retainedSelf = nil
        }
    }
}
