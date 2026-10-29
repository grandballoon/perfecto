#ifndef PERFECTO_THEORY_CHORD_SHAPE_HPP
#define PERFECTO_THEORY_CHORD_SHAPE_HPP

#include <string>
#include <vector>

namespace perfecto::theory {

/// One chord shape: the intervals that sound plus the quality name shown
/// for it, made together so the name cannot drift from the notes.
struct ChordShape {
    std::vector<int> intervals;
    std::string name;

    bool operator==(const ChordShape &) const = default;
};

/// The natural triad quality of a scale degree.
enum class TriadBase { major, minor, dim };

} // namespace perfecto::theory

#endif
