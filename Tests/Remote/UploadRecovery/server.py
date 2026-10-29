"""Disposable loopback FTPS server injecting final 426 responses for STOR."""
import argparse
import logging
from pathlib import Path
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import TLS_FTPHandler
from pyftpdlib.servers import FTPServer
p = argparse.ArgumentParser()
p.add_argument('--root', required=True)
p.add_argument('--cert', required=True)
p.add_argument('--key', required=True)
p.add_argument('--mode', choices=['normal', 'once', 'complete', 'corrupt', 'rename-failure'], required=True)
a = p.parse_args()
root = Path(a.root)
root.mkdir(parents=True, exist_ok=True)
(root / 'final.txt').write_bytes(b'previous contents')
auth = DummyAuthorizer()
auth.add_user('tester', 'secret', str(root), perm='elradfmwMT')
class Handler(TLS_FTPHandler):
    uploads = 0
    upload_pending = False
    def ftp_STOR(self, file, mode='w'):
        self.upload_pending = True
        Handler.uploads += 1
        (root / 'attempts').write_text(str(Handler.uploads))
        return super().ftp_STOR(file, mode)
    def respond(self, resp, logfun=logging.debug):
        if resp.startswith('226') and self.upload_pending:
            self.upload_pending = False
            if a.mode in ('complete', 'corrupt') or (a.mode == 'once' and Handler.uploads == 1):
                resp = '426 Failure reading network stream.'
        return super().respond(resp, logfun)
    def ftp_RNTO(self, path):
        if a.mode == 'rename-failure':
            self.respond('550 Test rename rejected.')
            return
        return super().ftp_RNTO(path)
    def on_file_received(self, file):
        if a.mode == 'corrupt' or (a.mode == 'once' and Handler.uploads == 1):
            Path(file).write_bytes(b'truncated')
Handler.authorizer = auth
Handler.certfile = a.cert
Handler.keyfile = a.key
Handler.tls_control_required = True
Handler.tls_data_required = True
FTPServer(('127.0.0.1', 21212), Handler).serve_forever()
