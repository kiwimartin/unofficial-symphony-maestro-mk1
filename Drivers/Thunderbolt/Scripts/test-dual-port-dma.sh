#!/bin/bash
set -euo pipefail
DRIVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$DRIVER_DIR/Source" "$DRIVER_DIR/Tests/DualPortDMATests.cpp" -o "$TMP_DIR/test"
"$TMP_DIR/test"
echo 'Dual-port buffer bounds, IRQ isolation and lifecycle policy: PASS (no hardware)'
