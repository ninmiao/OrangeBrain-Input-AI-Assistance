#define UNICODE
#define _UNICODE
#include <windows.h>
#include <WeaselIPC.h>
#include <ResponseParser.h>
#include <iostream>
#include <algorithm>
#include <cwctype>
int main() {
  weasel::Client client;if(!client.Connect())return 2;client.StartSession();
  weasel::Context ctx;weasel::Status status;std::wstring commit;weasel::Config config;weasel::UIStyle style;
  auto response=[&] {ctx.clear();commit.clear();weasel::ResponseParser p(&commit,&ctx,&status,&config,&style);return client.GetResponseData(std::ref(p));};
  auto key=[&](UINT code,UINT mask=0) {client.ProcessKeyEvent(weasel::KeyEvent(code,mask));return response();};
  response();
  for(int language=0;language<2;++language) {
    if(language){key(ibus::Shift_L,ibus::SHIFT_MASK);key(ibus::Shift_L,ibus::RELEASE_MASK);}
    const std::string raw=language?"I wnated to recieve teh updated report before our meeting tomorrow, please keep the original file.":"jintianxiaban yihouwoxianghexiaowangyiqiquchi huoguo danshimingtianshangwuhaiyouhuiyi suoyiwomenzaodianhuijia";
    for(char c:raw)key(c);
    bool ready=false;
    for(int i=0;i<300;++i) {
      Sleep(100);
      if(client.ProcessKeyEvent(weasel::KeyEvent(0,0))) {
        if(!response())return 3;
        if(!ctx.cinfo.comments.empty()&&ctx.cinfo.comments[0].str.rfind(L"AI",0)==0) {
          bool waiting=ctx.cinfo.comments[0].str==L"AI 纠错" &&
            (ctx.cinfo.candies.size()<2 || ctx.cinfo.candies[1].str==L"助手生成中…");
          if(!waiting){ready=true;break;}
        }
      }
    }
    if(!ready){std::cerr<<"Live AI candidate timeout, mode="<<language<<"\n";return 4;}
    if(ctx.preedit.str!=std::wstring(raw.begin(),raw.end())||!commit.empty()||!status.composing)return 5;
    std::wstring first=ctx.cinfo.candies[0].str,normalized=first;
    std::transform(normalized.begin(),normalized.end(),normalized.begin(),::towlower);
    // Semantic accuracy is measured by gold.jsonl, not this transport test.
    // Verify both candidate languages, then commit the exact returned text.
    bool han=std::any_of(first.begin(),first.end(),[](wchar_t c){return c>=0x3400&&c<=0x9fff;});
    bool latin=std::any_of(first.begin(),first.end(),[](wchar_t c){return (c>=L'a'&&c<=L'z')||(c>=L'A'&&c<=L'Z');});
    if(language ? (han||!latin) : !han) {std::cerr<<"Candidate language contract failed, mode="<<language<<"\n";return 6;}
    int bytes=WideCharToMultiByte(CP_UTF8,0,first.data(),int(first.size()),nullptr,0,nullptr,nullptr);std::string utf8(bytes,' ');
    WideCharToMultiByte(CP_UTF8,0,first.data(),int(first.size()),utf8.data(),bytes,nullptr,nullptr);
    std::cout<<"mode="<<language<<" candidate="<<utf8<<"\n";
    if(ctx.cinfo.comments[0].str==L"AI 纠错") {
      if(ctx.cinfo.candies.size()<2 || ctx.cinfo.comments[1].str!=L"AI 助手")return 8;
      auto assistant=ctx.cinfo.candies[1].str;
      if(assistant.empty()||assistant==L"助手未完成")return 9;
      key('2');if(commit!=assistant||status.composing)return 10;
    } else {key(ibus::Tab);if(commit!=first||status.composing)return 7;}
  }
  client.EndSession();std::cout<<"LIVE Chinese and English: C++ typing -> native broker -> model -> ranked candidate -> commit passed\n";return 0;
}
