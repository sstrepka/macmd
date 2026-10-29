#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C
VERSION=8.23.0
SHA256=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
ROOT="$PWD/.build/ftp-deps"
OPENSSL_ROOT="${MACMD_OPENSSL_ROOT:-/opt/homebrew/opt/openssl}"
if [ ! -f "$OPENSSL_ROOT/lib/libssl.a" ]; then
  echo "Build requires OpenSSL development static libraries; set MACMD_OPENSSL_ROOT." >&2
  exit 1
fi
STAMP="$VERSION|$(uname -m)|$("$OPENSSL_ROOT/bin/openssl" version)"
if [ -f "$ROOT/lib/libcurl.a" ] && [ "$(cat "$ROOT/build-stamp" 2>/dev/null)" = "$STAMP" ]; then exit 0; fi
mkdir -p .build/vendor-downloads "$ROOT"
ARCHIVE=".build/vendor-downloads/curl-$VERSION.tar.xz"
if [ ! -f "$ARCHIVE" ]; then
  /usr/bin/curl --disable --fail --location --silent --show-error "https://curl.se/download/curl-$VERSION.tar.xz" -o "$ARCHIVE"
fi
ACTUAL=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
[ "$ACTUAL" = "$SHA256" ] || { echo "curl source checksum mismatch" >&2; exit 1; }
if [ ! -d ".build/vendor-downloads/curl-$VERSION" ]; then tar -xf "$ARCHIVE" -C .build/vendor-downloads; fi
SOURCE="$PWD/.build/vendor-downloads/curl-$VERSION"
echo "==> Preparing libcurl $VERSION with OpenSSL (static)…"
cmake -S "$SOURCE" -B .build/ftp-curl-build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
  -DCMAKE_INSTALL_PREFIX="$ROOT" -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_CURL_EXE=ON -DBUILD_TESTING=OFF -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF \
  -DCURL_USE_OPENSSL=ON -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT" -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DCURL_USE_LIBPSL=OFF -DUSE_LIBIDN2=OFF -DCURL_USE_LIBSSH2=OFF -DCURL_USE_LIBSSH=OFF \
  -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
  -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON -DCURL_DISABLE_DICT=ON \
  -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_POP3=ON \
  -DCURL_DISABLE_SMTP=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_TELNET=ON \
  -DCURL_DISABLE_TFTP=ON -DCURL_DISABLE_MQTT=ON \
  -DCURL_CA_BUNDLE=/etc/ssl/cert.pem > .build/ftp-configure.log 2>&1 || { tail -60 .build/ftp-configure.log; exit 1; }
cmake --build .build/ftp-curl-build --parallel 6 > .build/ftp-compile.log 2>&1 || { tail -60 .build/ftp-compile.log; exit 1; }
cmake --install .build/ftp-curl-build > .build/ftp-install.log 2>&1
cp -f "$OPENSSL_ROOT/lib/libssl.a" "$OPENSSL_ROOT/lib/libcrypto.a" "$ROOT/lib/"
cp "$SOURCE/COPYING" ThirdParty/Notices/curl.txt
cp "$OPENSSL_ROOT/LICENSE.txt" ThirdParty/Notices/OpenSSL.txt
printf '%s\n' "$VERSION" > "$ROOT/engine-version"
printf '%s\n' "$STAMP" > "$ROOT/build-stamp"
"$ROOT/bin/curl" --version | head -2
