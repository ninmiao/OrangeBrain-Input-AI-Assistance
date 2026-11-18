#define UNICODE
#define _UNICODE
#include "ZephyrAiPipe.h"
#include <iostream>
#include <atomic>
int main() {
  auto name=L"\\\\.\\pipe\\Zephyr-stream-fixture-"+std::to_wstring(GetCurrentProcessId());
  HANDLE ready=CreateEventW(nullptr,TRUE,FALSE,nullptr);
  std::atomic<int> served{0};
  std::atomic<bool> manualReceived{false};
  std::thread server([&] {
    for(int i=0;i<3;++i) {
      HANDLE pipe=CreateNamedPipeW(name.c_str(),PIPE_ACCESS_DUPLEX,PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT,1,131072,16384,0,nullptr);
      SetEvent(ready);
      if(ConnectNamedPipe(pipe,nullptr)||GetLastError()==ERROR_PIPE_CONNECTED) {
        char request[16384];DWORD n=0;
        if(ReadFile(pipe,request,sizeof(request),&n,nullptr)&&std::string(request,n).rfind("Z4\t",0)==0) {
          const std::string wire(request,n), suffix="\tassistant";
          if(wire.size()>=suffix.size()&&wire.compare(wire.size()-suffix.size(),suffix.size(),suffix)==0)
            manualReceived=true;
          ++served;
          std::string first="Z1\t1\t50\t1\t0\t1\t1\n"+zephyr::hex("corrected")+"\n";
          WriteFile(pipe,first.data(),DWORD(first.size()),&n,nullptr);
          Sleep(350);
          std::string last="Z1\t1\t50\t1\t0\t1\t0\n"+zephyr::hex("corrected")+"\n"+zephyr::hex("assistant")+"\n";
          WriteFile(pipe,last.data(),DWORD(last.size()),&n,nullptr);
          // Wait for the reader only on successful, non-cancelled requests.
          FlushFileBuffers(pipe);
        }
      }
      DisconnectNamedPipe(pipe);CloseHandle(pipe);
    }
  });
  int checks=0;bool failed=false;
  {
    zephyr::AiPipe client(name);
    auto take=[&](int revision,int size) {
      for(int i=0;i<100;++i) {
        Sleep(20);auto r=client.take(123);
        if(r){if(r->revision!=revision||r->candidates.size()!=size){failed=true;return false;}
          auto status=client.status(123,revision);
          if(size==1 && status!=L"助手生成中…"){std::wcerr<<L"First status: "<<status<<L"\n";failed=true;}
          if(size==2 && status!=L"✓ 已返回" && status!=L"后台未连接"){std::wcerr<<L"Final status: "<<status<<L"\n";failed=true;}
          checks+=2;return true;}
      }
      failed=true;return false;
    };
    WaitForSingleObject(ready,5000);ResetEvent(ready);
    client.submit({123,1,"one",true,false});take(1,1);take(1,2);
    WaitForSingleObject(ready,5000);ResetEvent(ready);
    client.submit({123,2,"two",true,false});take(2,1);client.cancel(123);
    WaitForSingleObject(ready,5000);
    if(client.take(123))failed=true;else ++checks;
    client.submit({123,3,"three",true,false,"","",true});take(3,1);take(3,2);
  }
  server.join();CloseHandle(ready);
  {
    zephyr::AiPipe missing(name+L"-missing");
    if(missing.status(9,1)!=L"后台未连接")failed=true;else ++checks;
  }
  if(failed||served!=3||!manualReceived)return 1;
  std::cout<<checks<<" streaming pipe checks passed: early correction, final assistant, cancellation, reconnect\n";
}
