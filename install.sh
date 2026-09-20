#!/bin/bash
# Installs build/Underdock.app into /Applications and cleans up after the
# earlier one-app-per-widget layout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/Underdock.app"

[ -d "$APP" ] || { echo "Manca $APP — esegui prima ./build.sh"; exit 1; }

echo "→ chiudo le versioni in esecuzione"
osascript -e 'quit app "DockClock"' 2>/dev/null || true
osascript -e 'quit app "DockNowPlaying"' 2>/dev/null || true
osascript -e 'quit app "Underdock"' 2>/dev/null || true
# E la versione di prima, che si chiamava Dock Widgets.
osascript -e 'quit app "Dock Widgets"' 2>/dev/null || true
osascript -e 'quit app "WidgetPro"' 2>/dev/null || true
# The overlay agent must go too, or the freshly installed one sees a duplicate
# of itself and quits.
pkill -f "NowPlayingBar.app/Contents/MacOS/NowPlayingBar" 2>/dev/null || true

echo "→ sistemo le voci del Dock"
defaults export com.apple.dock - | python3 -c '
import sys, plistlib
prefs = plistlib.loads(sys.stdin.buffer.read())

# Voci rimaste senza bundle dietro: vanno tolte.
stale = ("DockClock.app", "DockNowPlaying.app", "/dock/build/")

# Il nome e cambiato, i widget no. Riscrivere le voci invece di cancellarle
# tiene la disposizione che era stata scelta: cancellarle vuol dire rimettere
# ogni widget nel Dock a mano.
renames = (
    ("DockWidgets.app", "Underdock.app"),
    ("WidgetPro.app", "Underdock.app"),
    ("Application%20Support/DockWidgets/", "Application%20Support/Underdock/"),
    ("Application Support/DockWidgets/", "Application Support/Underdock/"),
    ("Application%20Support/WidgetPro/", "Application%20Support/Underdock/"),
    ("Application Support/WidgetPro/", "Application Support/Underdock/"),
    ("dev.nicolo.dockwidgets", "dev.nicolo.underdock"),
    ("dev.nicolo.widgetpro", "dev.nicolo.underdock"),
)

def url(entry):
    return entry.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")

def rename(entry):
    data = entry.get("tile-data")
    if not isinstance(data, dict):
        return
    target = data.get("file-data")
    if isinstance(target, dict) and isinstance(target.get("_CFURLString"), str):
        text = target["_CFURLString"]
        for before, after in renames:
            text = text.replace(before, after)
        target["_CFURLString"] = text
    identifier = data.get("bundle-identifier")
    if isinstance(identifier, str):
        for before, after in renames:
            identifier = identifier.replace(before, after)
        data["bundle-identifier"] = identifier

for key in ("persistent-apps", "persistent-others"):
    entries = prefs.get(key)
    if not entries:
        continue
    kept = [e for e in entries if not any(name in url(e) for name in stale)]
    for entry in kept:
        rename(entry)
    prefs[key] = kept
plistlib.dump(prefs, sys.stdout.buffer)
' | defaults import com.apple.dock -

echo "→ rimuovo i bundle vecchi"
rm -rf /Applications/DockClock.app /Applications/DockNowPlaying.app
rm -rf /Applications/DockWidgets.app /Applications/WidgetPro.app
# Le copie si rifanno da sole al primo avvio, sotto il nome nuovo.
rm -rf "$HOME/Library/Application Support/DockWidgets" \
       "$HOME/Library/Application Support/WidgetPro"

echo "→ installo Underdock.app"
# Swapped into place instead of removed and recopied: the Dock watches the
# files behind its tiles, and a bundle that disappears even for a moment gets
# its tiles dropped from the Dock at the next save.
rm -rf /Applications/Underdock.app.new
cp -R "$APP" /Applications/Underdock.app.new
if [ -d /Applications/Underdock.app ]; then
  mv /Applications/Underdock.app /Applications/Underdock.app.old
fi
mv /Applications/Underdock.app.new /Applications/Underdock.app
rm -rf /Applications/Underdock.app.old
touch /Applications/Underdock.app

# LaunchServices caches an app's Info.plist. Without this, a widget that gains
# a Dock tile plug-in keeps being loaded from the old description and the Dock
# never asks for the plug-in.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f /Applications/Underdock.app 2>/dev/null || true

killall -KILL Dock 2>/dev/null || true
open /Applications/Underdock.app
echo "Fatto."
