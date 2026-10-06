// Catches memory being allocated on the render thread, which sooner or
// later makes a render late and the sound click.
//
// Built with PERFECTO_TRAP_ALLOCATIONS (the kernel's tests are), any
// `new` while a RenderGuard is alive on the thread stops the program on the
// spot. Built without it, a RenderGuard is nothing at all.

#ifndef PERFECTO_RENDER_GUARD_HPP
#define PERFECTO_RENDER_GUARD_HPP

namespace perfecto {

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
