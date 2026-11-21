#include "OrangeCellComposition.h"
#include "OrangeCellKeySettings.h"
#include <iostream>
#include <stdexcept>

int checks=0;
void check(bool condition,const char* message) {++checks;if(!condition)throw std::runtime_error(message);}
int main() {
  try {
    const std::filesystem::path settings="keyprefs-fixture.json";
    {std::ofstream f(settings);f<<R"({"enabled":true,"enterOriginal":false,"spaceOriginal":true})";}
    auto prefs=orangecell::readKeyPreferences(settings);
    check(prefs&&!prefs->enterOriginal&&prefs->spaceOriginal,"local shortcut settings ignore cloud state");
    {std::ofstream f(settings);f<<R"({"candidateCount":3})";}
    check(!orangecell::readKeyPreferences(settings),"legacy settings keep pipe compatibility");
    {std::ofstream f(settings);f<<"invalid";}
    check(!orangecell::readKeyPreferences(settings),"invalid local settings never crash typing");
    std::filesystem::remove(settings);

    for(bool chinese:{true,false}) {
      orangecell::Composition z;z.chinese=chinese;
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
    orangecell::Composition z;z.insert('x');z.add(L"x",L"Original");z.adopt(z.revision,{L"one",L"one",L"two"});
    check(z.candidates==std::vector<std::wstring>({L"one",L"two",L"x"}),"AI is first and deduplicates within its own results");
    orangecell::Composition mapped;mapped.insert('x');mapped.add(L"现在",L"Rime",2);
    auto previous=mapped.revision;mapped.adopt(previous,{L"现在"},true);
    check(mapped.rimeIndices==std::vector<int>({-1,2}),"same-text AI keeps the native partial choice and its index");
    mapped.partialSelection=true;mapped.changed();
    check(!mapped.adopt(previous,{L"old"}),"partial selection invalidates pending AI output");
    mapped.clear();check(!mapped.partialSelection&&mapped.rimeIndices.empty(),"cancel clears segment state");
    z.choose(50);check(z.input=="x","out of bounds selection is ignored");
    for(bool chinese:{true,false}) {
      for(int slot=1;slot<=5;++slot) {
        orangecell::Composition choice;choice.chinese=chinese;choice.insert('x');
        for(int i=0;i<8;++i)choice.add(L"candidate"+std::to_wstring(i),L"AI");
        check(choice.chooseDigit(slot),"direct digit selects existing slot");
        check(choice.commit==L"candidate"+std::to_wstring(slot-1),"digit selects correct rank");
        check(choice.input.empty(),"selection clears pending input");
      }
      orangecell::Composition choice;choice.chinese=chinese;choice.insert('x');
      for(int i=0;i<8;++i)choice.add(L"candidate"+std::to_wstring(i),L"Rime");
      choice.page=1;
      check(!choice.chooseDigit(4)&&!choice.chooseDigit(0)&&!choice.chooseDigit(6),"missing slot does not consume a digit");
      check(choice.input=="x"&&choice.commit.empty(),"invalid selection preserves composition");
      check(choice.chooseDigit(2)&&choice.commit==L"candidate6","digit respects current page");
      check(!choice.chooseDigit(1),"idle digit is not consumed");
    }
    for(bool chinese:{true,false}) {
      orangecell::Composition mixed;mixed.chinese=chinese;
      for(char c:std::string("hello123world2026"))mixed.insert(c);
      check(mixed.input=="hello123world2026"&&mixed.commit.empty(),"literal keypad digits remain in mixed composition");
      mixed.add(L"hello123world2026",L"Original");mixed.choose(0);
      check(mixed.commit==L"hello123world2026","mixed numbers commit without loss");
    }
    orangecell::Composition errorState;errorState.insert('n');errorState.add(L"你好",L"Rime");
    errorState.aiError=L"Preset unavailable";
    check(errorState.candidates.size()==1&&errorState.commit.empty(),"preset error is never a selectable candidate");
    errorState.insert('i');check(errorState.aiError.empty(),"new input clears stale preset failure");
    errorState.aiError=L"Preset unavailable";errorState.clear();check(errorState.aiError.empty(),"cancel clears preset failure");
    {
    orangecell::Composition pending;pending.insert('a');pending.add(L"本地",L"Rime",2);
    auto previous=pending.revision;pending.adopt(previous,{L"旧 AI"});
    check(pending.applyConfiguration(123),"new configuration invalidates");check(pending.refreshPending,"configuration requests redraw");
    check(pending.candidates.size()==1&&pending.candidates[0]==L"本地","local candidate survives settings change");
    check(!pending.adopt(previous,{L"过期响应"}),"old response rejected after settings change");check(!pending.applyConfiguration(123),"same configuration does not restart");
    check(pending.applyConfiguration(124),"second configuration applies");check(pending.input=="a","configuration preserves pending input");
  }
  {
    orangecell::Composition roles;roles.insert('x');roles.add(L"local",L"Rime",0);
    check(roles.adopt(roles.revision,{L"same",L"same"},true),"dual response adopted");
    check(roles.candidates.size()==3&&roles.comments[0]!=roles.comments[1],"identical role candidates retained");
    roles.applyConfiguration(1);
    check(roles.candidates.size()==1&&roles.candidates[0]==L"local","both AI roles invalidated");
    roles.adopt(roles.revision,{L"corrected",L"answer"},true);roles.chooseDigit(2);
    check(roles.commit==L"answer","assistant selection inserts only content");
  }
  {
    orangecell::Composition stream;stream.insert('x');
    for(int i=0;i<7;++i) stream.add(L"local "+std::to_wstring(i),L"Rime",i);
    stream.add(L"x",L"Original");
    check(stream.candidates[0]==L"local 0"&&stream.candidates[1]==L"local 1",
          "while AI waits, local candidates begin at slots one and two");
    stream.selected=4;
    stream.adopt(stream.revision,{L"corrected"},true);
    check(stream.selected==5&&stream.page==1&&stream.rimeIndices[5]==4,
          "first reorder follows the highlighted native candidate across pages");
    check(stream.candidates.size()==9&&stream.candidates[0]==L"corrected"&&stream.candidates[1]==L"local 0",
          "an unfinished assistant leaves slot two available to Rime");
    stream.adopt(stream.revision,{L"corrected",L"answer"},true);
    check(stream.selected==6&&stream.page==1&&stream.rimeIndices[6]==4,
          "assistant arrival follows the same native candidate");
    check(stream.candidates[1]==L"answer"&&stream.rimeIndices[2]==0,
          "assistant takes slot two and shifts locals in order");
    stream.retryAi();
    check(stream.selected==4&&stream.page==0&&stream.candidates[0]==L"local 0",
          "retry restores the local list and preserves its highlight");
    stream.adopt(stream.revision,{L"corrected"},true);
    stream.selected=0;stream.page=0;
    stream.adopt(stream.revision,{L"different correction",L"answer"},true);
    check(stream.selected==0&&stream.page==0&&stream.candidates[0]==L"corrected",
          "later frames keep the displayed correction and its highlight");
    stream.chooseDigit(1);check(stream.commit==L"corrected","digit one selects the displayed correction");
  }
  {
    orangecell::Composition context;
    context.insert('a');
    context.before = "first field";
    context.after = "end of first field";
    const auto previous = context.revision;
    context.commit = L"undelivered candidate";
    context.refreshPending = true;
    context.cancel();
    context.insert('b');
    check(context.before.empty() && context.after.empty(),
          "first request after focus change cannot contain the previous field");
    check(context.commit.empty() && !context.refreshPending,
          "focus cancellation discards unpublished commit and refresh");
    check(!context.adopt(previous, {L"old result"}), "old field result cannot enter new composition");
    context.before = "second field";
    context.after = "end of second field";
    context.add(L"confirmed", L"Original");
    context.choose(0);
    check(context.commit == L"confirmed", "ordinary selection preserves its commit for delivery");
    check(context.before.empty() && context.after.empty(),
          "committing a composition drops its cached surrounding range");
  }
  std::cout<<checks<<" native composition checks passed\n";return 0;
  } catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
