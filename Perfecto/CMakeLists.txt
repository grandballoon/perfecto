# The package's portable C++, built without SwiftPM: the theory core
# (`Sources/PerfectoTheory`) and its tests, for the engines and platforms the
# desk is to run on (docs/desk-engine-and-audio.md). SwiftPM builds the same
# sources for the Swift side (Package.swift).
#
#   cmake -S . -B .build/cmake && cmake --build .build/cmake && ctest --test-dir .build/cmake
cmake_minimum_required(VERSION 3.21)
project(Perfecto LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

file(GLOB PERFECTO_THEORY_SOURCES CONFIGURE_DEPENDS Sources/PerfectoTheory/*.cpp)
add_library(PerfectoTheory STATIC ${PERFECTO_THEORY_SOURCES})
target_include_directories(PerfectoTheory PUBLIC Sources/PerfectoTheory/include)
if(MSVC)
    target_compile_options(PerfectoTheory PRIVATE /W4 /utf-8)
else()
    target_compile_options(PerfectoTheory PRIVATE -Wall -Wextra -Wpedantic)
    # Each step rounded as Swift rounds it, never two fused into one, so the
    # C++ and the Swift agree to the last bit and every compiler (GCC fuses
    # by default) builds the same numbers.
    target_compile_options(PerfectoTheory PUBLIC -ffp-contract=off)
endif()

option(PERFECTO_BUILD_TESTS "Build the C++ tests" ON)
if(PERFECTO_BUILD_TESTS)
    include(FetchContent)
    # doctest is one header; fetched at a pinned version and checked.
    FetchContent_Declare(doctest
        URL https://raw.githubusercontent.com/doctest/doctest/v2.4.11/doctest/doctest.h
        URL_HASH SHA256=44faa038e9c3f9728efbda143748d01124ea0a27f4bf78f35a15d8fab2e039fb
        DOWNLOAD_NO_EXTRACT TRUE)
    FetchContent_MakeAvailable(doctest)

    file(GLOB PERFECTO_THEORY_TESTS CONFIGURE_DEPENDS Tests/PerfectoTheoryTests/*.cpp)
    add_executable(PerfectoTheoryTests ${PERFECTO_THEORY_TESTS})
    target_include_directories(PerfectoTheoryTests PRIVATE ${doctest_SOURCE_DIR})
    target_link_libraries(PerfectoTheoryTests PRIVATE PerfectoTheory)
    if(MSVC)
        target_compile_options(PerfectoTheoryTests PRIVATE /utf-8)
    endif()

    enable_testing()
    add_test(NAME PerfectoTheoryTests COMMAND PerfectoTheoryTests)
endif()
