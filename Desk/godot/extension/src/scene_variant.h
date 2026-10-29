// The desk's scene (`perfecto/desk/scene.hpp`) as Godot values, for the
// shell's scripts to draw: every struct a Dictionary of its fields in
// snake_case, every enum its name as a String, a missing value null, and
// each item of a panel tagged with its `type`.

#ifndef SCENE_VARIANT_H
#define SCENE_VARIANT_H

#include <perfecto/desk/scene.hpp>

#include <godot_cpp/variant/dictionary.hpp>

#include <optional>

namespace perfecto_godot {

godot::Dictionary sceneVariant(const perfecto::desk::Scene &scene);

/// The action a Dictionary names ({"kind": "choose_layout", "index": 1}),
/// if it names one.
std::optional<perfecto::desk::Action> actionOf(const godot::Dictionary &dictionary);

} // namespace perfecto_godot

#endif
