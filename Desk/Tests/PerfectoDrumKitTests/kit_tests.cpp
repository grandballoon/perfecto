// The drum kit's recordings: each the same every time, as long and as loud
// as it says, starting and ending quietly, and pitched where its drum is.

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>

#include "perfecto/drumkit/kit.hpp"

#include <algorithm>
#include <cmath>

using namespace perfecto::drumkit;

namespace {

constexpr double rate = 48000;

double loudest(const std::vector<float> &samples, size_t from, size_t to) {
    double most = 0;
    for (size_t i = from; i < std::min(to, samples.size()); ++i) most = std::max(most, double(std::abs(samples[i])));
    return most;
}

/// How often it crosses zero in its first `seconds`, a second: low for a
/// drum's thud, high for a cymbal's hiss.
double crossings(const std::vector<float> &samples, double seconds) {
    const size_t frames = std::min(samples.size(), size_t(seconds * rate));
    int count = 0;
    for (size_t i = 1; i < frames; ++i)
        if ((samples[i - 1] < 0) != (samples[i] < 0)) ++count;
    return count / seconds;
}

} // namespace

TEST_SUITE("Drum kit") {

TEST_CASE("each sample is the same every time it is rendered") {
    for (const Sample sample : allSamples) CHECK(render(sample, rate) == render(sample, rate));
}

TEST_CASE("each sample is as long and as loud as it says, and nothing is out of range") {
    for (const Sample sample : allSamples) {
        const auto samples = render(sample, rate);
        CAPTURE(name(sample));
        CHECK(samples.size() == size_t(std::ceil(length(sample) * rate)));
        CHECK(loudest(samples, 0, samples.size()) == doctest::Approx(peak(sample)).epsilon(1e-6));
        CHECK(std::all_of(samples.begin(), samples.end(), [](float x) { return std::isfinite(x); }));
    }
}

TEST_CASE("each sample starts without a step and dies away to nothing") {
    for (const Sample sample : allSamples) {
        const auto samples = render(sample, rate);
        CAPTURE(name(sample));
        CHECK(std::abs(samples.front()) < 0.05);
        CHECK(samples.back() == 0);
        // Its last tenth of a second is far quieter than its strike.
        CHECK(loudest(samples, samples.size() - size_t(0.1 * rate), samples.size()) < 0.1 * peak(sample));
        // And it strikes at once: its loudest is in its first 40 ms.
        CHECK(loudest(samples, 0, size_t(0.04 * rate)) == doctest::Approx(peak(sample)).epsilon(1e-6));
    }
}

TEST_CASE("the kick is lowest, the hat highest, and the snare and clap between") {
    const double kick = crossings(render(Sample::kick, rate), 0.2);
    const double snare = crossings(render(Sample::snare, rate), 0.2);
    const double clap = crossings(render(Sample::clap, rate), 0.2);
    const double hat = crossings(render(Sample::hat, rate), 0.2);
    CHECK(kick < 400);
    CHECK(kick < snare);
    CHECK(kick < clap);
    CHECK(snare < hat);
    CHECK(clap < hat);
    CHECK(hat > 8000);
}

TEST_CASE("at another rate a sample lasts as long") {
    for (const Sample sample : allSamples)
        CHECK(render(sample, 44100).size() == size_t(std::ceil(length(sample) * 44100)));
}

} // TEST_SUITE
