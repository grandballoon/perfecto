#include "perfecto/desk/scene.hpp"

#include "perfecto/desk/inputs.hpp"
#include "perfecto/desk/ring_pie.hpp"

#include <perfecto/theory/modes.hpp>
#include <perfecto/theory/tertian.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace perfecto::desk {

std::optional<Tint> tint(PadButton button) {
    switch (button) {
    case PadButton::a: return Tint::a;
    case PadButton::b: return Tint::b;
    case PadButton::x: return Tint::x;
    case PadButton::y: return Tint::y;
    default: return std::nullopt;
    }
}

namespace {

/// `value` with at least `least` and at most `most` places after the point.
std::string decimal(double value, int least, int most) {
    char text[32];
    std::snprintf(text, sizeof text, "%.*f", most, value);
    std::string out = text;
    const auto point = out.find('.');
    if (point == std::string::npos) return out;
    while (static_cast<int>(out.size() - point - 1) > least && out.back() == '0') out.pop_back();
    if (out.back() == '.') out.pop_back();
    return out;
}

std::string signedInt(int value) { return (value >= 0 ? "+" : "") + std::to_string(value); }

/// "C4": a note's name and octave.
std::string noteName(int note) {
    return theory::name(static_cast<theory::PitchClass>(note % 12)) + std::to_string(note / 12 - 1);
}

std::vector<std::optional<Target>> optionals(const std::vector<Target> &targets) {
    return {targets.begin(), targets.end()};
}

Sounding sounding(const ChordLine &line, const std::string &title) {
    const std::string text = !line.isSounding() ? title : line.chord() ? line.chord()->name() : "";
    return {line.isSounding(), text, line.arpeggio() ? "arp " + name(*line.arpeggio()) : ""};
}

std::vector<double> threeSteps() { return TriggerSteps::three().edges; }

Ring ringOf(const std::vector<std::vector<Target>> &bands, const RingPie &pie, const Stick &stick,
            const std::string &title, const std::string &detail) {
    Ring ring{bands, {}, RingPie::sectorSpan, pie.gap(), "", stick, title, detail};
    for (const auto &sector : pie.sectors) ring.sectors.push_back({displayName(sector.mode), sector.bearing, sector.isOwn});
    if (!pie.sectors.empty())
        ring.gapModes = displayName(pie.sectors.back().mode) + " | " + displayName(pie.sectors.front().mode);
    return ring;
}

// The layouts' stages, as the Mac desk's views drew them.

std::vector<Panel> twinRings(const TwinRings &layout, const DeskSettings &settings, const GamepadFrame &frame) {
    Panel left{{
        Caption{"Left stick", "Degree, I at the top and on clockwise"},
        Pie{optionals(layout.degreeTargets(settings)), std::nullopt, frame.left, numeral(layout.degree(), settings.key),
            theory::name(settings.key.root) + " " + displayName(settings.key.scale)},
        Triggers{{{"LT", frame.leftTrigger, threeSteps(), Tint::melody}}},
        Note{"Arpeggio: " + (layout.arpeggioStep() > 0 ? name(static_cast<ArpeggioRate>(layout.arpeggioStep())) : "off")},
    }};
    Panel right;
    const auto chord = layout.chord(settings);
    const auto resets = layout.resetsTo(settings);
    if (layout.isOnFavorites()) {
        right.items.push_back(Caption{"Y + right stick", "Favorites in " + settings.favorites.table().name + ": A pins, X unpins"});
        right.items.push_back(Pie{layout.favoriteTargets(settings), std::nullopt, frame.right, chord.name(), "flick keeps"});
    } else if (layout.isOnVoices()) {
        right.items.push_back(Caption{layout.compassLatched() ? "Both sticks" : "LB + both sticks",
                                      "The voices: each a semitone or two, to the consonant chords nearest", "L3: compass"});
        const auto shells = layout.voiceTargets(settings);
        right.items.push_back(Voices{layout.bassTargets(settings), frame.left,
                                     Pie{shells.inner, shells.outer, frame.right, chord.name(),
                                         resets ? "R3: back to " + resets->name() : "flick takes a step"}});
    } else if (layout.isOnCompass()) {
        right.items.push_back(Caption{layout.compassLatched() ? "Right stick" : "LB + right stick",
                                      "The step compass: a tone added, raised, taken away, lowered",
                                      layout.compassLatched() ? "ON · long-press LB to turn off" : "", Tint::chord});
        right.items.push_back(Pie{optionals(layout.compassTargets(settings)), std::nullopt, frame.right, chord.name(),
                                  resets ? "R3: back to " + resets->name() : "flick keeps"});
    } else {
        right.items.push_back(Caption{"Right stick",
                                      layout.isExtended() ? "The ring to the 13th" : "The color ring: mode round, height out"});
        std::vector<std::string> arrangements;
        for (const auto arrangement : allRingArrangements) arrangements.push_back(name(arrangement));
        right.items.push_back(Choices{"L3", arrangements, static_cast<int>(settings.ringArrangement), "",
                                      Action::Kind::arrangeRing});
        right.items.push_back(ringOf(layout.ringTargets(settings), settings.ring(layout.degree()), frame.right, chord.name(),
                                     !layout.kept() && !layout.keptStep() ? "plain" : "kept"));
        right.items.push_back(Facts{{{"Order", name(settings.ringOrder)}, {"Filter", name(settings.ringFilter)}},
                                    "Menu changes them"});
        right.items.push_back(Note{summary(settings.ringArrangement)});
    }
    right.items.push_back(Triggers{{{"RT", frame.rightTrigger, {}, Tint::chord}}});
    right.items.push_back(sounding(layout.line(), "Strike with RT or A"));
    return {left, right};
}

/// The drums under Face Chords: the beat's bar, its step lit as it sounds,
/// and the patterns and kits to choose from.
std::vector<Item> drumItems(const Drums &drums, const DeskSettings &settings, double time) {
    const auto &machine = drums.machine();
    const auto &pattern = machine.played();
    const auto heard = machine.step(time);
    Chips bar{{}, DrumPattern::steps};
    for (int step = 0; step < DrumPattern::steps; ++step)
        bar.chips.push_back({step % 4 == 0 ? std::to_string(step / 4 + 1) : "·", heard == step, !pattern.isStruck(step)});
    Choices patterns{"RB ◀", {}, machine.pattern(), "▶", Action::Kind::choosePattern};
    for (const auto &each : drumPatterns()) patterns.names.push_back(each.name);
    const Choices kits{"RB Back", drums.kits(), drums.kit(), "Start", Action::Kind::chooseKit};
    const std::string tempo = std::to_string(static_cast<int>(settings.tempo)) + " bpm";
    return {
        Caption{"L3 · RB", "Drums", machine.isPlaying() ? "▶ " + tempo : "L3 starts the beat",
                machine.isPlaying() ? Tint::chord : Tint::faint},
        bar,
        patterns,
        kits,
    };
}

/// The face buttons as the drum layer plays them: a drum on each.
Faces drumPads(const Drums &drums, const GamepadFrame &frame) {
    const bool shifted = drums.isShifted();
    Faces faces;
    for (const PadButton button : FaceChords::faces) {
        faces.faces.push_back({button, FaceChords::bearing(button), name(*Drums::pad(button, shifted)), "",
                               (shifted ? "−LT " : "+LT ") + name(*Drums::pad(button, !shifted)), frame.isDown(button),
                               false});
    }
    faces.detail = "Drum pads";
    return faces;
}

/// The left stick beside Face Chords: what each direction colors the chord
/// held with, or with LB, the chord's pins.
Panel faceColors(const FaceColors &colors, const FaceChords &layout, const DeskSettings &settings,
                 const GamepadFrame &frame) {
    const auto heard = layout.heard() ? layout.heard() : layout.voices()[1].heard();
    const std::optional<theory::Degree> degree = heard ? std::optional(heard->second) : std::nullopt;
    const auto &line = layout.heard() ? layout.line() : layout.voices()[1].line;
    const std::string title = heard && line.chord() ? line.chord()->name() : "";
    if (colors.isOnPins()) {
        const std::string whose = degree ? numeral(*degree, settings.key) : "the chord held";
        return Panel{{
            Caption{"LB + left stick", "The pins of " + whose, "in " + settings.favorites.table().name, Tint::chord},
            Pie{colors.targets(degree, settings), std::nullopt, frame.left, title.empty() ? "Pins" : title,
                degree ? "a place with none: plain" : "hold a face button"},
            Note{"LB pressed while coloring pins the color, or takes it out"},
        }};
    }
    const bool orchid = settings.faceStick == FaceStick::orchid;
    return Panel{{
        Caption{"Left stick", orchid ? "The Orchid's chord buttons" : "Perfecto's joystick table",
                name(settings.faceStick), Tint::faint},
        Pie{colors.targets(degree, settings), std::nullopt, frame.left, title.empty() ? "Color" : title,
            orchid ? "roll on to add a second" : "lean to color"},
        Note{"LB while coloring: pin · hold LB: the pins · Menu: Face Chords stick"},
    }};
}

std::vector<Panel> faceChords(const FaceChords &layout, const DeskSettings &settings, const GamepadFrame &frame,
                              const Drums *drums, const FaceColors *colors, double time) {
    const auto &map = layout.map();
    const bool layered = layout.isLayered();
    const auto heard = layout.heard();
    const auto over = layout.voices()[1].heard();
    Faces faces;
    for (const PadButton button : FaceChords::faces) {
        Faces::Face face{button, FaceChords::bearing(button), "", "", "", frame.isDown(button),
                         heard && heard->first == button, over && over->first == button};
        if (const auto degree = map.degree(button, layered)) {
            face.numeral = numeral(*degree, settings.key);
            face.name = DeskChord(settings.key, *degree).name();
        }
        const auto other = map.degree(button, !layered);
        if (other && other != map.degree(button, layered))
            face.other = (layered ? "−LT " : "+LT ") + numeral(*other, settings.key);
        faces.faces.push_back(face);
    }
    if (heard) {
        faces.numeral = numeral(heard->second, settings.key);
        faces.name = layout.line().chord() ? layout.line().chord()->name() : "";
        faces.detail = settings.summary() + " · " + settings.voicingName();
    } else {
        faces.detail = "Hold a face button";
    }
    if (over) {
        const auto &line = layout.voices()[1].line;
        faces.over = numeral(over->second, settings.key) + " · " + (line.chord() ? line.chord()->name() : "");
    }
    const auto legend = layout.legend(settings);
    Caption voices{"R3 · LB", "One voice", "R3 adds a second", Tint::faint};
    if (layout.isTogether()) {
        voices.title = "Both voices";
        voices.aside = "LB, or a face with LT: voice 2 over";
        voices.asideTint = Tint::melody;
    } else if (layout.hasSecond()) {
        voices.title = "Second voice";
        voices.aside = "Hold LB for it · double-click LB for both";
        voices.asideTint = Tint::melody;
    }
    Panel panel{{
        Caption{"Face buttons", layered ? "LT held" : "Chords by number", legend.at(PadControl::leftTrigger()),
                layered ? Tint::borrowed : Tint::faint},
        faces,
        Triggers{{{"LT", frame.leftTrigger, {0.5}, Tint::borrowed}}},
        voices,
    }};
    if (drums) {
        if (drums->isLayered()) {
            panel.items[0] = Caption{"RB held", "Drum pads", drums->isShifted() ? "LT held: toms, clap" : "LT: toms, clap",
                                     drums->isShifted() ? Tint::borrowed : Tint::faint};
            panel.items[1] = drumPads(*drums, frame);
        }
        for (auto &item : drumItems(*drums, settings, time)) panel.items.push_back(std::move(item));
    }
    if (colors) return {faceColors(*colors, layout, settings, frame), panel};
    return {panel};
}

std::vector<Panel> petals(const Petals &layout, const DeskSettings &settings, const GamepadFrame &frame) {
    const auto bend = layout.bend();
    const bool bent = bend.octaves != 0 || bend.roll != 0;
    Panel left{{
        Caption{"Left stick", "Degree"},
        Pie{optionals(layout.degreeTargets(settings)), std::nullopt, frame.left, numeral(layout.degree(), settings.key),
            settings.summary()},
        Caption{"Right stick", "Voicing bend",
                bent ? "octave " + signedInt(bend.octaves) + " · inversion " + signedInt(bend.roll)
                     : "as set · R3 keeps a bend",
                bent ? Tint::chord : Tint::secondary},
    }};
    Diamond diamond;
    const auto targets = layout.petalTargets(settings);
    for (size_t i = 0; i < Petals::diamond.size() && i < targets.size(); ++i)
        diamond.petals.push_back({Petals::diamond[i], frame.isDown(Petals::diamond[i]), targets[i]});
    Panel right{{
        Caption{layout.isMarking() ? "LB + face buttons" : "Face buttons",
                layout.isMarking() ? "Marks on the triad" : "Strike at four heights"},
        diamond,
        Caption{"LT ◀  ▶ RT", "Darker and brighter, a mode at a time"},
        Scale{layout.depthTargets(settings)},
        Triggers{{{"LT", frame.leftTrigger, threeSteps(), Tint::borrowed}, {"RT", frame.rightTrigger, threeSteps(), Tint::chord}}},
        sounding(layout.line(), "Hold a face button"),
    }};
    return {left, right};
}

std::vector<Panel> neighbourhood(const Neighbourhood &layout, const DeskSettings &settings, const GamepadFrame &frame) {
    std::vector<std::string> lenses;
    for (const auto lens : Neighbourhood::allLenses) lenses.push_back(name(lens));
    Panel left{{
        Choices{"LB", lenses, static_cast<int>(layout.lens()), "RB", std::nullopt},
        Pie{layout.neighbourTargets(settings), std::nullopt, frame.right, layout.centre().name(), layout.centreDetail(settings)},
        Note{layout.isOnPalette() ? "Y held: the bookmarks. Flick to jump, hold to listen."
                                  : "Flick the right stick to move there; hold it to listen and come back."},
    }};
    Chips path;
    const auto &chords = layout.path();
    // The last twelve, so a long path keeps its end in view.
    const size_t first = chords.size() > 12 ? chords.size() - 12 : 0;
    for (size_t i = first; i < chords.size(); ++i)
        path.chips.push_back({chords[i].name(), static_cast<int>(i) == layout.pathIndex()});
    Chips bookmarks{{}, 4};
    for (size_t i = 0; i < layout.palette().size(); ++i) {
        const auto &chord = layout.palette()[i];
        bookmarks.chips.push_back({chord ? chord->name() : std::to_string(i + 1), false, !chord});
    }
    Panel right{{
                    Caption{"Left stick ← →", "The path"},
                    path,
                    Caption{"L3 · Y", "Bookmarks"},
                    bookmarks,
                    Triggers{{{"RT", frame.rightTrigger, {}, Tint::chord}}},
                    Triggers{{{"LT", frame.leftTrigger, {}, Tint::melody}}},
                    sounding(layout.line(), "A strikes the centre"),
                },
                340};
    return {left, right};
}

std::vector<Panel> twoVoices(const TwoVoices &layout, const DeskSettings &settings, const GamepadFrame &frame) {
    Panel left{{
        Caption{"Left stick · LT", "Chords, swelled"},
        Pie{optionals(layout.degreeTargets(settings)), std::nullopt, frame.left, layout.chord(settings).name(),
            displayName(layout.height())},
        Triggers{{{"LT", frame.leftTrigger, {}, Tint::chord}}},
        sounding(layout.chords(), layout.drones() ? "Drone on" : "Pull LT to swell"),
    }};
    Panel right{{Caption{layout.isOnBar() ? "RB + right stick" : "Right stick · RT",
                         layout.isOnBar() ? "The bar: two octaves, at rest in tune" : "The line, pressure on RT"}}};
    const auto pitch = layout.melody().pitch();
    if (layout.isOnBar()) {
        const double low = (settings.octave + 1 + layout.lineOctave()) * 12 + static_cast<int>(settings.key.root);
        const double span = TwoVoices::barSpan;
        Bar bar;
        for (int step = 0; step <= static_cast<int>(span); ++step) {
            const int note = static_cast<int>(low) + step;
            if (settings.key.has(note))
                bar.marks.push_back({step / span, note % 12 == static_cast<int>(settings.key.root)});
        }
        if (const auto at = pitch ? pitch : layout.barPitch()) bar.pitch = (*at - low) / span;
        right.items.push_back(bar);
    } else {
        const auto petals = layout.petals(settings);
        std::vector<std::optional<Target>> notes;
        for (size_t i = 0; i < petals.size(); ++i) {
            const auto &petal = petals[i];
            notes.push_back(Target{static_cast<double>(i) * 360 / static_cast<double>(petals.size()), noteName(petal.note),
                                   petal.isChordTone ? "chord tone" : "",
                                   petal.isReachable ? ChordFit::inKey : ChordFit::tense, petal.isChordTone,
                                   layout.petal() == static_cast<int>(i)});
        }
        std::string melody = "—";
        if (pitch) {
            const double nearest = std::round(*pitch);
            melody = noteName(static_cast<int>(nearest)) + (std::abs(*pitch - nearest) > 0.05 ? " ~" : "");
        }
        right.items.push_back(Pie{notes, std::nullopt, frame.right, melody, "outer ring: octave up", Tint::melody});
    }
    right.items.push_back(Triggers{{{"RT", frame.rightTrigger, {}, Tint::melody}}});
    right.items.push_back(Note{layout.chordTonesOnly() ? "Y: chord tones only" : "Y: every note of the key"});
    return {left, right};
}

/// "bar 2 · beat 3.5"
std::string position(double beats) {
    const int bar = static_cast<int>(beats) / Arrangement::beatsPerBar + 1;
    const double beat = std::fmod(beats, static_cast<double>(Arrangement::beatsPerBar)) + 1;
    return "bar " + std::to_string(bar) + " · beat " + decimal(beat, 0, 2);
}

Lanes lanes(const Arranger &layout, const DeskSettings &settings) {
    Lanes lanes;
    const double beats = Arrangement::beatsPerBar;
    const double grid = std::min(step(settings.grid).value_or(1.0), 1.0);
    for (int bar = 0; bar < Arrangement::bars; ++bar) {
        const double from = bar * beats, to = from + beats;
        const auto place = [&](double at) { return (at - from) / beats; };
        Lanes::Lane lane{bar + 1, {}, {}, std::nullopt, std::nullopt, std::nullopt};
        for (double line = from; line < to; line += grid) lane.lines.push_back({place(line), line == std::round(line)});
        for (const auto &placed : layout.arrangement().chords()) {
            if (!(placed.start < to && placed.end() > from)) continue;
            const bool heard = layout.playhead() && !layout.writing() && placed.covers(*layout.playhead());
            lane.blocks.push_back({place(std::max(placed.start, from)), place(std::min(placed.end(), to)),
                                   placed.start >= from ? placed.chord.name() : "", heard});
        }
        if (const auto &writing = layout.writing(); writing && writing->start < to && writing->start + writing->length > from)
            lane.writing = std::pair{place(std::max(writing->start, from)),
                                     place(std::min(writing->start + std::max(writing->length, 0.05), to))};
        if (layout.cursor() >= from && layout.cursor() < to) lane.cursor = place(layout.cursor());
        if (const auto playhead = layout.playhead(); playhead && *playhead >= from && *playhead < to)
            lane.playhead = place(*playhead);
        lanes.lanes.push_back(lane);
    }
    return lanes;
}

std::vector<Panel> arranger(const Arranger &layout, const DeskSettings &settings, const GamepadFrame &frame) {
    std::string status;
    if (const auto &writing = layout.writing())
        status = (writing->isLive ? "Recording live: " : "Writing: ") + decimal(writing->length, 2, 2) +
                 " beats held, let go to place it";
    else if (layout.playing())
        status = "Playing round the four bars. RT records live at the playhead; Y stops.";
    else
        status = "Hold RT to write for as long as it's held. Y plays from the cursor.";
    Panel left{{
        Caption{"D-pad · RT · LB RB", "Four bars at " + std::to_string(static_cast<int>(settings.tempo)) + " bpm"},
        Facts{{{"Grid · L3", name(settings.grid)}, {"Cursor", position(layout.cursor())}}, ""},
        lanes(layout, settings),
        Note{status, layout.writing() ? Tint::chord : Tint::secondary, layout.writing().has_value()},
    }};
    // The ring's inner band, compactly: a sector for each mode.
    const auto pie = settings.ring(layout.degree());
    std::vector<std::optional<Target>> ring;
    for (const auto &sector : pie.sectors) {
        const DeskChord chord(settings.key, layout.degree(), pie.color(RingCell{sector.mode, theory::StackHeight::seventh}));
        ring.push_back(Target{sector.bearing, chord.name(), "", chord.fit(settings.key), false,
                              layout.aim() && layout.aim()->mode == sector.mode});
    }
    Panel right{{
                    Caption{"Both sticks", "Aim"},
                    Note{layout.aimed(settings).name(), Tint::chord, true, true},
                    Pies{{Pie{optionals(layout.degreeTargets(settings)), std::nullopt, frame.left, "", "", Tint::chord, true},
                          Pie{ring, std::nullopt, frame.right, "", "", Tint::chord, true}}},
                    Triggers{{{"RT", frame.rightTrigger, {}, Tint::chord}}},
                    Triggers{{{"LT", frame.leftTrigger, {}, Tint::melody}}},
                },
                460};
    return {left, right};
}

TopBar topBar(const Desk &desk) {
    const auto &settings = desk.settings;
    TopBar top{{}, 0, summary(desk.layout()), std::nullopt, {}};
    for (size_t i = 0; i < allLayoutKinds.size(); ++i) {
        top.layouts.push_back(name(allLayoutKinds[i]));
        if (allLayoutKinds[i] == desk.layout()) top.chosen = static_cast<int>(i);
    }
    if (settings.consonance.mode != GuardMode::off) {
        std::string pool;
        if (settings.consonance.mode == GuardMode::run) {
            for (const int note : settings.consonance.pool())
                pool += (pool.empty() ? "" : " ") + theory::name(static_cast<theory::PitchClass>(note));
            if (pool.empty()) pool = "nothing heard yet";
        }
        top.guard = std::pair{name(settings.consonance.mode) + (settings.consonance.inKey ? " · in key" : ""), pool};
    }
    top.facts = {
        {"Key", settings.summary()},
        {"Voicing", settings.voicingName() + (settings.voiceLeading ? " · led" : "")},
        {"Chords", desk.catalog().name(settings.chordSound)},
        {"Line", desk.catalog().name(settings.lineSound)},
        {"Out", name(settings.output)},
    };
    return top;
}

Hand hand(const Legend &legend, const GamepadFrame &frame, bool keyboard) {
    static const std::vector<PadControl> left = {
        PadControl::leftTrigger(),          PadControl::button(PadButton::lb),   PadControl::leftStick(),
        PadControl::button(PadButton::l3),  PadControl::button(PadButton::up),   PadControl::button(PadButton::down),
        PadControl::button(PadButton::left), PadControl::button(PadButton::right), PadControl::button(PadButton::back),
    };
    static const std::vector<PadControl> right = {
        PadControl::rightTrigger(),        PadControl::button(PadButton::rb), PadControl::rightStick(),
        PadControl::button(PadButton::r3), PadControl::button(PadButton::y),  PadControl::button(PadButton::x),
        PadControl::button(PadButton::b),  PadControl::button(PadButton::a),  PadControl::button(PadButton::start),
    };
    const auto entries = [&](const std::vector<PadControl> &controls) {
        std::vector<Hand::Entry> out;
        for (const auto &control : controls) {
            const auto found = legend.find(control);
            if (found == legend.end()) continue;
            Hand::Entry entry{name(control), found->second, keyboard ? KeyboardPad::key(control) : "", false, std::nullopt};
            std::visit(
                [&](const auto &value) {
                    using Kind = std::decay_t<decltype(value)>;
                    if constexpr (std::is_same_v<Kind, PadControl::Button>) {
                        entry.isHeld = frame.isDown(value.button);
                        entry.tint = tint(value.button);
                    } else if constexpr (std::is_same_v<Kind, PadControl::LeftStick>) {
                        entry.mark = "LS";
                        entry.isHeld = frame.left.radius() > 0.3;
                    } else if constexpr (std::is_same_v<Kind, PadControl::RightStick>) {
                        entry.mark = "RS";
                        entry.isHeld = frame.right.radius() > 0.3;
                    } else if constexpr (std::is_same_v<Kind, PadControl::LeftTrigger>) {
                        entry.isHeld = frame.leftTrigger > 0.08;
                    } else {
                        entry.isHeld = frame.rightTrigger > 0.08;
                    }
                },
                control.value());
            out.push_back(entry);
        }
        return out;
    };
    return {keyboard ? "Keyboard" : "Controller", entries(left), entries(right)};
}

FavoritesView favorites(const Desk &desk) {
    const auto &settings = desk.settings;
    const auto &favorites = settings.favorites;
    const auto &key = settings.key;
    const auto keyDefault = favorites.defaultTable(key);
    FavoritesView view;
    for (size_t i = 0; i < favorites.tables().size(); ++i) {
        const auto &table = favorites.tables()[i];
        int count = 0;
        for (const auto &pin : table.pins) count += static_cast<int>(pin.colors.size());
        view.tables.push_back({table.name, static_cast<int>(i) == favorites.active(), keyDefault == table.name, count});
    }
    view.canRemove = favorites.tables().size() > 1;
    view.keyDefault = "Play " + favorites.table().name + " whenever the key is " + settings.summary();
    view.isKeyDefault = keyDefault == favorites.table().name;
    view.pinnedCaption = settings.summary();
    view.pinnedTitle = "Pinned in " + favorites.table().name;
    const auto pinnable = desk.pinnable();
    view.pin = pinnable ? "Pin " + pinnable->name() : "Strike a chord to pin it";
    view.canPin = pinnable.has_value();
    for (const auto degree : theory::allDegrees) {
        FavoritesView::Degree row{numeral(degree, key), {}};
        for (const auto &color : favorites.colors(key, degree)) row.pinned.push_back(DeskChord(key, degree, color).name());
        view.degrees.push_back(row);
    }
    view.help = "In Twin Rings, hold Y: the right stick plays the chord's favorites (flick keeps, hold plays), "
                "Y + A pins the chord you're on, Y + X unpins the one aimed at. In Face Chords, LB pressed while the "
                "left stick colors a chord pins it (again, unpins it), and LB held puts the pins on the left stick.";
    return view;
}

MenuView menu(const Desk &desk, const DeskMenu &menu) {
    MenuView view;
    for (const auto row : DeskMenu::allRows)
        view.rows.push_back({name(row), desk.value(row), row == menu.row, row != DeskMenu::Row::saveMIDI});
    if (const auto &library = menu.library) {
        const auto &chosen = library->line == Line::chord ? desk.settings.chordSound : desk.settings.lineSound;
        MenuView::Library shown{library->line == Line::chord ? "Chords" : "Line", {}};
        const auto &categories = desk.catalog().categories();
        for (size_t i = 0; i < categories.size(); ++i) {
            MenuView::Library::Category category{categories[i].name, static_cast<int>(i) == library->category, {}};
            for (const auto &sound : categories[i].sounds) category.sounds.push_back({sound.name, sound.id == chosen});
            shown.categories.push_back(category);
        }
        view.library = shown;
    }
    return view;
}

} // namespace

