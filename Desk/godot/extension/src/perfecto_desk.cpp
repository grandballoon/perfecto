#include "perfecto_desk.h"

#include "scene_variant.h"

#include <perfecto/desk/inputs.hpp>

#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <utility>

using namespace godot;
namespace desk = perfecto::desk;

namespace perfecto_godot {

namespace {

String text(const std::string &value) { return String::utf8(value.c_str()); }
std::string text(const String &value) { return value.utf8().get_data(); }

/// The controller's buttons by where they are, as Godot (SDL) names them.
const std::vector<std::pair<JoyButton, desk::PadButton>> &padButtons() {
    static const std::vector<std::pair<JoyButton, desk::PadButton>> map = {
        {JOY_BUTTON_A, desk::PadButton::a},
        {JOY_BUTTON_B, desk::PadButton::b},
        {JOY_BUTTON_X, desk::PadButton::x},
        {JOY_BUTTON_Y, desk::PadButton::y},
        {JOY_BUTTON_LEFT_SHOULDER, desk::PadButton::lb},
        {JOY_BUTTON_RIGHT_SHOULDER, desk::PadButton::rb},
        {JOY_BUTTON_BACK, desk::PadButton::back},
        {JOY_BUTTON_START, desk::PadButton::start},
        {JOY_BUTTON_LEFT_STICK, desk::PadButton::l3},
        {JOY_BUTTON_RIGHT_STICK, desk::PadButton::r3},
        {JOY_BUTTON_DPAD_UP, desk::PadButton::up},
        {JOY_BUTTON_DPAD_DOWN, desk::PadButton::down},
        {JOY_BUTTON_DPAD_LEFT, desk::PadButton::left},
        {JOY_BUTTON_DPAD_RIGHT, desk::PadButton::right},
    };
    return map;
}

/// The keys `KeyboardPad` reads, by the names it gives them.
std::vector<Key> keysNamed(const std::string &name) {
    if (name == " ") return {KEY_SPACE};
    if (name == "up") return {KEY_UP};
    if (name == "down") return {KEY_DOWN};
    if (name == "left") return {KEY_LEFT};
    if (name == "right") return {KEY_RIGHT};
    if (name == "return") return {KEY_ENTER, KEY_KP_ENTER};
    if (name == "tab") return {KEY_TAB};
    if (name.size() == 1 && name[0] >= 'a' && name[0] <= 'z') return {Key(KEY_A + (name[0] - 'a'))};
    return {};
}

} // namespace

PerfectoDesk::PerfectoDesk() = default;
PerfectoDesk::~PerfectoDesk() = default;

double PerfectoDesk::now() const { return double(Time::get_singleton()->get_ticks_usec()) / 1e6; }

void PerfectoDesk::setup(const Ref<PerfectoStream> &stream, const Array &presets) {
    std::vector<desk::SoundCatalog::Category> categories;
    std::map<std::string, int> numbers;
    for (int64_t i = 0; i < presets.size(); ++i) {
        const Dictionary preset = presets[i];
        const std::string id = text(String(preset.get("id", "")));
        const std::string category = text(String(preset.get("category", "")));
        numbers[id] = int(i);
        // The recorded sound is the phone's mic sample, which the desk has no way to make.
        if (category == "Recorded") continue;
        if (categories.empty() || categories.back().name != category) categories.push_back({category, {}});
        categories.back().sounds.push_back({id, text(String(preset.get("name", "")))});
    }
    stream_ = stream;
    voices_ = std::make_unique<DeskVoices>(stream, numbers);
    drums_ = std::make_unique<DrumVoices>(stream, int(presets.size()));
    timelineVoices_ = std::make_unique<TimelineVoices>(stream, numbers);
    midi_ = std::make_unique<DeskMidi>();
    studio_.emplace(desk::Desk(desk::SoundCatalog(categories), desk::DeskSettings(), desk::LayoutKind::faceChords));
    voices_->setTempo(studio_->desk().settings.tempo);
    shown_.reset();
}

void PerfectoDesk::set_face_map(const Dictionary &plain, const Dictionary &layered) {
    if (!studio_) return;
    namespace theory = perfecto::theory;
    // Godot's joypad buttons A, B, X and Y are 0 to 3.
    static constexpr std::array<desk::PadButton, 4> faces = {desk::PadButton::a, desk::PadButton::b,
                                                             desk::PadButton::x, desk::PadButton::y};
    const auto layer = [](const Dictionary &given) {
        std::map<desk::PadButton, theory::Degree> degrees;
        const Array buttons = given.keys();
        for (int64_t i = 0; i < buttons.size(); ++i) {
            const int64_t button = buttons[i], degree = given[buttons[i]];
            if (button < 0 || button >= int64_t(faces.size())) continue;
            if (degree < 0 || degree >= int64_t(theory::allDegrees.size())) continue;
            degrees[faces[size_t(button)]] = theory::allDegrees[size_t(degree)];
        }
        return degrees;
    };
    studio_->setFaceMap({layer(plain), layer(layered)});
}

desk::GamepadFrame PerfectoDesk::frame(double time, bool keyboard) {
    Input *input = Input::get_singleton();
    desk::GamepadFrame frame{time};
    if (keyboard && !input->is_key_pressed(KEY_META)) {
        std::set<std::string> held;
        for (const auto &name : desk::KeyboardPad::keys())
            for (const Key key : keysNamed(name))
                if (input->is_key_pressed(key)) held.insert(name);
        frame = desk::KeyboardPad::frame(held, input->is_key_pressed(KEY_SHIFT), time);
    }
    const auto pads = input->get_connected_joypads();
    device_ = pads.is_empty() ? std::nullopt : std::optional<int>(int(pads[0]));
    if (!device_) return frame;
    const int device = *device_;
    // Godot's sticks are down positive; the desk's are up positive.
    const auto stick = [&](JoyAxis x, JoyAxis y) {
        return desk::Xbox360::stick(input->get_joy_axis(device, x), -input->get_joy_axis(device, y));
    };
    desk::GamepadFrame pad{time, stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y), stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y),
                           std::clamp(double(input->get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)), 0.0, 1.0),
                           std::clamp(double(input->get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)), 0.0, 1.0),
                           {}};
    for (const auto &[joy, button] : padButtons())
        if (input->is_joy_button_pressed(device, joy)) pad.buttons.insert(button);
    return pad.merged(frame);
}

