import os, socket, threading, tempfile, time
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer
import paramiko
root=tempfile.mkdtemp(prefix='macmd-ftp-server-')
auth=DummyAuthorizer();auth.add_user('tester','secret',root,perm='elradfmwMT')
class FTP(FTPHandler): pass
FTP.authorizer=auth
server=FTPServer(('127.0.0.1',21210), FTP)
threading.Thread(target=server.serve_forever,daemon=True).start()
key=paramiko.RSAKey.generate(2048)
keypath='/tmp/macmd-test-hostkey';key.write_private_key_file(keypath)
with open('/tmp/macmd-test-knownhost','w') as f:f.write('[127.0.0.1]:21211 '+key.get_name()+' '+key.get_base64()+'\n')
class Auth(paramiko.ServerInterface):
 def check_auth_password(self,u,p):return paramiko.AUTH_SUCCESSFUL if (u,p)==('tester','secret') else paramiko.AUTH_FAILED
 def get_allowed_auths(self,u):return 'password'
 def check_channel_request(self,kind,chanid):return paramiko.OPEN_SUCCEEDED if kind=='session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
class SFTP(paramiko.SFTPServerInterface):
 def path(self,p):
  path=os.path.abspath(os.path.join(root,p.lstrip('/')))
  if os.path.commonpath([path,root]) != root:raise OSError('bad path')
  return path
 def list_folder(self,p):
  try:
   result=[]
   for name in os.listdir(self.path(p)):
    item=paramiko.SFTPAttributes.from_stat(os.lstat(os.path.join(self.path(p),name)));item.filename=name;result.append(item)
   return result
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno)
 def stat(self,p):
  try:return paramiko.SFTPAttributes.from_stat(os.stat(self.path(p)))
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno)
 lstat=stat
 def open(self,p,flags,attr):
  try:
   fd=os.open(self.path(p),flags,0o644);f=os.fdopen(fd,'r+b' if flags & os.O_RDWR else 'wb' if flags & os.O_WRONLY else 'rb');h=paramiko.SFTPHandle(flags);h.readfile=f;h.writefile=f;return h
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno)
 def change(self,method,*args):
  try:method(*[self.path(p) for p in args]);return paramiko.SFTP_OK
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno)
 def remove(self,p):return self.change(os.remove,p)
 def rename(self,a,b):return self.change(os.rename,a,b)
 def mkdir(self,p,attr):return self.change(os.mkdir,p)
 def rmdir(self,p):return self.change(os.rmdir,p)
 def chattr(self,p,attr):
  try:paramiko.SFTPServer.set_file_attr(self.path(p),attr);return paramiko.SFTP_OK
  except OSError as e:return paramiko.SFTPServer.convert_errno(e.errno)
sock=socket.socket();sock.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);sock.bind(('127.0.0.1',21211));sock.listen()
print('READY',flush=True)
def handle(client):
 t=paramiko.Transport(client);t.add_server_key(key);t.set_subsystem_handler('sftp',paramiko.SFTPServer,SFTP);t.start_server(server=Auth())
 while t.is_active():time.sleep(.1)
while True:
 client,_=sock.accept();threading.Thread(target=handle,args=(client,),daemon=True).start()
