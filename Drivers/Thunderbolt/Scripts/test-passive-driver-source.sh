#!/bin/bash
set -euo pipefail
DRIVER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$DRIVER_DIR/Diagnostics" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1])
for p in root.glob('*.cpp'):
    code=p.read_text()
    for forbidden in ('MemoryWrite', 'ConfigurationWrite', 'ModifyRegister', 'WriteRegister',
                      'ReadVendor', 'SendVendor', 'IODMACommand', 'IOInterruptDispatchSource', 'IOSleep('):
        assert forbidden not in code, (p, forbidden)
service=(root/'SymphonyPassiveDiagnostics.cpp').read_text()
assert 'command & 2' in service and 'mask != 0' in service
assert 'kGCSR_DMAEnableMask' in service and 'kGCSR2_DMAEnableMask' in service
stop=service.split('IMPL(SymphonyPassiveDiagnostics, Stop)',1)[1].split('IMPL(SymphonyPassiveDiagnostics, SetPowerState)',1)[0]
assert stop.index('DispatchSync') < stop.index('Close(')
client=(root/'SymphonyPassiveUserClient.cpp').read_text()
assert 'selector != kSelectorReadDualPortDiagnostics' in client
assert 'kSelectorSendVendor' not in client
print('Passive-only driver no-write, dirty-device refusal and teardown gates: PASS')
PY
