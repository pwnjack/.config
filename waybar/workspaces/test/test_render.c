#include <cairo.h>
#include <stdint.h>

#include "check.h"
#include "../render.h"

static const Rgba WHITE = {1, 1, 1, 1}, RED = {1, 0, 0, 1};

typedef struct {
    double shape[WS_COUNT + 1], presence[WS_COUNT + 1], fill[WS_COUNT + 1], hover[WS_COUNT + 1];
} Amt;

static void rest(Amt *m, int active)
{
    for (int i = 0; i <= WS_COUNT; i++) {
        m->shape[i] = i == active;
        m->presence[i] = i >= 1 && i <= WS_ALWAYS;
        m->fill[i] = 0;
        m->hover[i] = 0;
    }
}

/* Unpremultiplied channel values at (x, y). */
static void px(cairo_surface_t *s, int x, int y, int *r, int *g, int *b, int *a)
{
    cairo_surface_flush(s);
    uint32_t v = *(uint32_t *)(cairo_image_surface_get_data(s) + y * cairo_image_surface_get_stride(s) + x * 4);
    *a = v >> 24;
    int pr = (v >> 16) & 0xff, pg = (v >> 8) & 0xff, pb = v & 0xff;
    *r = *a ? pr * 255 / *a : 0;
    *g = *a ? pg * 255 / *a : 0;
    *b = *a ? pb * 255 / *a : 0;
}

static cairo_surface_t *draw(const Theme *t, const Geometry *g, Amt *m)
{
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 120, 40);
    cairo_t *cr = cairo_create(s);
    Layout l;
    layout_compute(g, m->shape, m->presence, &l);
    Amounts a = {m->shape, m->presence, m->fill, m->hover};
    render_row(cr, t, g, &l, &a, 0, 40);
    cairo_destroy(cr);
    return s;
}

static void test_dots_rest(void)
{
    Theme t = {WHITE, RED, NULL, false};
    Amt m;
    rest(&m, 2);
    m.fill[1] = 1;
    cairo_surface_t *s = draw(&t, &GEOMETRY_DOTS, &m);
    int r, g, b, a;

    px(s, 5, 20, &r, &g, &b, &a);
    CHECK(a == 255 && r == 255 && g == 255, "occupied slot 1 is an opaque disc (a=%d)", a);
    px(s, 30, 20, &r, &g, &b, &a);
    CHECK(a == 255 && r == 255 && g == 0, "pill centre is opaque accent (a=%d r=%d g=%d)", a, r, g);
    px(s, 30, 15, &r, &g, &b, &a);
    CHECK(a == 255 && r == 255 && g == 0, "pill top row is crisp and opaque (a=%d)", a);
    px(s, 30, 14, &r, &g, &b, &a);
    CHECK(a == 0, "nothing above the pill (a=%d)", a);
    px(s, 15, 20, &r, &g, &b, &a);
    CHECK(a == 0, "the gap before the pill is empty (a=%d)", a);
    px(s, 44, 20, &r, &g, &b, &a);
    CHECK(a == 0, "the gap after the pill is empty (a=%d)", a);
    px(s, 50, 20, &r, &g, &b, &a);
    CHECK(a >= 140 && a <= 158, "the empty ring edge is ~60 %% foreground (a=%d)", a);
    px(s, 55, 20, &r, &g, &b, &a);
    CHECK(a == 0, "the empty ring is hollow (a=%d)", a);
    cairo_surface_destroy(s);
}

static void test_a1_colour_follows_shape(void)
{
    Theme t = {WHITE, RED, NULL, false};
    Amt m;
    rest(&m, 0);
    m.shape[2] = 0.5; /* halfway through growing: 19 px wide at x = 16 */
    cairo_surface_t *s = draw(&t, &GEOMETRY_DOTS, &m);
    int r, g, b, a;
    px(s, 25, 20, &r, &g, &b, &a);
    CHECK(a >= 125 && a <= 131 && r == 255 && g == 0,
          "an empty slot halfway to active is accent at ~50 %% (a=%d r=%d g=%d)", a, r, g);
    cairo_surface_destroy(s);
}

static int region_alpha(cairo_surface_t *s, int x0, int x1, int y0, int y1)
{
    int r, g, b, a, any = 0;
    for (int x = x0; x < x1; x++)
        for (int y = y0; y < y1; y++) {
            px(s, x, y, &r, &g, &b, &a);
            if (a > any)
                any = a;
        }
    return any;
}

