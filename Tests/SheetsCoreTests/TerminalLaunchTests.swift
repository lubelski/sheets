import Testing
@testable import SheetsCore

@Suite struct TerminalLaunchTests {
    let user = TerminalUser(shell: "/opt/shells/fish", home: "/home/someone", name: "someone")
    let folders: Set<String> = ["/home/someone", "/home/someone/projects"]
    let programs: Set<String> = ["/opt/shells/fish", "/bin/zsh"]

    func launch(
        in folder: String? = nil, user: TerminalUser? = nil, environment: [String: String] = [:],
        language: String? = "en", region: String? = "US", folders: Set<String>? = nil
    ) -> TerminalLaunch {
        let folders = folders ?? self.folders
        let programs = self.programs
        return TerminalLaunch.loginShell(
            in: folder, user: user ?? self.user, inheritedEnvironment: environment, language: language,
            region: region, programVersion: "1.2", isFolder: { folders.contains($0) },
            isExecutable: { programs.contains($0) })
    }

    // MARK: The shell

    @Test func theUsersShellRunsAsALoginShell() {
        let launch = launch()
        #expect(launch.executable == "/opt/shells/fish")
        #expect(launch.programName == "-fish")
        #expect(launch.arguments.isEmpty)
        #expect(launch.environment["SHELL"] == "/opt/shells/fish")
    }

    @Test func aMissingOrUnusableShellFallsBackToZsh() {
        for shell in [nil, "", "fish", "/nowhere/sh"] {
            let launch = launch(user: TerminalUser(shell: shell, home: "/home/someone", name: "someone"))
            #expect(launch.executable == "/bin/zsh", "shell \(shell ?? "nil")")
            #expect(launch.programName == "-zsh")
            #expect(launch.environment["SHELL"] == "/bin/zsh")
        }
    }

    // MARK: The folder

    @Test func itStartsInThePanesFolder() {
        #expect(launch(in: "/home/someone/projects").folder == "/home/someone/projects")
    }

    @Test func aMissingFolderFallsBackToHome() {
        #expect(launch(in: nil).folder == "/home/someone")
        #expect(launch(in: "").folder == "/home/someone")
        #expect(launch(in: "/home/someone/gone").folder == "/home/someone")
    }

    @Test func aMissingHomeFallsBackToTheRoot() {
        #expect(launch(in: "/gone", folders: []).folder == "/")
    }

    // MARK: The environment