Scene scene(const Desk &desk, const Legend &legend, const GamepadFrame &held, bool keyboard, const Drums *drums,
            const FaceColors *colors, double time) {
    const auto frame = desk.frame() ? desk.frame()->shown() : GamepadFrame();
    const auto &settings = desk.settings;
    Scene scene{topBar(desk), {}, hand(legend, held, keyboard), favorites(desk), std::nullopt, std::nullopt};
    switch (desk.layout()) {
    case LayoutKind::faceChords: scene.stage = faceChords(desk.faceChords(), settings, held, drums, colors, time); break;
    case LayoutKind::twinRings: scene.stage = twinRings(desk.twinRings(), settings, frame); break;
    case LayoutKind::petals: scene.stage = petals(desk.petals(), settings, frame); break;
    case LayoutKind::neighbourhood: scene.stage = neighbourhood(desk.neighbourhood(), settings, frame); break;
    case LayoutKind::twoVoices: scene.stage = twoVoices(desk.twoVoices(), settings, frame); break;
    case LayoutKind::arranger: scene.stage = arranger(desk.arranger(), settings, frame); break;
    }
    if (desk.menu()) scene.menu = menu(desk, *desk.menu());
    return scene;
}

Scene scene(const Desk &desk, bool keyboard) {
    const auto frame = desk.frame() ? desk.frame()->shown() : GamepadFrame();
    return scene(desk, desk.legend(), frame, keyboard, nullptr, nullptr, 0);
}

