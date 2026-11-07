#include <initializer_list>
#include <cassert>
#include "SymphonyDualPortDMA.h"
using namespace SymphonyDMA;
int main() {
    PortRegisters a{}, b{};
    assert(Registers(1, a) && Registers(2, b));
    assert(a.control == 0x04 && b.control == 0x90);
    assert(b.captureBase == 0x7C && b.playbackBase == 0x84);
    assert(b.captureCurrent == 0x80 && b.playbackCurrent == 0x88);
    assert(!Registers(0, b) && !Registers(3, b));
    Buffers ports[2] = {{{0x100000, 0x100000}, {0x200000, 0x100000}},
                        {{0x300000, 0x100000}, {0x400000, 0x100000}}};
    assert(ValidateBuffers(ports, 2, 8192));
    assert(!ValidateBuffers(nullptr, 2, 8192));
    assert(!ValidateBuffers(ports, 3, 8192));
    assert(!ValidateBuffers(ports, 2, UINT32_MAX));
    for (uint64_t bad : {uint64_t(0), uint64_t(3), uint64_t(0xFFF80000), uint64_t(0x100000000)}) {
        auto saved = ports[1].capture;
        ports[1].capture.address = bad;
        assert(!ValidateBuffers(ports, 2, 8192)); ports[1].capture = saved;
    }
    auto saved = ports[1];
    ports[1].capture.address = ports[0].playback.address;
    assert(!ValidateBuffers(ports, 2, 8192)); ports[1] = saved;
    ports[1].playback.bytes--;
    assert(!ValidateBuffers(ports, 2, 8192)); ports[1] = saved;
    for (unsigned p = 1; p <= 2; ++p) {
        PortRegisters r{}; Registers(p, r);
        auto own = DecodeIRQ(r.wrap | r.overflow | r.underflow | kInt_MeterTrigger, p);
        auto other = DecodeIRQ(r.wrap | r.overflow | r.underflow, 3 - p);
        assert(own.wrap && own.overflow && own.underflow);
        assert(!other.wrap && !other.overflow && !other.underflow);
        assert(!DecodeIRQ(UINT32_MAX, p).wrap);
        assert(!DecodeIRQ(kInt_MeterTrigger, p).wrap);
    }
    PortState first, second;
    first.Observe(true, 48000); second.Observe(true, 48000);
    assert(first.Prepare(true) && second.Prepare(true));
    assert(!second.Start(kPort2HardwareValidated, second.generation));
    assert(first.Start(true, first.generation) && second.Start(true, second.generation)); // simulator only
    assert(Synchronized(first, second));
    first.Interrupt(DecodeIRQ(kInt_A2HWrap, 1), 3);
    second.Interrupt(DecodeIRQ(kInt_A2H2Wrap | kInt_HostBufOverflow2, 2));
    assert(first.wraps == 3 && first.phase == Phase::running);
    assert(second.wraps == 1 && second.overruns == 1 && second.phase == Phase::faulted);
    assert(!Synchronized(first, second));
    second.Observe(true, 96000); assert(second.Prepare(true));
    auto oldGeneration = second.generation;
    second.Suspend(); assert(!second.Start(true, oldGeneration));
    second.Observe(true, 96000); assert(second.Prepare(true));
    assert(!second.Start(true, oldGeneration));
    assert(second.Start(true, second.generation)); assert(!Synchronized(first, second));
    second.Observe(false, 0); assert(second.phase == Phase::faulted);
    second.Disconnect(); assert(second.phase == Phase::detached && second.rate == 0);
    first.Stop(); assert(first.phase == Phase::observed);
}