    @Test func theTerminalsOwnVariablesAreSet() {
        let environment = launch(environment: ["TERM": "dumb", "TERM_PROGRAM": "Other"]).environment
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["COLORTERM"] == "truecolor")
        #expect(environment["TERM_PROGRAM"] == "sheets")
        #expect(environment["TERM_PROGRAM_VERSION"] == "1.2")
    }

    @Test func theAppsEnvironmentPassesThrough() {
        let environment = launch(environment: [
            "PATH": "/usr/local/bin:/usr/bin", "SSH_AUTH_SOCK": "/tmp/agent", "HOME": "/home/elsewhere",
            "LANG": "fr_FR.UTF-8",
        ]).environment
        #expect(environment["PATH"] == "/usr/local/bin:/usr/bin")
        #expect(environment["SSH_AUTH_SOCK"] == "/tmp/agent")
        #expect(environment["HOME"] == "/home/elsewhere")
        #expect(environment["LANG"] == "fr_FR.UTF-8")
    }

    @Test func variablesFromWhateverLaunchedTheAppAreLeftOut() {
        let environment = launch(environment: [
            "TERM_SESSION_ID": "w0t0p0", "ITERM_PROFILE": "Default", "XPC_SERVICE_NAME": "0",
            "DYLD_FRAMEWORK_PATH": "/somewhere", "PWD": "/elsewhere", "SHLVL": "2", "KEEP": "yes",
        ]).environment
        for name in ["TERM_SESSION_ID", "ITERM_PROFILE", "XPC_SERVICE_NAME", "DYLD_FRAMEWORK_PATH", "PWD", "SHLVL"] {
            #expect(environment[name] == nil, "\(name)")
        }
        #expect(environment["KEEP"] == "yes")
    }

    @Test func missingBasicsAreFilledIn() {
        let environment = launch(environment: ["LANG": ""]).environment
        #expect(environment["HOME"] == "/home/someone")
        #expect(environment["USER"] == "someone")
        #expect(environment["LOGNAME"] == "someone")
        #expect(environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environment["LANG"] == "en_US.UTF-8")
    }

    @Test func langComesFromTheLanguageAndRegion() {
        #expect(TerminalLaunch.lang(language: "de", region: "CH") == "de_CH.UTF-8")
        #expect(TerminalLaunch.lang(language: "EN", region: "gb") == "en_GB.UTF-8")
        #expect(TerminalLaunch.lang(language: nil, region: "US") == "en_US.UTF-8")
        #expect(TerminalLaunch.lang(language: "en", region: "001") == "en_US.UTF-8")
        #expect(TerminalLaunch.lang(language: "x-y", region: "US") == "en_US.UTF-8")
    }

    @Test func theEnvironmentListIsSortedNameValuePairs() {
        let launch = TerminalLaunch(executable: "/bin/zsh", folder: "/", environment: ["B": "2", "A": "1"])
        #expect(launch.environmentList == ["A=1", "B=2"])
        #expect(launch.programName == "/bin/zsh")
    }

    @Test func theRealLaunchIsALoginShellInAFolderThatExists() {
        let launch = TerminalLaunch.loginShell(in: "/nowhere/at/all", programVersion: nil)
        #expect(launch.programName.hasPrefix("-"))
        #expect(launch.executable.hasPrefix("/"))
        #expect(launch.folder != "/nowhere/at/all")
        #expect(launch.environment["TERM"] == "xterm-256color")
    }
}

@Suite struct TerminalFolderReportTests {
    let names: Set<String> = ["someones-mac.local", "someones-mac"]

    func folder(_ report: String) -> String? {
        TerminalEvent.folder(fromReport: report, localHostNames: names)
    }

    @Test func aFileURLOnThisMacIsItsPath() {
        #expect(folder("file://someones-mac.local/home/someone/a%20b") == "/home/someone/a b")
        #expect(folder("file://Someones-Mac/home/someone") == "/home/someone")
        #expect(folder("file://localhost/tmp") == "/tmp")
        #expect(folder("file:///tmp") == "/tmp")
    }

    @Test func aPlainPathIsItself() {
        #expect(folder("/home/someone") == "/home/someone")
    }

    @Test func anotherHostOrSchemeIsNoFolderHere() {
        #expect(folder("file://server.example/home/someone") == nil)
        #expect(folder("https://example.com/") == nil)
        #expect(folder("not a path") == nil)
    }
}

@Suite struct TerminalLaunchShellSettingTests {
    let user = TerminalUser(shell: "/bin/zsh", home: "/home/someone", name: "someone")

    func launch(shell: String?, arguments: [String] = [], executable: Set<String>) -> TerminalLaunch {
        TerminalLaunch.loginShell(
            in: nil, shell: shell, arguments: arguments, user: user, inheritedEnvironment: [:], language: "en",
            region: "US", programVersion: nil, isFolder: { $0 == "/home/someone" },
            isExecutable: { executable.contains($0) })
    }

    @Test func aChosenShellThatCanRunIsUsedWithItsArguments() {
        let launch = launch(shell: "/opt/fish", arguments: ["-l", "--private"], executable: ["/opt/fish", "/bin/zsh"])
        #expect(launch.executable == "/opt/fish")
        #expect(launch.programName == "-fish")
        #expect(launch.arguments == ["-l", "--private"])
        #expect(launch.environment["SHELL"] == "/opt/fish")
    }

    @Test func aChosenShellThatCannotRunFallsBackToTheUsersShell() {
        #expect(launch(shell: "/no/such/shell", executable: ["/bin/zsh"]).executable == "/bin/zsh")
        #expect(launch(shell: "fish", executable: ["fish", "/bin/zsh"]).executable == "/bin/zsh")
        #expect(launch(shell: nil, executable: ["/bin/zsh"]).executable == "/bin/zsh")
    }
}