static void test_presence(void)
{
    Theme t = {WHITE, RED, NULL, false};
    Amt m, n;
    rest(&m, 1);
    m.fill[3] = 1;
    m.presence[3] = 0;
    rest(&n, 1);
    n.presence[3] = 0;
    cairo_surface_t *s = draw(&t, &GEOMETRY_DOTS, &m), *e = draw(&t, &GEOMETRY_DOTS, &n);
    int same = 1;
    for (int x = 0; x < 120; x++)
        for (int y = 0; y < 40; y++) {
            int r, g, b, a, r2, g2, b2, a2;
            px(s, x, y, &r, &g, &b, &a);
            px(e, x, y, &r2, &g2, &b2, &a2);
            same &= a == a2;
        }
    CHECK(same, "a present slot at presence 0 draws nothing, whatever its fill");
    CHECK(region_alpha(s, 44, 50, 0, 40) == 0, "its rest area is empty");
    cairo_surface_destroy(s);
    cairo_surface_destroy(e);

    rest(&m, 0);
    m.fill[3] = 1;
    m.presence[3] = 0.5; /* slot 3 is a 5 px disc at x 29..34, centre (31.5, 20) */
    s = draw(&t, &GEOMETRY_DOTS, &m);
    int r, g, b, a, ca, ea;
    px(s, 31, 20, &r, &g, &b, &a);
    ca = a;
    CHECK(ca >= 125 && ca <= 131, "a half-present occupied slot is ~50 %% (a=%d)", ca);
    int edges[][2] = {{30, 20}, {32, 20}, {33, 20}, {31, 18}, {31, 21}};
    for (unsigned i = 0; i < sizeof edges / sizeof *edges; i++) {
        px(s, edges[i][0], edges[i][1], &r, &g, &b, &ea);
        CHECK(ea <= ca + 3, "no bright rim during a presence fade (%d,%d a=%d vs %d)",
              edges[i][0], edges[i][1], ea, ca);
    }
    cairo_surface_destroy(s);
}

static void test_half_active_ring(void)
{
    Theme t = {WHITE, RED, NULL, false};
    Amt m;
    rest(&m, 0);
    m.shape[2] = 0.5; /* ring mixes foreground 0.6 toward accent 1.0: a = 204 */
    cairo_surface_t *s = draw(&t, &GEOMETRY_DOTS, &m);
    int r, g, b, a;
    px(s, 25, 15, &r, &g, &b, &a);
    CHECK(a <= 206 && a >= 200, "the rim is the ring colour alone (a=%d)", a);
    px(s, 25, 20, &r, &g, &b, &a);
    CHECK(a >= 125 && a <= 131 && r == 255 && g == 0, "the interior stays accent at ~50 %% (a=%d)", a);
    cairo_surface_destroy(s);
}

static void test_hover(void)
{
    Theme t = {WHITE, RED, NULL, false};
    Amt m;
    int r, g, b, a;
    rest(&m, 0);
    m.hover[3] = 1; /* empty: a 10 px ring at x 32..42 */
    cairo_surface_t *s = draw(&t, &GEOMETRY_DOTS, &m);
    px(s, 37, 20, &r, &g, &b, &a);
    CHECK(a >= 85 && a <= 93 && r == 255 && g == 0, "hovered empty slot is accent at 35 %% (a=%d g=%d)", a, g);
    cairo_surface_destroy(s);

    m.fill[3] = 1;
    s = draw(&t, &GEOMETRY_DOTS, &m);
    px(s, 37, 20, &r, &g, &b, &a);
    CHECK(a == 255 && r == 255 && g == 0 && b == 0, "hovered occupied slot is opaque accent (a=%d g=%d)", a, g);
    cairo_surface_destroy(s);

    rest(&m, 3);
    m.hover[3] = 1; /* the active pill at x 32..60 */
    s = draw(&t, &GEOMETRY_DOTS, &m);
    px(s, 46, 20, &r, &g, &b, &a);
    CHECK(a == 255 && r == 255 && g > 0 && b > 0, "hovered active pill is lighter than the accent (g=%d b=%d)", g, b);
    cairo_surface_destroy(s);
}

