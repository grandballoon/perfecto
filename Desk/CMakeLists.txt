# The desk's core in portable C++ (`Sources/PerfectoDeskCore`), on the
# theory core's (`../Perfecto`), and its tests: what a game engine's shell is
# built on (docs/desk-engine-and-audio.md). SwiftPM builds the Mac desk.
#
#   cmake -S . -B .build/cmake && cmake --build .build/cmake && ctest --test-dir .build/cmake
cmake_minimum_required(VERSION 3.21)
project(PerfectoDesk LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(PERFECTO_DESK_BUILD_TESTS "Build the desk core's C++ tests" ON)

set(PERFECTO_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory(../Perfecto perfecto)

file(GLOB PERFECTO_DESK_CORE_SOURCES CONFIGURE_DEPENDS Sources/PerfectoDeskCore/*.cpp)
add_library(PerfectoDeskCore STATIC ${PERFECTO_DESK_CORE_SOURCES})
target_include_directories(PerfectoDeskCore PUBLIC Sources/PerfectoDeskCore/include)
target_link_libraries(PerfectoDeskCore PUBLIC PerfectoTheory)
if(MSVC)
    target_compile_options(PerfectoDeskCore PRIVATE /W4 /utf-8)
else()
    target_compile_options(PerfectoDeskCore PRIVATE -Wall -Wextra -Wpedantic)
    # Each step rounded as Swift rounds it, never two fused into one, so the
    # C++ and the Swift agree to the last bit and every compiler (GCC fuses
    # by default) builds the same numbers.
    target_compile_options(PerfectoDeskCore PUBLIC -ffp-contract=off)
endif()

# The drum kit, made in code (Sources/PerfectoDrumKit): pure, on nothing.
file(GLOB PERFECTO_DRUM_KIT_SOURCES CONFIGURE_DEPENDS Sources/PerfectoDrumKit/*.cpp)
add_library(PerfectoDrumKit STATIC ${PERFECTO_DRUM_KIT_SOURCES})
target_include_directories(PerfectoDrumKit PUBLIC Sources/PerfectoDrumKit/include)
if(MSVC)
    target_compile_options(PerfectoDrumKit PRIVATE /W4 /utf-8)
else()
    target_compile_options(PerfectoDrumKit PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(PERFECTO_DESK_BUILD_TESTS)
    include(FetchContent)
    # doctest is one header; fetched at a pinned version and checked.
    FetchContent_Declare(doctest
        URL https://raw.githubusercontent.com/doctest/doctest/v2.4.11/doctest/doctest.h
        URL_HASH SHA256=44faa038e9c3f9728efbda143748d01124ea0a27f4bf78f35a15d8fab2e039fb
        DOWNLOAD_NO_EXTRACT TRUE)
    FetchContent_MakeAvailable(doctest)

    file(GLOB PERFECTO_DESK_CORE_TESTS CONFIGURE_DEPENDS Tests/PerfectoDeskCoreTests/*.cpp)
    add_executable(PerfectoDeskCoreTests ${PERFECTO_DESK_CORE_TESTS})
    target_include_directories(PerfectoDeskCoreTests PRIVATE ${doctest_SOURCE_DIR})
    target_link_libraries(PerfectoDeskCoreTests PRIVATE PerfectoDeskCore)
    if(MSVC)
        target_compile_options(PerfectoDeskCoreTests PRIVATE /utf-8)
    endif()

    file(GLOB PERFECTO_DRUM_KIT_TESTS CONFIGURE_DEPENDS Tests/PerfectoDrumKitTests/*.cpp)
    add_executable(PerfectoDrumKitTests ${PERFECTO_DRUM_KIT_TESTS})
    target_include_directories(PerfectoDrumKitTests PRIVATE ${doctest_SOURCE_DIR})
    target_link_libraries(PerfectoDrumKitTests PRIVATE PerfectoDrumKit)

    enable_testing()
    add_test(NAME PerfectoDeskCoreTests COMMAND PerfectoDeskCoreTests)
    add_test(NAME PerfectoDrumKitTests COMMAND PerfectoDrumKitTests)
endif()
