// Passive register allowlist. Never read RX FIFOs (consumes responses), TX,
// flash, or IntStatus (the IRQ path documents read acknowledgement effects).
#pragma once
#include "Sym64Registers.h"
#include "SymphonyThunderbridgeShared.h"

static constexpr uint64_t kPassiveDiagnosticRegisters[] = {
    kRegIDReg, kRegXLinkClocking, kRegDNALower, kRegClkCtrl,
    kRegGCSR, kRegXLink1Status, kRegA2HBUFSIZE, kRegH2ABUFSIZE,
    kRegA2HCHA, kRegH2ACHA,
    kRegGCSR2, kRegXLink2Status, kRegA2H2BUFSIZE, kRegH2A2BUFSIZE,
    kRegA2H2CHA, kRegH2A2CHA
};
static_assert(sizeof(kPassiveDiagnosticRegisters) / sizeof(uint64_t) == 16);
static_assert(sizeof(SymphonyDualPortDiagnosticsOutput) == 104);

// Reader has only a load operation. All-ones is unavailable, never a live link.
// Bounds are checked before invoking the reader; partial captures are explicit.
template <typename Reader>
void CapturePassiveRegisters(uint64_t barSize, Reader read,
                             SymphonyDualPortDiagnosticsOutput &out) {
    out.validRegisters = 0;
    for (uint32_t i = 0; i < 16; ++i) {
        out.registers[i] = 0;
        const uint64_t offset = kPassiveDiagnosticRegisters[i];
        if (barSize < 4 || offset > barSize - 4) continue;
        uint32_t value = UINT32_MAX;
        read(offset, &value);
        if (value == UINT32_MAX) continue;
        out.registers[i] = value;
        out.validRegisters |= 1u << i;
    }
}
