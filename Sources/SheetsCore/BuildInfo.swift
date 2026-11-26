import Foundation
import Security

/// What Settings, Debugging shows about this copy of the app: its version, build, commit,
/// and how it is signed.
public struct BuildInfo: Sendable, Equatable {
    public var version: String
    public var build: String
    /// The short commit hash it was built from, with `-dirty` when the tree had changes.
    public var commit: String
    /// How the app is signed, in words. See `describeSigning`.
    public var signing: String

    public init(version: String, build: String, commit: String, signing: String) {
        self.version = version
        self.build = build
        self.commit = commit
        self.signing = signing
    }

    /// The `Info.plist` key that `scripts/bundle.sh` writes the commit into.
    public static let commitKey = "SheetsGitCommit"

    /// Reads a bundle's `Info.plist` and code signature.
    public static func current(bundle: Bundle = .main) -> BuildInfo {
        let info = bundle.infoDictionary ?? [:]
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown",
            commit: info[commitKey] as? String ?? "unknown",
            signing: signing(of: bundle.bundleURL))
    }

    static func signing(of url: URL) -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return describeSigning(isSigned: false, isAdHoc: false, teamID: nil)
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
            == errSecSuccess,
            let dictionary = information as? [String: Any]
        else {
            return describeSigning(isSigned: false, isAdHoc: false, teamID: nil)
        }
        let flags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return describeSigning(
            isSigned: dictionary[kSecCodeInfoIdentifier as String] != nil,
            isAdHoc: flags & SecCodeSignatureFlags.adhoc.rawValue != 0,
            teamID: dictionary[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    /// How the app is signed, in words.
    public static func describeSigning(isSigned: Bool, isAdHoc: Bool, teamID: String?) -> String {
        if !isSigned { return "Not signed" }
        if isAdHoc { return "Signed ad hoc" }
        if let teamID { return "Signed by team \(teamID)" }
        return "Signed"
    }
}
