import Foundation

/// What a session starts: a program, its arguments, the folder it starts in, and its
/// environment.
public struct TerminalLaunch: Hashable, Sendable {
    /// The program's path.
    public var executable: String
    /// The arguments after the program's name.
    public var arguments: [String]
    /// The name the program sees as its own, `argv[0]`. A leading `-` asks a shell to run as a
    /// login shell, the way `login` starts one.
    public var programName: String
    /// The folder the program starts in.
    public var folder: String
    public var environment: [String: String]

    public init(
        executable: String, arguments: [String] = [], programName: String? = nil, folder: String,
        environment: [String: String]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.programName = programName ?? executable
        self.folder = folder
        self.environment = environment
    }

    /// The environment as `NAME=value` strings, sorted by name, as `execve` takes it.
    public var environmentList: [String] {
        environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    }
}

/// The person the app runs as, from the user record.
public struct TerminalUser: Hashable, Sendable {
    /// The login shell. Nil or empty when the record has none.
    public var shell: String?
    public var home: String
    public var name: String?

    public init(shell: String?, home: String, name: String?) {
        self.shell = shell
        self.home = home
        self.name = name
    }

    /// The person running the app, from the user database, with the home folder from
    /// Foundation when the database has none.
    public static func current() -> TerminalUser {
        guard let record = getpwuid(getuid()) else {
            return TerminalUser(shell: nil, home: NSHomeDirectory(), name: nil)
        }
        func string(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
            pointer.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        return TerminalUser(
            shell: string(record.pointee.pw_shell), home: string(record.pointee.pw_dir) ?? NSHomeDirectory(),
            name: string(record.pointee.pw_name))
    }
}

extension TerminalLaunch {
    /// The shell used when the user record names none that can run.
    public static let fallbackShell = "/bin/zsh"

    /// The values a terminal sets in its shell's environment, whatever was there.
    public static func terminalVariables(programVersion: String?) -> [String: String] {
        var variables = [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "TERM_PROGRAM": "sheets",
        ]
        if let programVersion, !programVersion.isEmpty { variables["TERM_PROGRAM_VERSION"] = programVersion }
        return variables
    }

    /// Variables that describe the program that launched the app, or another terminal, rather
    /// than this one. They are left out of the shell's environment.
    static let launcherVariables: Set<String> = [
        "TERM_SESSION_ID", "TERM_PROGRAM_VERSION", "TERMINFO", "COLORFGBG", "LC_TERMINAL",
        "LC_TERMINAL_VERSION", "ITERM_SESSION_ID", "ITERM_PROFILE", "KITTY_WINDOW_ID", "KITTY_PID",
        "WEZTERM_PANE", "ALACRITTY_WINDOW_ID", "VTE_VERSION", "INSIDE_EMACS", "XPC_SERVICE_NAME",
        "XPC_FLAGS", "__CFBundleIdentifier", "PWD", "OLDPWD", "SHLVL", "_",
    ]

    /// Prefixes of variables that are left out for the same reason. `DYLD_` variables change
    /// how every program the shell runs is loaded, so they never pass through.
    static let launcherPrefixes = ["DYLD_", "GHOSTTY_", "ITERM_", "VSCODE_"]

    /// The person's login shell, started as a login shell in a folder.
    ///
    /// - The shell is the user record's, when it is an absolute path that can run, or else
    ///   `/bin/zsh`. Its name starts with `-`, which makes it a login shell.
    /// - It starts in `folder` when that is a folder, or else the home folder.
    /// - The environment is the app's own, without variables that belong to whatever launched
    ///   the app, with the terminal's variables set (`TERM=xterm-256color`,
    ///   `COLORTERM=truecolor`, `TERM_PROGRAM=sheets`), and `SHELL` set to the shell. `HOME`,
    ///   `USER`, `LOGNAME`, `PATH`, and `LANG` are filled in when they are missing. `LANG`
    ///   comes from the language and region, as `en_US.UTF-8`.
    ///
    /// Every input is a parameter, so tests can give their own. `loginShell(in:)` gives the
    /// real ones.
    public static func loginShell(
        in folder: String?, user: TerminalUser, inheritedEnvironment: [String: String], language: String?,
        region: String?, programVersion: String?, isFolder: (String) -> Bool, isExecutable: (String) -> Bool
    ) -> TerminalLaunch {
        let shell = user.shell.flatMap { $0.hasPrefix("/") && isExecutable($0) ? $0 : nil } ?? fallbackShell
        let start: String
        if let folder, !folder.isEmpty, isFolder(folder) {
            start = folder
        } else {
            start = isFolder(user.home) ? user.home : "/"
        }

        var environment = inheritedEnvironment.filter { name, _ in
            !launcherVariables.contains(name) && !launcherPrefixes.contains { name.hasPrefix($0) }
        }
        environment.merge(terminalVariables(programVersion: programVersion)) { _, new in new }
        environment["SHELL"] = shell
        func fill(_ name: String, _ value: String?) {
            if let value, environment[name]?.isEmpty ?? true { environment[name] = value }
        }
        fill("HOME", user.home)
        fill("USER", user.name)
        fill("LOGNAME", user.name)
        fill("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
        fill("LANG", lang(language: language, region: region))

        let name = "-" + (shell as NSString).lastPathComponent
        return TerminalLaunch(executable: shell, programName: name, folder: start, environment: environment)
    }

    /// `loginShell` with this Mac's real user, environment, language, and files.
    public static func loginShell(in folder: String?, programVersion: String?) -> TerminalLaunch {
        let files = FileManager.default
        let locale = Locale.current
        return loginShell(
            in: folder, user: .current(), inheritedEnvironment: ProcessInfo.processInfo.environment,
            language: locale.language.languageCode?.identifier, region: locale.region?.identifier,
            programVersion: programVersion,
            isFolder: { path in
                var isDirectory: ObjCBool = false
                return files.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            },
            isExecutable: { files.isExecutableFile(atPath: $0) })
    }

    /// A `LANG` value from a language and region, such as `en_US.UTF-8`. `en_US.UTF-8` when
    /// either is missing or is not plain letters, since a shell given a locale it does not
    /// know falls back to ASCII.
    public static func lang(language: String?, region: String?) -> String {
        func letters(_ value: String?, count: ClosedRange<Int>) -> String? {
            guard let value, count.contains(value.count), value.allSatisfy({ $0.isASCII && $0.isLetter }) else {
                return nil
            }
            return value
        }
        guard let language = letters(language, count: 2...3)?.lowercased(),
              let region = letters(region, count: 2...2)?.uppercased()
        else { return "en_US.UTF-8" }
        return "\(language)_\(region).UTF-8"
    }
}
