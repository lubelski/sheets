# The config file

<!-- Made by ConfigReference.markdown() from the key table in Sources/SheetsCore/Config/ConfigKeys.swift. -->
<!-- After changing a key, run: SHEETS_WRITE_CONFIG_REFERENCE=1 swift test --filter ConfigReferenceTests -->

sheets reads its settings from a plain text file, so a person or a tool can change them
with any editor. Settings, Terminal shows the same settings and writes to the same file.

## Where it is

`~/.config/sheets/config`, or `$XDG_CONFIG_HOME/sheets/config` when `XDG_CONFIG_HOME`
is set. `SHEETS_CONFIG_PATH` names another file, for tests.

The file does not need to exist. The app makes it the first time a setting is changed
in Settings.

## How it reads

- One setting per line: `key = value`. Keys are lowercase and dotted, such as
  `terminal.font-size`.
- Every line is valid TOML: strings in double quotes, numbers, `true` and `false`, and
  arrays on one line, such as `["-l"]`. Colors are strings such as `"#1D1E21"`.
  There are no `[tables]`.
- `#` starts a comment, on its own line or after a value.
- The file holds only what differs from the defaults. Remove a line to go back to the
  default.
- The app watches the file and applies a change while it runs. Some settings reach
  only terminals started after the change, as each one says.

## When a line is wrong

The app always starts. A line it cannot use is listed in Settings, Terminal, with its
line number:

- A line with a syntax error, or a value its key does not take, is skipped, and its key
  keeps its last good value, or its default at launch.
- A key the app does not know is skipped with a warning. The line stays in the file.
- A key set twice uses the last line, with a warning.

Changing a setting in Settings rewrites only that setting's line. Comments, blank
lines, the order of lines, and keys the app does not know stay as they are.

## Every setting

The file below sets nothing: every line is a comment showing a key at its default.

```toml
# sheets config file. Each line is one setting, `key = value`, in TOML.
# Lines starting with # are comments. A missing key uses its default, shown here.

# The font family, such as "Menlo".
# Unset by default, which means the system's monospaced font, SF Mono.
# terminal.font-family = "Menlo"

# The font size in points.
# terminal.font-size = 12

# The height of a line, as a multiple of the font's own. 1.2 adds a fifth.
# terminal.line-spacing = 1

# The color of text.
# terminal.foreground = "#DCDDE1"

# The color behind the text.
# terminal.background = "#1D1E21"

# The color of the cursor.
# terminal.cursor-color = "#C9CBD1"

# The color behind selected text.
# terminal.selection-color = "#3A4658"

# The 16 ANSI colors: black, red, green, yellow, blue, magenta, cyan, white, then the bright version of each.
# terminal.palette = ["#2B2D31", "#E0736F", "#8FC17E", "#DDBA6B", "#6FA3E0", "#C390D4", "#6BC3C4", "#C5C7CC", "#5D6067", "#F08F8B", "#A8D896", "#EED08A", "#8DB9EE", "#D5A9E3", "#8AD7D8", "#F0F1F3"]

# The cursor's shape: "block", "underline", or "bar". A program can change it while it runs.
# terminal.cursor-style = "block"

# Whether the cursor blinks.
# terminal.cursor-blink = true

# Which Option keys act as Meta: "off", "left", "right", or "both". Off types characters such as é.
# terminal.option-as-meta = "off"

# Whether selecting text copies it to the clipboard.
# terminal.copy-on-select = false

# Whether programs that ask for the mouse, such as vim and tmux, get clicks and scrolling.
# terminal.mouse-reporting = true

# What the bell does: "none", "sound", "visual", or "sound-and-visual".
# terminal.bell = "sound"

# How many lines a terminal keeps above the screen.
# Applies to terminals started after the change.
# terminal.scrollback-lines = 10000

# The shell's path. It starts as a login shell.
# Unset by default, which means the login shell from your user record, or else /bin/zsh.
# Applies to terminals started after the change.
# terminal.shell = "/bin/zsh"

# Arguments the shell starts with.
# Applies to terminals started after the change.
# terminal.shell-arguments = []

# The folder a new terminal starts in when no group above it has a folder. ~ is the home folder.
# Applies to terminals started after the change.
# terminal.starting-folder = "~"

# Drag sidebar rows to move panes.
# experiments.drag-to-move = false
```
