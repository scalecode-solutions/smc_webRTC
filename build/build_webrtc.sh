#!/bin/bash
set -e

# =============================================================================
# smc_webRTC Build Script
# Builds Google WebRTC M141 xcframework for iOS + macOS
# Slices: iOS device arm64, iOS simulator arm64+x86_64, macOS arm64+x86_64
# Produces WebRTC.xcframework with dSYMs
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/webrtc_build"
OUTPUT_DIR="$SCRIPT_DIR/output"
BRANCH="branch-heads/7390"  # M141
DEPOT_TOOLS_DIR="$BUILD_DIR/depot_tools"

echo "============================================"
echo "  smc_webRTC Build Script"
echo "  Branch: $BRANCH (M141)"
echo "  iOS:   arm64 device, arm64+x86_64 sim"
echo "  macOS: arm64+x86_64"
echo "============================================"
echo ""

# Step 1: Get depot_tools
echo "[1/10] Getting depot_tools..."
if [ ! -d "$DEPOT_TOOLS_DIR" ]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
else
    echo "  depot_tools already exists, updating..."
    cd "$DEPOT_TOOLS_DIR" && git pull && cd "$BUILD_DIR"
fi
export PATH="$DEPOT_TOOLS_DIR:$PATH"

# Step 2: Fetch WebRTC source
echo ""
echo "[2/10] Fetching WebRTC iOS source (this is the big download ~15-20GB)..."
mkdir -p "$BUILD_DIR/webrtc"
cd "$BUILD_DIR/webrtc"

if [ ! -d "src" ]; then
    fetch --nohooks webrtc_ios
    gclient sync
else
    echo "  Source already fetched, syncing..."
    gclient sync
fi

# Step 3: Checkout M141 branch
echo ""
echo "[3/10] Checking out $BRANCH..."
cd "$BUILD_DIR/webrtc/src"
git checkout "$BRANCH"
gclient sync

# Common GN args
COMMON_ARGS='is_debug=false is_component_build=false rtc_include_tests=false rtc_libvpx_build_vp9=true enable_dsyms=true enable_stripping=true symbol_level=1 rtc_enable_symbol_export=true'

# Step 4: Build for iOS device (arm64)
echo ""
echo "[4/10] Building for iOS device (arm64)..."
gn gen out/ios_arm64 --args="target_os=\"ios\" target_cpu=\"arm64\" target_environment=\"device\" ios_enable_code_signing=false $COMMON_ARGS"
ninja -C out/ios_arm64 framework_objc

# Step 5: Build for iOS simulator (arm64)
echo ""
echo "[5/10] Building for iOS simulator (arm64)..."
gn gen out/ios_sim_arm64 --args="target_os=\"ios\" target_cpu=\"arm64\" target_environment=\"simulator\" ios_enable_code_signing=false $COMMON_ARGS"
ninja -C out/ios_sim_arm64 framework_objc

# Step 6: Build for iOS simulator (x86_64)
echo ""
echo "[6/10] Building for iOS simulator (x86_64)..."
gn gen out/ios_sim_x64 --args="target_os=\"ios\" target_cpu=\"x64\" target_environment=\"simulator\" ios_enable_code_signing=false $COMMON_ARGS"
ninja -C out/ios_sim_x64 framework_objc

# Step 7: Build for macOS (arm64)
echo ""
echo "[7/10] Building for macOS (arm64)..."
gn gen out/mac_arm64 --args="target_os=\"mac\" target_cpu=\"arm64\" $COMMON_ARGS"
ninja -C out/mac_arm64 mac_framework_objc

# Step 8: Build for macOS (x86_64)
echo ""
echo "[8/10] Building for macOS (x86_64)..."
gn gen out/mac_x64 --args="target_os=\"mac\" target_cpu=\"x64\" $COMMON_ARGS"
ninja -C out/mac_x64 mac_framework_objc

# Step 9: Fix headers + create fat binaries
echo ""
echo "[9/10] Fixing headers and creating fat binaries..."

