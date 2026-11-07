#include <cassert>
#include <vector>
#include "SymphonyPassiveDiagnostics.h"

int main() {
    SymphonyDualPortDiagnosticsOutput out = {};
    std::vector<uint64_t> reads;
    auto reader = [&](uint64_t offset, uint32_t *value) {
        reads.push_back(offset);
        // Missing port 2 must not invalidate port 1 or fabricate zero registers.
        *value = offset == kRegXLink2Status ? UINT32_MAX : uint32_t(offset);
    };
    CapturePassiveRegisters(0x100, reader, out);
    assert(reads.size() == 16);
    assert(out.validRegisters == (0xFFFFu & ~(1u << 11)));
    assert(out.registers[11] == 0);
    assert(out.registers[5] == kRegXLink1Status);
    assert(out.registers[14] == kRegA2H2CHA);
    assert(out.registers[15] == kRegH2A2CHA);
    for (uint64_t offset : reads) {
        assert(offset != kRegXLink1RX && offset != kRegXLink2RX);
        assert(offset != kRegXLink1TX && offset != kRegXLink2TX);
        assert(offset != kRegIntStatus && offset != kRegFlash);
    }
    reads.clear();
    CapturePassiveRegisters(0, reader, out);
    assert(reads.empty() && out.validRegisters == 0);
    CapturePassiveRegisters(3, reader, out);
    assert(reads.empty() && out.validRegisters == 0);
    CapturePassiveRegisters(4, reader, out);
    assert(reads.size() == 1 && out.validRegisters == 1);
    reads.clear();
    CapturePassiveRegisters(kRegXLink2Status + 3, reader, out);
    for (uint64_t offset : reads) assert(offset + 4 <= kRegXLink2Status + 3);
    assert(!(out.validRegisters & (1u << 11)));
    CapturePassiveRegisters(0x100, [](uint64_t, uint32_t *value) { *value = UINT32_MAX; }, out);
    assert(out.validRegisters == 0);
}
