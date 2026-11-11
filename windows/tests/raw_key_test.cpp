#define UNICODE
#define _UNICODE
#include <windows.h>
#include <WeaselIPC.h>
#include <ResponseParser.h>
#include <iostream>
#include <stdexcept>
int main(int argc,char** argv) {
  bool originalEnter=argc<2||std::string(argv[1])!="candidate";
  bool originalSpace=argc>1&&std::string(argv[1])=="space";
  try {
    weasel::Client client;if(!client.Connect())throw std::runtime_error("server unavailable");client.StartSession();
    weasel::Context ctx;weasel::Status status;std::wstring commit;weasel::Config config;weasel::UIStyle style;
    auto response=[&]{ctx.clear();commit.clear();weasel::ResponseParser parser(&commit,&ctx,&status,&config,&style);if(!client.GetResponseData(std::ref(parser)))throw std::runtime_error("response");};
    auto key=[&](int k,int mask=0){client.ProcessKeyEvent(weasel::KeyEvent(k,mask));response();};
    auto type=[&]{for(char c:std::string("nihao"))key(c);bool ready=false;for(int i=0;i<100;i++){Sleep(50);if(client.ProcessKeyEvent(weasel::KeyEvent(0,0))){response();ready=true;break;}}if(!ready)throw std::runtime_error("config delivery timeout");};
    response();
    for(bool english:{false,true}) {
      if(english)(key(ibus::Shift_L,ibus::SHIFT_MASK),key(ibus::Shift_L,ibus::RELEASE_MASK));
      type();auto expected=originalEnter?L"nihao":ctx.cinfo.candies[0].str;
      key(ibus::Return);if(commit!=expected||status.composing)throw std::runtime_error("Enter action");
      type();key(' ');
      if(originalSpace) {if(commit!=L"nihao "||status.composing)throw std::runtime_error("Space raw action");}
      else {if(!commit.empty()||ctx.preedit.str!=L"nihao ")throw std::runtime_error("Space boundary action");key(ibus::Escape);}
    }
    client.EndSession();std::cout<<"Raw-key settings passed in Chinese and English (Enter="<<originalEnter<<", Space="<<originalSpace<<")\n";return 0;
  } catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
