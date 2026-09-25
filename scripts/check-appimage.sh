#!/bin/bash
# Static checks for a built Moonlight AppImage. Nothing here needs a GPU or a display.
#
#   scripts/check-appimage.sh <Moonlight.AppImage> [--pyrowave]
#
# The AppImage is unpacked with --appimage-extract. Running `strings` on the AppImage
# itself gives false negatives because the payload is a compressed squashfs.
set -uo pipefail

APPIMAGE=$(readlink -f "$1")
EXPECT_PYROWAVE=0
[ "${2:-}" = "--pyrowave" ] && EXPECT_PYROWAVE=1

SOURCE_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAILURES=0
pass() { echo "PASS: $1"; }
failcheck() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

pushd "$WORK" >/dev/null
"$APPIMAGE" --appimage-extract >/dev/null || { echo "FAIL: --appimage-extract failed"; exit 1; }
popd >/dev/null
ROOT=$WORK/squashfs-root
BIN=$ROOT/usr/bin/moonlight
LIBDIR=$ROOT/usr/lib

[ -x "$BIN" ] && pass "usr/bin/moonlight present" || failcheck "usr/bin/moonlight missing"

# The main binary must not hard-depend on anything the host may lack at startup
NEEDED=$(readelf -d "$BIN" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
echo "moonlight NEEDED: $(echo $NEEDED)"
if echo "$NEEDED" | grep -q pyrowave; then
    failcheck "moonlight links libpyrowave directly; it must be dlopen()ed"
else
    pass "moonlight does not link libpyrowave"
fi

# Every bundled library must resolve inside the AppImage or on a normal host
UNRESOLVED=$(for f in "$BIN" "$LIBDIR"/*.so*; do
    LD_LIBRARY_PATH=$LIBDIR ldd "$f" 2>/dev/null | grep "not found" | sed "s|^|$(basename "$f"): |"
done | sort -u)
if [ -n "$UNRESOLVED" ]; then
    failcheck "unresolved dependencies:"
    echo "$UNRESOLVED"
else
    pass "all bundled ELF dependencies resolve"
fi

# For reference: the Vulkan loader is bundled (as upstream does), so it overrides the host's
echo "Bundled Vulkan loader: $(ls "$LIBDIR" | grep -E '^libvulkan\.so' | tr '\n' ' ')"

PWLIB=$LIBDIR/libpyrowave-shared.so.0
if [ $EXPECT_PYROWAVE -eq 1 ]; then
    if [ -f "$PWLIB" ]; then
        pass "usr/lib/libpyrowave-shared.so.0 bundled ($(stat -c %s "$(readlink -f "$PWLIB")") bytes)"

        # Every entry point the client binds at runtime must be exported
        FUNCS=$(sed -n 's/^[[:space:]]*X(\(pyrowave_[a-z0-9_]*\)).*/\1/p' "$SOURCE_ROOT/app/streaming/video/pyrowaveloader.h")
        EXPORTED=$(nm -D --defined-only "$PWLIB" | awk '{print $3}')
        MISSING=
        for fn in $FUNCS; do
            echo "$EXPORTED" | grep -qx "$fn" || MISSING="$MISSING $fn"
        done
        if [ -z "$FUNCS" ]; then
            failcheck "could not read the PyroWave function list from pyrowaveloader.h"
        elif [ -n "$MISSING" ]; then
            failcheck "libpyrowave-shared is missing:$MISSING"
        else
            pass "libpyrowave-shared exports all $(echo $FUNCS | wc -w) bound entry points"
        fi

        # The host must be able to run it: glibc symbol versions no newer than the build host's
        MAXGLIBC=$(objdump -T "$PWLIB" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -n1)
        BUILDGLIBC=GLIBC_$(ldd --version | head -n1 | grep -oE '[0-9]+\.[0-9]+$')
        if [ "$(printf '%s\n%s\n' "$MAXGLIBC" "$BUILDGLIBC" | sort -V | tail -n1)" = "$BUILDGLIBC" ]; then
            pass "libpyrowave-shared needs at most $MAXGLIBC (build host $BUILDGLIBC)"
        else
            failcheck "libpyrowave-shared needs $MAXGLIBC, newer than $BUILDGLIBC"
        fi
        echo "libpyrowave-shared needs $(objdump -T "$PWLIB" | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -n1)," \
             "moonlight needs $(objdump -T "$BIN" | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -n1)"

        # Load it the way the client does and check the API version it reports
        cat > "$WORK/probe.c" <<'EOF'
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
int main(int argc, char** argv) {
    void* h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    void (*getVersion)(uint32_t*, uint32_t*, uint32_t*) =
        (void (*)(uint32_t*, uint32_t*, uint32_t*))dlsym(h, "pyrowave_get_api_version");
    if (!getVersion) { fprintf(stderr, "dlsym failed\n"); return 1; }
    uint32_t major, minor, patch;
    getVersion(&major, &minor, &patch);
    printf("%u.%u.%u\n", major, minor, patch);
    return 0;
}
EOF
        if cc -o "$WORK/probe" "$WORK/probe.c" -ldl 2>/dev/null; then
            LIBVER=$(LD_LIBRARY_PATH=$LIBDIR "$WORK/probe" "$PWLIB")
            HDRVER=$(sed -n 's/^#define PYROWAVE_API_VERSION_\(MAJOR\|MINOR\|PATCH\) \([0-9]*\)$/\2/p' \
                     "$SOURCE_ROOT/pyrowave/pyrowave/pyrowave.h" | paste -sd.)
            if [ -n "$LIBVER" ] && [ "$LIBVER" = "$HDRVER" ]; then
                pass "bundled library loads and reports API $LIBVER (header $HDRVER)"
            else
                failcheck "bundled library reports API '$LIBVER', header is $HDRVER"
            fi
        else
            failcheck "could not build the dlopen probe"
        fi
    else
        failcheck "usr/lib/libpyrowave-shared.so.0 is not bundled"
    fi
else
    [ -e "$PWLIB" ] && failcheck "libpyrowave-shared bundled in a non-PyroWave build" || pass "no PyroWave library (not requested)"
fi

echo "$FAILURES check(s) failed"
[ $FAILURES -eq 0 ]
