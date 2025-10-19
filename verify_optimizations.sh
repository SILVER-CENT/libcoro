#!/bin/bash
# Verification script for compiler optimization flags
# Usage: ./verify_optimizations.sh [build_dir]

set -e

BUILD_DIR="${1:-build-release}"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory '$BUILD_DIR' does not exist"
    echo "Usage: $0 [build_dir]"
    exit 1
fi

echo "============================================"
echo "Optimization Flags Verification"
echo "============================================"
echo "Build directory: $BUILD_DIR"
echo ""

# Check if library exists
if [ ! -f "$BUILD_DIR/libcoro.a" ]; then
    echo "Error: libcoro.a not found in $BUILD_DIR"
    exit 1
fi

echo "✓ Library found: $BUILD_DIR/libcoro.a"
echo ""

# Check library size
echo "Library size:"
ls -lh "$BUILD_DIR/libcoro.a" | awk '{print "  ", $5, $9}'
size "$BUILD_DIR/libcoro.a" 2>/dev/null || echo "  (size command not available)"
echo ""

# Check for LTO sections (if applicable)
echo "Checking for LTO/IPO markers:"
if readelf -S "$BUILD_DIR/libcoro.a" 2>/dev/null | grep -i "\.gnu\.lto" >/dev/null; then
    echo "  ✓ LTO sections detected (.gnu.lto.*)"
elif nm "$BUILD_DIR/libcoro.a" 2>/dev/null | grep -i "\.gnu\.lto" >/dev/null; then
    echo "  ✓ LTO markers detected in symbols"
else
    # LTO might be embedded differently or not visible in static lib
    echo "  ℹ LTO markers not found in archive (may be applied at link time)"
fi
echo ""

# Check symbol visibility
echo "Checking symbol visibility:"
if command -v nm >/dev/null 2>&1; then
    # Count global symbols (uppercase letters in nm output = global)
    GLOBAL_COUNT=$(nm -g --defined-only "$BUILD_DIR/libcoro.a" 2>/dev/null | grep " [A-Z] " | wc -l)
    # Count local symbols (lowercase letters = hidden/local)
    LOCAL_COUNT=$(nm -g --defined-only "$BUILD_DIR/libcoro.a" 2>/dev/null | grep " [a-z] " | wc -l)
    
    echo "  Global symbols: $GLOBAL_COUNT"
    echo "  Local symbols: $LOCAL_COUNT"
    
    if [ $GLOBAL_COUNT -lt 200 ]; then
        echo "  ✓ Good symbol visibility (hidden visibility is working)"
    else
        echo "  ⚠ High global symbol count (visibility flags may not be applied)"
    fi
else
    echo "  ℹ nm command not available, skipping symbol check"
fi
echo ""

# Check CMake cache for optimization settings
echo "CMake configuration:"
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "  Build type:"
    grep "CMAKE_BUILD_TYPE:" "$BUILD_DIR/CMakeCache.txt" | head -1 | sed 's/^/    /'
    
    echo "  CXX flags (Release):"
    grep "CMAKE_CXX_FLAGS_RELEASE:" "$BUILD_DIR/CMakeCache.txt" | head -1 | sed 's/^/    /'
    
    echo "  IPO/LTO:"
    if grep -q "CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE:BOOL=ON" "$BUILD_DIR/CMakeCache.txt"; then
        echo "    ✓ CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE=ON"
    else
        echo "    ✗ CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE not enabled"
    fi
else
    echo "  ℹ CMakeCache.txt not found"
fi
echo ""

# Check for security hardening flags in compile_commands.json
if [ -f "$BUILD_DIR/compile_commands.json" ]; then
    echo "Verifying optimization flags in compile commands:"
    
    # Extract one compile command for libcoro
    COMPILE_CMD=$(jq -r '.[] | select(.file | contains("src/event.cpp")) | .command' "$BUILD_DIR/compile_commands.json" 2>/dev/null)
    
    if [ -n "$COMPILE_CMD" ]; then
        # Check for key flags
        FLAGS_TO_CHECK=(
            "flto"
            "fvisibility=hidden"
            "fdata-sections"
            "ffunction-sections"
            "_FORTIFY_SOURCE=2"
            "fstack-protector-strong"
        )
        
        for FLAG in "${FLAGS_TO_CHECK[@]}"; do
            if echo "$COMPILE_CMD" | grep -q -- "-$FLAG"; then
                echo "  ✓ -$FLAG"
            else
                echo "  ✗ -$FLAG (missing)"
            fi
        done
    else
        echo "  ℹ Could not extract compile command (jq may not be available)"
    fi
else
    echo "  ℹ compile_commands.json not found"
fi
echo ""

echo "============================================"
echo "Verification complete!"
echo "============================================"
