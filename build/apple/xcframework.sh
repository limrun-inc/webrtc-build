#!/bin/bash

set -e

if [[ -z "$1" ]]; then
  echo "Usage: $0 'debug' | 'release' 'source_dir' 'out_dir' ['prefix']"
  exit 0
fi

MODE="$1"
SOURCE_DIR="$(realpath "$2")"
OUT_DIR="$(realpath "$3")"
PREFIX="${4:-""}"

if [ -z "$PREFIX" ]; then
  FRAMEWORK_NAME="WebRTC"
else
  FRAMEWORK_NAME="${PREFIX}WebRTC"
fi

DEBUG="false"
if [[ "$MODE" == "debug" ]]; then
  DEBUG="true"
fi

PARALLEL_BUILDS=6

echo "xcframework.sh: MODE=$MODE, DEBUG=$DEBUG, SOURCE_DIR=$SOURCE_DIR, OUT_DIR=$OUT_DIR, PREFIX=$PREFIX, FRAMEWORK_NAME=$FRAMEWORK_NAME"

start_group() {
  if [[ "$CI" == "true" ]]; then
    echo "::group::$1"
  else
    echo "=== $1 ==="
  fi
}

end_group() {
  if [[ "$CI" == "true" ]]; then
    echo "::endgroup::"
  fi
}

COMMON_ARGS="
      enable_dsyms = $DEBUG
      enable_libaom = true
      enable_stripping = true
      ios_enable_code_signing = false
      is_component_build = false
      is_debug = $DEBUG
      rtc_build_examples = false
      rtc_enable_protobuf = false
      rtc_enable_symbol_export = true
      rtc_include_dav1d_in_internal_decoder_factory = true
      rtc_include_tests = false
      rtc_libvpx_build_vp9 = true
      rtc_use_h264 = false
      treat_warnings_as_errors = true
      use_rtti = true"

PLATFORMS=(
  "iOS-arm64-device:target_os=\"ios\" target_environment=\"device\" target_cpu=\"arm64\" ios_deployment_target=\"13.0\""
  "iOS-arm64-simulator:target_os=\"ios\" target_environment=\"simulator\" target_cpu=\"arm64\" ios_deployment_target=\"13.0\""
  "iOS-x64-simulator:target_os=\"ios\" target_environment=\"simulator\" target_cpu=\"x64\" ios_deployment_target=\"13.0\""
  "macOS-arm64:target_os=\"mac\" target_cpu=\"arm64\" mac_deployment_target=\"10.15\""
  "macOS-x64:target_os=\"mac\" target_cpu=\"x64\" mac_deployment_target=\"10.15\""
  "catalyst-arm64:target_os=\"ios\" target_environment=\"catalyst\" target_cpu=\"arm64\" ios_deployment_target=\"14.0\""
  "catalyst-x64:target_os=\"ios\" target_environment=\"catalyst\" target_cpu=\"x64\" ios_deployment_target=\"14.0\""
  "tvOS-arm64-device:target_os=\"ios\" target_environment=\"appletv\" target_cpu=\"arm64\" ios_deployment_target=\"17.0\""
  "tvOS-arm64-simulator:target_os=\"ios\" target_environment=\"appletvsimulator\" target_cpu=\"arm64\" ios_deployment_target=\"17.0\""
  "xrOS-arm64-device:target_os=\"ios\" target_environment=\"xrdevice\" target_cpu=\"arm64\" ios_deployment_target=\"2.2.0\""
  "xrOS-arm64-simulator:target_os=\"ios\" target_environment=\"xrsimulator\" target_cpu=\"arm64\" ios_deployment_target=\"2.2.0\""
)

cd "$SOURCE_DIR"

end_group

for platform_config in "${PLATFORMS[@]}"; do
  platform="${platform_config%%:*}"
  config="${platform_config#*:}"
  
  start_group "Building $platform"
  
  gn gen "$OUT_DIR/$platform" --args="$COMMON_ARGS $config" --ide=xcode
  
  if [[ $platform == *"macOS"* ]]; then
    build_target="mac_framework_bundle"
  else
    build_target="ios_framework_bundle"
  fi
  
  ninja -C "$OUT_DIR/$platform" "$build_target" -j $PARALLEL_BUILDS --quiet || exit 1
  end_group
done

start_group "Creating universal binaries (x64 + arm64)"

