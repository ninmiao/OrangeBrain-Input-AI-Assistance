#define UNICODE
#define _UNICODE
#include <windows.h>
#include <WeaselIPC.h>
#include <ResponseParser.h>
#include <fstream>
#include <iostream>
#include <chrono>
#include <algorithm>

int main(int argc,char**argv) {
  if(argc!=2)return 2;
  weasel::Client client;if(!client.Connect())return 3;client.StartSession();
  weasel::Context ctx;weasel::Status status;std::wstring commit;weasel::Config config;weasel::UIStyle style;
  size_t assertions=0,cases=0;std::vector<double> latency;
  auto response=[&] {ctx.clear();commit.clear();weasel::ResponseParser parser(&commit,&ctx,&status,&config,&style);return client.GetResponseData(std::ref(parser));};
  auto key=[&](UINT code,UINT mask=0){auto start=std::chrono::steady_clock::now();client.ProcessKeyEvent(weasel::KeyEvent(code,mask));bool ok=response();latency.push_back(std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count());return ok;};
  response();bool chinese=true;std::ifstream stream(argv[1]);std::string line;
  while(std::getline(stream,line)) {
    if(line.size()<4)continue;
    bool next=line.substr(0,2)=="zh";auto raw=line.substr(3);
    if(next!=chinese){key(' ',ibus::CONTROL_MASK);chinese=next;}
    std::wstring expected;
    // Corpus replay uses keypad digits for literal text; number-row selection is covered by ipc_test.
    for(unsigned char ch:raw){expected+=wchar_t(ch);UINT code=(ch>='0'&&ch<='9')?ibus::KP_0+ch-'0':ch;if(!key(code)||ctx.preedit.str!=expected||!commit.empty()){std::cerr<<"FAIL case "<<cases<<" at character "<<expected.size()<<"\n";return 4;}assertions+=3;}
    if(!status.composing||ctx.cinfo.candies.empty())return 5;
    key(ibus::Return,ibus::CONTROL_MASK);if(commit!=expected||status.composing)return 6;assertions+=4;++cases;
  }
  client.EndSession();std::sort(latency.begin(),latency.end());
  std::cout<<"{\"cases\":"<<cases<<",\"assertions\":"<<assertions<<",\"key_events\":"<<latency.size()<<",\"p50_ms\":"<<latency[latency.size()/2]<<",\"p95_ms\":"<<latency[size_t(latency.size()*.95)]<<"}\n";return 0;
}
