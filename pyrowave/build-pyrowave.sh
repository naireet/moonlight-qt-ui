#!/bin/bash
# Builds libpyrowave-shared (the PyroWave C API) from the pinned pyrowave submodule
# and installs it, with its header, into a prefix.
#
#   pyrowave/build-pyrowave.sh <install-prefix> [patch ...]
#
# Granite is fetched at exactly the commit pyrowave's own checkout_granite.sh pins,
# so the codec and its Vulkan backend always move together with the submodule.
set -euo pipefail

fail() {
    echo "build-pyrowave: $1" 1>&2
    exit 1
}

[ $# -ge 1 ] || fail "usage: $0 <install-prefix> [patch ...]"
PREFIX=$1
shift

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/pyrowave
BUILD=${PYROWAVE_BUILD_DIR:-$HERE/build}

[ -f "$SRC/pyrowave.h" ] || fail "pyrowave submodule is not checked out"

GRANITE_COMMIT=$(sed -n 's/^GRANITE_COMMIT=\([0-9a-f]\{40\}\)[[:space:]]*$/\1/p' "$SRC/checkout_granite.sh")
[ -n "$GRANITE_COMMIT" ] || fail "unable to read GRANITE_COMMIT from checkout_granite.sh"
echo "Granite commit pinned by pyrowave: $GRANITE_COMMIT"

if [ ! -d "$SRC/Granite/.git" ]; then
    git init -q "$SRC/Granite"
    git -C "$SRC/Granite" remote add origin https://github.com/Themaister/Granite.git
fi
git -C "$SRC/Granite" fetch -q --depth 1 origin "$GRANITE_COMMIT"
git -C "$SRC/Granite" checkout -q --detach "$GRANITE_COMMIT"
# Only what the standalone C API build needs (same set as checkout_granite.sh)
git -C "$SRC/Granite" submodule update -q --init --depth 1 third_party/volk third_party/khronos/vulkan-headers || \
    git -C "$SRC/Granite" submodule update -q --init third_party/volk third_party/khronos/vulkan-headers
[ "$(git -C "$SRC/Granite" rev-parse HEAD)" = "$GRANITE_COMMIT" ] || fail "Granite is not at $GRANITE_COMMIT"

for patch in "$@"; do
    if git -C "$SRC" apply --reverse --check "$patch" 2>/dev/null; then
        echo "Already applied: $(basename "$patch")"
    else
        git -C "$SRC" apply "$patch" || fail "unable to apply $patch"
        echo "Applied: $(basename "$patch")"
    fi
done

cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_BINDIR=bin \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_INCLUDEDIR=include \
    -DCMAKE_INSTALL_DATAROOTDIR=share
cmake --build "$BUILD" -j"$(nproc)"
cmake --install "$BUILD"

[ -f "$PREFIX/lib/libpyrowave-shared.so.0" ] || fail "libpyrowave-shared.so.0 was not installed to $PREFIX/lib"
echo "Installed $(readlink -f "$PREFIX/lib/libpyrowave-shared.so.0")"
