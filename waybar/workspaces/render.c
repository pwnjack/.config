#include "render.h"

#include <math.h>
#include <pango/pangocairo.h>
#include <stdio.h>

static Rgba mix(Rgba a, Rgba b, double k)
{
    /* Premultiplied: a transparent colour carries no hue, so an empty slot
     * (no fill) fading toward the accent becomes the accent, not a blend. */
    double al = a.a + (b.a - a.a) * k;
    if (al <= 0)
        return (Rgba){b.r, b.g, b.b, 0};
    double pr = a.r * a.a * (1 - k) + b.r * b.a * k;
    double pg = a.g * a.a * (1 - k) + b.g * b.a * k;
    double pb = a.b * a.a * (1 - k) + b.b * b.a * k;
    return (Rgba){pr / al, pg / al, pb / al, al};
}

/* Toward white by k, alpha kept: the active pill's hover. */
static Rgba lighten(Rgba c, double k)
{
    return (Rgba){c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, c.a};
}

static void set(cairo_t *cr, Rgba c, double alpha)
{
    cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a * alpha);
}

/* A capsule: ends are half-circles of the smaller side. */
static void capsule(cairo_t *cr, double x, double y, double w, double h)
{
    double r = fmin(w, h) / 2;
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + h / 2, r, -M_PI / 2, M_PI / 2);
    cairo_arc(cr, x + r, y + h / 2, r, M_PI / 2, 3 * M_PI / 2);
    cairo_close_path(cr);
}

/* Every amount and alpha is a fraction: out-of-range values clamp, NaN is 0. */
static double clamp01(double v)
{
    if (!(v > 0))
        return 0;
    return v > 1 ? 1 : v;
}

/* Each slot is one layer (fill, then its ring written over it with SOURCE, so
 * the rim is exactly the ring colour) painted once at presence: no edge is
 * ever composited twice. */
static void draw_dot(cairo_t *cr, const Theme *t, double x, double y, double w, double h,
                     double s, double f, double hv, double alpha)
{
    double c = s;               /* A1: the accent mix is the shape amount */
    double tint = hv * (1 - c); /* hover tints the resting look */

    Rgba fill = t->fg;
    fill.a *= f; /* empty: no fill; occupied: foreground */
    Rgba hovered = t->accent;
    hovered.a *= fmax(f, 0.35);
    fill = mix(fill, hovered, tint);
    fill = mix(fill, t->accent, c);
    fill = lighten(fill, 0.15 * hv * c);

    Rgba ring = t->fg;
    ring.a *= 0.6 + 0.4 * f; /* an occupied ring is the disc's own edge */
    ring = mix(ring, t->accent, fmax(tint, c));
    ring = lighten(ring, 0.15 * hv * c);

    cairo_push_group(cr);
    if (fill.a > 0) {
        capsule(cr, x, y, w, h);
        set(cr, fill, 1);
        cairo_fill(cr);
    }
    if (w > 1 && h > 1) {
        capsule(cr, x + 0.5, y + 0.5, w - 1, h - 1);
        cairo_set_line_width(cr, 1);
        cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
        set(cr, ring, 1);
        cairo_stroke(cr);
    }
    cairo_pop_group_to_source(cr);
    cairo_paint_with_alpha(cr, alpha);
}

/* The slot is drawn at full size (w x h) and scaled about its centre by
 * `alpha` (presence), so the digit can never outgrow a shrinking box. */
static void draw_number(cairo_t *cr, const Theme *t, int slot, double cx, double cy, double w,
                        double h, double s, double f, double hv, double alpha)
{
    double c = s;
    double tint = hv * (1 - c);

    Rgba box = t->accent;
    box.a *= c + 0.35 * tint;
    box = lighten(box, 0.15 * hv * c);

    /* Empty numbers are dimmed (no hollow form); the active one is full. */
    double text_alpha = 0.4 + 0.6 * f;
    text_alpha += (1 - text_alpha) * c;

    PangoLayout *layout = pango_cairo_create_layout(cr);
    PangoFontDescription *font = t->font ? pango_font_description_copy(t->font)
                                         : pango_font_description_from_string("Sans");
    pango_font_description_set_absolute_size(font, 12 * PANGO_SCALE);
    pango_font_description_set_weight(font, PANGO_WEIGHT_BOLD);
    pango_layout_set_font_description(layout, font);
    char digits[12]; /* any int fits: -Wformat-truncation at -O1 */
    snprintf(digits, sizeof digits, "%d", slot);
    pango_layout_set_text(layout, digits, -1);
    PangoRectangle ink, logical;
    pango_layout_get_pixel_extents(layout, &ink, &logical);

    double ox = -logical.width / 2.0, oy = -logical.height / 2.0;
    if (alpha >= 1) {
        /* Whole pixels: text stays crisp; at 144 Hz a 1 px step is invisible. */
        ox = round(cx + ox) - cx;
        oy = round(cy + oy) - cy;
    }

    cairo_push_group(cr);
    cairo_save(cr);
    cairo_translate(cr, cx, cy);
    cairo_scale(cr, alpha, alpha);
    if (box.a > 0) {
        capsule(cr, -w / 2, -h / 2, w, h);
        set(cr, box, 1);
        cairo_fill(cr);
    }
    capsule(cr, -w / 2, -h / 2, w, h);
    cairo_clip(cr);
    cairo_move_to(cr, ox, oy);
    set(cr, t->fg, text_alpha);
    pango_cairo_show_layout(cr, layout);
    cairo_restore(cr);
    cairo_pop_group_to_source(cr);
    cairo_paint_with_alpha(cr, alpha);

    pango_font_description_free(font);
    g_object_unref(layout);
}

void render_row(cairo_t *cr, const Theme *t, const Geometry *g, const Layout *l,
                const Amounts *a, double x0, double height)
{
    Theme th = *t; /* alphas are fractions */
    th.fg.a = clamp01(th.fg.a);
    th.accent.a = clamp01(th.accent.a);
    x0 = round(x0);

    cairo_save(cr);
    cairo_new_path(cr);
    double top = round((height - g->height) / 2);
    for (int i = 1; i <= WS_COUNT; i++) {
        double p = clamp01(a->presence[i]);
        if (!isfinite(l->x[i]) || !isfinite(l->w[i]))
            continue; /* a NaN in cairo_translate poisons the caller's context for good */
        if (p <= 0.001 || l->w[i] <= 0)
            continue;
        double s = clamp01(a->shape[i]), f = clamp01(a->fill[i]), hv = clamp01(a->hover[i]);
        double x = x0 + l->x[i];
        cairo_save(cr);
        /* Slot-sized layer whatever the caller's clip; the SOURCE ring stays inside. */
        cairo_rectangle(cr, x - 1, top - 1, l->w[i] + 2, g->height + 2);
        cairo_clip(cr);
        if (th.numbers) {
            double w = l->w[i] / p; /* layout width carries presence */
            draw_number(cr, &th, i, x + l->w[i] / 2, top + g->height / 2.0, w, g->height, s, f,
                        hv, p);
        } else {
            double h = g->height * p; /* grows in uniformly from its centre */
            draw_dot(cr, &th, x, top + (g->height - h) / 2, l->w[i], h, s, f, hv, p);
        }
        cairo_restore(cr);
    }
    cairo_restore(cr);
    cairo_new_path(cr);
}