static void test_clamping(void)
{
    Theme t = {{1, 1, 1, 1.5}, {1, 0, 0, 1.5}, NULL, false};
    Amt m;
    rest(&m, 2);
    cairo_surface_t *s = draw(&t, &GEOMETRY_DOTS, &m);
    int r, g, b, a;
    px(s, 55, 15, &r, &g, &b, &a); /* top of slot 3's ring (a circle: ~95 %% coverage) */
    cairo_surface_destroy(s);
    Theme one = {WHITE, RED, NULL, false};
    cairo_surface_t *s1 = draw(&one, &GEOMETRY_DOTS, &m);
    int a1;
    px(s1, 55, 15, &r, &g, &b, &a1);
    cairo_surface_destroy(s1);
    CHECK(a == a1 && a >= 140 && a <= 157, "theme alpha 1.5 clamps: the empty ring reads 0.6, not 0.9 (a=%d vs %d)", a, a1);
    s = draw(&t, &GEOMETRY_DOTS, &m);
    px(s, 50, 20, &r, &g, &b, &a);
    CHECK(a <= 157, "the ring's left end stays at ~0.6 (a=%d)", a);
    cairo_surface_destroy(s);

    /* NaN amounts after the layout is computed from sane ones. */
    Theme u = {WHITE, RED, NULL, false};
    for (int numbers = 0; numbers < 2; numbers++) {
        u.numbers = numbers;
        const Geometry *gm = numbers ? &GEOMETRY_NUMBERS : &GEOMETRY_DOTS;
        rest(&m, 2);
        Layout l;
        layout_compute(gm, m.shape, m.presence, &l);
        m.shape[3] = m.fill[3] = m.hover[3] = NAN;
        m.presence[4] = NAN;
        m.shape[5] = 7;
        m.hover[5] = -3;
        s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 120, 40);
        cairo_t *cr = cairo_create(s);
        Amounts am = {m.shape, m.presence, m.fill, m.hover};
        render_row(cr, &u, gm, &l, &am, 0, 40);
        cairo_destroy(cr);
        CHECK(region_alpha(s, 0, 120, 0, 40) > 0, "NaN amounts render without crashing (numbers=%d)", numbers);
        cairo_surface_destroy(s);
    }
}

/* NaN in the amounts BEFORE layout_compute, so the layout itself carries it. */
static void test_nan_layout(void)
{
    for (int numbers = 0; numbers < 2; numbers++) {
        Theme t = {WHITE, RED, NULL, numbers};
        const Geometry *gm = numbers ? &GEOMETRY_NUMBERS : &GEOMETRY_DOTS;
        Amt m;
        rest(&m, 2);
        m.fill[1] = m.fill[2] = 1;
        m.shape[3] = m.presence[3] = NAN;
        cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 120, 40);
        cairo_t *cr = cairo_create(s);
        Layout l;
        layout_compute(gm, m.shape, m.presence, &l);
        Amounts am = {m.shape, m.presence, m.fill, m.hover};
        render_row(cr, &t, gm, &l, &am, 0, 40);
        CHECK(cairo_status(cr) == CAIRO_STATUS_SUCCESS, "a NaN layout leaves the cairo context valid (numbers=%d)", numbers);
        CHECK(region_alpha(s, 0, 30, 0, 40) > 0, "slots 1-2 still draw beside a NaN slot (numbers=%d)", numbers);
        cairo_destroy(cr);
        cairo_surface_destroy(s);
    }
}

static void test_state_kept(void)
{
    Theme t = {WHITE, RED, NULL, false};
    Amt m;
    rest(&m, 2);
    Layout l;
    layout_compute(&GEOMETRY_DOTS, m.shape, m.presence, &l);
    Amounts am = {m.shape, m.presence, m.fill, m.hover};
    for (int numbers = 0; numbers < 2; numbers++) {
        t.numbers = numbers;
        cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 120, 40);
        cairo_t *cr = cairo_create(s);
        cairo_set_line_width(cr, 3.5);
        cairo_move_to(cr, 5, 5);
        render_row(cr, &t, numbers ? &GEOMETRY_NUMBERS : &GEOMETRY_DOTS, &l, &am, 0, 40);
        CHECK(!cairo_has_current_point(cr), "no current point leaks out (numbers=%d)", numbers);
        CHECK(cairo_get_line_width(cr) == 3.5, "line width is restored (numbers=%d)", numbers);
        CHECK(cairo_get_operator(cr) == CAIRO_OPERATOR_OVER, "operator is restored (numbers=%d)", numbers);
        cairo_destroy(cr);
        cairo_surface_destroy(s);
    }
}

