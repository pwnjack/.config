#include <math.h>
#include <string.h>

#include "check.h"
#include "../anim.h"

#define MS 1000
/* Computed independently of anim.c (Step 2): CSS cubic-bezier at x = 0.5. */
#define REF_STANDARD 0.8778336 /* cubic-bezier(0.2, 0, 0, 1) */
#define REF_EASE_OUT 0.8392451 /* cubic-bezier(0, 0, 0.2, 1) */

static void fill_amounts(double v[WS_COUNT + 1], int one)
{
    for (int i = 0; i <= WS_COUNT; i++)
        v[i] = (i == one) ? 1 : 0;
}

static void presence_1_to_5(double p[WS_COUNT + 1])
{
    for (int i = 0; i <= WS_COUNT; i++)
        p[i] = (i >= 1 && i <= WS_ALWAYS) ? 1 : 0;
}

static void test_curves(void)
{
    for (int c = CURVE_STANDARD; c <= CURVE_EASE_OUT; c++) {
        CHECK(curve_eval(c, 0) == 0 && curve_eval(c, 1) == 1, "curve %d endpoints", c);
        double prev = 0;
        for (int i = 1; i <= 1000; i++) {
            double y = curve_eval(c, i / 1000.0);
            CHECK(y >= prev - 1e-12, "curve %d monotonic at %d", c, i);
            prev = y;
        }
    }
    CHECK_NEAR(curve_eval(CURVE_STANDARD, 0.5), REF_STANDARD, 1e-6, "standard at 0.5");
    CHECK_NEAR(curve_eval(CURVE_EASE_OUT, 0.5), REF_EASE_OUT, 1e-6, "ease-out at 0.5");
}

/* Sample a switch from slot a to slot b every 1 ms; check the invariants. */
static void check_switch(const Geometry *geo, int a, int b)
{
    double shape[WS_COUNT + 1], target[WS_COUNT + 1], presence[WS_COUNT + 1];
    fill_amounts(shape, a);
    fill_amounts(target, b);
    presence_1_to_5(presence);

    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, shape);
    Layout rest;
    layout_compute(geo, g.value, presence, &rest);
    group_retarget(&g, target);

    int lo = a < b ? a : b, hi = a < b ? b : a;
    Layout prev = rest;
    int64_t t0 = 1000000;
    for (int64_t t = t0; t <= t0 + 320 * MS; t += MS) {
        group_tick(&g, t);
        Layout l;
        layout_compute(geo, g.value, presence, &l);
        CHECK_NEAR(l.total, rest.total, 1e-9, "%d->%d total constant", a, b);
        for (int i = hi + 1; i <= WS_ALWAYS; i++)
            CHECK_NEAR(l.x[i], rest.x[i], 1e-9, "%d->%d slot %d beyond both pills stays", a, b, i);
        for (int i = lo + 1; i <= hi; i++) {
            /* Leaving the lower slot shrinks it: everything between moves left. */
            if (a < b)
                CHECK(l.x[i] <= prev.x[i] + 1e-12, "%d->%d slot %d moves left only", a, b, i);
            else
                CHECK(l.x[i] >= prev.x[i] - 1e-12, "%d->%d slot %d moves right only", a, b, i);
        }
        prev = l;
    }
    CHECK(!g.running, "%d->%d settles", a, b);
    for (int i = 1; i <= WS_ALWAYS; i++) {
        CHECK_NEAR(prev.x[i], round(prev.x[i]), 1e-9, "%d->%d slot %d x whole at rest", a, b, i);
        CHECK_NEAR(prev.w[i], round(prev.w[i]), 1e-9, "%d->%d slot %d w whole at rest", a, b, i);
    }
    CHECK_NEAR(prev.w[b], geo->pill, 1e-9, "%d->%d target is a pill", a, b);
}

static void test_switches(void)
{
    for (int a = 1; a <= WS_ALWAYS; a++)
        for (int b = 1; b <= WS_ALWAYS; b++)
            if (a != b)
                check_switch(&GEOMETRY_DOTS, a, b);
}

static void test_switches_numbers(void)
{
    for (int a = 1; a <= WS_ALWAYS; a++)
        for (int b = 1; b <= WS_ALWAYS; b++)
            if (a != b)
                check_switch(&GEOMETRY_NUMBERS, a, b);
}

