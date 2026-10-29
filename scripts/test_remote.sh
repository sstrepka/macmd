#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SUITE="${1:-transport}"
if [ $# -gt 0 ]; then shift; fi
BUILD_ONLY=false
if [ "${1:-}" = "--build-only" ]; then BUILD_ONLY=true; shift; fi
bash scripts/prepare_ftp_engine.sh
mkdir -p .build/remote-tests .build/ModuleCache
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -O2 -target "$(uname -m)-apple-macosx13.0" -isysroot "$SDK" \
  -I Sources/CNativeFTP/include -I .build/ftp-deps/include \
  -c Sources/CNativeFTP/macmd_ftp.c -o .build/remote-tests/native-$SUITE.o
SOURCES=(Sources/macmd/FTP.swift Sources/macmd/NativeFTPTransport.swift Sources/macmd/FileZilla.swift Sources/macmd/RemoteTrust.swift Tests/Remote/Models.swift)
FLAGS=(-D MACMD_NATIVE_FTP)
case "$SUITE" in
  transport) FLAGS+=(-D MACMD_TLS_TESTS); SOURCES+=(Sources/macmd/RemoteCredentials.swift Tests/Remote/main.swift);;
  tls) FLAGS+=(-D MACMD_TLS_TESTS); SOURCES+=(Sources/macmd/RemoteCredentials.swift Tests/Remote/TLSExceptions/main.swift);;
  upload) FLAGS+=(-D MACMD_TLS_TESTS); SOURCES+=(Sources/macmd/RemoteCredentials.swift Tests/Remote/UploadRecovery/main.swift);;
  live) FLAGS+=(-D MACMD_TLS_TESTS); SOURCES+=(Sources/macmd/RemoteCredentials.swift Tests/Remote/LiveNative/main.swift);;
  credentials) SOURCES+=(Tests/Remote/CredentialStore/RemoteCredentials.swift Tests/Remote/CredentialStore/main.swift);;
  menu) FLAGS+=(-D MACMD_FTP_MENU_TESTS); SOURCES=(); for source in Sources/macmd/*.swift; do if [ "$source" != "Sources/macmd/main.swift" ]; then SOURCES+=("$source"); fi; done; SOURCES+=(Tests/Remote/FTPMenu/main.swift);;
  import) FLAGS+=(-D MACMD_REMOTE_TESTS); SOURCES+=(Sources/macmd/RemoteCredentials.swift Sources/macmd/FTPConnectionManager.swift Sources/macmd/Dialogs.swift Tests/Remote/ImportRegression/main.swift);;
  *) echo "Unknown suite: $SUITE" >&2; exit 1;;
esac
xcrun swiftc "${FLAGS[@]}" -sdk "$SDK" -target "$(uname -m)-apple-macosx13.0" -module-cache-path .build/ModuleCache \
  -I Sources/CNativeFTP/include .build/remote-tests/native-$SUITE.o \
  .build/ftp-deps/lib/libcurl.a .build/ftp-deps/lib/libssl.a .build/ftp-deps/lib/libcrypto.a \
  -framework SystemConfiguration -framework CoreFoundation -framework CoreServices \
  "${SOURCES[@]}" -o ".build/remote-tests/$SUITE"
if [ "$BUILD_ONLY" = false ]; then ".build/remote-tests/$SUITE" "$@"; fi
