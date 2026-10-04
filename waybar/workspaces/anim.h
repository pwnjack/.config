/* Animation core. Every per-slot quantity (shape, presence, fill, hover)
 * lives in a Group: all of a group's slots move on ONE clock and ONE curve,
 * which is what keeps a switch exact — the leaving and arriving pills are
 * the same group, so their widths always sum to the same total. "Exact" means
 * to within floating-point rounding (~1e-14 px), far below anything cairo can
 * render; it does not mean bit-identical. */
#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "model.h"

typedef enum {
    CURVE_STANDARD, /* cubic-bezier(0.2, 0, 0, 1): shape and presence */
    CURVE_EASE_OUT, /* cubic-bezier(0, 0, 0.2, 1): colour fades */
} Curve;

double curve_eval(Curve c, double x);

typedef struct {
    double from[WS_COUNT + 1], to[WS_COUNT + 1], value[WS_COUNT + 1];
    int64_t start_us; /* meaningful only once `started` */
    int64_t duration_us;
    Curve curve;
    bool started; /* false until the first tick after init/retarget sets start_us */
    bool running;
} Group;

/* At rest on `initial`. Slot 0 is unused and always stays 0. */
void group_init(Group *g, int64_t duration_us, Curve curve, const double initial[WS_COUNT + 1]);
/* Every slot animates from its current value to `target` on a restarted clock
 * (the next tick starts it). A no-op when slots 1..WS_COUNT of `target` compare
 * equal (==, so -0.0 equals 0.0) to the current target. Slot 0 is ignored. */
void group_retarget(Group *g, const double target[WS_COUNT + 1]);
/* Advance to now_us (any int64 clock; negative times are fine). Returns
 * whether the group is still moving AFTER this tick. The tick that settles the
 * group returns false but has just snapped every value to its target, so
 * callers must redraw after every tick, including one that returns false, and
 * must evaluate every group's tick: combine results with `|` or
 * `x = group_tick(...) || x`, never `group_tick(a) || group_tick(b)`, which
 * short-circuits and leaves b untouched. */
bool group_tick(Group *g, int64_t now_us);

typedef struct {
    int dot;    /* resting slot width */
    int pill;   /* active slot width */
    int height; /* slot height */
    int gap;    /* space between slots */
} Geometry;

extern const Geometry GEOMETRY_DOTS;    /* 10, 28, 10, 6 */
extern const Geometry GEOMETRY_NUMBERS; /* 18, 30, 18, 2 */

typedef struct {
    double x[WS_COUNT + 1], w[WS_COUNT + 1]; /* relative to the row's left edge */
    double total;
} Layout;

/* width_i = presence_i * (dot + (pill - dot) * shape_i); the gap before slot
 * i > 1 is gap * presence_i, so an absent slot takes no space at all. */
void layout_compute(const Geometry *g, const double shape[WS_COUNT + 1],
                    const double presence[WS_COUNT + 1], Layout *out);