static void test_rest_geometry(void)
{
    double shape[WS_COUNT + 1], presence[WS_COUNT + 1];
    fill_amounts(shape, 2);
    presence_1_to_5(presence);
    Layout l;
    layout_compute(&GEOMETRY_DOTS, shape, presence, &l);
    CHECK(l.x[1] == 0 && l.w[1] == 10, "slot 1 at 0, 10 wide");
    CHECK(l.x[2] == 16 && l.w[2] == 28, "slot 2 pill at 16, 28 wide");
    CHECK(l.x[3] == 50 && l.x[5] == 82, "slots 3 and 5");
    CHECK(l.total == 92, "dots row is 92 wide (today's 110 minus the CSS insets 15 + 3)");
    layout_compute(&GEOMETRY_NUMBERS, shape, presence, &l);
    CHECK(l.total == 110, "numbers row is 110 wide (today's 120 minus the CSS insets 9 + 1)");
}

static void test_retarget(void)
{
    double s[WS_COUNT + 1], t[WS_COUNT + 1], presence[WS_COUNT + 1];
    fill_amounts(s, 2);
    presence_1_to_5(presence);
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, s);
    Layout rest;
    layout_compute(&GEOMETRY_DOTS, g.value, presence, &rest);

    fill_amounts(t, 4);
    group_retarget(&g, t);
    int64_t now = 0;
    for (; now <= 150 * MS; now += MS)
        group_tick(&g, now);
    double before[WS_COUNT + 1];
    memcpy(before, g.value, sizeof before);

    fill_amounts(t, 1);
    group_retarget(&g, t);
    group_tick(&g, now); /* first tick after a retarget starts the clock */
    for (int i = 1; i <= WS_COUNT; i++)
        CHECK_NEAR(g.value[i], before[i], 1e-12, "retarget is continuous at slot %d", i);

    for (; now <= 500 * MS; now += MS) {
        group_tick(&g, now);
        double sum = 0;
        for (int i = 1; i <= WS_COUNT; i++)
            sum += g.value[i];
        CHECK_NEAR(sum, 1, 1e-12, "amounts sum to 1 at %lld us", (long long)now);
        Layout l;
        layout_compute(&GEOMETRY_DOTS, g.value, presence, &l);
        CHECK_NEAR(l.total, rest.total, 1e-9, "total constant through a retarget");
    }
    CHECK(!g.running && g.value[1] == 1 && g.value[2] == 0 && g.value[4] == 0, "settles on slot 1");
}

static void test_same_target_no_restart(void)
{
    double s[WS_COUNT + 1], t[WS_COUNT + 1];
    fill_amounts(s, 2);
    fill_amounts(t, 4);
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, s);
    group_retarget(&g, t);
    group_tick(&g, 0);
    group_tick(&g, 100 * MS);
    int64_t start = g.start_us;
    double mid = g.value[4];
    group_retarget(&g, t);
    CHECK(g.start_us == start && g.value[4] == mid && g.running, "same target keeps the clock");
    double again[WS_COUNT + 1];
    fill_amounts(again, 2);
    group_init(&g, 300 * MS, CURVE_STANDARD, again);
    group_retarget(&g, again);
    CHECK(!g.running, "retargeting a resting group to where it is does nothing");
}

static void test_presence(void)
{
    double shape[WS_COUNT + 1], p0[WS_COUNT + 1], p1[WS_COUNT + 1];
    fill_amounts(shape, 1);
    presence_1_to_5(p0);
    presence_1_to_5(p1);
    p1[6] = 1;
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, p0);
    group_retarget(&g, p1);
    double prev_total = -1, prev_w = -1;
    for (int64_t t = 0; t <= 300 * MS; t += MS) {
        group_tick(&g, t);
        Layout l;
        layout_compute(&GEOMETRY_DOTS, shape, g.value, &l);
        if (t == 0)
            CHECK(l.w[6] == 0, "slot 6 starts at width 0");
        CHECK(l.total >= prev_total, "total grows monotonically");
        CHECK(l.w[6] >= prev_w, "slot 6 grows monotonically");
        prev_total = l.total;
        prev_w = l.w[6];
    }
    CHECK_NEAR(prev_w, GEOMETRY_DOTS.dot, 1e-9, "slot 6 ends at dot width");
}

