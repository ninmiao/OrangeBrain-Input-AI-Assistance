"""Pipe clients retaining handles must not retire all broker workers. No cloud calls."""
from pathlib import Path
import ctypes as C
from ctypes import wintypes as W
import subprocess,tempfile,time,os
ROOT=Path(__file__).resolve().parents[2]
k=C.WinDLL('kernel32',use_last_error=True)
k.CreateFileW.argtypes=[W.LPCWSTR,W.DWORD,W.DWORD,W.LPVOID,W.DWORD,W.DWORD,W.HANDLE];k.CreateFileW.restype=W.HANDLE
k.WaitNamedPipeW.argtypes=[W.LPCWSTR,W.DWORD];k.WaitNamedPipeW.restype=W.BOOL
k.WriteFile.argtypes=[W.HANDLE,W.LPCVOID,W.DWORD,C.POINTER(W.DWORD),W.LPVOID];k.WriteFile.restype=W.BOOL
k.ReadFile.argtypes=[W.HANDLE,W.LPVOID,W.DWORD,C.POINTER(W.DWORD),W.LPVOID];k.ReadFile.restype=W.BOOL
k.CloseHandle.argtypes=[W.HANDLE]
with tempfile.TemporaryDirectory(prefix='zephyr-pipe-lifetime-') as folder:
 pipe='\\\\.\\pipe\\Zephyr-lifetime-'+str(os.getpid())
 broker=subprocess.Popen([str(ROOT/'windows/build/native-app/Release/ZephyrBroker.exe'),'--data-dir',folder,'--test-pipe',pipe],creationflags=subprocess.CREATE_NO_WINDOW)
 handles=[]
 def connect():
  until=time.monotonic()+5
  while time.monotonic()<until:
   if k.WaitNamedPipeW(pipe,100):
    h=k.CreateFileW(pipe,0xC0000000,0,None,3,0,None)
    if h not in (None,C.c_void_p(-1).value):return h
   time.sleep(.01)
  raise AssertionError('Broker has no accepting worker; exit='+str(broker.poll()))
 def exchange(h):
  request=b'Z4\tzh\t0\t68656c6c6f\t\t';count=W.DWORD()
  assert k.WriteFile(h,request,len(request),C.byref(count),None)
  buf=C.create_string_buffer(131072)
  assert k.ReadFile(h,buf,len(buf),C.byref(count),None)
  assert buf.raw[:count.value].startswith(b'Z1\t')
 try:
  for round in range(20):
   handles=[connect() for _ in range(4)]
   for h in handles:exchange(h)
   # These handles still count toward the maximum number of pipe instances,
   # even after the server disconnects its end.
   time.sleep(.15)
   assert broker.poll() is None,'Broker exited after disconnect with client handles retained'
   for h in handles:k.CloseHandle(h)
   handles=[]
  h=connect();exchange(h);k.CloseHandle(h)
  print('PASS: 20 rounds / 81 requests; all workers survive delayed client close')
 finally:
  for h in handles:k.CloseHandle(h)
  if broker.poll() is None:broker.terminate()
  broker.wait(timeout=5)
