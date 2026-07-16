#if !APP_STORE
import Sparkle
import SwiftUI

/// Owns the SPUUpdater for the lifetime of the app.
/// Initialize once in the @main App struct and hold a reference.
final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
