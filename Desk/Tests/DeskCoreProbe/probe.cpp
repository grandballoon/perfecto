#include "desk_core_probe.h"

#include "perfecto/desk/desk.hpp"

#include <algorithm>
#include <cstdio>
#include <cstring>

using namespace perfecto::desk;
using namespace perfecto::theory;

struct pdp_desk {
    Desk desk;
};

namespace {

// The text both desks are written as: `DeskParityText` in
// Tests/DeskCoreParityTests, which this must be kept in step with.

std::string number(double value) {
    char text[64];
    std::snprintf(text, sizeof text, "%.17g", value);
    return text;
}

std::string notes(const std::vector<int> &notes) {
    std::string out;
    for (size_t i = 0; i < notes.size(); ++i) out += (i ? "," : "") + std::to_string(notes[i]);
    return out;
}

std::string lineName(Line line) { return line == Line::chord ? "chord" : "melody"; }

std::string rumbleName(Rumble rumble) {
    switch (rumble) {
    case Rumble::tick: return "tick";
    case Rumble::bump: return "bump";
    case Rumble::refuse: return "refuse";
    }
    return {};
}

template <class T, size_t N> int indexIn(const std::array<T, N> &all, T value) {
    return static_cast<int>(std::find(all.begin(), all.end(), value) - all.begin());
}

std::string effect(const DeskEffect &effect) {
    const auto &value = effect.value();
    if (const auto *e = std::get_if<DeskEffect::Sound>(&value))
        return "sound " + lineName(e->line) + " " + notes(e->notes) + " " + e->sound + " " + number(e->level) + " " +
               number(e->brightness) + " " + (e->tie ? "1" : "0");
    if (const auto *e = std::get_if<DeskEffect::Shape>(&value))
        return "shape " + lineName(e->line) + " " + number(e->level) + " " + number(e->brightness) + " " +
               number(e->bend);
    if (const auto *e = std::get_if<DeskEffect::Silence>(&value)) return "silence " + lineName(e->line);
    if (const auto *e = std::get_if<DeskEffect::Rumble>(&value)) return "rumble " + rumbleName(e->rumble);
    if (const auto *e = std::get_if<DeskEffect::Preview>(&value)) return "preview " + e->sound + " " + notes(e->notes);
    if (const auto *e = std::get_if<DeskEffect::SaveMIDI>(&value)) {
        std::string out = "saveMIDI " + e->name + " ";
        char hex[3];
        for (std::uint8_t byte : e->bytes) {
            std::snprintf(hex, sizeof hex, "%02x", byte);
            out += hex;
        }
        return out;
    }
    return "refuse " + std::get<DeskEffect::Refuse>(value).reason;
}

std::string effects(const std::vector<DeskEffect> &all) {
    std::string out;
    for (size_t i = 0; i < all.size(); ++i) out += (i ? "\n" : "") + effect(all[i]);
    return out;
}

std::string target(const Target &t) {
    const int fit = t.fit == ChordFit::inKey ? 0 : t.fit == ChordFit::tense ? 1 : 2;
    const auto bit = [](bool on) { return on ? "1" : "0"; };
    return number(t.bearing) + " " + t.name + "|" + t.detail + "|" + std::to_string(fit) + " " + bit(t.isNear) +
           bit(t.isAimed) + bit(t.isKept) + bit(t.isHidden);
}

void targets(std::vector<std::string> &lines, const std::string &name, const std::vector<Target> &all) {
    for (const Target &t : all) lines.push_back(name + " " + target(t));
}

void targets(std::vector<std::string> &lines, const std::string &name,
             const std::vector<std::optional<Target>> &all) {
    for (const auto &t : all) lines.push_back(name + " " + (t ? target(*t) : "-"));
}

/// What the layout played draws: every target round its sticks.
std::vector<std::string> screenOf(const Desk &desk) {
    const DeskSettings &s = desk.settings;
    std::vector<std::string> lines;
    switch (desk.layout()) {
    case LayoutKind::twinRings: {
        const TwinRings &rings = desk.twinRings();
        const auto resets = rings.resetsTo(s);
        lines.push_back("resetsTo " + (resets ? resets->name() : "-"));
        const auto voices = rings.voiceTargets(s);
        targets(lines, "voice inner", voices.inner);
        targets(lines, "voice outer", voices.outer);
        targets(lines, "bass", rings.bassTargets(s));
        targets(lines, "degree", rings.degreeTargets(s));
        const auto ring = rings.ringTargets(s);
        for (size_t n = 0; n < ring.size(); ++n) targets(lines, "ring " + std::to_string(n), ring[n]);
        targets(lines, "favorite", rings.favoriteTargets(s));
        targets(lines, "compass", rings.compassTargets(s));
        break;
    }
    case LayoutKind::petals:
        targets(lines, "degree", desk.petals().degreeTargets(s));
        targets(lines, "petal", desk.petals().petalTargets(s));
        targets(lines, "depth", desk.petals().depthTargets(s));
        break;
    case LayoutKind::neighbourhood:
        targets(lines, "neighbour", desk.neighbourhood().neighbourTargets(s));
        lines.push_back("centre " + desk.neighbourhood().centreDetail(s));
        break;
    case LayoutKind::twoVoices:
        targets(lines, "degree", desk.twoVoices().degreeTargets(s));
        for (const auto &petal : desk.twoVoices().petals(s))
            lines.push_back("petal " + std::to_string(petal.note) + " " + (petal.isChordTone ? "1" : "0") + " " +
                            (petal.isReachable ? "1" : "0"));
        break;
    case LayoutKind::arranger: targets(lines, "degree", desk.arranger().degreeTargets(s)); break;
    }
    return lines;
}

std::string shown(const Desk &desk) {
    std::vector<std::string> lines = {"layout " + std::to_string(indexIn(allLayoutKinds, desk.layout()))};
    // A legend is a dictionary, so it is written in the order of its
    // controls' names.
    std::vector<std::string> legend;
    for (const auto &[control, text] : desk.legend()) legend.push_back("legend " + name(control) + "=" + text);
    std::sort(legend.begin(), legend.end());
    lines.insert(lines.end(), legend.begin(), legend.end());
    const auto pinnable = desk.pinnable();
    lines.push_back("pinnable " + (pinnable ? pinnable->name() : "-"));
    if (const auto &menu = desk.menu()) {
        lines.push_back("menu " + std::to_string(indexIn(DeskMenu::allRows, menu->row)));
        if (const auto &library = menu->library)
            lines.push_back("library " + lineName(library->line) + " " + std::to_string(library->category) + " " +
                            std::to_string(library->index));
    } else {
        lines.push_back("menu -");
    }
    for (DeskMenu::Row row : DeskMenu::allRows) lines.push_back("value " + name(row) + "=" + desk.value(row));
    const DeskSettings &s = desk.settings;
    const auto i = [](int value) { return " " + std::to_string(value); };
    lines.push_back("settings " + std::to_string(raw(s.key.root)) + i(indexIn(allScaleTypes, s.key.scale)) +
                    i(s.octave) + i(s.inversion.steps) + i(s.voiceLeading) + " " + s.chordSound + " " + s.lineSound +
                    " " + number(s.tempo) + i(indexIn(allDeskOutputs, s.output)) +
                    i(s.ranking == ColorStepRanking::theory ? 0 : 1) +
                    i(indexIn(allRingArrangements, s.ringArrangement)) + i(indexIn(allRingOrders, s.ringOrder)) +
                    i(indexIn(allRingFilters, s.ringFilter)) + i(indexIn(allBeatGrids, s.grid)) +
                    i(indexIn(allLBLayers, s.lbLayer)) + i(indexIn(allGuardModes, s.consonance.mode)) +
                    i(s.consonance.inKey));
    lines.push_back("summary " + s.summary() + " · " + s.voicingName());
    const auto screen = screenOf(desk);
    lines.insert(lines.end(), screen.begin(), screen.end());
    std::string out;
    for (size_t n = 0; n < lines.size(); ++n) out += (n ? "\n" : "") + lines[n];
    return out;
}

int write(const std::string &text, char *out, int capacity) {
    const size_t n = std::min(text.size(), static_cast<size_t>(capacity - 1));
    std::memcpy(out, text.data(), n);
    out[n] = '\0';
    return static_cast<int>(text.size());
}

} // namespace

