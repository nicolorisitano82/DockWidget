#!/bin/bash
# Builds DockWidgets.app into ./build.
#
# The manager is the only app you install; each widget is an agent app nested
# under Contents/Library/Widgets, carrying its own .docktileplugin. The manager
# adds and removes those nested apps from the Dock.
#
#   ./build.sh                          native arch, ad-hoc signature
#   ARCHS="arm64 x86_64" ./build.sh     universal
#   SIGN_IDENTITY="Developer ID Application: …" ./build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
SDK="$(xcrun --show-sdk-path)"
DEPLOY="14.0"
ARCHS="${ARCHS:-$(uname -m)}"
# Every widget is built three times, so the same one can sit in the Dock more
# than once with different settings: two clocks, two folders.
WIDGET_COPIES="${WIDGET_COPIES:-3}"
# A stable signature is not cosmetic here: TCC ties the Accessibility consent
# the bar needs to the app's designated requirement, and an ad-hoc signature
# changes with every build. Tools/make-signing-cert.sh creates this identity.
LOCAL_IDENTITY="Dock Widgets Dev"
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "$LOCAL_IDENTITY"; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
  else
    SIGN_IDENTITY="-"
    echo "⚠︎  nessuna identità di firma: build ad-hoc, il permesso di Accessibilità decadrà"
    echo "   crea l'identità con ./Tools/make-signing-cert.sh"
  fi
fi

