#!/usr/bin/env bash
# Draws the main window's key states to PNG files in build/renders/, in light and dark, with
# the sample panes. It runs the app with --render-previews, which puts no window on screen,
# shows no Dock icon, takes no focus, and uses a throwaway preferences suite.
#
#   scripts/render-previews.sh           # into build/renders/
#   scripts/render-previews.sh <folder>  # into another folder
set -euo pipefail
cd "$(dirname "$0")/.."

# Use full Xcode for SwiftUI without changing the global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

OUT="${1:-build/renders}"
swift build
BIN="$(swift build --show-bin-path)/sheets"

# A copy of the binary, stamped with the SDK it was built with, as scripts/bundle.sh does.
# SwiftPM writes the deployment target into that field, and a binary that seems built for an
# older SDK draws in the older look.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MIN_OS=27.0
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace -output "$WORK/sheets" "$BIN" 2>/dev/null
STAMPED="$(xcrun vtool -show-build "$WORK/sheets" | awk '$1 == "sdk" { print $2 }')"
if [[ "$STAMPED" != "$SDK_VERSION" ]]; then
  echo "error: the binary is stamped with SDK '$STAMPED', expected '$SDK_VERSION'" >&2
  exit 1
fi
# Changing the binary breaks its signature, so sign the copy again, ad hoc.
codesign --force --sign - "$WORK/sheets" 2>/dev/null

# A sample config file for the renders of Settings, Terminal that read one. It changes a few
# settings, and has a line that cannot be used, an unknown key, and a key set twice, so the
# issues list shows.
cat > "$WORK/config" <<'CONFIG'
# Sample config for the renders.
terminal.font-size = 13
terminal.line-spacing = 1.1
terminal.background = "#16181C"   # a little darker
terminal.cursor-style = "bar"
terminal.cursor-blink = false
terminal.option-as-meta = "left"
terminal.scrollback-lines = lots
terminal.shell-arguments = ["-l"]
terminal.font-size = 14
terminal.colour = "#FFFFFF"
CONFIG

# Sparkle is found next to the original binary.
mkdir -p "$OUT"
rm -f "$OUT"/*.png
SHEETS_CONFIG_PATH="$WORK/config" DYLD_FRAMEWORK_PATH="$(dirname "$BIN")" "$WORK/sheets" --render-previews "$OUT"