Array PerfectoDesk::step(bool keyboard) {
    if (!studio_) return {};
    const double time = now();
    followRenders();
    voices_->tick(time);
    if (knock_ && time >= *knock_) {
        knock_.reset();
        if (device_) Input::get_singleton()->start_joy_vibration(*device_, 0, 0.6f, 0.05f);
    }
    const auto before = studio_->desk().settings;
    const Array out = play(studio_->step(frame(time, keyboard)), time);
    settingsChanged(before);
    return out;
}

Array PerfectoDesk::perform(const Dictionary &dictionary) {
    const auto action = actionOf(dictionary);
    if (!studio_ || !action) return {};
    const auto before = studio_->desk().settings;
    const Array out = play(studio_->perform(*action), now());
    settingsChanged(before);
    return out;
}

Array PerfectoDesk::play(const desk::Studio::Played &played, double time) {
    Array out;
    const auto output = studio_->desk().settings.output;
    for (const auto &effect : played.playback) {
        std::visit(
            [&](const auto &e) {
                using T = std::decay_t<decltype(e)>;
                if constexpr (std::is_same_v<T, desk::TimelineEffect::Sound>) {
                    if (desk::sounds(output)) timelineVoices_->sound(e.track, e.notes, e.sound, e.level, e.time - time);
                } else if constexpr (std::is_same_v<T, desk::TimelineEffect::Silence>) {
                    timelineVoices_->silence(e.track, e.time - time);
                } else {
                    timelineVoices_->silenceAll();
                }
            },
            effect.value());
    }
    for (const auto &effect : played.drums) drum(effect, time);
    for (const auto &effect : played.effects) {
        std::visit(
            [&](const auto &e) {
                using T = std::decay_t<decltype(e)>;
                if constexpr (std::is_same_v<T, desk::DeskEffect::Sound>) {
                    if (desk::sounds(output)) voices_->sound(e.line, e.notes, e.sound, e.level, e.brightness, e.tie);
                    if (desk::sendsMIDI(output)) midi_->sound(e.line, e.notes, e.level, e.brightness, e.tie);
                    sounding_[e.line] = e.notes;
                } else if constexpr (std::is_same_v<T, desk::DeskEffect::Shape>) {
                    if (desk::sounds(output)) voices_->shape(e.line, e.level, e.brightness, e.bend);
                    if (desk::sendsMIDI(output)) midi_->shape(e.line, e.level, e.brightness, e.bend);
                } else if constexpr (std::is_same_v<T, desk::DeskEffect::Silence>) {
                    voices_->silence(e.line);
                    midi_->silence(e.line);
                    sounding_[e.line].clear();
                } else if constexpr (std::is_same_v<T, desk::DeskEffect::Rumble>) {
                    rumble(e.rumble, time);
                    Dictionary d;
                    d["kind"] = "rumble";
                    d["rumble"] = e.rumble == desk::Rumble::tick ? "tick" : e.rumble == desk::Rumble::bump ? "bump" : "no";
                    out.push_back(d);
                } else if constexpr (std::is_same_v<T, desk::DeskEffect::Preview>) {
                    voices_->preview(e.sound, e.notes, time);
                } else if constexpr (std::is_same_v<T, desk::DeskEffect::SaveMIDI>) {
                    PackedByteArray bytes;
                    bytes.resize(int64_t(e.bytes.size()));
                    std::copy(e.bytes.begin(), e.bytes.end(), bytes.ptrw());
                    Dictionary d;
                    d["kind"] = "save_midi";
                    d["bytes"] = bytes;
                    d["name"] = text(e.name);
                    out.push_back(d);
                } else {
                    rumble(desk::Rumble::refuse, time);
                    Dictionary d;
                    d["kind"] = "refuse";
                    d["reason"] = text(e.reason);
                    out.push_back(d);
                }
            },
            effect.value());
    }
    return out;
}