mkdir -p "$OUT_DIR/macOS-lib"
cp -R "$OUT_DIR/macOS-x64/$FRAMEWORK_NAME.framework" "$OUT_DIR/macOS-lib/$FRAMEWORK_NAME.framework"
lipo -create -output "$OUT_DIR/macOS-lib/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/macOS-arm64/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/macOS-x64/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
if [ -d "$OUT_DIR/macOS-x64/$FRAMEWORK_NAME.dSYM" ]; then
  cp -R "$OUT_DIR/macOS-x64/$FRAMEWORK_NAME.dSYM" "$OUT_DIR/macOS-lib/$FRAMEWORK_NAME.dSYM"
  lipo -create -output "$OUT_DIR/macOS-lib/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/macOS-arm64/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/macOS-x64/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME"
fi

mkdir -p "$OUT_DIR/catalyst-lib"
cp -R "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.framework" "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.framework"
lipo -create -output "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-x64/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
if [ -d "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.dSYM" ]; then
  cp -R "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.dSYM" "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.dSYM"
  lipo -create -output "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-arm64/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/catalyst-x64/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME"
fi

mkdir -p "$OUT_DIR/iOS-device-lib"
cp -R "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.framework" "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.framework"
lipo -create -output "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
if [ -d "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.dSYM" ]; then
  cp -R "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.dSYM" "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.dSYM"
  lipo -create -output "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-device/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME"
fi

mkdir -p "$OUT_DIR/iOS-simulator-lib"
cp -R "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.framework" "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.framework"
lipo -create -output "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$OUT_DIR/iOS-x64-simulator/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
if [ -d "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.dSYM" ]; then
  cp -R "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.dSYM" "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.dSYM"
  lipo -create -output "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/iOS-arm64-simulator/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME" "$OUT_DIR/iOS-x64-simulator/$FRAMEWORK_NAME.dSYM/Contents/Resources/DWARF/$FRAMEWORK_NAME"
fi

end_group

start_group "Creating XCFramework"

XCFRAMEWORK_ARGS=(-create-xcframework)

FRAMEWORK_PATHS=(
  "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/macOS-lib/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/tvOS-arm64-device/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/tvOS-arm64-simulator/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/xrOS-arm64-device/$FRAMEWORK_NAME.framework"
  "$OUT_DIR/xrOS-arm64-simulator/$FRAMEWORK_NAME.framework"
)

DSYM_PATHS=(
  "$OUT_DIR/iOS-device-lib/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/iOS-simulator-lib/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/macOS-lib/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/catalyst-lib/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/tvOS-arm64-device/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/tvOS-arm64-simulator/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/xrOS-arm64-device/$FRAMEWORK_NAME.dSYM"
  "$OUT_DIR/xrOS-arm64-simulator/$FRAMEWORK_NAME.dSYM"
)

for i in "${!FRAMEWORK_PATHS[@]}"; do
  XCFRAMEWORK_ARGS+=(-framework "${FRAMEWORK_PATHS[$i]}")

  if [[ "$DEBUG" == "true" ]] && [[ -d "${DSYM_PATHS[$i]}" ]]; then
    XCFRAMEWORK_ARGS+=(-debug-symbols "${DSYM_PATHS[$i]}")
  fi
done

XCFRAMEWORK_ARGS+=(-output "$OUT_DIR/$FRAMEWORK_NAME.xcframework")

xcodebuild "${XCFRAMEWORK_ARGS[@]}"

end_group

start_group "Post-processing XCFramework"

cp LICENSE "$OUT_DIR/$FRAMEWORK_NAME.xcframework/"

cd "$OUT_DIR/$FRAMEWORK_NAME.xcframework/macos-arm64_x86_64/$FRAMEWORK_NAME.framework/"
mv "$FRAMEWORK_NAME" "Versions/A/$FRAMEWORK_NAME"
ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_NAME"

cd "$OUT_DIR/$FRAMEWORK_NAME.xcframework/ios-arm64_x86_64-maccatalyst/$FRAMEWORK_NAME.framework/"
mv "$FRAMEWORK_NAME" "Versions/A/$FRAMEWORK_NAME"
ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_NAME"

cd "$OUT_DIR"
zip --symlinks -9 -r "$FRAMEWORK_NAME.xcframework.zip" "$FRAMEWORK_NAME.xcframework"

end_group

if [[ "$CI" == "true" ]]; then
  echo "framework_name=$FRAMEWORK_NAME" >> "$GITHUB_OUTPUT"
fi
