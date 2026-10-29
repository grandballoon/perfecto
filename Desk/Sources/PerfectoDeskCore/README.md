# PerfectoDeskCore

The desk's core (`Sources/DeskCore`) in portable C++20, on the C++ theory core (`Perfecto/Sources/PerfectoTheory`), for the desk on game engines and consoles (`docs/desk-engine-and-audio.md`).
Like the theory core it is a port, not a new design: the same layouts, rules, legends and effects, file for file, and the Swift core is the reference for what is right.
A change to one is a change to the other in the same commit.

## The conventions it keeps

These are the theory core's (its README), and these besides:

- **One header and one source a Swift file**, `snake_case` (`twin_rings.hpp`, `twin_rings.cpp`), in namespace `perfecto::desk`, headers under `include/perfecto/desk/`.
- **Values, as in Swift.**
  A Swift struct is a C++ struct or class with value semantics and `operator==` (defaulted where Swift's is synthesized).
  A Swift `mutating func` is a non-const member; an `inout` parameter is a reference; what a layout returns is `std::vector<DeskEffect>`.
  `public private(set) var` is a private member with a const getter of the same name; a `private var` is a private member.
- **Swift enums.**
  A plain one is an `enum class` with an `all...` array in `allCases` order and free functions for its computed properties (`name(LayoutKind)`).
  One with associated values is a `std::variant` of structs, one struct a case (`DeskEffect`), with a defaulted `operator==` on each.
- **Swift collections.**
  `Set` is `std::set` and `Dictionary` is `std::map`, so their order is defined in C++ where it was not in Swift.
  Where Swift's output depends on iterating a `Set` or `Dictionary` (an order Swift does not define), say so in a comment and make the C++ order what any Swift run could give, sorted.
  `[PadControl: String]` (`Legend`) is a `std::map<PadControl, std::string>`, so `PadControl` has an ordering.
- **Swift arithmetic.**
  `Double` is `double`, `Int` is `int`.
  `x.rounded()` is `std::round` (half away from zero), `.rounded(.down)` is `std::floor`, `Int(x)` truncates toward zero (`static_cast<int>`), and `%` keeps the sign of its left side in both languages, so the Swift code's own wrapping (`((a % n) + n) % n`) is kept as it is.
- **Members.**
  A Swift `public let` or `public var` is a public data member; only `private(set)` hides one behind a getter.
  A Swift `static let` value is a `static constexpr` where it can be, and otherwise a function returning a `const &` to a function-local static (`RadialBands::three()`, `DegreePie::gate()`), so nothing depends on the order statics are made in.
  An `extension` of another file's type is a member declared with the type and defined in the extending file's source (`DeskSettings::ring` in `ring_pie.cpp`).
  The settings' types that live in later files (`BeatGrid`, `RingArrangement`, `RingOrder`, `RingFilter`) are declared opaque in `music.hpp` and given their values by `DeskSettings()`.
- **Swift labels.**
  Where two Swift functions differ only by an argument label, the label goes into the C++ name: `refusalOfNote`, `allowsNote`, `Favorites::pinOf`, `Arrangement::chordAt` and `chordNear`, `DeskChord::onRoot` (as `KeyDegree::onRoot` in the theory core).
  `PadEdges` keeps `pressed` and `released` as sets, so its queries are `pressed.contains(button)`.
- **Temporaries.**
  A member that returns a reference into its object returns a copy when the object is a temporary (`ChordTones::pitchClasses() &&`), so `for (int t : chord.tones().pitchClasses())` is safe; a new one does the same.
- **Numbers to the last bit.**
  Both cores are built with `-ffp-contract=off` (CMake and SwiftPM alike), so no compiler fuses a multiply and an add that Swift rounds apart; with it on, clang's levels and brightnesses differed from Swift's in their last bit, and GCC fuses by default.
- **The protocol `Layout`** has no C++ base class: `Desk` chooses the layout by its kind, as the Swift does, and every layout has the same three members (`step`, `releaseAll`, `legend`).
- **Persistence is the shell's.**
  The Swift settings are `Codable`; here they are plain values, and an engine keeps them as it keeps anything else.
- **Text is UTF-8**, every legend and name as the Swift has it, byte for byte.

## What is not a port

Two parts have no Swift original, and the parity test does not play them: what the screen shows (`scene.hpp`), and the drums (`drums.hpp`, a beat and pads in Face Chords).
The drums are played beside the desk, not inside it: `Band` (`band.hpp`) gives each frame to the drums first, which take the buttons they play, and steps the desk with what is left, so `Desk` is as the Swift has it.
Their recordings are made in code by `Sources/PerfectoDrumKit`, which has tests of its own (`Tests/PerfectoDrumKitTests`), built and run with these.

## Its tests

Two sets, each of which has been seen to catch a bug planted in the port:

- **Its own**, `Tests/PerfectoDeskCoreTests`: every test of `Tests/DeskCoreTests` ported one for one (doctest), but for the three that test the settings' `Codable`.
  From `Desk/`:

  ```bash
  cmake -S . -B .build/cmake && cmake --build .build/cmake && ctest --test-dir .build/cmake
  ```

- **Parity with the Swift core**, `Tests/DeskCoreParityTests`: a Swift desk and a C++ one are played with the same long runs of controller frames from a seeded chance (buttons, sticks that drift and flick, triggers, held presses, layouts chosen, the menu), through a C probe that only the tests use (`Tests/DeskCoreProbe`).
  After every frame what each did must read the same, and every few frames what each shows: the layout, the legend, the menu and its values, the settings and every target the layout draws.
  `swift test` plays 12 runs of 1,500 frames; an optimized build plays 60 runs of 6,000, in about 40 seconds:

  ```bash
  swift test -c release --filter DeskCoreParityTests
  ```
