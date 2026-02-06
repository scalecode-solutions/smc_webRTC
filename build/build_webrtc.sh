#!/bin/bash
set -e

# =============================================================================
# smc_webRTC Build Script
# Builds Google WebRTC M141 xcframework for iOS (arm64 device + arm64 simulator)
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
echo "  Architectures: arm64 (device + simulator)"
echo "============================================"
echo ""

# Step 1: Get depot_tools
echo "[1/7] Getting depot_tools..."
if [ ! -d "$DEPOT_TOOLS_DIR" ]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
else
    echo "  depot_tools already exists, updating..."
    cd "$DEPOT_TOOLS_DIR" && git pull && cd "$BUILD_DIR"
fi
export PATH="$DEPOT_TOOLS_DIR:$PATH"

# Step 2: Fetch WebRTC source
echo ""
echo "[2/7] Fetching WebRTC iOS source (this is the big download ~15-20GB)..."
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
echo "[3/7] Checking out $BRANCH..."
cd "$BUILD_DIR/webrtc/src"
git checkout "$BRANCH"
gclient sync

# Step 4: Build for iOS device (arm64)
echo ""
echo "[4/7] Building for iOS device (arm64)..."
GN_ARGS='target_os="ios" target_cpu="arm64" is_debug=false is_component_build=false rtc_include_tests=false rtc_libvpx_build_vp9=true enable_dsyms=true enable_stripping=true ios_enable_code_signing=false symbol_level=1'

gn gen out/ios_arm64 --args="$GN_ARGS"
ninja -C out/ios_arm64 framework_objc

# Step 5: Build for iOS simulator (arm64)
echo ""
echo "[5/7] Building for iOS simulator (arm64)..."
GN_ARGS_SIM='target_os="ios" target_cpu="arm64" is_debug=false is_component_build=false rtc_include_tests=false rtc_libvpx_build_vp9=true enable_dsyms=true enable_stripping=true ios_enable_code_signing=false target_environment="simulator" symbol_level=1'

gn gen out/ios_sim_arm64 --args="$GN_ARGS_SIM"
ninja -C out/ios_sim_arm64 framework_objc

# Step 6: Fix headers
echo ""
echo "[6/7] Fixing headers for Xcode 26.2 compatibility..."

fix_headers() {
    local framework_path="$1"
    find "$framework_path/Headers" -name "*.h" -exec sed -i '' \
        's|#import "sdk/objc/base/RTCMacros.h"|#import <WebRTC/RTCMacros.h>|g' {} +
    local count=$(grep -r '#import "sdk/objc' "$framework_path/Headers" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Remaining broken imports: $count"
}

fix_headers "out/ios_arm64/WebRTC.framework"
fix_headers "out/ios_sim_arm64/WebRTC.framework"

# Step 7: Create xcframework with dSYMs
echo ""
echo "[7/7] Creating xcframework..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Check for dSYMs
DSYM_DEVICE=""
DSYM_SIM=""
if [ -d "out/ios_arm64/WebRTC.dSYM" ]; then
    DSYM_DEVICE="-debug-symbols $(pwd)/out/ios_arm64/WebRTC.dSYM"
    echo "  Found device dSYM"
fi
if [ -d "out/ios_sim_arm64/WebRTC.dSYM" ]; then
    DSYM_SIM="-debug-symbols $(pwd)/out/ios_sim_arm64/WebRTC.dSYM"
    echo "  Found simulator dSYM"
fi

xcodebuild -create-xcframework \
    -framework out/ios_arm64/WebRTC.framework \
    $DSYM_DEVICE \
    -framework out/ios_sim_arm64/WebRTC.framework \
    $DSYM_SIM \
    -output "$OUTPUT_DIR/WebRTC.xcframework"

echo ""
echo "  xcframework created at: $OUTPUT_DIR/WebRTC.xcframework"

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
echo "    cp $OUTPUT_DIR/WebRTC.xcframework.zip ."
echo "    # Update checksum in Package.swift"
echo "    # gh release create 141.1.0 WebRTC.xcframework.zip --repo scalecode-solutions/smc_webRTC"
echo ""

# Also copy to package root for local dev
cp -R "$OUTPUT_DIR/WebRTC.xcframework" "$PACKAGE_DIR/WebRTC.xcframework"
echo "  Also copied xcframework to $PACKAGE_DIR/WebRTC.xcframework"
echo ""
