#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="macmd.app"
BINARY_NAME="macmd"
BUNDLE_ID="com.sstrepka.macmd"
VERSION="1.0.1"
DIST_DIR="dist"
PKG_NAME="macmd-${VERSION}.pkg"
PKG_PATH="$DIST_DIR/$PKG_NAME"
INSTALL_DIR_SYSTEM="/Applications"
INSTALL_APP_SYSTEM="$INSTALL_DIR_SYSTEM/$APP"
INSTALL_DIR_USER="$HOME/Applications"
INSTALL_APP_USER="$INSTALL_DIR_USER/$APP"

echo "==> Building macmd (release)…"
swift build -c release 2>&1

echo "==> Creating app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$DIST_DIR"

cp ".build/release/$BINARY_NAME" "$APP/Contents/MacOS/$BINARY_NAME"

mkdir -p Resources
swift scripts/make_icon.swift
iconutil -c icns Resources/macmd.iconset -o Resources/macmd.icns
cp Resources/macmd.icns "$APP/Contents/Resources/macmd.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>macmd</string>
    <key>CFBundleIconFile</key>
    <string>macmd.icns</string>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> Signing ad-hoc…"
codesign --force --sign - "$APP"

echo "==> Installing app bundle…"
mkdir -p "$INSTALL_DIR_USER"
rm -rf "$INSTALL_APP_USER"
cp -R "$APP" "$INSTALL_APP_USER"
echo "    App updated: $INSTALL_APP_USER"

echo "==> Creating installer package…"
rm -f "$PKG_PATH"
pkgbuild \
  --component "$APP" \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  --install-location "$INSTALL_DIR_USER" \
  "$PKG_PATH"

echo ""
echo "==> Hotovo! Spusti: open \"$INSTALL_APP_USER\""
echo "==> Installer: \"$PKG_PATH\""
echo ""
echo "==> Inštalácia Karabiner konfigurácie pre F-klávesy…"
KARABINER_DIR="$HOME/.config/karabiner/assets/complex_modifications"
if [ -d "$KARABINER_DIR" ]; then
    cp karabiner/macmd.json "$KARABINER_DIR/"
    echo "    Karabiner config nakopírovaný."
    echo "    Otvor Karabiner-Elements → Complex Modifications → Add Rule → macmd F-keys"
else
    echo "    Karabiner-Elements nie je nainštalovaný."
    echo "    Bez neho F-klávesy fungujú len ak máš v System Settings > Keyboard"
    echo "    zapnuté 'Use F1, F2 etc. as standard function keys'."
fi
