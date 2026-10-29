"""Run the FTPS recovery regression using this Python's pyftpdlib environment."""
import argparse
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
p = argparse.ArgumentParser()
p.add_argument('--harness', required=True)
a = p.parse_args()
# Do not accidentally test against an unrelated server.
try:
    with socket.create_connection(('127.0.0.1', 21212), timeout=.2):
        raise SystemExit('Port 21212 is already occupied; stop that test server first.')
except OSError:
    pass
with tempfile.TemporaryDirectory(prefix='macmd-recovery-') as workspace:
    base = pathlib.Path(workspace)
    cert, key = base / 'cert.pem', base / 'key.pem'
    subprocess.run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=wrong-host.example', '-keyout', str(key), '-out', str(cert)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    for mode, expected_attempts in [('normal', 1), ('normal-hostile-curlrc', 1), ('once', 2), ('complete', 1), ('corrupt', 3), ('rename-failure', 1)]:
        root = base / mode
        with tempfile.TemporaryFile() as log:
            server = subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name('server.py')), '--root', str(root), '--cert', str(cert), '--key', str(key), '--mode', 'normal' if mode == 'normal-hostile-curlrc' else mode], stdout=log, stderr=log)
            try:
                for _ in range(50):
                    if server.poll() is not None:
                        raise RuntimeError('Test server failed to start')
                    try:
                        with socket.create_connection(('127.0.0.1', 21212), timeout=.2):
                            break
                    except OSError:
                        time.sleep(.1)
                flags = ['--expect-failure'] if mode == 'corrupt' else ['--expect-rename-failure'] if mode == 'rename-failure' else []
                environment = os.environ.copy()
                if mode == 'normal-hostile-curlrc':
                    config = base / 'curl-config'
                    config.mkdir()
                    (config / '.curlrc').write_text('max-time = 0.001\n')
                    environment['CURL_HOME'] = str(config)
                result = subprocess.run([a.harness] + flags, capture_output=True, text=True, timeout=45, env=environment)
                if result.returncode:
                    log.seek(0)
                    raise RuntimeError(result.stderr + log.read().decode())
                attempts = int((root / 'attempts').read_text())
                assert attempts == expected_attempts, (mode, attempts)
                print(f'{mode}: {result.stdout.strip()} (attempts: {attempts})', flush=True)
            finally:
                server.terminate()
                server.wait(timeout=5)
