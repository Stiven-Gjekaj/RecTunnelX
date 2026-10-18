#!/bin/sh
# Build and run the tests of the core code.
# Usage: scripts/test.sh [--phone] [NAME]
# With no option, the tests operate on this Mac.
# With --phone, the tests operate on the iPhone at "ssh iphone4s".
# The phone test waits until no other project uses the phone.
# NAME runs only the tests with NAME in their name.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/tests"
mkdir -p "$OUT"
SOURCES=$(ls "$ROOT"/src/core/*.m "$ROOT"/tests/*.m 2>/dev/null || true)

if [ "$1" = "--phone" ]; then
    shift
    "$ROOT/build.sh" "$OUT/rxtests-armv7" -I"$ROOT/src/core" -I"$ROOT/tests" $SOURCES -framework Foundation
    "$ROOT/scripts/phone.sh" run sh -c "scp -q \"$OUT/rxtests-armv7\" iphone4s:/tmp/rxtests && ssh iphone4s \"ldid -S /tmp/rxtests && /tmp/rxtests $*\""
else
    clang -fobjc-arc -Wall -Werror -mmacosx-version-min=10.9 -I"$ROOT/src/core" -I"$ROOT/tests" $SOURCES \
        -framework Foundation -o "$OUT/rxtests"
    "$OUT/rxtests" "$@"
fi
