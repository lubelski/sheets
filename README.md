<p align="center"><img src="docs/icon.png" width="128" height="128" alt="The sheets app icon: four sheets stacked, each lower and further right than the one under it"></p>

# sheets

A Mac terminal app where everything is a sheet: terminals, browser pages, and the groups
that hold them. Sheets slide over each other instead of replacing each other, so the way
back is always on screen.

`sheets` is a working title.

## Status

Early. The app opens a window with one terminal pane and runs no shell yet. Panes can be
added, closed, renamed, and moved, but nothing is saved, so each launch starts over. The
sidebar and the stack of sheets over it are drawn, with stand-ins where a terminal or a page
will go. The models for the pane tree, the stack of sheets, and split layout are in place with
tests.

## The idea

- Every pane can have children. A group is a pane that summarizes its children.
- The sidebar is that tree. The screen shows one path through it, each sheet over its parent.
- A sheet that gets covered is not redrawn. It stays as it was, underneath.
- A link clicked in a terminal slides a page over that terminal. Dragging it makes it a split.
- Splits are placed by dwindle: a new pane takes half of the focused one.
- Settings is a pane too, not a window. It is pinned at the bottom of the sidebar, Command-comma
  opens it, and each of its sections opens as a sheet over it.

## Using the stack

- Click a row in the sidebar to open the path to that pane, each sheet over its parent.
- Click a row in a group's sheet to open that pane over it.
- Pick another row from the same list while one is open, and its sheet stays where it is. Only
  what is on it changes, with a short fade that moves up for a row lower in the list and down
  for one higher. Sheets that were open above it close.
- Press Escape to close the top sheet.
- Click the strip of a covered sheet to go back to it, or click a row in the strip to open that
  row instead.

## Editing panes

The app starts with one terminal, named `~` for the home folder.

- **New Terminal** (Command-T), **New Group** (Shift-Command-N), and **New Page** are in the
  File menu. The new pane opens as a sheet straight away. It goes last inside the open group,
  just after the open terminal or page, or at the end of the sidebar when nothing is open.
- A new terminal starts in the folder of the nearest group above it that has one, or else the
  home folder, and is named for that folder.
- A new group starts with its name ready to type.
- **Close** (Command-W) closes the top sheet's pane and everything under it. With only the
  sidebar showing, it closes the window. Closing a pane that has panes under it asks first.
- **Rename…** in the File menu edits the top sheet's name in its sidebar row. Return keeps the
  new name, Escape keeps the old one.
- Right-click a sidebar row, or a row in a group's sheet, for the same commands placed near
  that pane. Right-click empty space in a group's sheet to add to that group, or below the
  sidebar's rows to add at the top level.
- Settings and its sections stay as they are: they cannot be closed, renamed, or moved, and
  nothing goes under them.
- Dragging sidebar rows to move panes is an experiment, off by default. Turn it on in
  Settings, Experiments. Drop near the top or bottom of a row to put the pane above or below
  it, or on the middle to put it inside.

## Layout

| Path | What it holds |
|---|---|
| `Sources/SheetsCore` | The logic, with no UI: the pane tree, the sheet stack, dwindle layout |
| `Sources/sheets` | The app |
| `Tests/SheetsCoreTests` | Tests for `SheetsCore` |
| `Resources/AppIcon.icon` | The app icon, an Icon Composer file drawn by `scripts/render-icon.sh` |
| `scripts/bundle.sh` | Builds and signs `build/sheets.app` |
| `scripts/render-previews.sh` | Draws the window's key states to PNG files, with no window on screen |
| `scripts/render-icon.sh` | Redraws the app icon from `AppIconDrawing.swift` |
| `scripts/release.sh` | Builds, notarizes, and publishes a release |

## Building

Needs macOS 27 and Xcode with Swift 6.4.

```sh
swift build
swift test
scripts/bundle.sh
```

`scripts/bundle.sh` builds `build/sheets.app` and does not launch it. Run the bundle, not
`swift run`, so the app gets the current system look.

```sh
open build/sheets.app
```

## Looking at it without opening it

`scripts/render-previews.sh` draws the main window offscreen, mostly with sample panes, and writes
a PNG of each key state in light and dark to `build/renders/`. It runs the app with
`--render-previews <folder>`, which puts no window on screen, shows no Dock icon, takes no
focus, and uses a throwaway preferences suite.

```sh
scripts/render-previews.sh
```

## The icon

The icon is drawn in Swift in `Sources/SheetsCore/AppIconDrawing.swift`, which has a few
candidate designs. `AppIconDrawing.shipped` is the one in the app. `bundle.sh` compiles it with
`actool`.

```sh
scripts/render-icon.sh                      # the shipped design into Resources/AppIcon.icon and docs/icon.png
scripts/render-icon.sh --previews <folder>  # every design and a contact sheet, repo untouched
```

## Updates and releases

The app updates itself with [Sparkle](https://sparkle-project.org). It reads `appcast.xml`
from the latest GitHub Release of this repo, and installs updates signed with the key in
`scripts/sparkle-public-key.txt`.

Only a release build has a feed. A plain `scripts/bundle.sh` build never updates itself and
shows no Check for Updates item, so a development copy is never replaced by a release.

```sh
scripts/release.sh --check          # says whether this Mac can release now, changes nothing
scripts/release.sh 1.2.0 --dry-run  # builds the zip and the feed into build/release, publishes nothing
scripts/release.sh 1.2.0            # builds, signs, notarizes, tags v1.2.0, and publishes the release
```

A release is built from `main` with a clean tree. The setup it needs is described at the top
of `scripts/release.sh`.

## License

MIT. See [LICENSE](LICENSE).
