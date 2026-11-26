#!/usr/bin/env bash
# Builds, signs, notarizes and publishes a release that installed copies update to.
#
#   scripts/release.sh 1.2.0            # publish version 1.2.0 from main
#   scripts/release.sh 1.2.0 --dry-run  # build the files into build/release, publish nothing
#   scripts/release.sh --check          # say whether this Mac can release now, change nothing
#
# A release is a GitHub Release tagged v<version> with two files: the zipped app and
# appcast.xml, the feed Sparkle reads. Installed copies fetch the feed from the latest
# release, so publishing the release is what ships the update.
#
# --check needs no version and no clean tree. It prints one line for each of the Developer
# ID identity, the notarization credentials (with a real notarytool history call), the
# Sparkle public key, and the gh login, and exits 0 only when all of them work.
#
# One-time setup on the Mac that releases:
#   1. A Developer ID Application certificate in the Keychain.
#   2. Notarization credentials, one of these two:
#      a. An App Store Connect API key. This is the way to release with the screen locked
#         or with no one at the Mac. Make a team key in App Store Connect, Users and Access,
#         Integrations, and put three lines in ~/.appstoreconnect/notary.conf (mode 600):
#           NOTARY_KEY_FILE=~/.appstoreconnect/private_keys/AuthKey_<key id>.p8
#           NOTARY_KEY_ID=<key id>
#           NOTARY_ISSUER_ID=<issuer id>
#         The file is read as KEY=VALUE lines, never run. Blank lines and # comments are
#         ignored, and any other key is an error.
#      b. A notarization login in the Keychain:  xcrun notarytool store-credentials AIMeter
#         It works for a person at the Mac. macOS does not open it while the screen is
#         locked. The login belongs to the Apple ID, not the app, so one profile serves every
#         app released from that Mac. SHEETS_NOTARY_PROFILE picks another name.
#      The script uses the first that is set up: NOTARY_KEY_FILE, NOTARY_KEY_ID, and
#      NOTARY_ISSUER_ID in the environment, then the conf file, then the keychain profile.
#      A conf file that exists but is incomplete, or names a key file that is not there,
#      stops the release instead of falling back.
#   3. The Sparkle private signing key in the Keychain, the pair of the public key in
#      scripts/sparkle-public-key.txt. The key is shared with the other apps released from
#      the same Mac, so do not make a new one. Without it, installed copies can't be updated.
#
# Environment, all optional:
#   SHEETS_RELEASE_REPO      The GitHub repository that hosts releases. Defaults to
#                            lubelski/sheets. Installed copies download the feed and the zip
#                            without signing in, so it must be public.
#   NOTARY_KEY_FILE          The API key's .p8 file, its key ID, and its issuer ID.
#   NOTARY_KEY_ID            Used only when all three are set, ahead of the conf file.
#   NOTARY_ISSUER_ID
#   NOTARY_CONF              The file with the API key lines. Defaults to
#                            ~/.appstoreconnect/notary.conf.
#   SHEETS_NOTARY_PROFILE    The notarytool profile name, used when there is no API key.
#                            Defaults to AIMeter.
#   SHEETS_SPARKLE_KEY_FILE  A file with the private signing key, instead of the Keychain.
#   SHEETS_PUBLIC_KEY        The public signing key, instead of scripts/sparkle-public-key.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "usage: scripts/release.sh <version> [--dry-run]   (for example 1.2.0)" >&2
  echo "       scripts/release.sh --check" >&2
  exit 2
}

