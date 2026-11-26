import Foundation

/// The rules for updating the app, kept apart from Sparkle so they can be tested.
///
/// Only a release build updates itself. `scripts/release.sh` has `scripts/bundle.sh` write the
/// feed address and the public signing key into Info.plist. A build without them never
/// updates itself, so a development copy is never replaced by a release.
public enum AppUpdates {
    /// Whether a bundle with this Info.plist has a feed to update from: a feed URL and a
    /// public key, both present and not empty.
    public static func hasFeed(_ info: [String: Any]?) -> Bool {
        guard let feed = info?["SUFeedURL"] as? String,
              let key = info?["SUPublicEDKey"] as? String
        else { return false }
        return !feed.isEmpty && !key.isEmpty
    }
}
