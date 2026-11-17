#include "ZephyrComposition.h"
#include "ZephyrKeySettings.h"
#include <iostream>
#include <stdexcept>

int checks=0;
void check(bool condition,const char* message) {++checks;if(!condition)throw std::runtime_error(message);}
int main() {
  try {
    const std::filesystem::path settings="keyprefs-fixture.json";
    {std::ofstream f(settings);f<<R"({"enabled":true,"enterOriginal":false,"spaceOriginal":true})";}
    auto prefs=zephyr::readKeyPreferences(settings);
    check(prefs&&!prefs->enterOriginal&&prefs->spaceOriginal,"local shortcut settings ignore cloud state");
    {std::ofstream f(settings);f<<R"({"candidateCount":3})";}
    check(!zephyr::readKeyPreferences(settings),"legacy settings keep pipe compatibility");
    {std::ofstream f(settings);f<<"invalid";}
    check(!zephyr::readKeyPreferences(settings),"invalid local settings never crash typing");
    std::filesystem::remove(settings);

    for(bool chinese:{true,false}) {
      zephyr::Composition z;z.chinese=chinese;
      for(char c:std::string("hanbaowang haochi"))z.insert(c);
      check(z.originalKey(true,false),"Enter defaults to literal input");check(!z.originalKey(false,true),"Space defaults to boundary");
      z.enterOriginal=false;z.spaceOriginal=true;
      check(!z.originalKey(true,false),"Enter candidate setting honored");check(z.originalKey(false,true),"Space literal setting honored");
      check(z.input=="hanbaowang haochi","space must stay in composition");check(z.commit.empty(),"no premature commit");
      auto version=z.revision;z.insert('!');check(!z.adopt(version,{L"stale"}),"reject older revision");
      check(z.adopt(z.revision,{L"汉堡王好吃",L"Hamburger King is delicious"}),"accept current result");
      z.choose(1);check(z.commit==L"Hamburger King is delicious","choose exact candidate");check(z.input.empty(),"clear after commit");
      check(!z.adopt(version,{L"late"}),"late response cannot revive composition");
      z.commit.clear();for(char c:std::string("helo"))z.insert(c);z.caret=2;z.insert('l');check(z.input=="hello","insert at caret");
      z.backspace();check(z.input=="helo","backspace at caret");z.erase();check(z.input=="heo","delete at caret");
      version=z.revision;z.language();check(!z.adopt(version,{L"wrong language"}),"language change invalidates response");
      z.clear();check(z.caret==0&&z.candidates.empty(),"cancel clears all candidate state");
      for(int i=0;i<301;i++)z.insert('a');check(z.input.size()==300,"input bounded to 300");
    }
    zephyr::Composition z;z.insert('x');z.add(L"x",L"Original");z.adopt(z.revision,{L"one",L"one",L"two"});
    check(z.candidates==std::vector<std::wstring>({L"one",L"two",L"x"}),"ranking and deduplication");
    zephyr::Composition mapped;mapped.insert('x');mapped.add(L"现在",L"Rime",2);
    auto previous=mapped.revision;mapped.adopt(previous,{L"完整纠错"});
    check(mapped.rimeIndices==std::vector<int>({-1,2}),"AI ranking preserves native candidate indices");
    mapped.partialSelection=true;mapped.changed();
    check(!mapped.adopt(previous,{L"old"}),"partial selection invalidates pending AI output");
    mapped.clear();check(!mapped.partialSelection&&mapped.rimeIndices.empty(),"cancel clears segment state");
    z.choose(50);check(z.input=="x","out of bounds selection is ignored");
    for(bool chinese:{true,false}) {
      for(int slot=1;slot<=5;++slot) {
        zephyr::Composition choice;choice.chinese=chinese;choice.insert('x');
        for(int i=0;i<8;++i)choice.add(L"candidate"+std::to_wstring(i),L"AI");
        check(choice.chooseDigit(slot),"direct digit selects existing slot");
        check(choice.commit==L"candidate"+std::to_wstring(slot-1),"digit selects correct rank");
        check(choice.input.empty(),"selection clears pending input");
      }
      zephyr::Composition choice;choice.chinese=chinese;choice.insert('x');
      for(int i=0;i<8;++i)choice.add(L"candidate"+std::to_wstring(i),L"Rime");
      choice.page=1;
      check(!choice.chooseDigit(4)&&!choice.chooseDigit(0)&&!choice.chooseDigit(6),"missing slot does not consume a digit");
      check(choice.input=="x"&&choice.commit.empty(),"invalid selection preserves composition");
      check(choice.chooseDigit(2)&&choice.commit==L"candidate6","digit respects current page");
      check(!choice.chooseDigit(1),"idle digit is not consumed");
    }
    for(bool chinese:{true,false}) {
      zephyr::Composition mixed;mixed.chinese=chinese;
      for(char c:std::string("hello123world2026"))mixed.insert(c);
      check(mixed.input=="hello123world2026"&&mixed.commit.empty(),"literal keypad digits remain in mixed composition");
      mixed.add(L"hello123world2026",L"Original");mixed.choose(0);
      check(mixed.commit==L"hello123world2026","mixed numbers commit without loss");
    }
    zephyr::Composition errorState;errorState.insert('n');errorState.add(L"你好",L"Rime");
    errorState.aiError=L"Preset unavailable";
    check(errorState.candidates.size()==1&&errorState.commit.empty(),"preset error is never a selectable candidate");
    errorState.insert('i');check(errorState.aiError.empty(),"new input clears stale preset failure");
    errorState.aiError=L"Preset unavailable";errorState.clear();check(errorState.aiError.empty(),"cancel clears preset failure");
    {
    zephyr::Composition pending;pending.insert('a');pending.add(L"本地",L"Rime",2);
    auto previous=pending.revision;pending.adopt(previous,{L"旧 AI"});
    check(pending.applyConfiguration(123),"new configuration invalidates");check(pending.refreshPending,"configuration requests redraw");
    check(pending.candidates.size()==1&&pending.candidates[0]==L"本地","local candidate survives settings change");
    check(!pending.adopt(previous,{L"过期响应"}),"old response rejected after settings change");check(!pending.applyConfiguration(123),"same configuration does not restart");
    check(pending.applyConfiguration(124),"second configuration applies");check(pending.input=="a","configuration preserves pending input");
  }
  {
    zephyr::Composition roles;roles.insert('x');roles.add(L"local",L"Rime",0);
    check(roles.adopt(roles.revision,{L"same",L"same"},true),"dual response adopted");
    check(roles.candidates.size()==3&&roles.comments[0]!=roles.comments[1],"identical role candidates retained");
    roles.applyConfiguration(1);
    check(roles.candidates.size()==1&&roles.candidates[0]==L"local","both AI roles invalidated");
    roles.adopt(roles.revision,{L"corrected",L"answer"},true);roles.choose(1);
    check(roles.commit==L"answer","assistant selection inserts only content");
  }
  std::cout<<checks<<" native composition checks passed\n";return 0;
  } catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
