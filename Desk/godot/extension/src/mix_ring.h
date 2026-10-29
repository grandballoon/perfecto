// What the mixing thread tells the game thread about each `_mix` call: one
// writer, one reader, no locks, no allocation once made.

#ifndef PERFECTO_MIX_RING_H
#define PERFECTO_MIX_RING_H

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace perfecto_godot {

struct MixRecord {
    /// When the call began, on the steady clock, in ns.
    int64_t start;
    /// How long the kernel took to render it, in ns.
    int64_t render;
    /// The kernel's frame at the start, and how many frames were asked for.
    uint64_t frame;
    int32_t frames;
    /// How long the latest note waited for this render, in ns; -1 if none
    /// did, -2 if its frame had already been rendered.
    int64_t waited;
};

class MixRing {
public:
    /// The mixing thread's. A full ring drops the record.
    void push(const MixRecord &record) {
        const std::size_t head = written.load(std::memory_order_relaxed);
        if (head - read.load(std::memory_order_acquire) == records.size()) return;
        records[head % records.size()] = record;
        written.store(head + 1, std::memory_order_release);
    }

    /// The game thread's.
    template <typename Visit> void drain(Visit visit) {
        std::size_t tail = read.load(std::memory_order_relaxed);
        const std::size_t head = written.load(std::memory_order_acquire);
        for (; tail != head; ++tail) visit(records[tail % records.size()]);
        read.store(tail, std::memory_order_release);
    }

private:
    std::array<MixRecord, 4096> records{};
    std::atomic<std::size_t> written{0};
    std::atomic<std::size_t> read{0};
};

} // namespace perfecto_godot

#endif
