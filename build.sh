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
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

SHARED=("$ROOT"/Sources/Shared/*.swift)
CLOCK=("$ROOT"/Sources/Clock/*.swift)
NOWPLAYING=("$ROOT"/Sources/NowPlaying/*.swift)
MANAGER=("$ROOT"/Sources/Manager/*.swift)
WIDGET_HOST=("$ROOT"/Sources/WidgetHost/*.swift)

MANAGER_APP="$BUILD/DockWidgets.app"
WIDGETS_DIR="$MANAGER_APP/Contents/Library/Widgets"
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

  swift_build "$app/Contents/MacOS/$executable" "$executable" app "${WIDGET_HOST[@]}"
  swift_build "$plugin_bundle/Contents/MacOS/$plugin" "$plugin" bundle "${SHARED[@]}" "${sources[@]}"

  fill_plist "$ROOT/Resources/Widget-Info.plist" "$display" "$executable" \
    "dev.nicolo.dockwidgets.$widget_id" "$plugin" > "$app/Contents/Info.plist"
  fill_plist "$ROOT/Resources/Plugin-Info.plist" "$display" "$executable" \
    "dev.nicolo.dockwidgets.$widget_id.tile" "$plugin" "$principal" > "$plugin_bundle/Contents/Info.plist"
  printf 'APPL????' > "$app/Contents/PkgInfo"

  build_icons "$icon_kind" "$app/Contents/Resources/AppIcon.icns"

  # Inner bundles are sealed before the ones containing them.
  SIGN_QUEUE+=("$plugin_bundle" "$app")
}

echo "→ strumento icone"
swiftc -swift-version 5 -O -sdk "$SDK" -target "$(uname -m)-apple-macos${DEPLOY}" \
  -module-name makeicons -o "$BUILD/tmp/makeicons" \
  "${SHARED[@]}" "${CLOCK[@]}" "${NOWPLAYING[@]}" "$ROOT/Tools/MakeIcons/main.swift"

echo "→ manager"
mkdir -p "$MANAGER_APP/Contents/MacOS" "$MANAGER_APP/Contents/Resources" "$WIDGETS_DIR"
swift_build "$MANAGER_APP/Contents/MacOS/DockWidgets" DockWidgets app \
  "${SHARED[@]}" "${CLOCK[@]}" "${NOWPLAYING[@]}" "${MANAGER[@]}"
cp "$ROOT/Resources/Manager-Info.plist" "$MANAGER_APP/Contents/Info.plist"
printf 'APPL????' > "$MANAGER_APP/Contents/PkgInfo"
build_icons manager "$MANAGER_APP/Contents/Resources/AppIcon.icns"

echo "→ widget"
make_widget "Orologio" "ClockHost" "clock" \
  "ClockWidget" "ClockDockTilePlugin" "clock" "Orologio.app" "${CLOCK[@]}"
make_widget "In riproduzione" "NowPlayingHost" "nowplaying" \
  "NowPlayingWidget" "NowPlayingDockTilePlugin" "nowplaying" "NowPlaying.app" "${NOWPLAYING[@]}"

for target in "${SIGN_QUEUE[@]}" "$MANAGER_APP"; do
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$target" >/dev/null 2>&1
done
touch "$MANAGER_APP"

rm -rf "$BUILD/tmp"
echo
echo "Fatto: $MANAGER_APP"
