// Catches memory being allocated on the render thread, which sooner or
// later makes a render late and the sound click.
//
// Built with PERFECTO_TRAP_ALLOCATIONS (the kernel's tests are), any
// `new` while a RenderGuard is alive on the thread stops the program on the
// spot. Built without it, a RenderGuard is nothing at all.

#ifndef PERFECTO_RENDER_GUARD_HPP
#define PERFECTO_RENDER_GUARD_HPP

#include <cstdint>

#if defined(__SSE__)
#include <xmmintrin.h>
#endif

namespace perfecto {

/// While one is alive, numbers too small to matter are rounded to zero
/// instead of being worked out exactly, which a processor does many times
/// more slowly: a filter or a tail dying away would otherwise make its
/// last, inaudible moments the most expensive.
struct FlushToZero {
#if defined(__aarch64__)
    FlushToZero() : saved(__builtin_arm_rsr64("FPCR")) { __builtin_arm_wsr64("FPCR", saved | (1ull << 24)); }
    ~FlushToZero() { __builtin_arm_wsr64("FPCR", saved); }
    uint64_t saved;
#elif defined(__SSE__)
    FlushToZero() : saved(_mm_getcsr()) { _mm_setcsr(saved | 0x8040); }
    ~FlushToZero() { _mm_setcsr(saved); }
    unsigned int saved;
#else
    FlushToZero() {}
#endif
    FlushToZero(const FlushToZero &) = delete;
    FlushToZero &operator=(const FlushToZero &) = delete;
};

#ifdef PERFECTO_TRAP_ALLOCATIONS

/// Whether this thread is inside a render call.
bool &isRendering();

struct RenderGuard {
    RenderGuard() { isRendering() = true; }
    ~RenderGuard() { isRendering() = false; }
    RenderGuard(const RenderGuard &) = delete;
    RenderGuard &operator=(const RenderGuard &) = delete;
};

#else

struct RenderGuard {
    RenderGuard() {}
};

#endif

}

#endif
