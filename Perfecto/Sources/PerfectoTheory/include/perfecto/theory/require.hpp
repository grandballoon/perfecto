// A broken promise between callers: the theory has no recoverable errors,
// only inputs a caller must never give (a mode of six notes, a letter past
// B), and those stop the program where they are found, as Swift's
// `precondition` does. Nothing here throws, so it builds where exceptions
// are off (a Godot extension, a console).

#ifndef PERFECTO_THEORY_REQUIRE_HPP
#define PERFECTO_THEORY_REQUIRE_HPP

#include <cstdio>
#include <cstdlib>

#define PERFECTO_REQUIRE(condition, message)                                                          \
    do {                                                                                              \
        if (!(condition)) {                                                                           \
            std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, message);                         \
            std::abort();                                                                             \
        }                                                                                             \
    } while (false)

#endif
