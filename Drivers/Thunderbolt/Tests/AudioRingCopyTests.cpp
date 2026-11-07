#include <cassert>
#include <vector>
#include <algorithm>
#include "SymphonyAudioRingCopy.h"
using namespace SymphonyAudio;
int main() {
    constexpr unsigned ring = 17;
    for (unsigned count : {1u, 2u}) for (uint32_t start = 0; start < ring; ++start)
    for (uint32_t frames : {0u, 1u, 7u, ring, ring + 1u, UINT32_MAX}) {
        std::vector<int32_t> stream(ring * 32 * count), p1(ring * 32, -1), p2(ring * 32, -1);
        for (unsigned f = 0; f < ring; ++f) for (unsigned c = 0; c < 32 * count; ++c)
            stream[f * 32 * count + c] = int32_t(f * 1000 + c + 1);
        Buffer host{reinterpret_cast<uint8_t *>(stream.data()), stream.size() * 4};
        Buffer ports[] = {{reinterpret_cast<uint8_t *>(p1.data()), p1.size() * 4},
                          {reinterpret_cast<uint8_t *>(p2.data()), p2.size() * 4}};
        assert(Copy(Direction::playback, host, ports, count, ring, start + uint64_t(ring) * 12345, frames));
        const auto n = std::min(frames, uint32_t(ring));
        for (unsigned f = 0; f < ring; ++f) {
            const bool copied = (f + ring - start) % ring < n;
            for (unsigned c = 0; c < 32; ++c) {
                assert(p1[f * 32 + c] == (copied ? int32_t(f * 1000 + c + 1) : -1));
                assert(p2[f * 32 + c] == (copied && count == 2 ? int32_t(f * 1000 + c + 33) : -1));
            }
        }
        std::fill(stream.begin(), stream.end(), -2);
        assert(Copy(Direction::capture, host, ports, count, ring, start, frames));
        for (unsigned f = 0; f < ring; ++f) for (unsigned c = 0; c < 32 * count; ++c)
            assert(stream[f * 32 * count + c] == ((f + ring - start) % ring < n ? int32_t(f * 1000 + c + 1) : -2));
        auto before = stream;
        auto saved = ports[1]; ports[1] = {nullptr, 0};
        assert(!Copy(Direction::capture, host, ports, 2, ring, 0, 1));
        assert(stream == before); ports[1] = saved;
        assert(!Copy(Direction::capture, {host.data, host.bytes - 1}, ports, count, ring, 0, 1));
        assert(!Copy(Direction::capture, host, ports, 3, ring, 0, 1));
        assert(!Copy(Direction::capture, host, nullptr, count, ring, 0, 1));
        assert(!Copy(Direction::capture, host, ports, count, 0, 0, 1));
        auto overlapping = ports[0]; ports[0] = host;
        assert(!Copy(Direction::capture, host, ports, count, ring, 0, 1)); ports[0] = overlapping;
    }
}
