#!/bin/bash
# Compares qmllint findings for app/gui/*.qml against a base git ref, so new QML
# problems stand out from the existing baseline (qmllint can't resolve Moonlight's
# C++ types without type info, so the absolute count is large and meaningless).
#
#   scripts/qml-lint-diff.sh <qmllint> <base-ref>
#
# Fails on any new error-level finding, and self-tests with a deliberately
# broken copy (negative control) so a broken comparison can't pass silently.
set -uo pipefail

QMLLINT=$1
BASE=$2
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/base" "$WORK/head/gui" "$WORK/probe/gui"
git archive "$BASE" app/gui | tar -x -C "$WORK/base" --strip-components=1 || { echo "cannot read $BASE"; exit 1; }
cp app/gui/*.qml "$WORK/head/gui/"
cp app/gui/*.qml "$WORK/probe/gui/"

# Findings without positions, counted, so moved lines don't show up as new
lint() {
    (cd "$1" && "$QMLLINT" gui/*.qml 2>&1) |
        grep -E '^(Error|Warning|Info):' |
        sed -E 's/:[0-9]+:[0-9]+:/:/' |
        sort | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print c "\t" $0 }'
}

# Lines (with counts) present more often in $2 than in $1
new_findings() {
    awk -F'\t' 'NR == FNR { base[$2] = $1; next } { d = $1 - (($2 in base) ? base[$2] : 0); if (d > 0) print d "\t" $2 }' "$1" "$2"
}

lint "$WORK/base" > "$WORK/base.txt"
lint "$WORK/head" > "$WORK/head.txt"

# Negative control: an unresolvable reference must show up as a new finding
sed -i '0,/^\(Flickable\|Item\|Page\|Rectangle\|ScrollView\) *{/s//&\n    property int qmlLintProbe: qmlLintUndefinedId.width/' "$WORK/probe/gui/SettingsView.qml"
lint "$WORK/probe" > "$WORK/probe.txt"
if [ -z "$(new_findings "$WORK/head.txt" "$WORK/probe.txt")" ]; then
    echo "FAIL: negative control produced no new qmllint finding; the comparison is not working"
    exit 1
fi
echo "PASS: negative control detected"

echo "Baseline ($BASE): $(awk -F'\t' '{ s += $1 } END { print s + 0 }' "$WORK/base.txt") finding(s)"
echo "This tree:        $(awk -F'\t' '{ s += $1 } END { print s + 0 }' "$WORK/head.txt") finding(s)"

NEW=$(new_findings "$WORK/base.txt" "$WORK/head.txt")
if [ -z "$NEW" ]; then
    echo "PASS: no new qmllint findings"
    exit 0
fi

echo "New qmllint findings (count, message):"
echo "$NEW"
if echo "$NEW" | grep -q $'\tError:'; then
    echo "FAIL: new error-level findings"
    exit 1
fi
echo "PASS: no new errors (new warnings above are for review)"
