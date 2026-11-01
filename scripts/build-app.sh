#!/bin/bash
# Builds Pulse.app next to the repo root: release build, icon, Info.plist, ad-hoc signature.
# Usage: scripts/build-app.sh            (VERSION=1.2.3 scripts/build-app.sh to set the version)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP=Pulse.app

# Universal (arm64 + x86_64) when the toolchain can do it, otherwise this Mac's architecture.
ARCHS="arm64"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if swift build -c release --arch arm64 --arch x86_64 >"$WORK/universal.log" 2>&1; then
  ARCHS="arm64 x86_64 (universal)"
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
  echo "note: universal build is not available with this toolchain; building for $(uname -m) only." >&2
  tail -3 "$WORK/universal.log" >&2 || true
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Pulse" "$APP/Contents/MacOS/Pulse"

# Fonts: loaded from Contents/Resources/Fonts (Theme.registerFonts looks there first).
# They are copied from the source tree, because the resource bundle's layout differs between
# the Command Line Tools build (Pulse_Pulse.bundle/Fonts) and Xcode's (Contents/Resources/Fonts).
cp -R "Sources/Pulse/Resources/Fonts" "$APP/Contents/Resources/Fonts"

# Icon: drawn by the app itself, then scaled into an .icns.
"$APP/Contents/MacOS/Pulse" --icon "$WORK/icon.png"
ICONSET="$WORK/Pulse.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Pulse.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.mokssha.pulse</string>
  <key>CFBundleName</key><string>Pulse</string>
  <key>CFBundleDisplayName</key><string>Pulse</string>
  <key>CFBundleExecutable</key><string>Pulse</string>
  <key>CFBundleIconFile</key><string>Pulse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Pulse asks System Events to restart your Mac, only when you press Restart.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature: no developer account needed. Gatekeeper still treats a downloaded copy as unidentified.
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

echo "built $APP version $VERSION ($ARCHS)"
