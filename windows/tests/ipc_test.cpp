#define UNICODE
#define _UNICODE
#include <windows.h>
#include <WeaselIPC.h>
#include <ResponseParser.h>
#include <iostream>
#include <stdexcept>

int checks=0;
void check(bool value,const char* message){++checks;if(!value)throw std::runtime_error(message);}
int main() {
  SetConsoleOutputCP(CP_UTF8);
  try {
    weasel::Client client;check(client.Connect(),"input server must be running");client.StartSession();
    weasel::Context ctx;weasel::Status status;std::wstring commit;weasel::Config config;weasel::UIStyle style;
    auto response=[&] {ctx.clear();commit.clear();weasel::ResponseParser parser(&commit,&ctx,&status,&config,&style);check(client.GetResponseData(std::ref(parser)),"response must parse");};
    auto key=[&](UINT code,UINT mask=0) {bool handled=client.ProcessKeyEvent(weasel::KeyEvent(code,mask));response();return handled;};
    auto type=[&](const std::string& input){for(unsigned char ch:input)key(ch);};
    response();
    for(bool mouse:{false,true}) {
      type("xianzaishurufahouxuanyouenti");
      size_t index=0;
      for(;index<ctx.cinfo.candies.size();++index)if(ctx.cinfo.candies[index].str==L"现在")break;
      check(index<ctx.cinfo.candies.size(),"prefix candidate is available");
      if(mouse) {client.SelectCandidateOnCurrentPage(index);check(key(0),"partial click refreshes without a commit");}
      else key(UINT('1'+index));
      check(commit.empty(),"prefix choice must not commit or discard the tail");
      check(status.composing,"prefix selection remains composing");
      check(ctx.preedit.str.find(L"现在")==0,"chosen phrase appears in preedit");
      check(ctx.preedit.str.find(L"shu")!=std::wstring::npos,"remaining pinyin is preserved");
      for(int i=0;i<20&&status.composing;++i)key('1');
      check(!status.composing,"remaining segments can be selected to completion");
      check(commit.find(L"现在")==0&&commit.size()>2,"final commit keeps selected prefix and remaining text");
    }
    type("nihao");check(status.composing,"Chinese composition visible");check(ctx.preedit.str==L"nihao","raw input shown");
    check(!ctx.cinfo.candies.empty()&&ctx.cinfo.candies[0].str==L"你好","real Rime simplified candidate");
    check(ctx.cinfo.labels[0].str==L"1","candidate label is plain digit");
    key('1');check(commit==L"你好","plain digit selects Chinese candidate");check(!status.composing,"composition ends after commit");
    type("hello world");key(ibus::Return);check(commit==L"hello world","Chinese mode Enter submits literal English");
    type("nihao");key(ibus::Return);check(commit==L"nihao","Enter never forces Chinese candidate");
    type("nihao");key(ibus::Tab);check(commit==L"你好","Tab still selects candidate");
    key('T',ibus::CONTROL_MASK|ibus::SHIFT_MASK);type("hanyu");
    check(!ctx.cinfo.candies.empty()&&ctx.cinfo.candies[0].str==L"漢語","real OpenCC traditional candidate");
    key(ibus::Escape);key('T',ibus::CONTROL_MASK|ibus::SHIFT_MASK);
    type("hanbaowang haochi");check(ctx.preedit.str==L"hanbaowang haochi","Chinese spaces retained");check(commit.empty(),"Chinese space did not commit");key(ibus::Escape);
    (key(ibus::Shift_L,ibus::SHIFT_MASK),key(ibus::Shift_L,ibus::RELEASE_MASK));type("I wnated to recieve teh package.");
    check(status.composing,"English must show IME composition");check(ctx.preedit.str==L"I wnated to recieve teh package.","English spaces and punctuation retained");check(!ctx.cinfo.candies.empty(),"English original candidate available offline");
    key(ibus::Return,ibus::CONTROL_MASK);check(commit==L"I wnated to recieve teh package.","explicit original commit");
    type("hello world");key(ibus::Return);check(commit==L"hello world","English mode Enter submits literal input");
    type("helo");key(ibus::Left);key(ibus::Left);key('l');check(ctx.preedit.str==L"hello","caret edit");key(ibus::BackSpace);check(ctx.preedit.str==L"helo","caret delete");
    key(ibus::Escape);type("cancel this");client.FocusOut();client.FocusIn();key(ibus::Shift_L);check(!status.composing,"focus loss cancels old input");
    type("keep me");key(ibus::Control_L,ibus::CONTROL_MASK);check(ctx.preedit.str==L"keep me","Ctrl down preserves composition");
    key(ibus::Return,ibus::CONTROL_MASK);check(commit==L"keep me","physical Ctrl then Enter commits original");
    for(char digit:std::string("0123456789")) {check(!key(digit),"idle number goes to host");check(!status.composing,"idle number does not create composition");}
    type("plain choice");key('1');check(commit==L"plain choice","plain digit selects English candidate");
    type("v");key('2');check(ctx.preedit.str==L"v2","unassigned digit remains literal");key(ibus::Escape);
    type("v");key(ibus::KP_1);check(ctx.preedit.str==L"v1","numpad enters literal digit while composing");key(ibus::Escape);
    check(!key(ibus::KP_1),"idle numpad digit passes through");
    type("shift");key('1',ibus::SHIFT_MASK);check(commit.empty()&&ctx.preedit.str==L"shift1","shifted digit is not a selection");key(ibus::Escape);
    (key(ibus::Shift_L,ibus::SHIFT_MASK),key(ibus::Shift_L,ibus::RELEASE_MASK));type("shi");
    check(ctx.cinfo.candies.size()==5,"first page has five candidates");
    auto second=ctx.cinfo.candies[1].str;key('2');check(commit==second,"plain 2 chooses second Chinese candidate");
    type("shi");for(int i=0;i<5;i++)key(ibus::Down);
    check(ctx.cinfo.currentPage==1&&!ctx.cinfo.candies.empty(),"second page available");
    auto paged=ctx.cinfo.candies[0].str;key('1');check(commit==paged,"plain 1 selects within current page");
    (key(ibus::Shift_L,ibus::SHIFT_MASK),key(ibus::Shift_L,ibus::RELEASE_MASK));
    type("select me");key(ibus::Alt_L,ibus::MOD1_MASK);check(ctx.preedit.str==L"select me","Alt down preserves composition");
    key('1',ibus::MOD1_MASK);check(commit==L"select me","physical Alt then digit selects candidate");
    type("click me");client.SelectCandidateOnCurrentPage(0);key(0);check(commit==L"click me","mouse selection produces commit without synthetic keystroke");
    client.EndSession();std::cout<<checks<<" native IPC assertions passed\n";return 0;
  }catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
