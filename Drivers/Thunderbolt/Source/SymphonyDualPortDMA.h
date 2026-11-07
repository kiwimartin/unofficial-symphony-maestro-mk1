// Hardware-independent dual-port DMA policy. Does not program registers.
#pragma once
#include <cstdint>
#include "Sym64Registers.h"

namespace SymphonyDMA {
enum class Phase { detached, observed, prepared, running, suspended, faulted };
struct PortRegisters {
    uint64_t control, captureSize, playbackSize, captureBase, playbackBase;
    uint64_t captureCurrent, playbackCurrent;
    uint32_t wrap, overflow, underflow;
};
inline bool Registers(unsigned port, PortRegisters &out) {
    if (port == 1) out = {kRegGCSR, kRegA2HBUFSIZE, kRegH2ABUFSIZE,
        kRegA2HHBA, kRegH2AHBA, kRegA2HCHA, kRegH2ACHA,
        kInt_A2HWrap, kInt_HostBufOverflow, kInt_AudioBufUnderflow};
    else if (port == 2) out = {kRegGCSR2, kRegA2H2BUFSIZE, kRegH2A2BUFSIZE,
        kRegA2H2HBA, kRegH2A2HBA, kRegA2H2CHA, kRegH2A2CHA,
        kInt_A2H2Wrap, kInt_HostBufOverflow2, kInt_AudioBufUnderflow2};
    else return false;
    return true;
}
struct Region { uint64_t address = 0, bytes = 0; };
inline bool Valid(const Region &r, uint64_t requiredBytes) {
    // Existing FPGA host-base registers are 32-bit. Do not truncate IOVAs.
    return requiredBytes && r.address && !(r.address % 4) && r.bytes >= requiredBytes &&
        r.address <= UINT32_MAX && r.bytes <= uint64_t(UINT32_MAX) + 1 - r.address;
}
inline bool Overlap(const Region &a, const Region &b) {
    // Call only after Valid: endpoints then cannot overflow uint64_t.
    return a.address < b.address + b.bytes && b.address < a.address + a.bytes;
}
struct Buffers { Region capture, playback; };
inline bool ValidateBuffers(const Buffers *ports, unsigned count, uint32_t frames) {
    if (!ports || count < 1 || count > 2 || frames != kNumSampleFrames) return false;
    const uint64_t bytes = uint64_t(frames) * kMaxChannelsPerPort * sizeof(int32_t);
    for (unsigned p = 0; p < count; ++p) {
        if (!Valid(ports[p].capture, bytes) || !Valid(ports[p].playback, bytes) ||
            Overlap(ports[p].capture, ports[p].playback)) return false;
        for (unsigned q = 0; q < p; ++q)
            if (Overlap(ports[p].capture, ports[q].capture) ||
                Overlap(ports[p].capture, ports[q].playback) ||
                Overlap(ports[p].playback, ports[q].capture) ||
                Overlap(ports[p].playback, ports[q].playback)) return false;
    }
    return true;
}
struct IRQEvent { bool wrap, overflow, underflow; };
inline IRQEvent DecodeIRQ(uint32_t status, unsigned port) {
    PortRegisters r{};
    if (status == UINT32_MAX || !Registers(port, r)) return {};
    return {bool(status & r.wrap), bool(status & r.overflow), bool(status & r.underflow)};
}
struct PortState {
    Phase phase = Phase::detached;
    uint64_t generation = 0, wraps = 0, overruns = 0, underruns = 0;
    uint32_t rate = 0;
    void Disconnect() { phase = Phase::detached; rate = 0; ++generation; }
    void Observe(bool clockPresent, uint32_t observedRate) {
        if (!clockPresent || !observedRate) { phase = Phase::faulted; rate = 0; ++generation; return; }
        if (rate != observedRate || phase == Phase::detached || phase == Phase::faulted || phase == Phase::suspended) {
            ++generation; phase = Phase::observed;
        }
        rate = observedRate;
    }
    bool Prepare(bool validatedBuffers) {
        if (phase != Phase::observed || !validatedBuffers) return false;
        phase = Phase::prepared; return true;
    }
    // This is a policy decision only, never proof of hardware readiness.
    bool Start(bool protocolVerified, uint64_t expectedGeneration) {
        if (phase != Phase::prepared || !protocolVerified || expectedGeneration != generation) return false;
        phase = Phase::running; return true;
    }
    void Suspend() { phase = Phase::suspended; ++generation; }
    void Stop() { phase = rate ? Phase::observed : Phase::detached; ++generation; }
    void Interrupt(IRQEvent event, uint64_t count = 1) {
        if (phase != Phase::running) return;
        if (event.wrap) wraps += count;
        if (event.overflow) ++overruns;
        if (event.underflow) ++underruns;
        if (event.overflow || event.underflow) { phase = Phase::faulted; ++generation; }
    }
};
inline bool Synchronized(const PortState &a, const PortState &b) {
    return a.phase == Phase::running && b.phase == Phase::running && a.rate && a.rate == b.rate;
}
// No runtime flag can turn this into an operational Port-2 driver.
static constexpr bool kPort2HardwareValidated = false;
}
