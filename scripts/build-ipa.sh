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

# Copy header ra thư mục include để Swift/ObjC import được
INCLUDE_DIR="Frameworks/AirliftFFI"
rm -rf "$INCLUDE_DIR"
mkdir -p "$INCLUDE_DIR"

AIRLIFT_H=$(find AirCardCore -name "airlift.h" | head -n 1)
GRAPPA_H=$(find AirCardCore -name "GrappaHelper.h" | head -n 1)

if [ -n "$AIRLIFT_H" ]; then
  cp "$AIRLIFT_H" "$INCLUDE_DIR/airlift.h"
else
  echo "ERROR: Cannot find airlift.h in AirCardCore!"
  exit 1
fi

if [ -n "$GRAPPA_H" ]; then
  cp "$GRAPPA_H" "$INCLUDE_DIR/GrappaHelper.h"
else
  echo "WARNING: Cannot find GrappaHelper.h in AirCardCore!"
fi

echo "✅ Built libairlift_ffi.a!"

# =============================================================================
# INJECT VÀO XCODE (link trực tiếp file .a)
# =============================================================================
echo "==> Injecting AirliftFFI into Xcode project..."
gem install xcodeproj --no-document
ruby -e '
  require "xcodeproj"
  project_path = "EnsWilde.xcodeproj"
  lib_path = "AirCardCore/target/aarch64-apple-ios/release/libairlift_ffi.a"
  include_dir = "Frameworks/AirliftFFI"

  project = Xcodeproj::Project.open(project_path)
  target = project.targets.find { |t| t.name == "EnsWilde" }

  if target.nil?
    puts "❌ Lỗi: Không tìm thấy target EnsWilde"
    exit 1
  end

  # Tránh thêm trùng nếu chạy lại
  existing = target.frameworks_build_phase.files.find do |f|
    f.file_ref && f.file_ref.path && f.file_ref.path.end_with?("libairlift_ffi.a")
  end

  unless existing
    file_ref = project.new_file(lib_path)
    target.frameworks_build_phase.add_file_reference(file_ref)
  end

  # Đảm bảo group Frameworks/AirliftFFI có trong project để header path hợp lệ
  unless project.files.any? { |f| f.path && f.path.end_with?("AirliftFFI/airlift.h") }
    project.new_file("#{include_dir}/airlift.h")
  end

  target.build_configurations.each do |config|
    config.build_settings["LIBRARY_SEARCH_PATHS"] ||= ["$(inherited)"]
    lib_search = config.build_settings["LIBRARY_SEARCH_PATHS"]
    lib_search = [lib_search] if lib_search.is_a?(String)
    unless lib_search.include?("$(PROJECT_DIR)/AirCardCore/target/aarch64-apple-ios/release")
      lib_search << "$(PROJECT_DIR)/AirCardCore/target/aarch64-apple-ios/release"
    end
    config.build_settings["LIBRARY_SEARCH_PATHS"] = lib_search

    config.build_settings["HEADER_SEARCH_PATHS"] ||= ["$(inherited)"]
    hdr = config.build_settings["HEADER_SEARCH_PATHS"]
    hdr = [hdr] if hdr.is_a?(String)
    unless hdr.include?("$(PROJECT_DIR)/Frameworks/AirliftFFI")
      hdr << "$(PROJECT_DIR)/Frameworks/AirliftFFI"
    end
    config.build_settings["HEADER_SEARCH_PATHS"] = hdr

    config.build_settings["OTHER_LDFLAGS"] ||= ["$(inherited)"]
    ldf = config.build_settings["OTHER_LDFLAGS"]
    ldf = [ldf] if ldf.is_a?(String)
    ldf << "-lc++" unless ldf.include?("-lc++")
    config.build_settings["OTHER_LDFLAGS"] = ldf
  end

  project.save
  puts "✅ Thành công: Đã link libairlift_ffi.a vào target EnsWilde!"
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