static void test_numbers(void)
{
    Theme t = {WHITE, RED, NULL, true};
    Amt m;
    rest(&m, 2);
    m.fill[1] = 1;
    cairo_surface_t *s = draw(&t, &GEOMETRY_NUMBERS, &m);
    int r, g, b, a, ink = 0;
    for (int x = 0; x < 18; x++)
        for (int y = 11; y < 29; y++) {
            px(s, x, y, &r, &g, &b, &a);
            ink |= a;
        }
    CHECK(ink > 0, "slot 1 draws its digit");
    px(s, 44, 20, &r, &g, &b, &a); /* inside the active box's right end, clear of the digit */
    CHECK(a == 255 && r == 255 && g == 0, "the active number sits in an opaque accent box (a=%d)", a);
    cairo_surface_destroy(s);
}

static void test_numbers_alpha(void)
{
    Theme t = {WHITE, RED, NULL, true};
    Amt m;
    rest(&m, 0);
    cairo_surface_t *s = draw(&t, &GEOMETRY_NUMBERS, &m);
    int top = region_alpha(s, 0, 18, 11, 29);
    CHECK(top >= 96 && top <= 108, "an empty number's digit peaks at 40 %% (a=%d)", top);
    cairo_surface_destroy(s);

    m.fill[1] = 1;
    s = draw(&t, &GEOMETRY_NUMBERS, &m);
    top = region_alpha(s, 0, 18, 11, 29);
    CHECK(top >= 250, "an occupied number's digit is solid (a=%d)", top);
    cairo_surface_destroy(s);

    /* Slot 3 at presence 0.5 is a 9x9 box at x 39..48, y 15.5..24.5. */
    rest(&m, 0);
    m.fill[3] = 1;
    m.presence[3] = 0.5;
    s = draw(&t, &GEOMETRY_NUMBERS, &m);
    CHECK(region_alpha(s, 39, 48, 15, 25) > 0, "the half-present number still draws");
    CHECK(region_alpha(s, 49, 50, 0, 40) == 0, "nothing right of the scaled box");
    CHECK(region_alpha(s, 38, 39, 14, 26) == 0, "nothing left of the scaled box");
    CHECK(region_alpha(s, 39, 49, 0, 15) == 0, "nothing above the scaled box");
    CHECK(region_alpha(s, 39, 49, 25, 40) == 0, "nothing below the scaled box");
    cairo_surface_destroy(s);
}

/* Bounding box of foreground (white, alpha > 32) pixels; false if none. */
static int ink_box(cairo_surface_t *s, int *w, int *h)
{
    int x0 = 999, x1 = -1, y0 = 999, y1 = -1, r, g, b, a;
    for (int x = 0; x < 120; x++)
        for (int y = 0; y < 40; y++) {
            px(s, x, y, &r, &g, &b, &a);
            if (a > 32 && r > 200 && g > 200 && b > 200) {
                x0 = x < x0 ? x : x0;
                x1 = x > x1 ? x : x1;
                y0 = y < y0 ? y : y0;
                y1 = y > y1 ? y : y1;
            }
        }
    *w = x1 - x0 + 1;
    *h = y1 - y0 + 1;
    return x1 >= 0;
}

static void test_numbers_uniform_scale(void)
{
    Theme t = {WHITE, RED, NULL, true};
    Amt m;
    int fw, fh, hw, hh;
    rest(&m, 0);
    m.fill[1] = 1;
    for (int i = 2; i <= WS_COUNT; i++)
        m.presence[i] = 0; /* only slot 1 inks, so the box is its digit */
    cairo_surface_t *s = draw(&t, &GEOMETRY_NUMBERS, &m);
    int full = ink_box(s, &fw, &fh);
    cairo_surface_destroy(s);
    m.presence[1] = 0.5;
    s = draw(&t, &GEOMETRY_NUMBERS, &m);
    int half = ink_box(s, &hw, &hh);
    cairo_surface_destroy(s);
    CHECK(full && half, "the digit has ink at presence 1 and 0.5");
    CHECK(hw >= 0.35 * fw && hw <= 0.65 * fw, "half-presence digit ink width scales (%d vs %d)", hw, fw);
    CHECK(hh >= 0.35 * fh && hh <= 0.65 * fh, "half-presence digit ink height scales (%d vs %d)", hh, fh);
}

int main(void)
{
    test_dots_rest();
    test_a1_colour_follows_shape();
    test_presence();
    test_half_active_ring();
    test_hover();
    test_clamping();
    test_state_kept();
    test_numbers();
    test_numbers_alpha();
    test_nan_layout();
    test_numbers_uniform_scale();
    return check_done("test_render");
}
