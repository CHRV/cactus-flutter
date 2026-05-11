#!/bin/bash -e
#
# update_native_libs.sh - Build and update cactus native libraries
#
# Usage:
#   ./scripts/update_native_libs.sh [VERSION]
#
# Arguments:
#   VERSION  Cactus version tag (default: v1.14)
#
# Prerequisites:
#   - python3.12, cmake, build-essential
#   - Android NDK (for Android builds)
#   - Xcode + command line tools (for iOS/macOS builds, macOS only)
#
# What it does:
#   1. Clones the cactus repo at the specified version tag
#   2. Builds native libraries for available platforms
#   3. Copies them into the correct locations in this Flutter project
#

VERSION="${1:-v1.14}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_PROJECT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/cactus-build-${VERSION}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Cactus Native Library Updater ===${NC}"
echo "Version: ${VERSION}"
echo "Flutter project: ${FLUTTER_PROJECT}"
echo "Build directory: ${BUILD_DIR}"
echo ""

# ─── Step 1: Clone ──────────────────────────────────────────────────────
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Build directory exists, reusing: ${BUILD_DIR}${NC}"
    echo -e "${YELLOW}Delete it first if you want a fresh clone.${NC}"
else
    echo -e "${BLUE}Step 1: Cloning cactus at ${VERSION}...${NC}"
    git clone --depth 1 --branch "${VERSION}" \
        https://github.com/cactus-compute/cactus.git "$BUILD_DIR"
    echo -e "${GREEN}✓ Cloned${NC}"
fi
echo ""

# ─── Step 2: Build Android ─────────────────────────────────────────────
echo -e "${BLUE}Step 2: Building Android (arm64-v8a)...${NC}"

if [ -z "$ANDROID_NDK_HOME" ]; then
    if [ -n "$ANDROID_HOME" ]; then
        ANDROID_NDK_HOME=$(ls -d "$ANDROID_HOME/ndk/"* 2>/dev/null | sort -V | tail -1)
    elif [ -d "$HOME/Library/Android/sdk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    elif [ -d "$HOME/Android/Sdk" ]; then
        ANDROID_NDK_HOME=$(ls -d "$HOME/Android/Sdk/ndk/"* 2>/dev/null | sort -V | tail -1)
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo -e "${YELLOW}⚠ Android NDK not found. Skipping Android build.${NC}"
    echo -e "${YELLOW}  Set ANDROID_NDK_HOME or ANDROID_HOME to enable.${NC}"
else
    export ANDROID_NDK_HOME
    echo "  NDK: ${ANDROID_NDK_HOME}"
    bash "${BUILD_DIR}/android/build.sh"

    TARGET="${FLUTTER_PROJECT}/android/src/main/jniLibs/arm64-v8a/libcactus.so"
    cp "${BUILD_DIR}/android/libcactus.so" "$TARGET"
    echo -e "${GREEN}✓ Android: $(ls -lh "$TARGET" | awk '{print $5}') → $TARGET${NC}"
fi
echo ""

# ─── Step 3: Build Apple (iOS/macOS) ────────────────────────────────────
echo -e "${BLUE}Step 3: Building Apple (iOS/macOS)...${NC}"

if [ "$(uname)" != "Darwin" ]; then
    echo -e "${YELLOW}⚠ Not on macOS. Skipping iOS/macOS builds.${NC}"
    echo -e "${YELLOW}  Run this script on a Mac with Xcode to build Apple frameworks.${NC}"
else
    if [ -f "${BUILD_DIR}/apple/build.sh" ]; then
        bash "${BUILD_DIR}/apple/build.sh"

        IOS_SRC="${BUILD_DIR}/apple/cactus-ios.xcframework"
        MACOS_SRC="${BUILD_DIR}/apple/cactus-macos.xcframework"

        if [ -d "$IOS_SRC" ]; then
            rm -rf "${FLUTTER_PROJECT}/ios/cactus.xcframework"
            cp -R "$IOS_SRC" "${FLUTTER_PROJECT}/ios/cactus.xcframework"
            echo -e "${GREEN}✓ iOS: cactus-ios.xcframework → ios/cactus.xcframework${NC}"
        fi

        if [ -d "$MACOS_SRC" ]; then
            rm -rf "${FLUTTER_PROJECT}/macos/cactus.xcframework"
            cp -R "$MACOS_SRC" "${FLUTTER_PROJECT}/macos/cactus.xcframework"
            echo -e "${GREEN}✓ macOS: cactus-macos.xcframework → macos/cactus.xcframework${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ apple/build.sh not found. Skipping.${NC}"
    fi
fi
echo ""

# ─── Step 4: Verify ────────────────────────────────────────────────────
echo -e "${BLUE}Step 4: Verifying symbols...${NC}"

ANDROID_SO="${FLUTTER_PROJECT}/android/src/main/jniLibs/arm64-v8a/libcactus.so"
if [ -f "$ANDROID_SO" ]; then
    SYMBOL_COUNT=$(nm -D "$ANDROID_SO" | grep " T cactus_" | wc -l)
    echo -e "${GREEN}✓ Android libcactus.so: ${SYMBOL_COUNT} exported symbols${NC}"

    MISSING=""
    for sym in cactus_init cactus_complete cactus_destroy cactus_reset cactus_stop \
               cactus_embed cactus_image_embed cactus_audio_embed \
               cactus_transcribe cactus_stream_transcribe_start \
               cactus_prefill cactus_tokenize cactus_score_window \
               cactus_vad cactus_diarize cactus_embed_speaker \
               cactus_detect_language cactus_rag_query \
               cactus_index_init cactus_index_add cactus_index_delete \
               cactus_index_get cactus_index_query cactus_index_compact cactus_index_destroy \
               cactus_get_last_error cactus_set_telemetry_environment \
               cactus_set_app_id cactus_telemetry_flush cactus_telemetry_shutdown \
               cactus_log_set_level cactus_log_set_callback; do
        if ! nm -D "$ANDROID_SO" | grep -q " T ${sym}$"; then
            MISSING="${MISSING} ${sym}"
        fi
    done

    if [ -n "$MISSING" ]; then
        echo -e "${RED}✗ Missing symbols:${MISSING}${NC}"
    else
        echo -e "${GREEN}✓ All expected engine symbols present${NC}"
    fi
else
    echo -e "${RED}✗ Android libcactus.so not found${NC}"
fi
echo ""

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}Update complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "Clean up build directory:"
echo "  rm -rf ${BUILD_DIR}"