std::vector<DeskEffect> perform(Desk &desk, const Action &action) {
    auto &favorites = desk.settings.favorites;
    const auto valid = [](int index, size_t count) { return index >= 0 && static_cast<size_t>(index) < count; };
    switch (action.kind) {
    case Action::Kind::chooseLayout:
        if (valid(action.index, allLayoutKinds.size())) return desk.choose(allLayoutKinds[static_cast<size_t>(action.index)]);
        break;
    case Action::Kind::toggleMenu: return desk.toggleMenu();
    case Action::Kind::arrangeRing:
        if (valid(action.index, allRingArrangements.size()))
            desk.settings.ringArrangement = allRingArrangements[static_cast<size_t>(action.index)];
        break;
    case Action::Kind::pinPlayed:
        if (const auto chord = desk.pinnable()) favorites.pin(*chord, desk.settings.key);
        break;
    case Action::Kind::unpin:
        if (valid(action.index, theory::allDegrees.size()))
            favorites.unpin(desk.settings.key, theory::allDegrees[static_cast<size_t>(action.index)], action.value);
        break;
    case Action::Kind::addTable: favorites.addTable("Table"); break;
    case Action::Kind::removeTable: favorites.removeTable(favorites.active()); break;
    case Action::Kind::renameTable: favorites.rename(action.index, action.text); break;
    case Action::Kind::playTable:
        if (valid(action.index, favorites.tables().size())) favorites.play(action.index);
        break;
    case Action::Kind::setKeyDefault: favorites.setDefault(desk.settings.key, action.value != 0); break;
    case Action::Kind::record:
    case Action::Kind::play:
    case Action::Kind::rewind:
    case Action::Kind::loop:
    case Action::Kind::quantize:
    case Action::Kind::erase:
    case Action::Kind::undo:
    case Action::Kind::redo:
    case Action::Kind::chooseLane:
    case Action::Kind::muteLane:
    case Action::Kind::selectEvent:
    case Action::Kind::stretchChoice:
    case Action::Kind::deselect:
    case Action::Kind::choosePattern:
    case Action::Kind::chooseKit: break; // The studio's.
    }
    return {};
}

} // namespace perfecto::desk
