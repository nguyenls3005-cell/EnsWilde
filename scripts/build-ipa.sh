#!/usr/bin/env bash
#
# build-ipa.sh — the only supported build path for EnsWilde.
#
# Produces an *unsigned* IPA at build/EnsWilde.ipa.  Unsigned means: no
# _CodeSignature, no embedded.mobileprovision.  The result must be sideloaded
# (AltStore / Sideloadly / Scarlet / TrollStore) with the user's own signing
# identity — it will not install by dragging it into Xcode.
#
# Usage:
#   bash ./scripts/build-ipa.sh [Release|Debug]
#
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="EnsWilde"
PROJECT="EnsWilde.xcodeproj"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/EnsWilde.xcarchive"
APP_NAME="EnsWilde"
IPA_PATH="$BUILD_DIR/${APP_NAME}.ipa"

# -----------------------------------------------------------------------------
# Sanity check: the project must be present, otherwise xcodebuild will fail
# with a cryptic message and waste a runner minute.
# -----------------------------------------------------------------------------
if [[ ! -d "$PROJECT" ]]; then
  echo "error: $PROJECT not found in $(pwd)" >&2
  echo "hint: this script must be run from the repository root" >&2
  exit 1
fi

echo "==> Building $APP_NAME ($CONFIG)"
echo "    project : $PROJECT"
echo "    scheme  : $SCHEME"
echo "    output  : $IPA_PATH"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# -----------------------------------------------------------------------------
# Archive without any code signing.  Every CODE_SIGN_* override is required:
# xcodebuild will otherwise refuse to build a device target with no team set.
# -----------------------------------------------------------------------------
XCB_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -sdk iphoneos
  -archivePath "$ARCHIVE_PATH"
  -destination "generic/platform=iOS"
  CODE_SIGN_IDENTITY=""
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGN_ENTITLEMENTS=""
  EXPANDED_CODE_SIGN_IDENTITY=""
  DEVELOPMENT_TEAM=""
  PROVISIONING_PROFILE_SPECIFIER=""
)

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild archive "${XCB_ARGS[@]}" | xcbeautify
else
  xcodebuild archive "${XCB_ARGS[@]}"
fi

# -----------------------------------------------------------------------------
# Locate the .app inside the archive and repackage it as an IPA.
# -----------------------------------------------------------------------------
APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "error: no .app found in $ARCHIVE_PATH/Products/Applications" >&2
  exit 1
fi
echo "==> App bundle: $APP_PATH"

APP_BASENAME="$(basename "$APP_PATH")"

rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"

# Strip anything that would make the IPA look signed — an unsigned IPA that
# still carries a stale signature will be rejected by most sideloaders.
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
rm -f  "$BUILD_DIR/Payload/${APP_BASENAME}/embedded.mobileprovision"

# Zip from inside Payload so the archive root is "Payload/…", which is what
# every sideloader expects.
(
  cd "$BUILD_DIR"
  zip -qry "$IPA_PATH" Payload
)

echo "==> Done: $IPA_PATH"
ls -lh "$IPA_PATH"
