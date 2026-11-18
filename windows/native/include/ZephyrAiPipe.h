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
  struct Work { DWORD session;uint64_t revision;std::string input;bool chinese,traditional;std::string before,after;bool manual=false; };
  struct Result { DWORD session;uint64_t revision;std::vector<std::wstring> candidates;bool segmentation=true,enterOriginal=true,spaceOriginal=false;std::wstring error;bool assistantEnabled=false,streaming=false; };
  explicit AiPipe(std::wstring testPipe={}):nameOverride(std::move(testPipe)),thread([this]{run();}) {}
  ~AiPipe() {
    { std::lock_guard<std::mutex> lock(mutex);stop=true;if(pipe!=INVALID_HANDLE_VALUE)CancelIoEx(pipe,nullptr); }
    cv.notify_all();thread.join();
  }
  void submit(Work work) {
    { std::lock_guard<std::mutex> lock(mutex);statusSession=work.session;statusRevision=work.revision;statusText=L"等待";pending=std::move(work);result.reset();++generation;
      if(pipe!=INVALID_HANDLE_VALUE)CancelIoEx(pipe,nullptr); }
    cv.notify_all();
  }
  void updateContext(DWORD session, uint64_t revision,
                     const std::string& before, const std::string& after) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!pending || pending->manual || pending->session != session ||
        pending->revision != revision) return;
    pending->before = before;
    pending->after = after;
  }
  void cancel(DWORD session) {
    std::lock_guard<std::mutex> lock(mutex);
    if(statusSession!=session)return;
    if(pending&&pending->session==session)pending.reset();
    if(result&&result->session==session)result.reset();
    statusText=L"已取消";
    ++generation;if(pipe!=INVALID_HANDLE_VALUE)CancelIoEx(pipe,nullptr);
    cv.notify_all();
  }
  std::wstring status(DWORD session,uint64_t revision) {
    std::lock_guard<std::mutex> lock(mutex);
    if(GetTickCount64()-checkedAt>1000) {
      checkedAt=GetTickCount64();wchar_t user[256];DWORD n=256;
      if(GetUserNameW(user,&n)) {
        auto name=nameOverride.empty()?L"\\\\.\\pipe\\ZephyrAI-"+std::wstring(user):nameOverride;
        BOOL available=WaitNamedPipeW(name.c_str(),1);auto error=GetLastError();
        missing=!available&&(error==ERROR_FILE_NOT_FOUND||error==ERROR_PATH_NOT_FOUND);
      }
    }
    if(missing)return L"后台未连接";
    return statusSession==session&&statusRevision==revision?statusText:L"待请求";
  }
  std::optional<Result> take(DWORD session) {
    std::lock_guard<std::mutex> lock(mutex);
    if(!result||result->session!=session)return {};auto r=std::move(result);result.reset();return r;
  }
 private:
  std::mutex mutex;std::condition_variable cv;bool stop=false;uint64_t generation=0;
  std::optional<Work> pending;std::optional<Result> result;HANDLE pipe=INVALID_HANDLE_VALUE;
  DWORD statusSession=0;uint64_t statusRevision=0,checkedAt=0;bool missing=false;std::wstring statusText;
  std::wstring nameOverride;
  std::thread thread;int debounce=200;
  void run() {
    while(true) {
      Work w;uint64_t token;
      {
        std::unique_lock<std::mutex> lock(mutex);cv.wait(lock,[&]{return stop||pending.has_value();});if(stop)return;
        token=generation;
        if(!pending->manual && cv.wait_for(lock,std::chrono::milliseconds(debounce),[&]{return stop||generation!=token;}))continue;
        w=*pending;pending.reset();
      }
      wchar_t username[256];DWORD size=256;
      if(!GetUserNameW(username,&size)) {
        std::lock_guard<std::mutex> lock(mutex);
        if(token==generation)statusText=L"无法连接后台";
        continue;
      }
      std::wstring name=nameOverride.empty()?L"\\\\.\\pipe\\ZephyrAI-"+std::wstring(username):nameOverride;
      auto open=[&] { return CreateFileW(name.c_str(),GENERIC_READ|GENERIC_WRITE,
                                        0,nullptr,OPEN_EXISTING,FILE_FLAG_OVERLAPPED,nullptr); };
      HANDLE h=open();
      auto error = h == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;
      if(error==ERROR_PIPE_BUSY && WaitNamedPipeW(name.c_str(),250)) {
        h=open();
        error=h==INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;
      }
      if(h==INVALID_HANDLE_VALUE) {
        std::lock_guard<std::mutex> lock(mutex);
        if(token==generation)
          statusText = error==ERROR_PIPE_BUSY ? L"后台忙" : L"后台未连接";
        continue;
      }
      { std::lock_guard<std::mutex> lock(mutex);if(stop||token!=generation){CloseHandle(h);continue;}pipe=h;missing=false;statusText=L"请求中…"; }
      DWORD mode=PIPE_READMODE_MESSAGE;SetNamedPipeHandleState(h,&mode,nullptr,nullptr);
      std::string payload="Z4\t"+std::string(w.chinese?"zh":"en")+"\t"+(w.traditional?"1":"0")+"\t"+hex(w.input)+"\t"+hex(w.before)+"\t"+hex(w.after);
      if(w.manual)payload+="\tassistant";
      char output[131072];DWORD bytes=0;OVERLAPPED ov{};ov.hEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);
      const auto deadline=GetTickCount64()+65000;
      auto operation=[&](bool writing,void* buffer,DWORD length) {
        std::unique_lock<std::mutex> ioLock(mutex);if(stop||token!=generation)return false;
        ResetEvent(ov.hEvent);bytes=0;
        BOOL ok=writing?WriteFile(h,buffer,length,&bytes,&ov):ReadFile(h,buffer,length,&bytes,&ov);
        auto error=GetLastError();ioLock.unlock();
        if(!ok&&error==ERROR_IO_PENDING) {
          auto now=GetTickCount64();
          if(now<deadline&&WaitForSingleObject(ov.hEvent,DWORD(deadline-now))==WAIT_OBJECT_0)
            ok=GetOverlappedResult(h,&ov,&bytes,FALSE);
          else {CancelIoEx(h,&ov);GetOverlappedResult(h,&ov,&bytes,TRUE);}
        }
        return ok!=0;
      };
      bool completed=false;
      if(operation(true,payload.data(),DWORD(payload.size()))) while(operation(false,output,sizeof(output))) {
        std::lock_guard<std::mutex> lock(mutex);
        if(token!=generation||stop||bytes>sizeof(output))break;
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
            r.streaming=fields.size()>=7&&fields[6]=="1";
            bool more=r.streaming;
            statusText=!r.error.empty()?(r.candidates.empty()?L"请求失败":L"部分返回"):more?(r.candidates.empty()?L"请求中…":L"助手生成中…"):
              (r.candidates.empty()?L"无结果":r.assistantEnabled&&r.candidates.size()==1?L"助手未完成":L"✓ 已返回");
            completed=!more;result=std::move(r);
            if(!more)break;
          } else break;
      }
      {std::lock_guard<std::mutex> lock(mutex);pipe=INVALID_HANDLE_VALUE;if(!completed&&token==generation&&!stop)statusText=L"连接中断";}
      CloseHandle(ov.hEvent);CloseHandle(h);
    }
  }
};
}
