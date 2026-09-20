#!/bin/bash
# Packs build/Underdock.app into a disk image ready to hand to someone.
#
# When Resources/Art/DmgBackground.png is there, the image opens as a window
# with that backdrop and the two icons sitting in the places it draws for them.
# Without it the image is still made, just plain.
#
# The signature is the local one: the image is not notarised, so the first
# launch on another Mac needs right-click → Open. Notarising takes an Apple
# developer account, which this project deliberately does not require.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Underdock.app"
BACKDROP="$ROOT/Resources/Art/DmgBackground.png"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$ROOT/build/Underdock-$VERSION.dmg"
VOLUME="Underdock"
STAGE="$(mktemp -d)"
SCRATCH="$ROOT/build/scratch.dmg"
cleanup() {
  [ -n "${MOUNT:-}" ] && [ -d "$MOUNT" ] && hdiutil detach "$MOUNT" -force >/dev/null 2>&1
  rm -rf "$STAGE" "$SCRATCH"
}
trap cleanup EXIT

[ -d "$APP" ] || { echo "Manca $APP — esegui prima ./build.sh"; exit 1; }

# Un volume dello stesso nome rimasto in giro da un giro andato storto si porta
# via il nome: il nuovo si monta come "Underdock 1" e il Finder, a cui avremmo
# detto "Underdock", sistemerebbe con cura la finestra di quello vecchio.
for stale in /Volumes/"$VOLUME" /Volumes/"$VOLUME "*; do
  [ -d "$stale" ] && hdiutil detach "$stale" -force >/dev/null 2>&1 || true
done

echo "→ preparo il contenuto"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

STYLED=0
if [ -f "$BACKDROP" ]; then
  mkdir -p "$STAGE/.background"
  cp "$BACKDROP" "$STAGE/.background/background.png"
  # Il Finder misura lo sfondo in punti, e un PNG a 72 dpi dice che un pixel è
  # un punto: l'immagine verrebbe disegnata grande il doppio della finestra e
  # se ne vedrebbe un quarto. A 144 dpi dichiara di essere a 2×, che è quello
  # che è.
  sips -s dpiWidth 144 -s dpiHeight 144 "$STAGE/.background/background.png" >/dev/null
  # The picture is drawn at twice the window's size, so the window is half of
  # it and the two icons land where the picture drew their places.
  PIXEL_WIDTH="$(sips -g pixelWidth "$BACKDROP" | awk '/pixelWidth/ {print $2}')"
  PIXEL_HEIGHT="$(sips -g pixelHeight "$BACKDROP" | awk '/pixelHeight/ {print $2}')"
  WINDOW_WIDTH=$((PIXEL_WIDTH / 2))
  WINDOW_HEIGHT=$((PIXEL_HEIGHT / 2))
  # Le frazioni sono misurate sui due riquadri disegnati nello sfondo, non
  # stimate a occhio: se lo sfondo cambia, si rimisurano.
  APP_X=$(printf '%.0f' "$(echo "$WINDOW_WIDTH * 0.27764" | bc -l)")
  APP_Y=$(printf '%.0f' "$(echo "$WINDOW_HEIGHT * 0.54862" | bc -l)")
  LINK_X=$(printf '%.0f' "$(echo "$WINDOW_WIDTH * 0.72236" | bc -l)")
  LINK_Y=$(printf '%.0f' "$(echo "$WINDOW_HEIGHT * 0.54862" | bc -l)")
  STYLED=1
fi

echo "→ costruisco l'immagine"
rm -f "$DMG" "$SCRATCH"

if [ "$STYLED" = 0 ]; then
  hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
else
  # Writable first: a window cannot be arranged inside a read-only image.
  SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 60 ))
  hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDRW \
    -size "${SIZE_MB}m" "$SCRATCH" >/dev/null
  # Sotto /Volumes e non altrove: il Finder scrive il .DS_Store — che è dove
  # finiscono sfondo e posizioni — solo per i volumi montati lì. Con un
  # -mountpoint nostro l'immagine si monta, la finestra si lascia perfino
  # sistemare, e poi non resta niente.
  #
  # Il punto di mount si legge dal plist invece che dal testo: il testo hdiutil
  # lo stampa diversamente a ogni giro di sistema.
  MOUNT="$(hdiutil attach "$SCRATCH" -readwrite -noverify -noautoopen -plist \
    | python3 -c 'import sys, plistlib
p = plistlib.loads(sys.stdin.buffer.read())
print(next((e["mount-point"] for e in p.get("system-entities", []) if e.get("mount-point")), ""))')"
  [ -n "$MOUNT" ] && [ -d "$MOUNT/Underdock.app" ] || {
    echo "non sono riuscito a montare l'immagine"; exit 1;
  }
  # Il nome con cui si è montata davvero, che è quello che il Finder conosce.
  MOUNTED_NAME="$(basename "$MOUNT")"

  echo "→ sistemo la finestra"
  # L'ordine conta: la finestra va aperta prima di poterle dare delle opzioni,
  # e va lasciata aperta finché il Finder non ha scritto il .DS_Store — che è
  # il file dove finiscono sfondo e posizioni.
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$MOUNTED_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, $((200 + WINDOW_WIDTH)), $((140 + WINDOW_HEIGHT))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    -- Per percorso POSIX e non per nome: il Finder non riesce a riferirsi a un
    -- file dentro una cartella nascosta con la forma "cartella:file", e la
    -- cosa non dà errore — semplicemente lo sfondo non viene salvato.
    set background picture of viewOptions to POSIX file "$MOUNT/.background/background.png"
    set position of item "Underdock.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$LINK_X, $LINK_Y}
    update without registering applications
    delay 3
    close
  end tell
end tell
APPLESCRIPT

  # Il Finder scrive con comodo suo: si aspetta il file invece di sperarci.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$MOUNT/.DS_Store" ] && break
    sleep 1
  done
  if [ ! -f "$MOUNT/.DS_Store" ]; then
    echo "⚠︎  il Finder non ha salvato la disposizione: l'immagine esce spoglia"
  fi

  sync
  hdiutil detach "$MOUNT" >/dev/null
  hdiutil convert "$SCRATCH" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
fi

echo "→ verifico"
codesign -v --deep --strict "$APP"
SIZE="$(du -h "$DMG" | cut -f1)"
echo
echo "Fatto: $DMG ($SIZE)"
echo "Non è notarizzata: al primo avvio su un altro Mac serve tasto destro → Apri."
