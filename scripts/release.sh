#!/usr/bin/env bash
# Port Killer local release script. Builds, signs and packages the app.
#
#   Mode A (default, no Developer ID / no NOTARY_PROFILE): ad-hoc signed, NOT notarized .zip and .dmg
#   Mode B (Developer ID identity + NOTARY_PROFILE env): signed, notarized, stapled .dmg
#
# Usage: scripts/release.sh [--version X.Y.Z] [--out DIR] [--notarize] [--dry-run]
#
# Credentials are only read from the keychain (notarytool keychain profile name in
# $NOTARY_PROFILE). Nothing is published, pushed, tagged or uploaded.
set -euo pipefail

APP_NAME="Port Killer"
SCHEME="Port Killer"
PROJECT="Port Killer.xcodeproj"
ZIP_PREFIX="Port-Killer"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
OUT_DIR="./dist"
NOTARIZE=0
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: scripts/release.sh [--version X.Y.Z] [--out DIR] [--notarize] [--dry-run]
  --version X.Y.Z  Version used in file names (default: MARKETING_VERSION from the project)
  --out DIR        Output directory (default: ./dist)
  --notarize       Force notarization mode (Mode B); fails if Developer ID or NOTARY_PROFILE is missing
  --dry-run        Print what would run; build, sign and package nothing
Env: NOTARY_PROFILE  name of an 'xcrun notarytool store-credentials' keychain profile
USAGE
}

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ $# -ge 2 ]] || die "--version needs a value"; VERSION="$2"; shift 2 ;;
    --out)     [[ $# -ge 2 ]] || die "--out needs a value"; OUT_DIR="$2"; shift 2 ;;
    --notarize) NOTARIZE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

# Quote a command for display.
show() { printf '+'; printf ' %q' "$@"; printf '\n'; }
# Run a command, or only print it with --dry-run.
run() {
  show "$@"
  if [[ $DRY_RUN -eq 0 ]]; then "$@"; fi
}

cd "$REPO_ROOT"

# Xcode: prefer the full Xcode if xcode-select points at CommandLineTools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]] \
   && [[ "$(xcode-select -p 2>/dev/null)" != *Xcode*.app* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Version.
if [[ -z "$VERSION" ]]; then
  VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
      -showBuildSettings 2>/dev/null | awk -F' = ' '/^[[:space:]]*MARKETING_VERSION = /{print $2; exit}')"
  [[ -n "$VERSION" ]] || die "could not read MARKETING_VERSION; pass --version"
fi
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-.][0-9A-Za-z.]+)?$ ]] || die "invalid version: $VERSION"

# Output dir (absolute).
if [[ $DRY_RUN -eq 0 ]]; then mkdir -p "$OUT_DIR"; OUT_DIR="$(cd "$OUT_DIR" && pwd)"; fi

# Mode selection.
DEV_ID=""
IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -n 1 || true)"
if [[ -n "$IDENTITY_LINE" ]]; then
  DEV_ID="$(awk '{print $2}' <<<"$IDENTITY_LINE")"  # SHA-1 hash of the identity
fi
MODE="A"
if [[ -n "$DEV_ID" && -n "${NOTARY_PROFILE:-}" ]]; then
  MODE="B"
elif [[ $NOTARIZE -eq 1 ]]; then
  [[ -n "$DEV_ID" ]] || die "--notarize requested but no 'Developer ID Application' identity found (security find-identity -v -p codesigning)"
  die "--notarize requested but NOTARY_PROFILE is not set (name of a notarytool keychain profile)"
fi

echo "== Port Killer release $VERSION, mode $MODE, out: $OUT_DIR"
[[ $DRY_RUN -eq 1 ]] && echo "== DRY RUN: nothing below is executed"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/portkiller-release.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT
DERIVED="$WORK_DIR/DerivedData"
APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"

# Universal build if the toolchain can produce both slices.
ARCH_ARGS=()
if xcrun --sdk macosx clang -arch arm64 -arch x86_64 -x c -fsyntax-only /dev/null >/dev/null 2>&1; then
  ARCH_ARGS=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
else
  echo "note: toolchain cannot target both arm64 and x86_64; building for the host arch only"
fi

# Signing is done manually below, so the build itself is unsigned.
NOSIGN=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)

echo "== 1/4 Unit tests"
run xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
  -derivedDataPath "$WORK_DIR/TestDerivedData" "${NOSIGN[@]}" -quiet

echo "== 2/4 Clean Release build"
run xcodebuild clean build -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  ENABLE_HARDENED_RUNTIME=YES "${ARCH_ARGS[@]}" "${NOSIGN[@]}" -quiet

echo "== 3/4 Sign"
if [[ "$MODE" == "A" ]]; then
  run codesign --force --deep --options runtime -s - "$APP_PATH"
else
  run codesign --force --deep --options runtime --timestamp -s "$DEV_ID" "$APP_PATH"
fi

# Drag-to-install disk image: the app next to an /Applications link.
make_dmg() {
  local dmg="$1" stage="$WORK_DIR/dmg-staging"
  run rm -f "$dmg"
  run rm -rf "$stage"
  run mkdir -p "$stage"
  run ditto "$APP_PATH" "$stage/$APP_NAME.app"
  run ln -s /Applications "$stage/Applications"
  run hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$stage" -ov -format UDZO "$dmg"
  run hdiutil verify -quiet "$dmg"
}

echo "== 4/4 Package"
ARTIFACTS=()
if [[ "$MODE" == "A" ]]; then
  ZIP="$OUT_DIR/$ZIP_PREFIX-$VERSION-unsigned.zip"
  run rm -f "$ZIP"
  run ditto -c -k --keepParent "$APP_PATH" "$ZIP"
  DMG="$OUT_DIR/$ZIP_PREFIX-$VERSION-unsigned.dmg"
  make_dmg "$DMG"
  ARTIFACTS=("$ZIP" "$DMG")
else
  DMG="$OUT_DIR/$ZIP_PREFIX-$VERSION.dmg"
  make_dmg "$DMG"
  run codesign --force --timestamp -s "$DEV_ID" "$DMG"
  run xcrun notarytool submit "$DMG" --wait --keychain-profile "${NOTARY_PROFILE:-<NOTARY_PROFILE>}"
  run xcrun stapler staple "$DMG"
  run spctl --assess -vv --type open --context context:primary-signature "$DMG"
  ARTIFACTS=("$DMG")
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "== Dry run finished. Would produce: ${ARTIFACTS[*]}"
  exit 0
fi

echo
for ARTIFACT in "${ARTIFACTS[@]}"; do
  echo "Artifact: $ARTIFACT"
  echo "SHA-256:  $(shasum -a 256 "$ARTIFACT" | awk '{print $1}')"
done

if [[ "$MODE" == "A" ]]; then
  cat <<'NOTICE'

############################################################################
#  WARNING: this build is NOT notarized and only ad-hoc signed.            #
#  Gatekeeper WILL warn users on first launch (right-click > Open, or      #
#  System Settings > Privacy & Security > Open Anyway).                    #
#  For a clean install experience, use Mode B (Developer ID + notarize).   #
############################################################################
NOTICE
fi

echo
echo "Nothing was published. To publish manually (hint only, not executed):"
echo "  gh release create v$VERSION$(printf ' "%s"' "${ARTIFACTS[@]}") --title \"Port Killer $VERSION\" --notes-file CHANGELOG.md"