pdp_desk *pdp_desk_new(void) {
    SoundCatalog catalog({
        {"Keys", {{"electricPiano", "Electric Piano"}, {"piano", "Piano"}}},
        {"Leads", {{"soloLead", "Solo Lead"}, {"squareLead", "Square Lead"}, {"saw", "Saw"}}},
        {"Pads", {{"warmPad", "Warm Pad"}}},
    });
    return new pdp_desk{Desk(std::move(catalog))};
}

void pdp_desk_free(pdp_desk *desk) { delete desk; }

int pdp_desk_step(pdp_desk *desk, const pdp_frame *f, char *out, int capacity) {
    std::set<PadButton> buttons;
    for (size_t b = 0; b < allPadButtons.size(); ++b)
        if (f->buttons & (1 << b)) buttons.insert(allPadButtons[b]);
    const GamepadFrame frame{.time = f->time,
                             .left = Stick{f->leftX, f->leftY},
                             .right = Stick{f->rightX, f->rightY},
                             .leftTrigger = f->leftTrigger,
                             .rightTrigger = f->rightTrigger,
                             .buttons = buttons};
    return write(effects(desk->desk.step(frame)), out, capacity);
}

int pdp_desk_choose(pdp_desk *desk, int layout, char *out, int capacity) {
    return write(effects(desk->desk.choose(allLayoutKinds[layout])), out, capacity);
}

int pdp_desk_toggle_menu(pdp_desk *desk, char *out, int capacity) {
    return write(effects(desk->desk.toggleMenu()), out, capacity);
}

int pdp_desk_let_go(pdp_desk *desk, char *out, int capacity) {
    return write(effects(desk->desk.letGo()), out, capacity);
}

int pdp_desk_shown(pdp_desk *desk, char *out, int capacity) { return write(shown(desk->desk), out, capacity); }