static void test_negative_clock(void)
{
    double s[WS_COUNT + 1], t[WS_COUNT + 1];
    fill_amounts(s, 2);
    fill_amounts(t, 4);
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, s);
    group_retarget(&g, t);
    int64_t t0 = -1000000;
    bool ran_at_299 = false;
    for (int64_t now = t0; now <= t0 + 320 * MS; now += MS) {
        group_tick(&g, now);
        if (now == t0 + 299 * MS)
            ran_at_299 = g.running;
    }
    CHECK(ran_at_299, "negative clock: still running at 299 ms");
    CHECK(!g.running && g.value[4] == 1 && g.value[2] == 0, "negative clock reaches the target and stops");
}

static void test_negative_zero_target(void)
{
    double s[WS_COUNT + 1], t[WS_COUNT + 1];
    fill_amounts(s, 2);
    fill_amounts(t, 4);
    t[1] = -0.0;
    t[0] = 7; /* slot 0 is unused and ignored */
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, s);
    group_retarget(&g, t);
    CHECK(g.to[0] == 0 && g.value[0] == 0 && g.from[0] == 0, "slot 0 stays 0");
    group_tick(&g, 0);
    group_tick(&g, 100 * MS);
    int64_t start = g.start_us;
    double again[WS_COUNT + 1];
    fill_amounts(again, 4);
    again[1] = 0.0;
    again[0] = -3;
    group_retarget(&g, again);
    CHECK(g.start_us == start && g.started && g.running, "-0.0 vs 0.0 and slot 0 do not restart the clock");
}

static void test_settle_tick(void)
{
    double s[WS_COUNT + 1], t[WS_COUNT + 1];
    fill_amounts(s, 2);
    fill_amounts(t, 4);
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, s);
    group_retarget(&g, t);
    bool more = true;
    for (int64_t now = 0; more && now <= 400 * MS; now += MS)
        more = group_tick(&g, now);
    CHECK(!more, "the group settles");
    for (int i = 0; i <= WS_COUNT; i++)
        CHECK(g.value[i] == g.to[i], "settle tick leaves slot %d exactly on target", i);
}

static void test_presence_removal(void)
{
    double shape[WS_COUNT + 1], p0[WS_COUNT + 1], p1[WS_COUNT + 1];
    fill_amounts(shape, 1);
    presence_1_to_5(p0);
    p0[6] = 1;
    presence_1_to_5(p1);
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, p0);
    group_retarget(&g, p1);
    double prev_total = 1e9, prev_w = 1e9;
    for (int64_t t = 0; t <= 300 * MS; t += MS) {
        group_tick(&g, t);
        Layout l;
        layout_compute(&GEOMETRY_DOTS, shape, g.value, &l);
        CHECK(l.total <= prev_total, "total shrinks monotonically");
        CHECK(l.w[6] <= prev_w, "slot 6 shrinks monotonically");
        prev_total = l.total;
        prev_w = l.w[6];
    }
    CHECK(prev_w == 0, "slot 6 ends at exactly 0");
}

static void test_retarget_no_jump(void)
{
    double s[WS_COUNT + 1], t[WS_COUNT + 1];
    fill_amounts(s, 2);
    fill_amounts(t, 4);
    Group g;
    group_init(&g, 300 * MS, CURVE_STANDARD, s);
    group_retarget(&g, t);
    double at149[WS_COUNT + 1], at150[WS_COUNT + 1];
    for (int64_t now = 0; now <= 150 * MS; now += MS) {
        group_tick(&g, now);
        if (now == 149 * MS)
            memcpy(at149, g.value, sizeof at149);
    }
    memcpy(at150, g.value, sizeof at150);
    fill_amounts(t, 1);
    group_retarget(&g, t);
    group_tick(&g, 151 * MS);
    for (int i = 1; i <= WS_COUNT; i++) {
        double jump = fabs(g.value[i] - at150[i]);
        double step = fabs(at150[i] - at149[i]);
        /* Slots that never moved have step 0 and must not jump either. */
        CHECK(jump <= step, "retarget does not jump slot %d (%g vs one step %g)", i, jump, step);
    }
}

int main(void)
{
    test_curves();
    test_switches();
    test_switches_numbers();
    test_rest_geometry();
    test_retarget();
    test_same_target_no_restart();
    test_presence();
    test_negative_clock();
    test_negative_zero_target();
    test_settle_tick();
    test_presence_removal();
    test_retarget_no_jump();
    return check_done("test_anim");
}
