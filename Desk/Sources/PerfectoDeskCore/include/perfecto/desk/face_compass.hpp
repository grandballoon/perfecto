// The phone's step compass on Face Chords' left stick: up adds a tone, right
// raises one, down takes one away and left lowers one. Each direction is a
// kind's first choice, and with LT held its second, the compass's outer place.
//
// Key assist is the phone's three settings. Normal and Color code play every
// place. Assist plays only chords in the key: a place whose chord is outside
// it falls back to the nearest choice of the same kind that is in the key,
// and to the plain chord if the kind has none.

#ifndef PERFECTO_DESK_FACE_COMPASS_HPP
#define PERFECTO_DESK_FACE_COMPASS_HPP

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/music.hpp"

#include <perfecto/theory/step_compass.hpp>

#include <optional>
#include <string>

namespace perfecto::desk::FaceCompass {

/// The stick's four directions, clockwise from up.
const PieGate &gate();

/// The place at `direction` (clockwise from up), its outer one if `isOuter`.
theory::CompassPlace place(int direction, bool isOuter);

/// What a place does, before a chord is held: "Add", "Lower 2nd".
std::string name(const theory::CompassPlace &place);

/// The step `place` plays on `degree`'s triad under `assist`, or none if it
/// plays the plain chord.
std::optional<theory::ColorStep> step(const theory::CompassPlace &place, const theory::Key &key, theory::Degree degree,
                                      theory::ColorStepRanking ranking, KeyAssist assist);

/// The color `place` plays on `degree`: plain if it has no step.
theory::ChordColor color(const theory::CompassPlace &place, const theory::Key &key, theory::Degree degree,
                         theory::ColorStepRanking ranking, KeyAssist assist);

/// How a chord of `fit` is shown under `assist`: Normal tells nothing apart,
/// and the others tell only what is in the key from what is not.
ChordFit shownFit(ChordFit fit, KeyAssist assist);

} // namespace perfecto::desk::FaceCompass

#endif
