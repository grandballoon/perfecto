#include "perfecto/desk/ring_pie.hpp"

#include <perfecto/theory/color_ring.hpp>
#include <perfecto/theory/color_steps.hpp>
#include <perfecto/theory/grid.hpp>

#include <algorithm>
#include <cmath>
#include <deque>
#include <numeric>
#include <tuple>

namespace perfecto::desk {

using namespace theory;

std::string name(RingArrangement arrangement) {
    switch (arrangement) {
    case RingArrangement::home: return "Home";
    case RingArrangement::fixed: return "Fixed";
    case RingArrangement::centred: return "Centred";
    }
    return {};
}

std::string summary(RingArrangement arrangement) {
    switch (arrangement) {
    case RingArrangement::home: return "The key's own chord at the top; the gap moves with the degree.";
    case RingArrangement::fixed: return "Every direction always the same mode; the gap always at the bottom.";
    case RingArrangement::centred:
        return "The key's own chord at the top, balanced, borrowing from minor scales at the ends.";
    }
    return {};
}

std::string name(RingOrder order) {
    switch (order) {
    case RingOrder::brightness: return "Brightness";
    case RingOrder::quality: return "Quality";
    case RingOrder::character: return "Character note";
    case RingOrder::borrowed: return "Fewest borrowed";
    case RingOrder::common: return "Common first";
    case RingOrder::nearness: return "Nearest";
    }
    return {};
}

std::string name(RingFilter filter) {
    switch (filter) {
    case RingFilter::all: return "All";
    case RingFilter::inKey: return "In key";
    case RingFilter::majorThird: return "Major third";
    case RingFilter::minorThird: return "Minor third";
    case RingFilter::noClash: return "No clash";
    }
    return {};
}

const std::array<HeptatonicMode, 7> RingPie::popularity = {
    HeptatonicMode::ionian, HeptatonicMode::aeolian, HeptatonicMode::dorian,  HeptatonicMode::mixolydian,
    HeptatonicMode::lydian, HeptatonicMode::phrygian, HeptatonicMode::locrian,
};

namespace {

using Modes = std::vector<HeptatonicMode>;

/// A list of modes laid round the ring, and where in it the top is (an
/// index, or between two).
struct Laid {
    Modes list;
    double top;
};

bool has(const std::vector<int> &intervals, int interval) {
    return std::find(intervals.begin(), intervals.end(), interval) != intervals.end();
}

int brightness(HeptatonicMode mode) {
    const auto &steps = intervals(mode);
    return std::accumulate(steps.begin(), steps.end(), 0);
}

std::optional<size_t> indexOf(const Modes &modes, HeptatonicMode mode) {
    const auto found = std::find(modes.begin(), modes.end(), mode);
    if (found == modes.end()) return std::nullopt;
    return static_cast<size_t>(found - modes.begin());
}

/// `modes` sorted by `key`, keeping the order of equals as Swift's sort
/// does.
template <class By> Modes sortedBy(Modes modes, By key) {
    std::stable_sort(modes.begin(), modes.end(), [&](HeptatonicMode a, HeptatonicMode b) { return key(a) < key(b); });
    return modes;
}

} // namespace

RingPie::RingPie(RingArrangement arrangement, RingOrder order, RingFilter filter, const Key &key, Degree degree,
                 const std::optional<DeskChord> &sounding, const ConsonanceGuard &consonance)
    : arrangement(arrangement), order(order), filter(filter), own(ChordGrid::ownMode(key, degree)), key_(key),
      degree_(degree), consonance_(consonance) {
    const HeptatonicMode own = this->own;
    // The modes, darkest first.
    Modes modes;
    if (arrangement == RingArrangement::centred) {
        modes = rowsAround(own, 7);
        std::reverse(modes.begin(), modes.end());
    } else {
        modes = ColorRing::modes();
    }
    const std::optional<size_t> ownIndex = indexOf(modes, own);
    const auto distance = [&](HeptatonicMode mode) { return std::abs(brightness(mode) - brightness(own)); };
    const auto turned = [&](Modes list, double natural) {
        const auto at = indexOf(list, own);
        const double top =
            arrangement == RingArrangement::fixed ? natural : (at ? static_cast<double>(*at) : natural);
        return Laid{std::move(list), top};
    };
    /// A ranking laid out from the top, the next two either side of it,
    /// the two after either side of them, and so on. Of two ranked alike
    /// by `score`, the brighter goes clockwise, as it does on the ring.
    const auto fanned = [&](const Modes &ranked, const auto &score) {
        Modes rights, lefts;
        std::deque<HeptatonicMode> rest(ranked.begin() + 1, ranked.end());
        while (!rest.empty()) {
            const HeptatonicMode first = rest.front();
            rest.pop_front();
            if (rest.empty()) {
                rights.push_back(first);
                break;
            }
            const HeptatonicMode second = rest.front();
            rest.pop_front();
            const bool swap = score(first) == score(second) && brightness(second) > brightness(first);
            rights.push_back(swap ? second : first);
            lefts.push_back(swap ? first : second);
        }
        Modes list(lefts.rbegin(), lefts.rend());
        list.push_back(ranked[0]);
        list.insert(list.end(), rights.begin(), rights.end());
        return Laid{std::move(list), static_cast<double>(lefts.size())};
    };

    Laid laid{{}, 0};
    switch (order) {
    case RingOrder::brightness:
        if (arrangement == RingArrangement::fixed || !ownIndex) {
            const double top = arrangement == RingArrangement::centred ? static_cast<double>(modes.size() / 2)
                                                                       : static_cast<double>(ColorRing::topSector);
            laid = Laid{modes, top};
        } else {
            laid = Laid{modes, static_cast<double>(*ownIndex)};
        }
        break;
    case RingOrder::quality: {
        Modes other, minor, major;
        for (HeptatonicMode mode : modes) {
            const auto &steps = intervals(mode);
            if (!has(steps, 7)) other.push_back(mode);
            if (has(steps, 7) && has(steps, 3) && !has(steps, 4)) minor.push_back(mode);
            if (has(steps, 7) && has(steps, 4)) major.push_back(mode);
        }
        Modes list = other;
        list.insert(list.end(), minor.begin(), minor.end());
        list.insert(list.end(), major.rbegin(), major.rend());
        laid = turned(std::move(list), static_cast<double>(other.size() + minor.size()) - 0.5);
        break;
    }
    case RingOrder::character: {
        const Modes scored =
            sortedBy(modes, [](HeptatonicMode mode) { return std::tuple(alteration(mode), brightness(mode)); });
        std::vector<size_t> plain;
        for (size_t i = 0; i < scored.size(); ++i)
            if (alteration(scored[i]) == 0) plain.push_back(i);
        const double natural =
            plain.empty() ? static_cast<double>(scored.size() / 2)
                          : static_cast<double>(std::accumulate(plain.begin(), plain.end(), size_t{0})) /
                                static_cast<double>(plain.size());
        laid = turned(scored, natural);
        break;
    }
    case RingOrder::borrowed: {
        const auto outside = [&](HeptatonicMode mode) {
            const auto &steps = intervals(mode);
            return static_cast<int>(std::count_if(steps.begin(), steps.end(), [&](int step) {
                return !key.has(raw(key.root) + offset(key.scale, degree) + step);
            }));
        };
        laid = fanned(sortedBy(modes,
                               [&](HeptatonicMode mode) {
                                   return std::tuple(outside(mode), distance(mode), brightness(mode));
                               }),
                      outside);
        break;
    }
    case RingOrder::common: {
        const auto rank = [](HeptatonicMode mode) {
            const auto found = std::find(popularity.begin(), popularity.end(), mode);
            return static_cast<int>(found - popularity.begin());
        };
        Modes ranked = sortedBy(
            modes, [&](HeptatonicMode mode) { return std::tuple(rank(mode), distance(mode), brightness(mode)); });
        if (arrangement != RingArrangement::fixed) {
            if (const auto at = indexOf(ranked, own)) {
                ranked.erase(ranked.begin() + static_cast<std::ptrdiff_t>(*at));
                ranked.insert(ranked.begin(), own);
            }
        }
        laid = fanned(ranked, rank);
        break;
    }
    case RingOrder::nearness: {
        const auto steps = [&](HeptatonicMode mode) {
            if (!sounding) return mode == own ? 0 : 1;
            const DeskChord chord(key, degree,
                                  ChordColor::grid(StackHeight::seventh,
                                                   mode == own ? std::nullopt : std::optional<HeptatonicMode>(mode)));
            const std::set<int> a = chord.pitchClasses(), b = sounding->pitchClasses();
            return colorSteps(std::vector<int>(a.begin(), a.end()), std::vector<int>(b.begin(), b.end()));
        };
        laid = fanned(sortedBy(modes,
                               [&](HeptatonicMode mode) {
                                   return std::tuple(steps(mode), distance(mode), brightness(mode));
                               }),
                      steps);
        break;
    }
    }
    for (size_t index = 0; index < laid.list.size(); ++index) {
        const HeptatonicMode mode = laid.list[index];
        sectors.push_back(Sector{mode, (static_cast<double>(index) - laid.top) * sectorSpan, mode == own});
    }
}

int RingPie::alteration(HeptatonicMode mode) {
    const auto &steps = intervals(mode);
    const auto &plain = has(steps, 4) ? intervals(HeptatonicMode::ionian) : intervals(HeptatonicMode::aeolian);
    int raised = 0, lowered = 0;
    for (size_t i = 0; i < std::min(steps.size(), plain.size()); ++i) {
        if (steps[i] > plain[i]) ++raised;
        if (steps[i] < plain[i]) ++lowered;
    }
    return raised > 0 && lowered == 0 ? raised : -lowered - raised;
}

double RingPie::gap() const {
    const double middle = (sectors.front().bearing + sectors.back().bearing) / 2 + 180;
    return std::fmod(std::fmod(middle, 360) + 360, 360);
}

bool RingPie::allows(const RingCell &cell) const {
    if (!consonance_.allows(DeskChord(key_, degree_, color(cell)), key_)) return false;
    const auto &steps = intervals(cell.mode);
    switch (filter) {
    case RingFilter::all: return true;
    case RingFilter::majorThird: return has(steps, 4);
    case RingFilter::minorThird: return has(steps, 3) && !has(steps, 4);
    case RingFilter::inKey:
    case RingFilter::noClash: {
        const ChordFit fit = DeskChord(key_, degree_, color(cell)).fit(key_);
        return filter == RingFilter::inKey ? fit != ChordFit::borrowed : fit != ChordFit::tense;
    }
    }
    return true;
}

RingPie::Gate RingPie::gate(bool extended) const {
    const auto heights = RingPie::heights(extended);
    std::vector<int> reachable;
    std::vector<double> bearings;
    for (size_t index = 0; index < sectors.size(); ++index) {
        const bool reached = std::any_of(heights.begin(), heights.end(), [&](StackHeight height) {
            return allows(RingCell{sectors[index].mode, height});
        });
        if (!reached) continue;
        reachable.push_back(static_cast<int>(index));
        bearings.push_back(sectors[index].bearing);
    }
    return Gate{PieGate(std::move(bearings), sectorSpan / 2 + 4), std::move(reachable)};
}

HeptatonicMode RingPie::mode(int steps) const {
    return sectors[static_cast<size_t>(clamped(steps) + ownIndex())].mode;
}

int RingPie::clamped(int steps) const {
    const int own = ownIndex();
    return std::min(static_cast<int>(sectors.size()) - 1 - own, std::max(-own, steps));
}

int RingPie::ownIndex() const {
    const auto found = std::find_if(sectors.begin(), sectors.end(), [](const Sector &sector) { return sector.isOwn; });
    if (found != sectors.end()) return static_cast<int>(found - sectors.begin());
    // The first of equals, as Swift's `min(by:)`.
    size_t nearest = 0;
    for (size_t i = 1; i < sectors.size(); ++i)
        if (std::fabs(sectors[i].bearing) < std::fabs(sectors[nearest].bearing)) nearest = i;
    return static_cast<int>(nearest);
}

ChordColor RingPie::color(const RingCell &cell) const {
    return ChordColor::grid(cell.height, cell.mode == own ? std::nullopt : std::optional<HeptatonicMode>(cell.mode));
}

std::optional<RingCell> RingPie::cell(int sector, int band, bool extended) const {
    const RingCell cell{sectors[static_cast<size_t>(sector)].mode, heights(extended)[static_cast<size_t>(band)]};
    if (!allows(cell)) return std::nullopt;
    return cell;
}

std::array<StackHeight, 3> RingPie::heights(bool extended) {
    if (extended) return {StackHeight::ninth, StackHeight::eleventh, StackHeight::thirteenth};
    return {StackHeight::seventh, StackHeight::ninth, StackHeight::eleventh};
}

// DeskSettings, from RingPie.swift.

RingPie DeskSettings::ring(Degree degree, const std::optional<DeskChord> &sounding) const {
    return RingPie(ringArrangement, ringOrder, ringFilter, key, degree, sounding, consonance);
}

RingPie DeskSettings::brightnessRing(Degree degree) const { return RingPie(ringArrangement, key, degree); }

void DeskSettings::moveRingOrder(int steps) {
    const int count = static_cast<int>(allRingOrders.size());
    const int at =
        static_cast<int>(std::find(allRingOrders.begin(), allRingOrders.end(), ringOrder) - allRingOrders.begin());
    ringOrder = allRingOrders[static_cast<size_t>(((at + steps) % count + count) % count)];
}

void DeskSettings::moveRingFilter(int steps) {
    const int count = static_cast<int>(allRingFilters.size());
    const int at =
        static_cast<int>(std::find(allRingFilters.begin(), allRingFilters.end(), ringFilter) - allRingFilters.begin());
    ringFilter = allRingFilters[static_cast<size_t>(((at + steps) % count + count) % count)];
}

// CompassPie

namespace CompassPie {

const std::vector<CompassPlace> &places() {
    static const std::vector<CompassPlace> all = {
        CompassPlace(ColorStepKind::add, 1),      CompassPlace(ColorStepKind::add, 2),
        CompassPlace(ColorStepKind::raise, 1),    CompassPlace(ColorStepKind::raise, 2),
        CompassPlace(ColorStepKind::takeAway, 1), CompassPlace(ColorStepKind::takeAway, 2),
        CompassPlace(ColorStepKind::lower, 1),    CompassPlace(ColorStepKind::lower, 2),
    };
    return all;
}

const PieGate &gate() {
    static const PieGate pie = PieGate::even(8);
    return pie;
}

std::optional<DeskChord> chord(int index, const DeskChord &from, ColorStepRanking ranking) {
    const auto step = StepCompass::step(places()[static_cast<size_t>(index)], from.tones(), from.key,
                                        from.spec.degree, ranking);
    if (!step) return std::nullopt;
    return DeskChord(from.key, from.spec.degree, ChordColor::tones(step->tones));
}

std::optional<std::string> edit(int index, const DeskChord &from, ColorStepRanking ranking) {
    const auto step = StepCompass::step(places()[static_cast<size_t>(index)], from.tones(), from.key,
                                        from.spec.degree, ranking);
    if (!step) return std::nullopt;
    return step->editName();
}

} // namespace CompassPie

} // namespace perfecto::desk
