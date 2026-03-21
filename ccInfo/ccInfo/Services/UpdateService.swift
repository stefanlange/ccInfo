import Sparkle
import Combine

@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updater: SPUUpdater

    init(updaterController: SPUStandardUpdaterController) {
        self.updater = updaterController.updater
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
