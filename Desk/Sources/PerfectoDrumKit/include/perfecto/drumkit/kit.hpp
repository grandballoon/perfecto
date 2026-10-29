// The desk's drum kit, made in code: each drum is rendered here as a
// recording, once, and the kernel plays the recordings as it plays a mic
// sample (a capture, through a sampled patch), so the drums are mixed,
// limited and timed as every other note is. Nothing is downloaded: every
// sound is the sum of a few oscillators, filters and envelopes, from a
// noise whose seed is fixed, so a kit rendered twice is the same to the bit.
//
// Four recordings make the kit, as the kernel has four captures: the kick
// (played higher, the toms), the snare, the hi-hat (shut short by its
// patch, the closed hat; let ring, the open one) and the clap.

#ifndef PERFECTO_DRUMKIT_KIT_HPP
#define PERFECTO_DRUMKIT_KIT_HPP

#include <array>
#include <string>
#include <vector>

namespace perfecto::drumkit {

enum class Sample { kick, snare, hat, clap };

inline constexpr std::array<Sample, 4> allSamples = {Sample::kick, Sample::snare, Sample::hat, Sample::clap};

std::string name(Sample sample);

/// How long `sample` lasts, in seconds.
double length(Sample sample);

/// The loudest `sample` is, 0 to 1: what it is brought to when rendered.
double peak(Sample sample);

/// `sample` rendered at `rate` frames a second: one channel, starting at
/// once and dying away to silence by its end.
std::vector<float> render(Sample sample, double rate);

} // namespace perfecto::drumkit

#endif
