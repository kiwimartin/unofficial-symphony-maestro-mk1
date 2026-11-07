#!/bin/bash
# Compile/link only. No bundle, profile lookup, signing or installation.
set -euo pipefail
DRIVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$DRIVER_DIR/Diagnostics"
BUILD="$DRIVER_DIR/build/passive"
SDK="$(xcrun --sdk driverkit --show-sdk-path)"
IIG="$(xcrun --sdk driverkit -f iig)"
CLANG="$(xcrun --sdk driverkit -f clang++)"
FRAMEWORKS="$SDK/System/DriverKit/System/Library/Frameworks"
mkdir -p "$BUILD"
for unit in SymphonyPassiveDiagnostics SymphonyPassiveUserClient; do
    "$IIG" --def "$SOURCE/$unit.iig" --header "$BUILD/$unit.h" --impl "$BUILD/$unit.iig.cpp" \
        --deployment-target 25.2 -- -isysroot "$SDK" -x c++ -std=c++17 -D__IIG=1 -iframework "$FRAMEWORKS"
done
for unit in SymphonyPassiveDiagnostics SymphonyPassiveUserClient; do
    for source in "$SOURCE/$unit.cpp" "$BUILD/$unit.iig.cpp"; do
        "$CLANG" -c -target arm64-apple-driverkit25.2 -isysroot "$SDK" -std=c++17 \
            -iframework "$FRAMEWORKS" -I "$BUILD" -I "$DRIVER_DIR/Source" -O2 \
            "$source" -o "$BUILD/$(basename "$source").o"
    done
done
"$CLANG" -target arm64-apple-driverkit25.2 -isysroot "$SDK" -F "$FRAMEWORKS" \
    -L "$SDK/System/DriverKit/usr/lib" -framework DriverKit -framework PCIDriverKit \
    "$BUILD"/*.cpp.o -o "$BUILD/SymphonyPassiveDiagnostics-unsigned"
echo 'Passive diagnostic driver compiled; no installable bundle or signing performed.'
