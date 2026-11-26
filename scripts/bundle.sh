#!/usr/bin/env bash
# Builds sheets.app into ./build. It installs nothing and launches nothing.
#
# Environment, all optional:
#   SHEETS_BUNDLE_DIR        The folder the app goes in. Defaults to build. Use another to
#                            check a build while a copy from build runs.
#   SHEETS_VERSION           The version to show, such as 1.2.0. Defaults to the latest v* tag,
#                            or 0.1 without one.
#   SHEETS_SIGNING_IDENTITY  The signing identity. See "Sign" below for the default.
#
# Not here yet: Sparkle, the app icon, and entitlements. The app is not sandboxed, since a
# terminal has to start shells and other programs as the person who runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

# Use full Xcode for SwiftUI without changing the global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

SWIFT_ARGS=(-c release --arch arm64)
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/sheets"

BUNDLE_DIR="${SHEETS_BUNDLE_DIR:-build}"
mkdir -p "$BUNDLE_DIR"
APP="$BUNDLE_DIR/sheets.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/sheets"

# SwiftPM writes the deployment target into the binary's SDK field. macOS reads that field
# to decide whether to run the app in a compatibility mode for older apps, so stamp the
# SDK the app was really built with.
MIN_OS=27.0
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/sheets" "$APP/Contents/MacOS/sheets"
STAMPED="$(xcrun vtool -show-build "$APP/Contents/MacOS/sheets" | awk '$1 == "sdk" { print $2 }')"
if [[ "$STAMPED" != "$SDK_VERSION" ]]; then
  echo "error: the binary is stamped with SDK '$STAMPED', expected '$SDK_VERSION'" >&2
  exit 1
fi

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  GIT_COMMIT="$GIT_COMMIT-dirty"
fi
LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
VERSION="${SHEETS_VERSION:-${LATEST_TAG#v}}"
VERSION="${VERSION:-0.1}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>sheets</string>
  <key>CFBundleDisplayName</key><string>Sheets</string>
  <key>CFBundleIdentifier</key><string>dev.lubelski.sheets</string>
  <key>CFBundleExecutable</key><string>sheets</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>SheetsGitCommit</key><string>$GIT_COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign. The identity is the first of these that exists, as in mac-os-agent:
#   1. SHEETS_SIGNING_IDENTITY, when it is set.
#   2. A Developer ID Application certificate in the keychain.
#   3. This Mac's self-signed "sheets development" certificate, if the owner made one. This
#      script never makes one.
#   4. Ad hoc.
DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
if [[ -n "${SHEETS_SIGNING_IDENTITY:-}" ]]; then
  IDENTITY="$SHEETS_SIGNING_IDENTITY"
elif [[ -n "$DEVELOPER_ID" ]]; then
  IDENTITY="$DEVELOPER_ID"
elif security find-certificate -c "sheets development" >/dev/null 2>&1; then
  IDENTITY="sheets development"
else
  IDENTITY="-"
fi
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" == *"Developer ID Application"* ]]; then
  # Notarization needs the hardened runtime and a secure timestamp.
  SIGN+=(--options runtime --timestamp)
fi
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signed ad hoc."
else
  echo "Signed with \"$IDENTITY\""
fi
echo "Built $APP, version $VERSION ($BUILD_NUMBER), commit $GIT_COMMIT"
