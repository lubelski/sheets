#!/usr/bin/env bash
# Redraws the app icon, Resources/AppIcon.icon, from Sources/SheetsCore/AppIconDrawing.swift,
# and the picture of it in docs/icon.png. Run it after changing the drawing. bundle.sh
# compiles the icon itself. It writes files only and launches nothing.
#
#   scripts/render-icon.sh                     # the shipped design, AppIconDrawing.shipped
#   scripts/render-icon.sh 3                   # design 3 instead
#   scripts/render-icon.sh --previews <folder> # every design at 1024, 256, 64, and 32 px, and a
#                                              # contact sheet. Leaves the repo alone.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -O -o "$WORK/render-icon" scripts/icon/main.swift Sources/SheetsCore/AppIconDrawing.swift

# Icon Composer's own renderer, which draws the icon as macOS does, with the system's glass.
ICTOOL="$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"
export_png() { # <icon> <output> <pixels>
  "$ICTOOL" "$1" --export-image --output-file "$2" \
    --platform macOS --rendition Default --width "$3" --height "$3" --scale 1 >/dev/null
}

if [[ "${1:-}" == "--previews" ]]; then
  OUT="${2:?usage: scripts/render-icon.sh --previews <folder>}"
  [[ -x "$ICTOOL" ]] || { echo "error: Icon Composer's ictool is not in this Xcode" >&2; exit 1; }
  mkdir -p "$OUT"
  DESIGNS="$(sed -n 's/^ *case [a-zA-Z]* = \([0-9]*\)$/\1/p' Sources/SheetsCore/AppIconDrawing.swift)"
  for n in $DESIGNS; do
    "$WORK/render-icon" "$WORK/design-$n.icon" "$n" >/dev/null
    for px in 1024 256 64 32; do
      export_png "$WORK/design-$n.icon" "$OUT/design-$n-$px.png" "$px"
    done
  done
  "$WORK/render-icon" --sheet "$OUT"
  echo "Drew designs $(echo $DESIGNS | tr ' ' ',') into $OUT"
  exit 0
fi

"$WORK/render-icon" Resources/AppIcon.icon "$@"

mkdir -p docs
if [[ -x "$ICTOOL" ]]; then
  "$ICTOOL" Resources/AppIcon.icon --export-image --output-file docs/icon.png \
    --platform macOS --rendition Default --width 256 --height 256 --scale 2 >/dev/null
  echo "Drew docs/icon.png"
else
  echo "warning: Icon Composer's ictool is not in this Xcode, so docs/icon.png is unchanged" >&2
fi
