#!/bin/bash
# Installs build/DockWidgets.app into /Applications and cleans up after the
# earlier one-app-per-widget layout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/DockWidgets.app"

[ -d "$APP" ] || { echo "Manca $APP — esegui prima ./build.sh"; exit 1; }

echo "→ chiudo le versioni in esecuzione"
osascript -e 'quit app "DockClock"' 2>/dev/null || true
osascript -e 'quit app "DockNowPlaying"' 2>/dev/null || true
osascript -e 'quit app "Dock Widgets"' 2>/dev/null || true

echo "→ tolgo dal Dock le voci che non esistono più"
defaults export com.apple.dock - | python3 -c '
import sys, plistlib
prefs = plistlib.load(sys.stdin.buffer)
stale = ("DockClock.app", "DockNowPlaying.app")

def url(entry):
    return entry.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")

for key in ("persistent-apps", "persistent-others"):
    entries = prefs.get(key)
    if entries:
        prefs[key] = [e for e in entries if not any(name in url(e) for name in stale)]
plistlib.dump(prefs, sys.stdout.buffer)
' | defaults import com.apple.dock -

echo "→ rimuovo i bundle vecchi"
rm -rf /Applications/DockClock.app /Applications/DockNowPlaying.app

echo "→ installo DockWidgets.app"
rm -rf /Applications/DockWidgets.app
cp -R "$APP" /Applications/
touch /Applications/DockWidgets.app

killall Dock 2>/dev/null || true
open /Applications/DockWidgets.app
echo "Fatto."