SHARED=("$ROOT"/Sources/Shared/*.swift)
CLOCK=("$ROOT"/Sources/Clock/*.swift)
NOWPLAYING=("$ROOT"/Sources/NowPlaying/*.swift)
MANAGER=("$ROOT"/Sources/Manager/*.swift)
OVERLAY=("$ROOT"/Sources/Overlay/*.swift)
ACTIONS=("$ROOT"/Sources/Actions/*.swift)
BLANK_TILE=("$ROOT"/Sources/BlankTile/*.swift)
SENSORS=("$ROOT"/Sources/Sensors/*.swift)
DISKS=("$ROOT"/Sources/Disks/*.swift)
FOLDER=("$ROOT"/Sources/Folder/*.swift)
NOTE=("$ROOT"/Sources/Note/*.swift)
WIDGET_HOST=("$ROOT"/Sources/WidgetHost/*.swift)

MANAGER_APP="$BUILD/DockWidgets.app"
WIDGETS_DIR="$MANAGER_APP/Contents/Library/Widgets"
AGENTS_DIR="$MANAGER_APP/Contents/Library/LoginItems"
SIGN_QUEUE=()

rm -rf "$BUILD"
mkdir -p "$BUILD/tmp"

swift_build() {
  local output="$1" module="$2" kind="$3"
  shift 3
  local slices=()
  for arch in $ARCHS; do
    local slice="$BUILD/tmp/${module}-${arch}"
    local flags=(-swift-version 5 -O -sdk "$SDK" -target "${arch}-apple-macos${DEPLOY}" -module-name "$module")
    [ "$kind" = bundle ] && flags+=(-emit-library -Xlinker -bundle)
    swiftc "${flags[@]}" -o "$slice" "$@"
    slices+=("$slice")
  done
  mkdir -p "$(dirname "$output")"
  if [ "${#slices[@]}" -gt 1 ]; then
    lipo -create -output "$output" "${slices[@]}"
  else
    cp "${slices[0]}" "$output"
  fi
}

# A malformed Info.plist does not fail loudly: the app simply becomes
# unlaunchable and the Dock shows it with a prohibition sign.
check_plist() {
  plutil -lint "$1" >/dev/null || { echo "Info.plist non valido: $1"; exit 1; }
}

fill_plist() {
  sed -e "s/__DISPLAY_NAME__/$2/g" \
      -e "s/__EXECUTABLE__/$3/g" \
      -e "s/__BUNDLE_ID__/$4/g" \
      -e "s/__PLUGIN_NAME__/$5/g" \
      -e "s/__PRINCIPAL_CLASS__/${6:-}/g" \
      "$1"
}

build_icons() {
  local kind="$1" destination="$2"
  local iconset="$BUILD/tmp/$kind.iconset"
  rm -rf "$iconset"
  "$BUILD/tmp/makeicons" "$kind" "$iconset"
  iconutil --convert icns --output "$destination" "$iconset"
}

# A widget: an agent app with no UI of its own, plus the plug-in the Dock loads.
make_widget() {
  local display="$1" executable="$2" widget_id="$3" plugin="$4" principal="$5" icon_kind="$6" bundle_name="$7"
  shift 7
  local sources=("$@")

  local app="$WIDGETS_DIR/$bundle_name"
  local plugin_bundle="$app/Contents/PlugIns/$plugin.docktileplugin"
  echo "  · $display"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$plugin_bundle/Contents/MacOS"

  # The helper links the shared code so it can take a drop on its tile.
  swift_build "$app/Contents/MacOS/$executable" "$executable" app \
    "${SHARED[@]}" "${WIDGET_HOST[@]}"
  swift_build "$plugin_bundle/Contents/MacOS/$plugin" "$plugin" bundle "${SHARED[@]}" "${sources[@]}"

  fill_plist "$ROOT/Resources/Widget-Info.plist" "$display" "$executable" \
    "dev.nicolo.dockwidgets.$widget_id" "$plugin" > "$app/Contents/Info.plist"
  fill_plist "$ROOT/Resources/Plugin-Info.plist" "$display" "$executable" \
    "dev.nicolo.dockwidgets.$widget_id.tile" "$plugin" "$principal" > "$plugin_bundle/Contents/Info.plist"
  printf 'APPL????' > "$app/Contents/PkgInfo"
  check_plist "$app/Contents/Info.plist"
  check_plist "$plugin_bundle/Contents/Info.plist"

  build_icons "$icon_kind" "$app/Contents/Resources/AppIcon.icns"

  # Inner bundles are sealed before the ones containing them.
  SIGN_QUEUE+=("$plugin_bundle" "$app")

  # The copies are the same bundle under another name and identifier: the Dock
  # gives one tile per application, so a second clock needs a second app.
  local base="${bundle_name%.app}"
  for copy in $(seq 2 "$WIDGET_COPIES"); do
    local copy_app="$WIDGETS_DIR/$base $copy.app"
    rm -rf "$copy_app"
    cp -R "$app" "$copy_app"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.nicolo.dockwidgets.$widget_id$copy" \
      "$copy_app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $display $copy" "$copy_app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $display $copy" "$copy_app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.nicolo.dockwidgets.$widget_id$copy.tile" \
      "$copy_app/Contents/PlugIns/$plugin.docktileplugin/Contents/Info.plist"
    check_plist "$copy_app/Contents/Info.plist"
    SIGN_QUEUE+=("$copy_app/Contents/PlugIns/$plugin.docktileplugin" "$copy_app")
  done
}

echo "→ strumento icone"
swiftc -swift-version 5 -O -sdk "$SDK" -target "$(uname -m)-apple-macos${DEPLOY}" \
  -module-name makeicons -o "$BUILD/tmp/makeicons" \
  "${SHARED[@]}" "${CLOCK[@]}" "${NOWPLAYING[@]}" "${ACTIONS[@]}" "${SENSORS[@]}" "${DISKS[@]}" "${FOLDER[@]}" "${NOTE[@]}" \
  "$ROOT/Tools/MakeIcons/main.swift"

echo "→ manager"
mkdir -p "$MANAGER_APP/Contents/MacOS" "$MANAGER_APP/Contents/Resources" "$WIDGETS_DIR"
swift_build "$MANAGER_APP/Contents/MacOS/DockWidgets" DockWidgets app \
  "${SHARED[@]}" "${CLOCK[@]}" "${NOWPLAYING[@]}" "${ACTIONS[@]}" "${SENSORS[@]}" \
  "${DISKS[@]}" "${FOLDER[@]}" "${NOTE[@]}" "${MANAGER[@]}"
cp "$ROOT/Resources/Manager-Info.plist" "$MANAGER_APP/Contents/Info.plist"
check_plist "$MANAGER_APP/Contents/Info.plist"
printf 'APPL????' > "$MANAGER_APP/Contents/PkgInfo"
build_icons manager "$MANAGER_APP/Contents/Resources/AppIcon.icns"

echo "→ agent barra"
AGENT_APP="$AGENTS_DIR/NowPlayingBar.app"
mkdir -p "$AGENT_APP/Contents/MacOS" "$AGENT_APP/Contents/Resources"
swift_build "$AGENT_APP/Contents/MacOS/NowPlayingBar" NowPlayingBar app \
  "${SHARED[@]}" "${NOWPLAYING[@]}" "${ACTIONS[@]}" "${SENSORS[@]}" "${DISKS[@]}" "${NOTE[@]}" \
  "${OVERLAY[@]}"
cp "$ROOT/Resources/Agent-Info.plist" "$AGENT_APP/Contents/Info.plist"
check_plist "$AGENT_APP/Contents/Info.plist"
printf 'APPL????' > "$AGENT_APP/Contents/PkgInfo"
SIGN_QUEUE+=("$AGENT_APP")

echo "→ widget"
make_widget "Orologio" "ClockHost" "clock" \
  "ClockWidget" "ClockDockTilePlugin" "clock" "Orologio.app" "${CLOCK[@]}"
make_widget "In riproduzione" "NowPlayingHost" "nowplaying" \
  "NowPlayingWidget" "NowPlayingDockTilePlugin" "nowplaying" "NowPlaying.app" "${NOWPLAYING[@]}"
make_widget "Azioni" "ActionsHost" "actions" \
  "BlankWidget" "BlankDockTilePlugin" "actions" "Azioni.app" "${BLANK_TILE[@]}"
make_widget "Sensori" "SensorsHost" "sensors" \
  "SensorsWidget" "SensorsDockTilePlugin" "sensors" "Sensori.app" "${SENSORS[@]}"
make_widget "Dischi" "DisksHost" "disks" \
  "DisksWidget" "DisksDockTilePlugin" "disks" "Dischi.app" "${DISKS[@]}" "${SENSORS[@]}"
make_widget "Cartella" "FolderHost" "folder" \
  "FolderWidget" "FolderDockTilePlugin" "folder" "Cartella.app" "${FOLDER[@]}"
make_widget "Appunto" "NoteHost" "note" \
  "BlankWidget" "BlankDockTilePlugin" "note" "Appunto.app" "${BLANK_TILE[@]}"

for target in "${SIGN_QUEUE[@]}" "$MANAGER_APP"; do
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$target" || {
    echo "firma fallita: $target"; exit 1;
  }
done
touch "$MANAGER_APP"

rm -rf "$BUILD/tmp"
echo
echo "Fatto: $MANAGER_APP"
