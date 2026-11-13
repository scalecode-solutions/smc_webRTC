#!/bin/bash
set -e

# =============================================================================
# smc_webRTC Build Script
# Builds Google WebRTC M158 xcframework for iOS + macOS
# Slices: iOS device arm64, iOS simulator arm64+x86_64, macOS arm64+x86_64
# Produces WebRTC.xcframework with dSYMs
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/webrtc_build"
OUTPUT_DIR="$SCRIPT_DIR/output"
BRANCH="branch-heads/8127"  # M158
DEPOT_TOOLS_DIR="$BUILD_DIR/depot_tools"

echo "============================================"
echo "  smc_webRTC Build Script"
echo "  Branch: $BRANCH (M158)"
echo "  iOS:   arm64 device, arm64+x86_64 sim"
echo "  macOS: arm64+x86_64"
echo "============================================"
echo ""

# PACKAGE_ONLY=1 skips steps 1-8 (sync + ninja) and re-runs only the
# packaging (header fixes, fat binaries, xcframework, zip) on the existing out/.
if [ "${PACKAGE_ONLY:-0}" = "1" ]; then
echo "PACKAGE_ONLY=1: skipping sync and builds, repackaging existing out/"
export PATH="$DEPOT_TOOLS_DIR:$PATH"
cd "$BUILD_DIR/webrtc/src"
else

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

# Step 3: Checkout M158 branch
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

fi  # PACKAGE_ONLY

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

# The mac bundle step ships only the umbrella header (WebRTC.h) in
# Versions/A/Headers; the public headers it imports are generated into
# gen/sdk/WebRTC.framework/Headers but never copied in (true since at least
# M147; found during the M158 bump). Copy them in so the mac slice imports.
for mac in mac_arm64 mac_x64; do
    dest="out/$mac/WebRTC.framework/Versions/A/Headers"
    for h in out/$mac/gen/sdk/WebRTC.framework/Headers/*.h; do
        # WebRTC.h in the bundle is the same file (hard link) as the generated one.
        [ "$h" -ef "$dest/$(basename "$h")" ] || cp -f "$h" "$dest/"
    done
done

# Tripwire: every header the umbrella imports must exist in every framework.
check_umbrella() {
    local headers="$1/Headers" missing=0
    for h in $(grep -oE 'WebRTC/[A-Za-z0-9+_]+\.h' "$headers/WebRTC.h" | sed 's#WebRTC/##'); do
        [ -f "$headers/$h" ] || { echo "    MISSING: $h"; missing=$((missing+1)); }
    done
    echo "  Umbrella check $(basename $(dirname $1))/WebRTC.framework: $(ls "$headers" | wc -l | tr -d ' ') headers, missing $missing"
    [ "$missing" -eq 0 ] || { echo "ERROR: umbrella imports missing headers"; exit 1; }
}

# Fix headers for all 5 builds
fix_headers "out/ios_arm64/WebRTC.framework"
fix_headers "out/ios_sim_arm64/WebRTC.framework"
fix_headers "out/ios_sim_x64/WebRTC.framework"
fix_headers "out/mac_arm64/WebRTC.framework"
fix_headers "out/mac_x64/WebRTC.framework"
for fw in ios_arm64 ios_sim_arm64 ios_sim_x64 mac_arm64 mac_x64; do
    check_umbrella "out/$fw/WebRTC.framework"
done

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
# macOS frameworks use a Versions/A layout — the real binary lives at
# Versions/A/WebRTC and the top-level is expected to be a symlink. On M147 the
# ninja output ships the top-level as a regular file, so we must write the fat
# binary into Versions/A and restore the symlink at the top.
lipo -create \
    out/mac_arm64/WebRTC.framework/Versions/A/WebRTC \
    out/mac_x64/WebRTC.framework/Versions/A/WebRTC \
    -output out/mac_fat/WebRTC.framework/Versions/A/WebRTC
rm -f out/mac_fat/WebRTC.framework/WebRTC
ln -s Versions/Current/WebRTC out/mac_fat/WebRTC.framework/WebRTC
echo "  macOS fat binary archs: $(lipo -archs out/mac_fat/WebRTC.framework/Versions/A/WebRTC)"

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
echo "    # gh release create 158.2.0 $OUTPUT_DIR/WebRTC.xcframework.zip --repo scalecode-solutions/smc_webRTC"
echo ""

# Also copy to package root for local dev
rm -rf "$PACKAGE_DIR/WebRTC.xcframework"
cp -R "$OUTPUT_DIR/WebRTC.xcframework" "$PACKAGE_DIR/WebRTC.xcframework"
echo "  Also copied xcframework to $PACKAGE_DIR/WebRTC.xcframework"
echo ""
