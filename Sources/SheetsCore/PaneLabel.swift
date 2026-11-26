import Foundation

/// What a pane's row says: a title over a shorter, grayer line.
///
/// For most panes the title is the pane's own name and the second line is its summary, such as
/// "2 panes". A terminal says more about what is going on in it:
///
/// - Its title is the title its shell or a program set, such as `npm run dev`, when there is
///   one. A name the person typed by renaming the pane wins over it, and with neither, the
///   pane's own name shows.
/// - Its second line is its folder, with the home folder written `~`, and a count of the panes
///   under it, as in `~/dev/acme-web · 1 page`. The folder is the one its shell last reported,
///   or else the one it started in. With no folder known, the line is the summary.
///
/// The sheet's title bar shows the same title. See `SheetTitle`.
public struct PaneLabel: Hashable, Sendable {
    public let title: String
    /// The whole second line.
    public let subtitle: String
    /// The folder the second line starts with, when it starts with one. A row cuts a long one
    /// short at its head, so the last folder in it stays readable.
    public let folder: String?
    /// What follows the folder on the second line, such as "1 page", or nil for nothing.
    public let folderDetail: String?

    /// A title over a plain second line, with no folder in it, such as a Settings section's.
    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        folder = nil
        folderDetail = nil
    }

    /// - Parameters:
    ///   - sessionTitle: The title a terminal's shell set, if any. Ignored for other panes.
    ///   - folder: A terminal's folder, as a full path: the one its shell last reported, or the
    ///     one it started in, or nil when none is known. Ignored for other panes.
    ///   - home: The home folder, which `~` stands for.
    public init(pane: Pane, sessionTitle: String? = nil, folder: String? = nil, home: String) {
        title = pane.shownTitle(sessionTitle: sessionTitle)
        guard pane.kind == .terminal, let folder, !folder.isEmpty else {
            subtitle = pane.summary
            self.folder = nil
            folderDetail = nil
            return
        }
        let shown = Self.shortened(folder, home: home)
        let detail = pane.childrenCount
        self.folder = shown
        folderDetail = detail
        subtitle = detail.map { shown + " · " + $0 } ?? shown
    }

    /// A folder with the home folder at its start written `~`, as a shell's prompt does:
    /// `~` for the home folder itself, `~/dev/acme-web` for a folder in it, and any other folder
    /// as its full path. A trailing `/` is dropped.
    public static func shortened(_ folder: String, home: String) -> String {
        let path = (folder as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

extension Pane {
    /// The title a pane shows in its row and on its sheet's title bar.
    ///
    /// A terminal shows the title its shell or a program set, unless the person named the pane
    /// by hand. Every other pane, and a terminal whose shell set no title, shows its own name.
    public func shownTitle(sessionTitle: String?) -> String {
        guard kind == .terminal, !isNamedByHand,
              let sessionTitle = sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionTitle.isEmpty
        else { return title }
        return sessionTitle
    }
}

extension TerminalSessionStore {
    /// What a pane's row says, from the pane and, for a terminal, what its session reports.
    /// It reads the session's title and folder, so a view that calls it while drawing is drawn
    /// again when either changes.
    ///
    /// A terminal's folder is the one its shell last reported, or else the one its session
    /// started in, or else, before it has a session, the pane's own.
    public func label(for pane: Pane, home: String) -> PaneLabel {
        guard pane.kind == .terminal else { return PaneLabel(pane: pane, home: home) }
        let record = record(for: pane.id)
        return PaneLabel(
            pane: pane, sessionTitle: record?.title, folder: record?.folder ?? record?.launch.folder ?? pane.folder,
            home: home)
    }
}
