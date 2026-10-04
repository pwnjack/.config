# Native Waybar workspace module (cffi/workspaces).
#
# Out-of-tree only: the repository is public and must never hold build
# output, so BUILD is required. build-workspaces.sh and the test suite both
# pass a temporary directory.
#
#   make BUILD=/tmp/ws /tmp/ws/workspaces.so
#   make BUILD=/tmp/ws test

ifndef BUILD
$(error BUILD is required, e.g. make BUILD=/tmp/workspaces-build)
endif

CC ?= cc
PKGS := gtk+-3.0 json-glib-1.0
CFLAGS += -std=gnu11 -O2 -g -Wall -Wextra -Werror -fPIC $(shell pkg-config --cflags $(PKGS))
LDLIBS += $(shell pkg-config --libs $(PKGS)) -lm

HEADERS := $(wildcard *.h)
LIB_SRC := $(wildcard model.c anim.c render.c hypr.c module.c)
TEST_SRC := $(wildcard test/test_*.c)
TESTS := $(patsubst test/%.c,$(BUILD)/%,$(TEST_SRC))

$(BUILD):
	mkdir -p $@

$(BUILD)/workspaces.so: $(LIB_SRC) $(HEADERS) | $(BUILD)
	$(CC) $(CFLAGS) -shared -o $@ $(LIB_SRC) $(LDLIBS)

# Each test links the library sources it needs; hypr's retry is shortened so
# the reconnect test runs in milliseconds.
$(BUILD)/test_%: test/test_%.c test/check.h $(LIB_SRC) $(HEADERS) | $(BUILD)
	$(CC) $(CFLAGS) -DHYPR_RETRY_MS=50 -I. -o $@ $< $(filter-out module.c,$(LIB_SRC)) $(LDLIBS) -ldl

test: $(TESTS) $(if $(wildcard module.c),$(BUILD)/workspaces.so)
	@set -e; for t in $(TESTS); do "$$t" "$(BUILD)"; done

.PHONY: test
