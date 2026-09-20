#!/bin/bash
# Packs build/DockWidgets.app into a disk image ready to hand to someone.
#
# The signature is the local one: the image is not notarised, so the first
# launch on another Mac needs right-click → Open. Notarising takes an Apple
# developer account, which this project deliberately does not require.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DockWidgets.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$ROOT/build/DockWidgets-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -d "$APP" ] || { echo "Manca $APP — esegui prima ./build.sh"; exit 1; }

echo "→ preparo il contenuto"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "→ costruisco l'immagine"
rm -f "$DMG"
hdiutil create -volname "Dock Widgets" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "→ verifico"
codesign -v --deep --strict "$APP"
SIZE="$(du -h "$DMG" | cut -f1)"
echo
echo "Fatto: $DMG ($SIZE)"
echo "Non è notarizzata: al primo avvio su un altro Mac serve tasto destro → Apri."
