#!/bin/sh
# Build RecTunnelX.app and the daemon rectunnelxd into build/.
# Usage: scripts/app.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/RecTunnelX.app"
rm -rf "$APP"
mkdir -p "$APP"

# shellcheck disable=SC2046
"$ROOT/build.sh" "$APP/RecTunnelX" -I"$ROOT/src/core" -I"$ROOT/src/ui" \
    "$ROOT/src/core/RXSettings.m" $(ls "$ROOT"/src/ui/*.m) \
    -framework Foundation -framework UIKit -framework CoreGraphics

# shellcheck disable=SC2046
"$ROOT/build.sh" "$ROOT/build/rectunnelxd" -I"$ROOT/src/core" -I"$ROOT/src/phone" \
    "$ROOT/src/daemon/main.m" $(ls "$ROOT"/src/core/*.m "$ROOT"/src/phone/*.m) \
    -framework Foundation -framework CoreMedia -framework CoreVideo

cp "$ROOT/resources/Info.plist" "$APP/Info.plist"
cp "$ROOT"/resources/*.png "$APP/"
printf 'APPL????' > "$APP/PkgInfo"
echo "$APP"
