// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <windows.h>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <optional>
#include <sstream>
#include "ZephyrComposition.h"

namespace zephyr {
inline std::string hex(const std::string& s) {
  const char* h="0123456789abcdef";std::string out;
  for(unsigned char c:s) { out+=h[c>>4];out+=h[c&15]; }return out;
}
inline std::wstring unhex(const std::string& s) {
  if(s.size()>16000 || s.size()%2) return {};
  std::string utf8;
  for(size_t i=0;i<s.size();i+=2) {
    auto nibble=[](char c)->int { if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;return -1; };
    int a=nibble(s[i]),b=nibble(s[i+1]);if(a<0||b<0)return {};utf8+=char(a*16+b);
  }
  int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,utf8.data(),int(utf8.size()),nullptr,0);
  if(n<1||n>2000)return {};std::wstring out(n,L' ');
  MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,utf8.data(),int(utf8.size()),out.data(),n);return out;
}
class AiPipe {
 public:
  struct Work { DWORD session;uint64_t revision;std::string input;bool chinese,traditional;std::string before,after; };
  struct Result { DWORD session;uint64_t revision;std::vector<std::wstring> candidates;bool segmentation=true,enterOriginal=true,spaceOriginal=false;std::wstring error;bool assistantEnabled=false; };
  AiPipe():thread([this]{run();}) {}
  ~AiPipe() {
    { std::lock_guard<std::mutex> lock(mutex);stop=true;if(pipe!=INVALID_HANDLE_VALUE)CancelIoEx(pipe,nullptr); }
    cv.notify_all();thread.join();
  }
  void submit(Work work) {
    { std::lock_guard<std::mutex> lock(mutex);pending=std::move(work);result.reset();++generation;
      if(pipe!=INVALID_HANDLE_VALUE)CancelIoEx(pipe,nullptr); }
    cv.notify_all();
  }
  void cancel(DWORD session) {
    std::lock_guard<std::mutex> lock(mutex);
    if(pending&&pending->session==session)pending.reset();
    if(result&&result->session==session)result.reset();
    ++generation;if(pipe!=INVALID_HANDLE_VALUE)CancelIoEx(pipe,nullptr);
  }
  std::optional<Result> take(DWORD session) {
    std::lock_guard<std::mutex> lock(mutex);
    if(!result||result->session!=session)return {};auto r=std::move(result);result.reset();return r;
  }
 private:
  std::mutex mutex;std::condition_variable cv;bool stop=false;uint64_t generation=0;
  std::optional<Work> pending;std::optional<Result> result;HANDLE pipe=INVALID_HANDLE_VALUE;
  std::thread thread;int debounce=200;
  void run() {
    while(true) {
      Work w;uint64_t token;
      {
        std::unique_lock<std::mutex> lock(mutex);cv.wait(lock,[&]{return stop||pending.has_value();});if(stop)return;
        token=generation;
        if(cv.wait_for(lock,std::chrono::milliseconds(debounce),[&]{return stop||generation!=token;}))continue;
        w=*pending;pending.reset();
      }
      wchar_t username[256];DWORD size=256;
      if(!GetUserNameW(username,&size))continue;
      std::wstring name=L"\\\\.\\pipe\\ZephyrAI-"+std::wstring(username);
      HANDLE h=CreateFileW(name.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,FILE_FLAG_OVERLAPPED,nullptr);
      if(h==INVALID_HANDLE_VALUE)continue;
      { std::lock_guard<std::mutex> lock(mutex);if(stop||token!=generation){CloseHandle(h);continue;}pipe=h; }
      DWORD mode=PIPE_READMODE_MESSAGE;SetNamedPipeHandleState(h,&mode,nullptr,nullptr);
      std::string payload="Z2\t"+std::string(w.chinese?"zh":"en")+"\t"+(w.traditional?"1":"0")+"\t"+hex(w.input)+"\t"+hex(w.before)+"\t"+hex(w.after);
      char output[131072];DWORD bytes=0;OVERLAPPED ov{};ov.hEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);
      BOOL ok=TransactNamedPipe(h,payload.data(),DWORD(payload.size()),output,sizeof(output),&bytes,&ov);
      if(!ok&&GetLastError()==ERROR_IO_PENDING) {
        if(WaitForSingleObject(ov.hEvent,65000)==WAIT_OBJECT_0)ok=GetOverlappedResult(h,&ov,&bytes,FALSE);
        else { CancelIoEx(h,&ov);GetOverlappedResult(h,&ov,&bytes,TRUE); }
      }
      {
        std::lock_guard<std::mutex> lock(mutex);pipe=INVALID_HANDLE_VALUE;
        if(ok&&token==generation&&!stop&&bytes<=sizeof(output)) {
          std::istringstream stream(std::string(output,bytes));std::string line;
          Result r{w.session,w.revision,{}};
          if(std::getline(stream,line)&&line.rfind("Z1\t",0)==0) {
            r.segmentation=line.size()>3&&line[3]=='1';
            auto pos=line.find('\t',3);if(pos!=std::string::npos) {
              try { debounce=std::clamp(std::stoi(line.substr(pos+1)),50,2000); }catch(...){}
            }
            std::istringstream header(line);std::string field;std::vector<std::string> fields;
            while(std::getline(header,field,'\t'))fields.push_back(field);
            if(fields.size()>=5){r.enterOriginal=fields[3]=="1";r.spaceOriginal=fields[4]=="1";}
            if(fields.size()>=6)r.assistantEnabled=fields[5]=="1";
            while(std::getline(stream,line)) {
              if(line.rfind("E\t",0)==0)r.error=unhex(line.substr(2));
              else if(r.candidates.size()<8){auto v=unhex(line);if(!v.empty())r.candidates.push_back(v);}
            }
            result=std::move(r);
          }
        }
      }
      CloseHandle(ov.hEvent);CloseHandle(h);
    }
  }
};
}