/// A drum's hit or choke, on the kernel and MIDI as the output says, placed
/// as far ahead of `time` as the core gave it.
void PerfectoDesk::drum(const desk::DrumEffect &effect, double time) {
    const auto output = studio_->desk().settings.output;
    std::visit(
        [&](const auto &e) {
            using T = std::decay_t<decltype(e)>;
            const double ahead = e.time - time;
            if constexpr (std::is_same_v<T, desk::DrumEffect::Hit>) {
                if (desk::sounds(output)) drums_->hit(e.drum, e.level, ahead);
                if (desk::sendsMIDI(output)) midi_->hit(desk::generalMidi(e.drum), e.level, ahead);
            } else {
                drums_->choke(e.drum, ahead);
            }
        },
        effect.value());
}

/// What follows from a setting changed: a sink switched off falls silent,
/// and the delay follows the tempo.
void PerfectoDesk::settingsChanged(const desk::DeskSettings &before) {
    const auto &after = studio_->desk().settings;
    if (desk::sounds(before.output) && !desk::sounds(after.output)) {
        voices_->silenceAll();
        timelineVoices_->silenceAll();
    }
    if (desk::sendsMIDI(before.output) && !desk::sendsMIDI(after.output)) midi_->silenceAll();
    if (before.tempo != after.tempo) voices_->setTempo(after.tempo);
}

/// The controller's motors say what the ear might miss: a tick is short and
/// light, a bump heavy, and a refusal two quick dull knocks: no.
void PerfectoDesk::rumble(desk::Rumble kind, double time) {
    if (!device_) return;
    Input *input = Input::get_singleton();
    switch (kind) {
    case desk::Rumble::tick: input->start_joy_vibration(*device_, 0.45f, 0, 0.03f); break;
    case desk::Rumble::bump: input->start_joy_vibration(*device_, 0.3f, 0.9f, 0.06f); break;
    case desk::Rumble::refuse:
        input->start_joy_vibration(*device_, 0, 0.6f, 0.05f);
        knock_ = time + 0.08;
        break;
    }
}

/// Notes are struck a lead ahead, one render and a millisecond, so every
/// strike is equally late: the lead follows the longest render seen.
void PerfectoDesk::followRenders() {
    const Dictionary stats = stream_->take_mix_stats();
    const int block = int(stats.get("block_max", 0));
    if (block <= blockMax_) return;
    blockMax_ = block;
    stream_->set_lead_frames(blockMax_ + int(stream_->sample_rate() / 1000));
}

Dictionary PerfectoDesk::scene() {
    if (!studio_) return {};
    shown_ = desk::scene(*studio_, !device_.has_value());
    return sceneVariant(*shown_);
}

bool PerfectoDesk::scene_changed() const {
    return studio_ && (!shown_ || desk::scene(*studio_, !device_.has_value()) != *shown_);
}

Dictionary PerfectoDesk::sounding() const {
    Dictionary d;
    for (const auto line : desk::allLines) {
        PackedInt32Array notes;
        const auto found = sounding_.find(line);
        if (found != sounding_.end())
            for (const int note : found->second) notes.push_back(note);
        d[line == desk::Line::chord ? "chord" : "melody"] = notes;
    }
    return d;
}

String PerfectoDesk::input_name() const {
    return device_ ? Input::get_singleton()->get_joy_name(*device_) : String("Keyboard");
}

void PerfectoDesk::let_go() {
    if (!studio_) return;
    play(studio_->letGo(), now());
    voices_->silenceAll();
    timelineVoices_->silenceAll();
    midi_->silenceAll();
}

void PerfectoDesk::_bind_methods() {
    ClassDB::bind_method(D_METHOD("setup", "stream", "presets"), &PerfectoDesk::setup);
    ClassDB::bind_method(D_METHOD("step", "keyboard"), &PerfectoDesk::step);
    ClassDB::bind_method(D_METHOD("perform", "action"), &PerfectoDesk::perform);
    ClassDB::bind_method(D_METHOD("scene"), &PerfectoDesk::scene);
    ClassDB::bind_method(D_METHOD("scene_changed"), &PerfectoDesk::scene_changed);
    ClassDB::bind_method(D_METHOD("sounding"), &PerfectoDesk::sounding);
    ClassDB::bind_method(D_METHOD("input_name"), &PerfectoDesk::input_name);
    ClassDB::bind_method(D_METHOD("has_controller"), &PerfectoDesk::has_controller);
    ClassDB::bind_method(D_METHOD("midi_ready"), &PerfectoDesk::midi_ready);
    ClassDB::bind_method(D_METHOD("let_go"), &PerfectoDesk::let_go);
    ClassDB::bind_method(D_METHOD("set_face_map", "plain", "layered"), &PerfectoDesk::set_face_map);
}

} // namespace perfecto_godot
