#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRIVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$DRIVER_DIR/Source" \
    "$DRIVER_DIR/Tests/PassiveDiagnosticsTests.cpp" -o "$TMP_DIR/test"
"$TMP_DIR/test"
python3 - "$DRIVER_DIR" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
source = (root / 'Source/SymphonyThunderbridge.cpp').read_text()
block = source.split('kern_return_t SymphonyThunderbridge::ReadDualPortDiagnostics(', 1)[1].split('// ── ReadTimingHealth', 1)[0]
for forbidden in ('WriteRegister(', 'ModifyRegister(', 'MemoryWrite', 'ConfigurationWrite',
                  'HardwareReachable(', 'XLinkTxAdmissible(', 'ReadVendor', 'MaybeRecover',
                  'SendVendor', 'ReprogramCard', '__atomic_store', 'IOSleep('):
    assert forbidden not in block, forbidden
for gate in ('stopping', 'txShutdown', 'providerPowerOff', 'hwSuspended', 'PCIEndpointPresent'):
    assert block.index(gate) < block.index('CapturePassiveRegisters'), gate
assert 'DispatchSync' in block
print('Passive capture, BAR bounds, invalid reads and lifecycle source gates: PASS')
PY
