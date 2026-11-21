"""Native WinHTTP + pipe integration. Local fixtures only; no user config or API key."""
from pathlib import Path
import ctypes as C
from ctypes import wintypes as W
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, os, subprocess, tempfile, threading, time, zipfile

ROOT=Path(__file__).resolve().parents[2]
BIN=ROOT/'windows/build/native-app/Release'
class Handler(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args): pass
    def handle(self):
        try: super().handle()
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError): pass
    def do_GET(self):
        try:
            if self.path=='/stream':
                self.send_response(200);self.send_header('Content-Type','text/event-stream');self.send_header('Connection','close');self.end_headers();self.close_connection=True
                self.wfile.write(b'data: first\n\n');self.wfile.flush();time.sleep(1.5)
                self.wfile.write(b'data: second\n\n');self.wfile.flush();return
            if self.path=='/slow': time.sleep(2)
            body=b'x'*65536 if self.path=='/huge' else b'fixture-ok'
            self.send_response(302 if self.path=='/redirect' else 200)
            if self.path=='/redirect': self.send_header('Location','http://127.0.0.1:1/never-follow')
            self.send_header('Content-Length',str(len(body)));self.end_headers()
            if self.path=='/body-slow':
                self.wfile.write(body[:1]);self.wfile.flush();time.sleep(2);body=body[1:]
            self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError): pass

def main():
    http=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=http.serve_forever,daemon=True).start()
    with tempfile.TemporaryDirectory(prefix='orangecell-native-integration-') as tmp:
        tmp=Path(tmp)
        for filename,entries in [('good.zip',{'dicts/zi.dict.yaml':'词库测试\n'}),('unsafe.zip',{'../escape':'unsafe','dicts/zi.dict.yaml':'x'}),('missing.zip',{'other':'x'})]:
            with zipfile.ZipFile(tmp/filename,'w',compression=zipfile.ZIP_DEFLATED) as z:
                for name,value in entries.items():z.writestr(name,value)
        bad=bytearray((tmp/'good.zip').read_bytes());bad[bad.index(b'PK\x01\x02')+16]^=1;(tmp/'bad-crc.zip').write_bytes(bad)
        env=os.environ.copy();env['ORANGECELL_TEST_ZIPS']=str(tmp)
        subprocess.run([str(BIN/'orangecell_windows_test.exe'),str(ROOT/'tests/corpus/truncated-output.jsonl'),f'http://127.0.0.1:{http.server_port}'],env=env,check=True,timeout=30)
        pipe='\\\\.\\pipe\\OrangeCell-native-test-'+str(os.getpid())
        broker=subprocess.Popen([str(BIN/'OrangeCellBroker.exe'),'--data-dir',str(tmp/'data'),'--test-pipe',pipe],creationflags=subprocess.CREATE_NO_WINDOW)
        k=C.WinDLL('kernel32',use_last_error=True)
        k.CreateFileW.argtypes=[W.LPCWSTR,W.DWORD,W.DWORD,W.LPVOID,W.DWORD,W.DWORD,W.HANDLE];k.CreateFileW.restype=W.HANDLE
        k.WaitNamedPipeW.argtypes=[W.LPCWSTR,W.DWORD];k.WaitNamedPipeW.restype=W.BOOL
        k.WriteFile.argtypes=[W.HANDLE,W.LPCVOID,W.DWORD,C.POINTER(W.DWORD),W.LPVOID];k.WriteFile.restype=W.BOOL
        k.ReadFile.argtypes=[W.HANDLE,W.LPVOID,W.DWORD,C.POINTER(W.DWORD),W.LPVOID];k.ReadFile.restype=W.BOOL
        k.CloseHandle.argtypes=[W.HANDLE]
        def connect():
            until=time.monotonic()+8
            while time.monotonic()<until:
                if k.WaitNamedPipeW(pipe,200):
                    h=k.CreateFileW(pipe,0xC0000000,0,None,3,0,None)
                    if h not in (None,C.c_void_p(-1).value):return h
                time.sleep(.02)
            raise OSError(C.get_last_error(),'Pipe did not become available')
        def call(data,delay=0):
            h=connect()
            try:
                count=W.DWORD();assert k.WriteFile(h,data,len(data),C.byref(count),None)
                if delay:time.sleep(delay)
                buf=C.create_string_buffer(131072);assert k.ReadFile(h,buf,len(buf),C.byref(count),None)
                return buf.raw[:count.value].decode()
            finally:k.CloseHandle(h)
        try:
            raw='xianzaishurufahouxuanyouenti'
            request=('Z2\tzh\t0\t'+raw.encode().hex()+'\t'+ '前文 😀'.encode().hex()+'\t').encode()
            assert call(request,.2).startswith('Z1\t1\t200\t1\t0\t0\t0\n')
            for _ in range(12):assert call(request).startswith('Z1\t')
            assert '\nE\t' in call(b'Z2\tzh\t0\tbadhex\t\t')
            handles=[connect() for _ in range(4)]
            for h in handles:k.CloseHandle(h)
            assert call(request).startswith('Z1\t')
            assert broker.poll() is None
            print('PASS: 16 native pipe checks (framing, delayed read, malformed input, reconnect)')
        finally:
            broker.terminate();broker.wait(timeout=10)
    http.shutdown()
if __name__=='__main__':main()
