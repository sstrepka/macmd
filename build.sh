#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="macmd.app"
BINARY_NAME="macmd"
BUNDLE_ID="com.sstrepka.macmd"
VERSION="1.0.4"
DIST_DIR="dist"
PKG_NAME="macmd-${VERSION}.pkg"
PKG_PATH="$DIST_DIR/$PKG_NAME"
INSTALL_DIR_SYSTEM="/Applications"
INSTALL_APP_SYSTEM="$INSTALL_DIR_SYSTEM/$APP"
INSTALL_DIR_USER="$HOME/Applications"
INSTALL_APP_USER="$INSTALL_DIR_USER/$APP"

bash scripts/prepare_ftp_engine.sh
echo "==> Building macmd (release)…"
# Compile directly: SwiftPM can request PlatformPath, which Command Line Tools
# do not provide. The native FTP engine is statically linked below.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_ARCH="$(uname -m)"
mkdir -p .build/release .build/ModuleCache
xcrun clang -O2 -target "${TARGET_ARCH}-apple-macosx13.0" -isysroot "$SDK_PATH" \
  -I Sources/CNativeFTP/include -I .build/ftp-deps/include \
  -c Sources/CNativeFTP/macmd_ftp.c -o .build/release/macmd_ftp.o
xcrun swiftc -O -sdk "$SDK_PATH" \
  -target "${TARGET_ARCH}-apple-macosx13.0" \
  -module-cache-path .build/ModuleCache \
  -I Sources/CNativeFTP/include .build/release/macmd_ftp.o \
  .build/ftp-deps/lib/libcurl.a .build/ftp-deps/lib/libssl.a .build/ftp-deps/lib/libcrypto.a \
  -framework SystemConfiguration -framework CoreFoundation -framework CoreServices \
  Sources/macmd/*.swift -o ".build/release/$BINARY_NAME"

echo "==> Creating app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$DIST_DIR"

cp ".build/release/$BINARY_NAME" "$APP/Contents/MacOS/$BINARY_NAME"

mkdir -p Resources
xcrun swift -sdk "$SDK_PATH" -module-cache-path .build/ModuleCache scripts/make_icon.swift
iconutil -c icns Resources/macmd.iconset -o Resources/macmd.icns
cp Resources/macmd.icns "$APP/Contents/Resources/macmd.icns"
cp -R ThirdParty/Notices "$APP/Contents/Resources/ThirdPartyNotices"

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
