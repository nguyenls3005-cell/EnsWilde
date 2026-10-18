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

# =============================================================================
# BẮT ĐẦU PHẦN TÍCH HỢP AIRLIFT
# =============================================================================
echo "==> Downloading AirliftFFI from Mak5er's repo..."
curl -L -o AirliftFFI.xcframework.zip https://github.com/Mak5er/AirCard-iOS/archive/refs/heads/main.zip
unzip -q AirliftFFI.xcframework.zip
mv AirCard-iOS-main/AirliftFFI.xcframework ./AirliftFFI.xcframework
rm -rf AirCard-iOS-main AirliftFFI.xcframework.zip

echo "==> Injecting AirliftFFI into Xcode project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  framework_path = "AirliftFFI.xcframework"
  
  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }
  
  unless target.nil?
    # Thêm file vào project
    file_ref = project.new_file(framework_path)
    
    # Thêm vào Frameworks Build Phase
    target.frameworks_build_phase.add_file_reference(file_ref)
    
    # Thêm vào Embed Frameworks
    embed_phase = target.copy_files_build_phases.find { |p| p.name == "Embed Frameworks" } 
    if embed_phase.nil?
      embed_phase = target.new_copy_files_build_phase("Embed Frameworks")
      embed_phase.dst_subfolder_spec = "10" # Frameworks
    end
    build_file = embed_phase.add_file_reference(file_ref)
    build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
    
    project.save
    puts "✅ Thành công: Đã nhúng AirliftFFI vào project!"
  else
    puts "❌ Lỗi: Không tìm thấy target EnsWilde"
    exit 1
  end
'
# =============================================================================
# KẾT THÚC PHẦN TÍCH HỢP AIRLIFT
# =============================================================================

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