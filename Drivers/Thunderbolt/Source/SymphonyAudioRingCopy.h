#pragma once
#include <cstdint>
#include <cstring>
#include <cstddef>

namespace SymphonyAudio {
enum class Direction { capture, playback };
struct Buffer { uint8_t *data; size_t bytes; };
inline bool RangeValid(Buffer b, size_t required) {
    return b.data && b.bytes >= required && uintptr_t(b.data) <= UINTPTR_MAX - required;
}
inline bool Overlap(Buffer a, size_t aBytes, Buffer b, size_t bBytes) {
    return uintptr_t(a.data) < uintptr_t(b.data) + bBytes &&
           uintptr_t(b.data) < uintptr_t(a.data) + aBytes;
}
// Interleaved SInt32 host frames: [port1 ch1..32, port2 ch1..32]. FPGA rings
// remain separate 32-channel interleaved buffers. No allocation/locks/MMIO.
inline bool Copy(Direction direction, Buffer stream, const Buffer *ports,
                 unsigned portCount, uint32_t ringFrames, uint64_t sampleTime,
                 uint32_t requestedFrames) {
    if (!ports || (portCount != 1 && portCount != 2) || !ringFrames) return false;
    constexpr size_t portFrameBytes = 32 * sizeof(int32_t);
    if (ringFrames > SIZE_MAX / (portFrameBytes * portCount)) return false;
    const size_t portBytes = size_t(ringFrames) * portFrameBytes;
    const size_t hostFrameBytes = portFrameBytes * portCount;
    const size_t hostBytes = portBytes * portCount;
    if (!RangeValid(stream, hostBytes)) return false;
    for (unsigned p = 0; p < portCount; ++p) {
        if (!RangeValid(ports[p], portBytes) || Overlap(stream, hostBytes, ports[p], portBytes)) return false;
        for (unsigned q = 0; q < p; ++q)
            if (Overlap(ports[p], portBytes, ports[q], portBytes)) return false;
    }
    // Validate everything before touching a destination. Missing port 2 is an
    // error, never a channel shift or duplication of port 1.
    const uint32_t frames = requestedFrames > ringFrames ? ringFrames : requestedFrames;
    const uint32_t start = uint32_t(sampleTime % ringFrames);
    if (portCount == 1) {
        const size_t offset = size_t(start) * portFrameBytes;
        const size_t bytes = size_t(frames) * portFrameBytes;
        const size_t first = bytes < portBytes - offset ? bytes : portBytes - offset;
        auto dst = direction == Direction::playback ? ports[0].data : stream.data;
        auto src = direction == Direction::playback ? stream.data : ports[0].data;
        memcpy(dst + offset, src + offset, first);
        if (bytes > first) memcpy(dst, src, bytes - first);
    } else {
        for (uint32_t f = 0; f < frames; ++f) {
            const size_t frame = (uint64_t(start) + f) % ringFrames;
            for (unsigned p = 0; p < portCount; ++p) {
                auto host = stream.data + frame * hostFrameBytes + p * portFrameBytes;
                auto card = ports[p].data + frame * portFrameBytes;
                if (direction == Direction::playback) memcpy(card, host, portFrameBytes);
                else memcpy(host, card, portFrameBytes);
            }
        }
    }
    return true;
}
}
