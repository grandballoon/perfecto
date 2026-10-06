#include "RenderGuard.hpp"

#ifdef PERFECTO_TRAP_ALLOCATIONS

#include <cstdio>
#include <cstdlib>
#include <new>

namespace perfecto {

bool &isRendering() {
    thread_local bool rendering = false;
    return rendering;
}

}

namespace {

void *allocate(std::size_t size) {
    if (perfecto::isRendering()) {
        std::fputs("PerfectoKernel: memory allocated on the render thread\n", stderr);
        std::abort();
    }
    if (void *memory = std::malloc(size ? size : 1)) return memory;
    throw std::bad_alloc();
}

}

void *operator new(std::size_t size) { return allocate(size); }
void *operator new[](std::size_t size) { return allocate(size); }
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete[](void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, std::size_t) noexcept { std::free(memory); }
void operator delete[](void *memory, std::size_t) noexcept { std::free(memory); }

#endif