VERSION="${1:-}"
CHECK_ONLY=false
DRY_RUN=false
if [[ "$VERSION" == "--check" ]]; then
  CHECK_ONLY=true
  [[ $# -eq 1 ]] || usage
else
  [[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || usage
fi

REPO="${SHEETS_RELEASE_REPO:-lubelski/sheets}"
NOTARY_PROFILE="${SHEETS_NOTARY_PROFILE:-AIMeter}"
TAG="v$VERSION"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
OUT=build/release
ZIP="$OUT/sheets-$VERSION.zip"

fail() { echo "error: $*" >&2; exit 1; }

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# --- Notarization credentials ---

NOTARY_CONF_DEFAULT="$HOME/.appstoreconnect/notary.conf"
NOTARY_CONF="${NOTARY_CONF:-$NOTARY_CONF_DEFAULT}"
NOTARY_ARGS=()
NOTARY_METHOD=""
NOTARY_USES_KEY=false
NOTARY_ERROR=""
# A blank line or a comment in the conf file.
NOTARY_SKIP_LINE='^[[:space:]]*(#.*)?$'

# Sets NOTARY_ARGS, the arguments every notarytool call gets, and NOTARY_METHOD, which
# names the method for the log. On a problem it sets NOTARY_ERROR and returns 1. Nothing
# it prints holds the key ID, the issuer ID, or the key file's path.
choose_notary_credentials() {
  local key_file="${NOTARY_KEY_FILE:-}" key_id="${NOTARY_KEY_ID:-}" issuer="${NOTARY_ISSUER_ID:-}"
  local from line name value missing=""
  # shellcheck disable=SC2088 # The tilde is text for messages, not a path to expand.
  local conf_name="~/.appstoreconnect/notary.conf"
  [[ "$NOTARY_CONF" == "$NOTARY_CONF_DEFAULT" ]] || conf_name="the file NOTARY_CONF names"

  if [[ -n "$key_file" && -n "$key_id" && -n "$issuer" ]]; then
    from="the environment"
  elif [[ -e "$NOTARY_CONF" ]]; then
    from="$conf_name"
    key_file="" key_id="" issuer=""
    if [[ ! -f "$NOTARY_CONF" || ! -r "$NOTARY_CONF" ]]; then
      NOTARY_ERROR="$conf_name is not a readable file"
      return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ "$line" =~ $NOTARY_SKIP_LINE ]] && continue
      if [[ "$line" != *=* ]]; then
        NOTARY_ERROR="$conf_name has a line that is not KEY=VALUE"
        return 1
      fi
      name="${line%%=*}"
      name="${name#"${name%%[![:space:]]*}"}"
      name="${name%"${name##*[![:space:]]}"}"
      value="${line#*=}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      case "$name" in
        NOTARY_KEY_FILE) key_file="$value" ;;
        NOTARY_KEY_ID) key_id="$value" ;;
        NOTARY_ISSUER_ID) issuer="$value" ;;
        *)
          NOTARY_ERROR="$conf_name sets $name. It may set only NOTARY_KEY_FILE, NOTARY_KEY_ID, and NOTARY_ISSUER_ID"
          return 1
          ;;
      esac
    done < "$NOTARY_CONF"
    [[ -n "$key_file" ]] || missing="$missing NOTARY_KEY_FILE"
    [[ -n "$key_id" ]] || missing="$missing NOTARY_KEY_ID"
    [[ -n "$issuer" ]] || missing="$missing NOTARY_ISSUER_ID"
    if [[ -n "$missing" ]]; then
      NOTARY_ERROR="$conf_name is incomplete. It does not set:$missing"
      return 1
    fi
  else
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    NOTARY_METHOD="the keychain profile '$NOTARY_PROFILE'"
    NOTARY_USES_KEY=false
    return 0
  fi

  # shellcheck disable=SC2088 # A leading ~/ in the value is expanded here, by hand.
  if [[ "$key_file" == "~/"* ]]; then
    key_file="$HOME/${key_file#"~/"}"
  fi
  if [[ ! -f "$key_file" || ! -r "$key_file" ]]; then
    NOTARY_ERROR="NOTARY_KEY_FILE, from $from, names a key file that is missing or not a readable file"
    return 1
  fi
  NOTARY_ARGS=(--key "$key_file" --key-id "$key_id" --issuer "$issuer")
  NOTARY_METHOD="the App Store Connect API key from $from"
  NOTARY_USES_KEY=true
}

# A read-only call that proves the credentials work.
notary_works() { xcrun notarytool history "${NOTARY_ARGS[@]}" >/dev/null 2>&1; }

