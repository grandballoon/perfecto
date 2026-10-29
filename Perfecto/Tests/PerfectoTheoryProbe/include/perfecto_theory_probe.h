// The C++ theory core (PerfectoTheory) through plain C, for the parity
// tests, which compare it with the Swift core (MusicTheoryCore) over whole
// spaces of inputs. Every enum is passed as its index in the Swift type's
// `allCases` (the C++ `all...` arrays are in the same order); a degree is
// 0 for I to 6 for vii°. Strings are written NUL-terminated into `out`.

#ifndef PERFECTO_THEORY_PROBE_H
#define PERFECTO_THEORY_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { PTP_JOYSTICK = 0, PTP_GRID = 1, PTP_MARKED = 2, PTP_BUILT = 3, PTP_TONES = 4 };

/// A chord color.
typedef struct {
    int kind;
    /// Joystick: the mode and the direction. Grid and marked: the stack
    /// height and the mode, -1 for the degree's own. Built: the type, -1 for
    /// none, and the extensions as a mask.
    int a, b;
    /// Marked: each chord tone's move (-1, 0 or +1), and the tones whose
    /// leaving out is turned round, as a mask.
    int moves[6];
    int skips;
    /// Tones: the pitch classes above the root, as a mask.
    int tones;
} ptp_color;

/// `computeVoicing`'s notes, written to `notes` (room for 32); the count.
int ptp_voicing(int root, int scale, int degree, const ptp_color *color, int inversion, int octave,
                int voiceLeading, const int *previous, int previousCount, int *notes);

void ptp_chord_label(int root, int scale, int degree, const ptp_color *color, char *out, int capacity);
void ptp_color_action_label(const ptp_color *color, char *out, int capacity);
void ptp_degree_numeral(int root, int scale, int degree, char *out, int capacity);

/// A chord's tones, as a mask of pitch classes: its name, and whether it is
/// another chord over its root (1, with that chord's root and quality).
int ptp_chord_tones(int toneMask, char *name, int nameCapacity, int *slashRoot, char *slashQuality,
                    int qualityCapacity);

/// The step compass's step at a place (kind, rank) from `toneMask`: 1 and
/// the step, or 0 if the place has none. `from` and `to` are -1 for none.
int ptp_step(int root, int scale, int degree, int toneMask, int ranking, int kind, int rank, int *madeMask,
             int *from, int *to, int *fit, char *editName, int capacity);

/// A walk of places (each kind × 2 + rank − 1), as a mask of pitch classes.
int ptp_walk(int root, int scale, int degree, int ranking, const int *places, int count);

/// The key and degree a root plays in a key.
void ptp_key_degree(int root, int scale, int note, int *keyRoot, int *keyScale, int *degree);

int ptp_color_steps(const int *a, int aCount, const int *b, int bCount);

/// The chord grid's rows (room for 7), as mode indices; the count.
int ptp_grid_rows(int root, int scale, int degree, int *modes);
int ptp_ring_turn(int arrangement, int root, int scale, int degree);

/// A ChordLink chord frame (room for 64 bytes); the count.
int ptp_chord_wire(int root, int scale, int degree, int mode, int direction, int inversion, int octave,
                   int voiceLeading, const int *notes, int count, int bass, uint8_t *out);

/// What a frame states for a chord rolled to `inversion`: 1, or 0 if none.
int ptp_stated(int inversion, int octave, int root, int scale, int degree, const ptp_color *color,
               int *statedInversion, int *statedOctave);

void ptp_midi_key_signature(int root, int scale, int *sharps, int *isMinor);

#ifdef __cplusplus
}
#endif

#endif
