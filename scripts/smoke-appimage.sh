#!/bin/bash
# Launches an AppImage for a few seconds under a virtual X server and fails if the
# QML UI does not come up. Complements the qmlcachegen parse check, which covers
# views (like SettingsView) that are only loaded on navigation.
#
#   scripts/smoke-appimage.sh <Moonlight.AppImage> [seconds]
set -uo pipefail

APPIMAGE=$(readlink -f "$1")
RUN_SECONDS=${2:-20}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
"$APPIMAGE" --appimage-extract >/dev/null || { echo "FAIL: --appimage-extract failed"; exit 1; }

# A throwaway portable-mode directory: settings, logs and qmlcache stay in here
mkdir run && touch run/portable.dat && cd run

timeout -k 5 "$RUN_SECONDS" xvfb-run -a -s "-screen 0 1280x800x24" ../squashfs-root/AppRun > log.txt 2>&1
RC=$?

echo "----- log (first 150 lines) -----"
head -n 150 log.txt
echo "---------------------------------"

# 124 means it was still running when the timeout fired, which is the expected outcome
if [ $RC -ne 124 ]; then
    echo "FAIL: Moonlight exited after less than ${RUN_SECONDS}s with status $RC"
    exit 1
fi

FATAL='(is not installed|is not a type|Expected token|SyntaxError|failed to load component|QQmlApplicationEngine failed)'
if grep -E "$FATAL" log.txt; then
    echo "FAIL: QML load errors (above)"
    exit 1
fi

WARNINGS=$(grep -c 'qrc:/' log.txt || true)
echo "PASS: UI stayed up for ${RUN_SECONDS}s; $WARNINGS informational qrc:/ log line(s)"
