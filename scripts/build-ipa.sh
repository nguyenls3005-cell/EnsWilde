#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-Release}"
SCHEME="EnsWilde"
PROJECT="EnsWilde.xcodeproj"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="$BUILD_DIR/EnsWilde.xcarchive"
APP_NAME="EnsWilde"
IPA_PATH="$BUILD_DIR/${APP_NAME}.ipa"

echo "==> Building $APP_NAME ($CONFIG)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# =============================================================================
# BUILD AIRLIFT TỪ SOURCE CODE TRONG REPO
# =============================================================================
echo "==> Building AirliftFFI from local source in AirCardCore..."

if ! rustup target list --installed | grep -q "aarch64-apple-ios"; then
  rustup target add aarch64-apple-ios
fi

cd AirCardCore
cargo build --release --target aarch64-apple-ios
cd ..

LIB_PATH="AirCardCore/target/aarch64-apple-ios/release/libairlift_ffi.a"
if [ ! -f "$LIB_PATH" ]; then
  echo "ERROR: Cannot find $LIB_PATH"
  exit 1
fi

# =============================================================================
# TẠO STATIC FRAMEWORK AirliftFFI (đúng chuẩn: binary là file .a)
# =============================================================================
FRAMEWORK_DIR="Frameworks/AirliftFFI.framework"
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$FRAMEWORK_DIR/Headers"
mkdir -p "$FRAMEWORK_DIR/Modules"

# Binary của static framework chính là file .a
cp "$LIB_PATH" "$FRAMEWORK_DIR/AirliftFFI"

AIRLIFT_H=$(find AirCardCore -name "airlift.h" | head -n 1)
GRAPPA_H=$(find AirCardCore -name "GrappaHelper.h" | head -n 1)

if [ -z "$AIRLIFT_H" ]; then
  echo "ERROR: Cannot find airlift.h in AirCardCore!"
  exit 1
fi
cp "$AIRLIFT_H" "$FRAMEWORK_DIR/Headers/airlift.h"

if [ -n "$GRAPPA_H" ]; then
  cp "$GRAPPA_H" "$FRAMEWORK_DIR/Headers/GrappaHelper.h"
else
  echo "WARNING: Cannot find GrappaHelper.h in AirCardCore!"
fi

cat > "$FRAMEWORK_DIR/Modules/module.modulemap" <<EOF
framework module AirliftFFI {
    umbrella header "airlift.h"
    export *
    module * { export * }
}
EOF

cat > "$FRAMEWORK_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AirliftFFI</string>
    <key>CFBundleIdentifier</key>
    <string>com.enswilde.AirliftFFI</string>
    <key>CFBundleName</key>
    <string>AirliftFFI</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
EOF

echo "✅ Built AirliftFFI.framework (static)!"

# =============================================================================
# INJECT VÀO XCODE: thêm framework vào Link + FRAMEWORK_SEARCH_PATHS
# =============================================================================
echo "==> Injecting AirliftFFI into Xcode project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  framework_path = "Frameworks/AirliftFFI.framework"

  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }

  if target.nil?
    puts "❌ Lỗi: Không tìm thấy target EnsWilde"
    exit 1
  end

  # Tránh thêm trùng nếu chạy lại
  existing = target.frameworks_build_phase.files.find do |f|
    f.file_ref && f.file_ref.path && f.file_ref.path.end_with?("AirliftFFI.framework")
  end

  unless existing
    file_ref = project.new_file(framework_path)
    target.frameworks_build_phase.add_file_reference(file_ref)
  end

  target.build_configurations.each do |config|
    config.build_settings["FRAMEWORK_SEARCH_PATHS"] ||= ["$(inherited)"]
    fsp = config.build_settings["FRAMEWORK_SEARCH_PATHS"]
    fsp = [fsp] if fsp.is_a?(String)
    unless fsp.include?("$(PROJECT_DIR)/Frameworks")
      fsp << "$(PROJECT_DIR)/Frameworks"
    end
    config.build_settings["FRAMEWORK_SEARCH_PATHS"] = fsp

    config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
    ldf = config.build_settings["OTHER_LDFLAGS"]
    ldf = [ldf] if ldf.is_a?(String)
    ldf << "-lc++" unless ldf.include?("-lc++")
    config.build_settings["OTHER_LDFLAGS"] = ldf
  end

  project.save
  puts "✅ Thành công: Đã link AirliftFFI.framework vào target EnsWilde!"
'

# =============================================================================
# ARCHIVE VÀ ĐÓNG GÓI IPA
# =============================================================================
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

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
  echo "error: no .app found" >&2
  exit 1
fi

APP_BASENAME="$(basename "$APP_PATH")"
rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
rm -rf "$BUILD_DIR/Payload/${APP_BASENAME}/_CodeSignature"
rm -f  "$BUILD_DIR/Payload/${APP_BASENAME}/embedded.mobileprovision"

(
  cd "$BUILD_DIR"
  zip -qry "$IPA_PATH" Payload
)

echo "==> Done: $IPA_PATH"