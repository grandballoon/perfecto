#include "perfecto/desk/song.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <map>
#include <tuple>
#include <utility>

namespace perfecto::desk {

namespace {

/// How near two beats are to be the same place: a chord let go of on the
/// frame the next was struck ends exactly where it starts.
constexpr double near = 1e-9;

bool same(double a, double b) { return std::abs(a - b) < near; }

void order(std::vector<Event> &events) {
    std::sort(events.begin(), events.end(),
              [](const Event &a, const Event &b) { return a.start != b.start ? a.start < b.start : a.id < b.id; });
}

/// The layer's events by channel, each channel's in order.
std::map<int, std::vector<Event>> channels(const Layer &layer) {
    std::map<int, std::vector<Event>> out;
    for (const Event &event : layer.events) out[channel(event.part)].push_back(event);
    return out;
}

/// The layer with `ids` placed where `place` puts each (its start and its
/// end), and the rest settled round them, channel by channel: an event that
/// ran into the next still does, one that would overlap the next ends where
/// it starts, and one left with no length is gone.
template <class Place> Layer settled(const Layer &layer, const std::set<int> &ids, Place place) {
    Layer out = layer;
    out.events.clear();
    for (const auto &[_, events] : channels(layer)) {
        const size_t n = events.size();
        std::vector<double> starts(n), ends(n);
        for (size_t i = 0; i < n; ++i) {
            if (ids.contains(events[i].id)) {
                std::tie(starts[i], ends[i]) = place(events[i]);
            } else {
                starts[i] = events[i].start;
                ends[i] = events[i].end();
            }
        }
        for (size_t i = 0; i < n; ++i) {
            if (i + 1 < n) {
                if (same(events[i].end(), events[i + 1].start)) ends[i] = starts[i + 1];
                ends[i] = std::min(ends[i], starts[i + 1]);
            }
            if (ends[i] - starts[i] > near) out.events.push_back({events[i].id, starts[i], ends[i] - starts[i], events[i].part});
        }
    }
    order(out.events);
    return out;
}

} // namespace

int channel(const Part &part) {
    return std::visit([](const ChordPart &chord) { return chord.voice; }, part);
}

// MARK: – A layer

std::vector<Event> Layer::chosen(const std::set<int> &ids) const {
    std::vector<Event> out;
    for (const Event &event : events)
        if (ids.contains(event.id)) out.push_back(event);
    return out;
}

std::set<int> Layer::between(int a, int b) const {
    const auto at = [&](int id) {
        return std::find_if(events.begin(), events.end(), [&](const Event &e) { return e.id == id; }) - events.begin();
    };
    const auto first = at(a), last = at(b);
    const auto count = static_cast<std::ptrdiff_t>(events.size());
    if (first == count || last == count) return {};
    std::set<int> ids;
    for (auto i = std::min(first, last); i <= std::max(first, last); ++i) ids.insert(events[static_cast<size_t>(i)].id);
    return ids;
}

std::optional<Span> Layer::span(const std::set<int> &ids) const {
    const auto events = chosen(ids);
    if (events.empty()) return std::nullopt;
    Span span{events.front().start, events.front().end()};
    for (const Event &event : events) span.to = std::max(span.to, event.end());
    return span;
}

// MARK: – The song

bool Song::isEmpty() const {
    return std::all_of(layers.begin(), layers.end(), [](const Layer &layer) { return layer.events.empty(); });
}

const Layer *Song::layer(int id) const {
    const auto found = std::find_if(layers.begin(), layers.end(), [&](const Layer &layer) { return layer.id == id; });
    return found == layers.end() ? nullptr : &*found;
}

Layer *Song::layer(int id) { return const_cast<Layer *>(std::as_const(*this).layer(id)); }

std::optional<double> Song::end() const {
    std::optional<double> end;
    for (const Layer &layer : layers) {
        if (layer.isMuted || layer.loop) continue;
        for (const Event &event : layer.events) end = std::max(end.value_or(0), event.end());
    }
    return end;
}

bool Song::isEndless() const {
    return std::any_of(layers.begin(), layers.end(), [](const Layer &layer) { return !layer.isMuted && layer.loop; });
}

std::vector<Occurrence> Song::heard(const Layer &layer, double from, double to) const {
    std::vector<Occurrence> out;
    const auto add = [&](const Event &event, double start, double end) {
        start = std::max(start, 0.0);
        if (end - start > near && start < to && end > from)
            out.push_back({start, end, Track{layer.id, channel(event.part)}, event.id, event.part});
    };
    if (!layer.loop) {
        for (const Event &event : layer.events) add(event, event.start, event.end());
        return out;
    }
    // The loop's repetitions over [from, to), each in step with where it
    // was recorded: the k-th starts k lengths from it, either way.
    const Span loop = *layer.loop;
    const double length = loop.length();
    if (length <= near) return out;
    const auto first = static_cast<long>(std::floor((from - loop.to) / length));
    const auto last = static_cast<long>(std::ceil((to - loop.from) / length));
    for (long k = first; k <= last; ++k) {
        const double offset = static_cast<double>(k) * length;
        for (const Event &event : layer.events) {
            const double start = std::max(event.start, loop.from), end = std::min(event.end(), loop.to);
            if (end - start > near) add(event, start + offset, end + offset);
        }
    }
    std::sort(out.begin(), out.end(), [](const Occurrence &a, const Occurrence &b) {
        return a.start != b.start ? a.start < b.start : a.id < b.id;
    });
    return out;
}

std::vector<Occurrence> Song::onsets(double from, double to, std::optional<int> skip, bool entering) const {
    std::vector<Occurrence> out;
    for (const Layer &layer : layers) {
        if (layer.isMuted || layer.id == skip) continue;
        for (Occurrence occurrence : heard(layer, from, to)) {
            if (occurrence.start >= from && occurrence.start < to) {
                out.push_back(occurrence);
            } else if (entering && occurrence.start < from && occurrence.end > from) {
                occurrence.start = from;
                out.push_back(occurrence);
            }
        }
    }
    std::stable_sort(out.begin(), out.end(), [](const Occurrence &a, const Occurrence &b) {
        return a.start != b.start ? a.start < b.start : a.track < b.track;
    });
    return out;
}

// MARK: – The edits

double nudgeReach(const Layer &layer, const std::set<int> &ids, double beats) {
    double lo = -std::numeric_limits<double>::infinity(), hi = std::numeric_limits<double>::infinity();
    for (const auto &[_, events] : channels(layer)) {
        for (size_t i = 0; i < events.size(); ++i) {
            if (!ids.contains(events[i].id)) continue;
            if (i == 0) lo = std::max(lo, -events[i].start);
            else if (!ids.contains(events[i - 1].id))
                lo = std::max(lo, events[i - 1].start + shortestEvent - events[i].start);
            if (i + 1 < events.size() && !ids.contains(events[i + 1].id))
                hi = std::min(hi, events[i + 1].start - shortestEvent - events[i].start);
        }
    }
    return std::clamp(beats, std::min(lo, 0.0), std::max(hi, 0.0));
}

Layer nudged(const Layer &layer, const std::set<int> &ids, double beats) {
    const double by = nudgeReach(layer, ids, beats);
    if (by == 0) return layer;
    return settled(layer, ids, [&](const Event &event) { return std::pair(event.start + by, event.end() + by); });
}

Layer quantized(const Layer &layer, const std::set<int> &ids, double step) {
    if (step <= 0) return layer;
    const auto line = [&](double beats) { return std::round(beats / step) * step; };
    return settled(layer, ids, [&](const Event &event) {
        const double start = line(event.start);
        return std::pair(start, std::max(line(event.end()), start + step));
    });
}

Layer rechorded(const Layer &layer, const std::set<int> &ids, const ChordPart &part) {
    Layer out = layer;
    for (Event &event : out.events)
        if (ids.contains(event.id) && channel(event.part) == part.voice) event.part = part;
    return out;
}

Layer looped(const Layer &layer, const std::set<int> &ids) {
    const auto span = layer.span(ids);
    if (!span) return layer;
    Layer out = layer;
    const double from = std::round(span->from);
    out.loop = Span{from, std::max(std::round(span->to), from + 1)};
    return out;
}

Layer erased(const Layer &layer, const std::set<int> &ids) {
    Layer out = layer;
    std::erase_if(out.events, [&](const Event &event) { return ids.contains(event.id); });
    return out;
}

Layer shifted(const Layer &layer, double beats) {
    Layer out = layer;
    for (Event &event : out.events) event.start += beats;
    if (out.loop) out.loop = Span{out.loop->from + beats, out.loop->to + beats};
    return out;
}

} // namespace perfecto::desk
