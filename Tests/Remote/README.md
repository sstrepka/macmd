# Remote transport verification

The release app uses statically linked libcurl/OpenSSL for FTP and FTPS, and the macOS OpenSSH client for SFTP. Tests link the same C bridge and engine. The build scripts prepare pinned libcurl source and use OpenSSL static development libraries (set `MACMD_OPENSSL_ROOT` if needed). The installed app requires neither Homebrew nor an external curl executable for FTP.

## Isolated regressions

From the repository root:

```sh
bash scripts/test_remote.sh transport
bash scripts/test_remote.sh tls
bash scripts/test_remote.sh credentials
bash scripts/test_remote.sh import /absolute/path/to/FileZilla.xml
```

These cover FileZilla XML/Unicode/unknown-field roundtrips, encrypted-password preservation, session and saved TLS exceptions, exact certificate changes and cancellation, per-batch validation caching, credential vault persistence/error handling, and connection-manager form refresh. The import regression reads the specified XML without printing or storing credentials; all UI models use injected profiles. Credential regressions use a disposable preferences suite and in-memory Keychain substitute. Test-only certificate/approval/pin hooks are absent from release builds.

## Local network integration

Use a disposable Python environment containing `pyftpdlib`, `pyOpenSSL`, and `paramiko`:

```sh
/path/to/test-env/bin/python Tests/Remote/servers.py
```

This starts loopback-only FTP `21210` and SFTP `21211`, test user `tester` / `secret`. Temporary host keys and the generated known-host entry are stored under `/tmp/macmd-test-*`. In another terminal:

```sh
bash scripts/test_remote.sh transport 0 21210
bash scripts/test_remote.sh transport 1 21211
```

Transport tests use an isolated trust directory and cover recursive transfers, UTF-8 and spaced paths, chmod, rename, relay copy, atomic replacement, preserving an existing local file after failure, cancellation before connection, and recursive deletion.

For an explicit FTPS server on `127.0.0.1:21212`, with its certificate at `/tmp/macmd-test-tls.pem`, also run:

```sh
bash scripts/test_remote.sh transport 4 21212
bash scripts/test_remote.sh tls --local-server
```

The TLS network test exercises automatic approval/retry, transfers and rejection of a wrong public-key pin by native libcurl, including when the handle already has a reusable connection.

## Interrupted uploads and atomicity

```sh
bash scripts/test_remote.sh upload --build-only
/path/to/test-env/bin/python Tests/Remote/UploadRecovery/run.py --harness "$PWD/.build/remote-tests/upload"
```

The runner generates certificates and loopback servers. It tests normal overwrite, a hostile `.curlrc` (native libcurl never reads it), a partial transfer followed by successful retry, complete bytes followed by a misleading 426, repeated corrupted uploads, and rejected rename. It asserts attempt counts, exact content, preservation of the existing final file on failure, and removal of staging files. Postquote RNFR/RNTO executes on the upload connection only after success. Recovery from 426 requires independent SHA-256 readback; size alone never counts as success.

## Explicit live-server regression

Only run when authorized to access the supplied account and create temporary remote files:

```sh
bash scripts/test_remote.sh live /path/to/FileZilla.xml host.example /path/to/innsbruck-source-files
```

This selects exactly one matching FTP/FTPS profile. It copies the already approved certificate into an isolated test trust directory and refuses new certificate approvals. It creates a new UUID directory beneath the account's initial path, uploads/downloads the three source files three times, compares SHA-256, tests a recursive 1 MB binary transfer with Unicode/spaced names, recursively removes only that UUID directory, and verifies cleanup. Credentials remain in memory and are never printed. No existing remote content is overwritten.

The installed app's `--import-filezilla /absolute/path/to/FileZilla.xml` mode remains available for one-shot import through the app's Keychain identity. It merges accounts and verifies credential readback, without connecting to remote servers.

## FTP toolbar menu

```sh
bash scripts/test_remote.sh menu
```

This AppKit regression constructs the actual main-window FTP menu with injected test profiles. It checks complete profile snapshots, target/action dispatch deferred out of the menu action, and screen-coordinate anchors in flipped/unflipped view hierarchies and after moving a window. It never loads real saved FTP accounts or connects to a server. Actual onscreen menu placement and mouse tracking require an interactive GUI check.
