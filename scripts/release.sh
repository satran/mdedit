#!/bin/bash
# Packages build/MDEdit.app into build/MDEdit-<version>.dmg (drag-to-Applications layout).
#
#   make release                                   ad hoc signed: runs on your own Macs (see README for the first-open step)
#   make release SIGN="Developer ID Application: Name (TEAMID)"
#                                                  signed for distribution outside the App Store
#   make release SIGN="Developer ID Application: ..." NOTARY=my-profile
#                                                  also notarised and stapled (profile made once with `xcrun notarytool store-credentials`)
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN="${SIGN:--}"
NOTARY="${NOTARY:-}"
APP=build/MDEdit.app
VERSION=$(sed -n 's/.*MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
DMG="build/MDEdit-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

[ -d "$APP" ] || { echo "build/MDEdit.app is missing; run through 'make release'" >&2; exit 1; }
[ -n "$NOTARY" ] && [ "$SIGN" = "-" ] && { echo "NOTARY needs a Developer ID identity in SIGN" >&2; exit 1; }

echo "Checking the signature of the app"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority|Signature|flags" || true

cp -R "$APP" "$STAGE/MDEdit.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "MDEdit $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"

if [ "$SIGN" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN" "$DMG"
  if [ -n "$NOTARY" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
  fi
fi

hdiutil verify -quiet "$DMG"
# the same file under a fixed name, so the website's link (releases/latest/download/MDEdit.dmg) always reaches the newest release
cp "$DMG" build/MDEdit.dmg
echo "Built $DMG (also build/MDEdit.dmg: attach this one to the GitHub release as well)"
shasum -a 256 "$DMG"
