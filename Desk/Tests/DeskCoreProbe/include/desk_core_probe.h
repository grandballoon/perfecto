// The C++ desk core (PerfectoDeskCore) through plain C, for the parity
// tests, which play it and the Swift one (DeskCore) with the same frames and
// compare what each does. What a desk does is written as text in one format
// both sides write (`DeskParityText` in the tests, `probe.cpp` here), so a
// difference is a difference of text. Strings are UTF-8, written
// NUL-terminated into `out`; each call returns the length the whole text
// needs, so a caller can try again with more room.

#ifndef DESK_CORE_PROBE_H
#define DESK_CORE_PROBE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct pdp_desk pdp_desk;

/// What a controller is doing: as `GamepadFrame`, its buttons a mask of
/// `PadButton`'s cases in order.
typedef struct {
    double time;
    double leftX, leftY, rightX, rightY;
    double leftTrigger, rightTrigger;
    int buttons;
} pdp_frame;

/// A desk with the parity tests' catalog (`DeskParityText.catalog`) and
/// settings as they start.
pdp_desk *pdp_desk_new(void);
void pdp_desk_free(pdp_desk *desk);

/// The effects of one frame, one a line.
int pdp_desk_step(pdp_desk *desk, const pdp_frame *frame, char *out, int capacity);
/// `Desk.choose`, by `LayoutKind`'s index; `toggleMenu`; `letGo`.
int pdp_desk_choose(pdp_desk *desk, int layout, char *out, int capacity);
int pdp_desk_toggle_menu(pdp_desk *desk, char *out, int capacity);
int pdp_desk_let_go(pdp_desk *desk, char *out, int capacity);

/// What the desk shows: the layout, the legend, the chord to pin, the
/// menu and every menu row's value, and the settings.
int pdp_desk_shown(pdp_desk *desk, char *out, int capacity);

#ifdef __cplusplus
}
#endif

#endif
