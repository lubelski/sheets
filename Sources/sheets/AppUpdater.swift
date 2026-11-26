import Foundation
import Observation
import SheetsCore
import Sparkle

/// Keeps the app up to date with Sparkle. This is the only file that imports Sparkle.
///
/// Only a release build updates itself. `scripts/release.sh` writes the feed address and the
/// public signing key into Info.plist. A build without them, such as one from
/// `scripts/bundle.sh` alone, has no updater, so a development copy is never replaced.
///
/// There is no updater delegate yet. Sparkle installs a downloaded update when the app quits.
/// An app that stays open for long would install and relaunch as soon as an update is ready,
/// unless it is busy. This app has no busy state yet, so that logic waits until it does.
@MainActor
@Observable
final class AppUpdater {
    /// Whether this build can update itself.
    let isAvailable: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    /// `info` is the bundle's Info.plist.
    init(info: [String: Any]? = Bundle.main.infoDictionary) {
        guard AppUpdates.hasFeed(info) else {
            isAvailable = false
            controller = nil
            return
        }
        isAvailable = true
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
    }

    /// False while a check is already running, and always false without a feed.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Checks now and shows Sparkle's own windows with the result.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
