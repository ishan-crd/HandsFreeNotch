#!/bin/sh
# Builds HandsFreeNotch.app from the Swift package.
#
#   scripts/bundle.sh            release build into build/HandsFreeNotch.app
#   CONFIG=debug scripts/bundle.sh
#   CODESIGN_IDENTITY="Apple Development: …" scripts/bundle.sh
#
# macOS ties the Accessibility grant to the code signature, so an ad-hoc build has to be
# re-allowed after every rebuild. `scripts/make-cert.sh` creates a local identity named
# "HandsFreeNotch Dev"; when it exists it is used automatically and the grant survives rebuilds.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
if [ -z "${CODESIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "HandsFreeNotch Dev"; then
  CODESIGN_IDENTITY="HandsFreeNotch Dev"
fi
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/HandsFreeNotch.app"

swift build -c "$CONFIG" --product HandsFreeNotch
BIN="$(swift build -c "$CONFIG" --show-bin-path)/HandsFreeNotch"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HandsFreeNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" || true
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign "$IDENTITY" --identifier com.ishan.HandsFreeNotch "$APP"
echo "built $APP"
