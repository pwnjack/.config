#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "check.h"

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: test_module BUILD_DIR\n");
        return 2;
    }
    char path[4096];
    snprintf(path, sizeof path, "%s/workspaces.so", argv[1]);
    void *h = dlopen(path, RTLD_NOW);
    CHECK(h != NULL, "dlopen %s: %s", path, h ? "" : dlerror());
    if (!h)
        return check_done("test_module");
    const size_t *version = dlsym(h, "wbcffi_version");
    CHECK(version && *version == 2, "ABI version 2");
    const char *fns[] = {"wbcffi_init", "wbcffi_deinit", "wbcffi_update", "wbcffi_refresh",
                         "wbcffi_doaction"};
    for (size_t i = 0; i < sizeof fns / sizeof *fns; i++)
        CHECK(dlsym(h, fns[i]) != NULL, "%s is exported", fns[i]);
    const char *hidden[] = {"group_init",   "render_row",  "layout_compute",
                            "ws_slot",      "hypr_dispatch", "GEOMETRY_DOTS"};
    for (size_t i = 0; i < sizeof hidden / sizeof *hidden; i++)
        CHECK(dlsym(h, hidden[i]) == NULL, "%s is not exported", hidden[i]);

    /* nm -D: every defined text/data symbol is a wbcffi_ one. */
    char cmd[4200];
    snprintf(cmd, sizeof cmd, "nm -D --defined-only '%s'", path);
    FILE *p = popen(cmd, "r");
    CHECK(p != NULL, "run nm -D");
    if (p) {
        char line[512];
        int listed = 0, stray = 0;
        while (fgets(line, sizeof line, p)) {
            char addr[64], type[8], name[256];
            if (sscanf(line, "%63s %7s %255s", addr, type, name) != 3)
                continue;
            if (strchr("TtDdRrBbVvWwGgSs", type[0]) == NULL)
                continue;
            if (strncmp(name, "wbcffi_", 7) == 0) {
                listed++;
            } else if (strcmp(name, "_init") && strcmp(name, "_fini") &&
                       strcmp(name, "__bss_start") && strcmp(name, "_edata") &&
                       strcmp(name, "_end")) {
                stray++;
                fprintf(stderr, "  stray exported symbol: %s\n", name);
            }
        }
        pclose(p);
        CHECK(listed == 6, "nm -D lists the six wbcffi_ symbols (got %d)", listed);
        CHECK(stray == 0, "nm -D lists no other module symbols (%d)", stray);
    }
    return check_done("test_module");
}
