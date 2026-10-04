/* Draws the workspace row. No GTK: everything comes in through Theme,
 * Geometry, Layout and Amounts, so it is tested on an image surface. */
#pragma once
#include <cairo.h>
#include <pango/pango.h>
#include <stdbool.h>

#include "anim.h"

typedef struct {
    double r, g, b, a;
} Rgba;

typedef struct {
    Rgba fg;                    /* #workspaces color */
    Rgba accent;                /* #workspaces.active color */
    PangoFontDescription *font; /* numbers family; NULL: "Sans" */
    bool numbers;
} Theme;

typedef struct {
    const double *shape;    /* 1 = active pill (also the accent mix, A1) */
    const double *presence; /* 1 = slot shown, 0 = collapsed */
    const double *fill;     /* 1 = has windows (disc), 0 = empty (ring) */
    const double *hover;    /* 1 = under the pointer */
} Amounts;

/* The row's left edge is at x0 (rounded to a whole pixel); slots are centred
 * vertically in height. Amounts and theme alphas clamp to [0, 1], NaN is 0.
 * Each slot is one layer painted once at its presence. The caller's cairo
 * state (path, current point, line width, operator) is left as found. */
void render_row(cairo_t *cr, const Theme *t, const Geometry *g, const Layout *l,
                const Amounts *a, double x0, double height);
