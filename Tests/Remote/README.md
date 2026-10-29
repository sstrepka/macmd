# Remote transport integration harness

Compile from the repository root (does not start the app or read saved accounts):

```sh
xcrun swiftc -module-cache-path .build/ModuleCache Sources/macmd/FTP.swift Sources/macmd/FileZilla.swift Sources/macmd/RemoteTrust.swift Sources/macmd/RemoteCredentials.swift Tests/Remote/Models.swift Tests/Remote/main.swift -o /tmp/macmd-remote-harness
/tmp/macmd-remote-harness
```

`servers.py` needs a disposable Python environment with `pyftpdlib` and `paramiko`. It binds **127.0.0.1 only**, uses temporary server data, test user `tester` / `secret`, FTP port 21210 and SFTP port 21211. It writes a temporary generated host key and public known-host entry under `/tmp/macmd-test-*`.

Run the server, then `/tmp/macmd-remote-harness 0 21210` and `/tmp/macmd-remote-harness 1 21211`. The SFTP harness temporarily adds its generated test key to macmd's trust file and removes that exact key afterwards. Do not terminate a running harness abruptly; failed assertions may require removing its test-only `[127.0.0.1]:21211` entry manually.

Tests cover FileZilla password and XML roundtrips, unknown fields, nested site folders, Unicode/spaced paths, actual recursive transfers, rename, chmod, atomic local replacement, preserving an existing file after failed download, failed rename propagation, relay copy, and recursive deletion. FTPS mode `4 21212` (or implicit mode `3 21213`) expects a local explicit TLS server and test certificate `/tmp/macmd-test-tls.pem` for 127.0.0.1; the harness temporarily installs and removes that certificate in macmd's trust directory.

No production credentials, remote servers, or existing user data are used. Interactive trust dialogs, external FileZilla import of generated files, MFA, and live UI behavior require separate verification.
