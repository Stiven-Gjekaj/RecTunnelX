#!/bin/sh
# Build the Cydia package of RecTunnelX into build/.
# Usage: scripts/deb.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/app.sh" >/dev/null
VERSION=$(plutil -extract CFBundleShortVersionString raw "$ROOT/resources/Info.plist")
NAME="io.github.stivengjekaj.rectunnelx_${VERSION}_iphoneos-arm.deb"

# iOS 6 reads only the first code directory, so SHA-1 must be first.
codesign -s - --digest-algorithm=sha1,sha256 -f "$ROOT/build/RecTunnelX.app/RecTunnelX" 2>/dev/null
codesign -s - --digest-algorithm=sha1,sha256 -f "$ROOT/build/rectunnelxd" 2>/dev/null

STAGE="$ROOT/build/deb"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/Applications" "$STAGE/usr/libexec" "$STAGE/Library/LaunchDaemons"
cp -R "$ROOT/build/RecTunnelX.app" "$STAGE/Applications/"
cp "$ROOT/build/rectunnelxd" "$STAGE/usr/libexec/"
cp "$ROOT/resources/io.github.stivengjekaj.rectunnelxd.plist" "$STAGE/Library/LaunchDaemons/"
sed "s/@VERSION@/$VERSION/" "$ROOT/packaging/control" > "$STAGE/DEBIAN/control"
cp "$ROOT/packaging/postinst" "$ROOT/packaging/prerm" "$ROOT/packaging/postrm" "$STAGE/DEBIAN/"
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm" "$STAGE/DEBIAN/postrm" \
    "$STAGE/Applications/RecTunnelX.app/RecTunnelX" "$STAGE/usr/libexec/rectunnelxd"
chmod 644 "$STAGE/Library/LaunchDaemons/io.github.stivengjekaj.rectunnelxd.plist"
xattr -cr "$STAGE"

# The dpkg of Cydia on iOS 6 reads gzip, not xz or zstd.
dpkg-deb -Zgzip --root-owner-group -b "$STAGE" "$ROOT/build/$NAME" >/dev/null
echo "$ROOT/build/$NAME"