fix_headers() {
    local framework_path="$1"
    find "$framework_path/Headers" -name "*.h" -exec sed -i '' \
        's|#import "sdk/objc/base/RTCMacros.h"|#import <WebRTC/RTCMacros.h>|g' {} +
    local count=$(grep -r '#import "sdk/objc' "$framework_path/Headers" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Fixed headers in $(basename $(dirname $framework_path))/WebRTC.framework (remaining broken: $count)"
}

# Fix headers for all 5 builds
fix_headers "out/ios_arm64/WebRTC.framework"
fix_headers "out/ios_sim_arm64/WebRTC.framework"
fix_headers "out/ios_sim_x64/WebRTC.framework"
fix_headers "out/mac_arm64/WebRTC.framework"
fix_headers "out/mac_x64/WebRTC.framework"

# Create fat iOS simulator framework (arm64 + x86_64)
echo "  Creating fat iOS simulator framework..."
rm -rf out/ios_sim_fat
mkdir -p out/ios_sim_fat
cp -R out/ios_sim_arm64/WebRTC.framework out/ios_sim_fat/WebRTC.framework
lipo -create \
    out/ios_sim_arm64/WebRTC.framework/WebRTC \
    out/ios_sim_x64/WebRTC.framework/WebRTC \
    -output out/ios_sim_fat/WebRTC.framework/WebRTC
echo "  iOS sim fat binary archs: $(lipo -archs out/ios_sim_fat/WebRTC.framework/WebRTC)"

# Create fat iOS simulator dSYM
if [ -d "out/ios_sim_arm64/WebRTC.dSYM" ] && [ -d "out/ios_sim_x64/WebRTC.dSYM" ]; then
    cp -R out/ios_sim_arm64/WebRTC.dSYM out/ios_sim_fat/WebRTC.dSYM
    lipo -create \
        out/ios_sim_arm64/WebRTC.dSYM/Contents/Resources/DWARF/WebRTC \
        out/ios_sim_x64/WebRTC.dSYM/Contents/Resources/DWARF/WebRTC \
        -output out/ios_sim_fat/WebRTC.dSYM/Contents/Resources/DWARF/WebRTC
    echo "  iOS sim fat dSYM created"
fi

# Create fat macOS framework (arm64 + x86_64)
echo "  Creating fat macOS framework..."
rm -rf out/mac_fat
mkdir -p out/mac_fat
cp -R out/mac_arm64/WebRTC.framework out/mac_fat/WebRTC.framework
lipo -create \
    out/mac_arm64/WebRTC.framework/WebRTC \
    out/mac_x64/WebRTC.framework/WebRTC \
    -output out/mac_fat/WebRTC.framework/WebRTC
echo "  macOS fat binary archs: $(lipo -archs out/mac_fat/WebRTC.framework/WebRTC)"

# Create fat macOS dSYM
if [ -d "out/mac_arm64/WebRTC.dSYM" ] && [ -d "out/mac_x64/WebRTC.dSYM" ]; then
    cp -R out/mac_arm64/WebRTC.dSYM out/mac_fat/WebRTC.dSYM
    lipo -create \
        out/mac_arm64/WebRTC.dSYM/Contents/Resources/DWARF/WebRTC \
        out/mac_x64/WebRTC.dSYM/Contents/Resources/DWARF/WebRTC \
        -output out/mac_fat/WebRTC.dSYM/Contents/Resources/DWARF/WebRTC
    echo "  macOS fat dSYM created"
fi

# Step 10: Create xcframework
echo ""
echo "[10/10] Creating xcframework..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Build xcframework command with optional dSYMs
XCFW_CMD="xcodebuild -create-xcframework"

# iOS device
XCFW_CMD="$XCFW_CMD -framework out/ios_arm64/WebRTC.framework"
if [ -d "out/ios_arm64/WebRTC.dSYM" ]; then
    XCFW_CMD="$XCFW_CMD -debug-symbols $(pwd)/out/ios_arm64/WebRTC.dSYM"
    echo "  Including iOS device dSYM"
fi

# iOS simulator (fat)
XCFW_CMD="$XCFW_CMD -framework out/ios_sim_fat/WebRTC.framework"
if [ -d "out/ios_sim_fat/WebRTC.dSYM" ]; then
    XCFW_CMD="$XCFW_CMD -debug-symbols $(pwd)/out/ios_sim_fat/WebRTC.dSYM"
    echo "  Including iOS simulator dSYM (arm64+x86_64)"
fi

# macOS (fat)
XCFW_CMD="$XCFW_CMD -framework out/mac_fat/WebRTC.framework"
if [ -d "out/mac_fat/WebRTC.dSYM" ]; then
    XCFW_CMD="$XCFW_CMD -debug-symbols $(pwd)/out/mac_fat/WebRTC.dSYM"
    echo "  Including macOS dSYM (arm64+x86_64)"
fi

XCFW_CMD="$XCFW_CMD -output $OUTPUT_DIR/WebRTC.xcframework"
eval $XCFW_CMD

echo ""
echo "  xcframework created at: $OUTPUT_DIR/WebRTC.xcframework"
echo "  Slices:"
echo "    - ios-arm64 (device)"
echo "    - ios-arm64_x86_64-simulator"
echo "    - macos-arm64_x86_64"

# Create zip for SPM distribution
cd "$OUTPUT_DIR"
zip -r -q WebRTC.xcframework.zip WebRTC.xcframework
CHECKSUM=$(shasum -a 256 WebRTC.xcframework.zip | awk '{print $1}')

echo ""
echo "============================================"
echo "  BUILD COMPLETE"
echo "============================================"
echo ""
echo "  xcframework: $OUTPUT_DIR/WebRTC.xcframework"
echo "  zip:         $OUTPUT_DIR/WebRTC.xcframework.zip"
echo "  SHA256:      $CHECKSUM"
echo ""
echo "  To update Package.swift, use this checksum."
echo "  To publish:"
echo "    cd $PACKAGE_DIR"
echo "    # Update checksum in Package.swift"
echo "    # gh release create <version> $OUTPUT_DIR/WebRTC.xcframework.zip --repo scalecode-solutions/smc_webRTC"
echo ""

# Also copy to package root for local dev
rm -rf "$PACKAGE_DIR/WebRTC.xcframework"
cp -R "$OUTPUT_DIR/WebRTC.xcframework" "$PACKAGE_DIR/WebRTC.xcframework"
echo "  Also copied xcframework to $PACKAGE_DIR/WebRTC.xcframework"
echo ""
