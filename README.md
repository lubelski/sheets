# sheets

A Mac terminal app where everything is a sheet: terminals, browser pages, and the groups
that hold them. Sheets slide over each other instead of replacing each other, so the way
back is always on screen.

`sheets` is a working title.

## Status

Early. The app opens a window with sample data and runs no shell yet. The models for the
pane tree, the stack of sheets, and split layout are in place with tests.

## The idea

- Every pane can have children. A group is a pane that summarizes its children.
- The sidebar is that tree. The screen shows one path through it, each sheet over its parent.
- A sheet that gets covered is not redrawn. It stays as it was, underneath.
- A link clicked in a terminal slides a page over that terminal. Dragging it makes it a split.
- Splits are placed by dwindle: a new pane takes half of the focused one.

## Layout

| Path | What it holds |
|---|---|
| `Sources/SheetsCore` | The logic, with no UI: the pane tree, the sheet stack, dwindle layout |
| `Sources/sheets` | The app |
| `Tests/SheetsCoreTests` | Tests for `SheetsCore` |
| `scripts/bundle.sh` | Builds and signs `build/sheets.app` |
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
