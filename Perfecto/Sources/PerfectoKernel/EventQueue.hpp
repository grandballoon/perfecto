// How events get from the thread that sends them to the render thread, and
// wait there for their frame.

#ifndef PERFECTO_EVENT_QUEUE_HPP
#define PERFECTO_EVENT_QUEUE_HPP

#include "PerfectoKernel.h"

#include <array>
#include <atomic>
#include <cstddef>

namespace perfecto {

/// A fixed ring that one thread writes and one other thread reads, with no
/// lock: each side only ever moves its own end.
template <std::size_t Capacity>
class Mailbox {
public:
    /// The writer's. False if the ring is full.
    bool push(const PerfectoEvent &event) {
        const auto write = written.load(std::memory_order_relaxed);
        if (write - read.load(std::memory_order_acquire) == Capacity) return false;
        slots[write % Capacity] = event;
        written.store(write + 1, std::memory_order_release);
        return true;
    }

    /// The reader's. False if the ring is empty.
    bool pop(PerfectoEvent &event) {
        const auto next = read.load(std::memory_order_relaxed);
        if (next == written.load(std::memory_order_acquire)) return false;
        event = slots[next % Capacity];
        read.store(next + 1, std::memory_order_release);
        return true;
    }

    /// Empties the ring. Only while neither side is running.
    void clear() {
        read.store(0);
        written.store(0);
    }

private:
    std::array<PerfectoEvent, Capacity> slots{};
    std::atomic<std::size_t> written{0};
    std::atomic<std::size_t> read{0};
};

/// The render thread's events, waiting for their frames: kept in time
/// order, and in the order they were sent where times are equal.
template <std::size_t Capacity>
class Agenda {
public:
    /// False if there is no room.
    bool add(const PerfectoEvent &event) {
        if (count == Capacity) return false;
        std::size_t at = count;
        while (at > 0 && events[at - 1].time > event.time) {
            events[at] = events[at - 1];
            --at;
        }
        events[at] = event;
        ++count;
        return true;
    }

    bool empty() const { return count == first; }

    /// The earliest event. Only when not empty.
    const PerfectoEvent &next() const { return events[first]; }

    void removeNext() {
        ++first;
        if (first == count) first = count = 0;
    }

    /// Makes room at the end by closing the gap the removed events left.
    void compact() {
        if (first == 0) return;
        for (std::size_t i = first; i < count; ++i) events[i - first] = events[i];
        count -= first;
        first = 0;
    }

    void clear() { first = count = 0; }

private:
    std::array<PerfectoEvent, Capacity> events{};
    std::size_t first = 0;
    std::size_t count = 0;
};

}

#endif
