#include "anim.h"

#include <math.h>
#include <string.h>

const Geometry GEOMETRY_DOTS = {.dot = 10, .pill = 28, .height = 10, .gap = 6};
const Geometry GEOMETRY_NUMBERS = {.dot = 18, .pill = 30, .height = 18, .gap = 2};

/* One axis of a cubic bezier through (0,0), (p1,_), (p2,_), (1,1). */
static double bez(double p1, double p2, double t)
{
    double u = 1 - t;
    return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t;
}

double curve_eval(Curve c, double x)
{
    if (x <= 0)
        return 0;
    if (x >= 1)
        return 1;
    double x1, y1, x2, y2;
    if (c == CURVE_STANDARD) {
        x1 = 0.2, y1 = 0, x2 = 0, y2 = 1;
    } else {
        x1 = 0, y1 = 0, x2 = 0.2, y2 = 1;
    }
    /* x(t) is monotonic for control x in [0,1]: bisection always converges. */
    double lo = 0, hi = 1, t = x;
    for (int i = 0; i < 64; i++) {
        t = (lo + hi) / 2;
        if (bez(x1, x2, t) < x)
            lo = t;
        else
            hi = t;
    }
    return bez(y1, y2, t);
}

void group_init(Group *g, int64_t duration_us, Curve curve, const double initial[WS_COUNT + 1])
{
    memset(g, 0, sizeof *g);
    g->duration_us = duration_us;
    g->curve = curve;
    for (int i = 1; i <= WS_COUNT; i++)
        g->from[i] = g->to[i] = g->value[i] = initial[i];
}

void group_retarget(Group *g, const double target[WS_COUNT + 1])
{
    bool same = true;
    for (int i = 1; i <= WS_COUNT; i++)
        if (g->to[i] != target[i])
            same = false;
    if (same)
        return;
    bool moving = false;
    for (int i = 1; i <= WS_COUNT; i++) {
        g->from[i] = g->value[i];
        g->to[i] = target[i];
        if (g->from[i] != g->to[i])
            moving = true;
    }
    g->started = false;
    g->running = moving;
}

bool group_tick(Group *g, int64_t now_us)
{
    if (!g->running)
        return false;
    if (!g->started) {
        g->start_us = now_us;
        g->started = true;
    }
    double x = g->duration_us > 0 ? (double)(now_us - g->start_us) / (double)g->duration_us : 1;
    if (x >= 1) {
        memcpy(g->value, g->to, sizeof g->value);
        g->running = false;
        return false;
    }
    double e = curve_eval(g->curve, x);
    for (int i = 1; i <= WS_COUNT; i++)
        g->value[i] = g->from[i] + (g->to[i] - g->from[i]) * e;
    return true;
}

void layout_compute(const Geometry *g, const double shape[WS_COUNT + 1],
                    const double presence[WS_COUNT + 1], Layout *out)
{
    double x = 0;
    out->x[0] = out->w[0] = 0;
    for (int i = 1; i <= WS_COUNT; i++) {
        double p = presence[i];
        if (i > 1)
            x += g->gap * p;
        out->x[i] = x;
        out->w[i] = p * (g->dot + (g->pill - g->dot) * shape[i]);
        x += out->w[i];
    }
    out->total = x;
}
