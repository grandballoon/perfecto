#include "perfecto/desk/gates.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace perfecto::desk {

PieGate::PieGate(std::vector<double> bearings, std::optional<double> width)
    : bearings(std::move(bearings)), width(width.value_or(this->bearings.size() > 1 ? 180 : 360)) {}

PieGate PieGate::even(int count, double first) {
    const double step = 360 / static_cast<double>(count);
    std::vector<double> bearings;
    for (int i = 0; i < count; ++i) bearings.push_back(first + static_cast<double>(i) * step);
    // A little past half a step, so no bearing falls between two targets.
    return PieGate(std::move(bearings), step / 2 + 1);
}

std::optional<int> PieGate::select(const Stick &stick, std::optional<int> last) const {
    if (bearings.empty() || !(stick.radius() >= (last ? rest : reach))) return std::nullopt;
    const double bearing = stick.bearing();
    const int count = static_cast<int>(bearings.size());
    if (last && *last >= 0 && *last < count &&
        turn(bearings[static_cast<size_t>(*last)], bearing) <= sideOf(*last) + hold) {
        return last;
    }
    // The first of equals, as Swift's `min(by:)`.
    int nearest = 0;
    for (int i = 1; i < count; ++i)
        if (turn(bearings[static_cast<size_t>(i)], bearing) < turn(bearings[static_cast<size_t>(nearest)], bearing))
            nearest = i;
    if (turn(bearings[static_cast<size_t>(nearest)], bearing) <= width) return nearest;
    return std::nullopt;
}

double PieGate::sideOf(int index) const {
    std::optional<double> nearest;
    for (size_t i = 0; i < bearings.size(); ++i) {
        if (static_cast<int>(i) == index) continue;
        const double apart = turn(bearings[static_cast<size_t>(index)], bearings[i]);
        if (!nearest || apart < *nearest) nearest = apart;
    }
    return std::min(width, nearest.value_or(360) / 2);
}

double PieGate::turn(double a, double b) {
    const double difference = std::fmod(std::fabs(a - b), 360);
    return std::min(difference, 360 - difference);
}

const RadialBands &RadialBands::three() {
    static const RadialBands bands{{0.72, 0.9}};
    return bands;
}

const RadialBands &RadialBands::two() {
    static const RadialBands bands{{0.86}};
    return bands;
}

int RadialBands::band(double radius, std::optional<int> last) const {
    const int plain = static_cast<int>(std::count_if(edges.begin(), edges.end(), [&](double e) { return radius >= e; }));
    if (!last) return plain;
    // Kept while the radius is within the hold of the ring it was in.
    const int at = *last;
    const double low = at == 0 ? 0 : edges[static_cast<size_t>(at - 1)] - hold;
    const double high = at >= static_cast<int>(edges.size()) ? std::numeric_limits<double>::infinity()
                                                              : edges[static_cast<size_t>(at)] + hold;
    return radius >= low && radius < high ? at : plain;
}

std::vector<TriggerStrike::Event> TriggerStrike::step(double value, double time) {
    if (std::holds_alternative<Resting>(phase_)) {
        if (!(value >= threshold)) return {};
        phase_ = Crossing{time};
        return value >= 0.95 ? strike(value) : std::vector<Event>{};
    }
    if (const auto *crossing = std::get_if<Crossing>(&phase_)) {
        if (value < letGo) {
            phase_ = Resting{};
            return {};
        }
        return time - crossing->since >= window || value >= 0.95 ? strike(value) : std::vector<Event>{};
    }
    if (value < letGo) {
        phase_ = Resting{};
        return {Release{}};
    }
    return {Depth{value}};
}

std::vector<TriggerStrike::Event> TriggerStrike::strike(double value) {
    phase_ = Held{};
    const double speed = std::min(1.0, std::max(0.0, (value - threshold) / fullPull));
    return {Strike{softest + (1 - softest) * speed}, Depth{value}};
}

const TriggerSteps &TriggerSteps::three() {
    static const TriggerSteps steps{{0.15, 0.45, 0.78}};
    return steps;
}

int TriggerSteps::step(double value, int last) const {
    const int plain = static_cast<int>(std::count_if(edges.begin(), edges.end(), [&](double e) { return value >= e; }));
    const double low = last == 0 ? -std::numeric_limits<double>::infinity() : edges[static_cast<size_t>(last - 1)] - hold;
    const double high = last >= static_cast<int>(edges.size()) ? std::numeric_limits<double>::infinity()
                                                               : edges[static_cast<size_t>(last)] + hold;
    return value >= low && value < high ? last : plain;
}

std::vector<StickGesture::Event> StickGesture::step(const Stick &stick, const PieGate &gate, double time) {
    const std::optional<int> next = gate.select(stick, target_);
    if (next == target_) return {};
    const std::optional<int> last = target_;
    target_ = next;
    if (!last) {
        since_ = time;
        return {Aim{*next}};
    }
    if (!next) {
        if (time - since_ <= flickTime) return {Flick{*last}};
        return {Lift{*last}};
    }
    return {Aim{*next}};
}

void TapOrHold::press(double time) {
    pressedAt_ = time;
    wasUsed_ = false;
}

bool TapOrHold::release(double time) {
    const std::optional<double> pressedAt = pressedAt_;
    pressedAt_ = std::nullopt;
    if (!pressedAt) return false;
    return !wasUsed_ && time - *pressedAt <= tapTime;
}

} // namespace perfecto::desk