# --- Checks, before anything is built ---

PUBLIC_KEY="${SHEETS_PUBLIC_KEY:-$(cat scripts/sparkle-public-key.txt 2>/dev/null || true)}"

if $CHECK_ONLY; then
  ready=true

  printf '%-28s ' "Developer ID identity:"
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ "$identities" == *"Developer ID Application"* ]]; then
    echo "ok"
  else
    echo "MISSING - see step 1 at the top of this script"; ready=false
  fi

  printf '%-28s ' "Notarization credentials:"
  if ! choose_notary_credentials; then
    echo "FAILED - $NOTARY_ERROR"; ready=false
  elif notary_works; then
    echo "ok, with $NOTARY_METHOD"
  else
    echo "FAILED - notarytool history did not work with $NOTARY_METHOD. See step 2 at the top of this script"; ready=false
  fi

  printf '%-28s ' "Sparkle public key:"
  if [[ -n "$PUBLIC_KEY" ]]; then
    echo "ok"
  else
    echo "MISSING - see step 3 at the top of this script"; ready=false
  fi

  printf '%-28s ' "gh auth:"
  if gh auth status >/dev/null 2>&1; then
    echo "ok"
  else
    echo "MISSING - run: gh auth login"; ready=false
  fi

  if $ready; then
    echo "Ready to release."
    exit 0
  fi
  echo "Not ready."
  exit 1
fi

[[ -n "$PUBLIC_KEY" ]] || fail "no Sparkle public key. See step 3 at the top of this script."

if ! $DRY_RUN; then
  [[ -z "$(git status --porcelain)" ]] || fail "the working tree has uncommitted changes"
  git fetch --quiet origin main --tags
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || fail "HEAD is not origin/main. Releases are built from main, so build numbers only grow."
  git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null && fail "tag $TAG already exists"
  security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || fail "no Developer ID Application certificate in the Keychain"
  choose_notary_credentials || fail "$NOTARY_ERROR"
  echo "Notarizing with $NOTARY_METHOD"
  if ! notary_works; then
    if $NOTARY_USES_KEY; then
      fail "notarytool history did not work with $NOTARY_METHOD. See step 2 at the top of this script."
    fi
    fail "no notarytool profile named '$NOTARY_PROFILE'. Run: xcrun notarytool store-credentials $NOTARY_PROFILE"
  fi
fi

# --- Build ---

# The bundle goes in build/, whatever SHEETS_BUNDLE_DIR says, so the steps below find it.
SHEETS_BUNDLE_DIR=build \
SHEETS_VERSION="$VERSION" \
SHEETS_FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml" \
SHEETS_PUBLIC_KEY="$PUBLIC_KEY" \
  ./scripts/bundle.sh

APP="build/sheets.app"
rm -rf "$OUT"
mkdir -p "$OUT"

# --- Notarize ---

if $DRY_RUN; then
  echo "Dry run: skipping notarization"
else
  # Apple notarizes an archive, but the ticket is stapled to the app. So zip, submit,
  # staple, and zip again below with the ticket inside.
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" "${NOTARY_ARGS[@]}" --wait
  rm "$OUT/notarize.zip"
  xcrun stapler staple "$APP"
  spctl --assess --type execute "$APP"
fi

# --- Feed ---

ditto -c -k --keepParent "$APP" "$ZIP"
KEY_ARGS=()
[[ -n "${SHEETS_SPARKLE_KEY_FILE:-}" ]] && KEY_ARGS=(--ed-key-file "$SHEETS_SPARKLE_KEY_FILE")
"$SPARKLE_BIN/generate_appcast" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$REPO" \
  -o "$OUT/appcast.xml" "$OUT"
grep -q 'sparkle:edSignature=' "$OUT/appcast.xml" || fail "the feed has no signature for the update"

if $DRY_RUN; then
  echo "Dry run: built $ZIP and $OUT/appcast.xml, published nothing"
  exit 0
fi

# --- Publish ---

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" --title "Sheets $VERSION" --generate-notes
echo "Released $TAG. Installed copies pick it up at their next update check."
