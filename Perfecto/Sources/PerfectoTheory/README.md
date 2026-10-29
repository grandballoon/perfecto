# PerfectoTheory

The theory core (`Sources/MusicTheoryCore`) in portable C++20, for the desk on the engines and platforms Swift does not reach (`docs/desk-engine-and-audio.md`, sections 5 and 7).
It is a port, not a new design: the same types, functions and rules, file for file, and the Swift core is the reference for what is right.

## The rules it keeps

- Pure functions over values, as the Swift core is: nothing here does I/O, keeps state between calls or reads a clock.
- No exceptions.
  A broken contract (a grid row out of range, a compass rank that is not 1 or 2) stops the program, as a Swift `precondition` does (`require.hpp`).
- Swift's semantics, not C++'s habits, where they differ: `%` is made to wrap below zero where Swift's code did, a "first minimal" choice takes the first of equals as Swift's `min(by:)` does, and every enum's `all...` array is in the Swift type's `allCases` order.
- Enums are in the order of the Swift ones, so an index means the same in both.
- Numbers to the last bit: it is built with `-ffp-contract=off` (CMake and SwiftPM alike), so no compiler fuses a multiply and an add that Swift rounds apart.

## The layout

| C++ | Swift |
| --- | --- |
| `key` | `PitchClass`, `Degree`, `Scale`, `Key` |
| `modes` | `HeptatonicMode` |
| `tertian`, `tone_marks`, `chord_tones`, `chord_build`, `joystick` | the same names |
| `chord_color` | `ChordSpec` (`ChordColor` is a `std::variant` of its kinds) |
| `naming` | `ChordNaming` |
| `grid`, `color_ring`, `color_steps`, `key_degree`, `step_compass` | the same names |
| `voicing` | `Voicing`, `Inversion`, `ComputeVoicing` |
| `chord_wire`, `midi_file` | the same names |

## Its tests

Two sets, each of which has been seen to catch a bug planted in the port:

- **Its own**, `Tests/PerfectoTheoryTests`: every Swift test of the core ported one for one (doctest), so they run wherever the C++ is built, with no Swift.
  From `Perfecto/`:

  ```bash
  cmake -S . -B .build/cmake && cmake --build .build/cmake && ctest --test-dir .build/cmake
  ```

- **Parity with the Swift core**, `Tests/PerfectoTheoryParityTests`: the two cores compared over whole spaces of inputs (every color on every degree of every key, every chord of up to four notes, every compass step from each, ChordLink frames, MIDI key signatures), through a C probe that only the tests use (`Tests/PerfectoTheoryProbe`).
  `swift test` runs it on a sample of the larger spaces; an optimized build runs all of it, in about 8 seconds:

  ```bash
  swift test -c release --filter PerfectoTheoryParityTests
  ```

A change to the Swift core is a change to this one in the same commit, and the parity tests are what say the two still agree.
