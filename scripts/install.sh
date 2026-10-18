#!/bin/sh
# Build the package, install it on the phone at "ssh iphone4s", and open
# the app. The script waits until no other project uses the phone.
# Usage: scripts/install.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEB=$("$ROOT/scripts/deb.sh")
"$ROOT/scripts/phone.sh" run sh -c "
    scp -q '$DEB' iphone4s:/tmp/rectunnelx.deb &&
    ssh iphone4s 'dpkg -i /tmp/rectunnelx.deb >/dev/null && rm /tmp/rectunnelx.deb &&
        launchctl list | grep rectunnelxd'"
