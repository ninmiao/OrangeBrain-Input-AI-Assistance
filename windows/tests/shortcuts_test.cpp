#include "OrangeCellShortcuts.h"
#include "OrangeCellKeySettings.h"
#include <iostream>
#include <stdexcept>
using namespace orangecell;
int main() {
  int checks=0;auto check=[&](bool ok){++checks;if(!ok)throw std::runtime_error("shortcut regression");};
  constexpr int S=ibus::SHIFT_MASK,C=ibus::CONTROL_MASK,U=ibus::RELEASE_MASK;
  using A=ShortcutAction;
  for(int shift:{ibus::Shift_L,ibus::Shift_R}) {
    ShortcutState s;
    check(s.process(shift,S,0,"shift","ctrl_shift_t")==A::None);
    check(s.process(0,0,100,"shift","ctrl_shift_t")==A::None);
    check(s.process(shift,U,200,"shift","ctrl_shift_t")==A::Language);
    check(s.process(shift,U,201,"shift","ctrl_shift_t")==A::None);
    s.process(shift,S,300,"shift","ctrl_shift_t");
    s.process('A',S,350,"shift","ctrl_shift_t");
    check(s.process(shift,U,400,"shift","ctrl_shift_t")==A::None);
    s.process(shift,S,500,"shift","ctrl_shift_t");
    s.process(ibus::Left,S,550,"shift","ctrl_shift_t");
    check(s.process(shift,U,600,"shift","ctrl_shift_t")==A::None);
    s.process(shift,S,700,"shift","ctrl_shift_t");
    check(s.process(shift,U,1300,"shift","ctrl_shift_t")==A::None);
    s.process(shift,S,1400,"shift","ctrl_shift_t");s.reset();
    check(s.process(shift,U,1500,"shift","ctrl_shift_t")==A::None);
    for(auto selected:{"shift_left","shift_right","disabled","ctrl_space"}) {
      s.process(shift,S,1600,selected,"ctrl_shift_t");
      bool expected=(std::string(selected)=="shift_left"&&shift==ibus::Shift_L)||(std::string(selected)=="shift_right"&&shift==ibus::Shift_R);
      check((s.process(shift,U,1700,selected,"ctrl_shift_t")==A::Language)==expected);
    }
  }
  for(auto script:{"ctrl_shift_t","ctrl_shift_f","ctrl_shift_c"}) {
    ShortcutState s;int key=std::string(script).back();
    check(s.process(key,C|S,1,"shift",script)==A::Script);
    check(s.process(key,C,2,"shift",script)==A::None);
    check(s.process(key,C|S|U,3,"shift",script)==A::None);
    check(s.process(ibus::Shift_L,U,4,"shift",script)==A::None);
  }
  ShortcutState s;
  check(s.process(' ',C,1,"ctrl_space","disabled")==A::Language);
  check(s.process(' ',C|S,2,"ctrl_space","disabled")==A::None);
  check(s.process(' ',C|S,3,"ctrl_shift_space","disabled")==A::Language);
  check(s.process(' ',C,4,"shift","disabled")==A::None);
  check(s.process('T',C|S,5,"shift","disabled")==A::None);
  check(shortcutChord("f8",ibus::F8,0));
  check(shortcutChord("f9",ibus::F9,0));
  check(shortcutChord("f10",ibus::F10,0));
  check(shortcutChord("ctrl_shift_f8",ibus::F8,C|S));
  check(!shortcutChord("f8",ibus::F8,U));
  check(!shortcutChord("f8",ibus::F8,C|S));
  check(!shortcutChord("disabled",ibus::F8,0));
  check(candidateListKey('1',0,true,true));
  check(candidateListKey('5',ibus::ALT_MASK,true,true));
  check(!candidateListKey('1',S,true,true));
  check(!candidateListKey('1',U,true,true));
  check(candidateListKey(ibus::Tab,S,true,true));
  check(candidateListKey(ibus::Down,0,true,true));
  check(candidateListKey(ibus::Return,0,false,true));
  check(!candidateListKey(ibus::Return,0,true,true));
  check(!candidateListKey(ibus::Return,C,false,false));
  check(candidateListKey(' ',0,true,false));
  check(!candidateListKey(' ',0,true,true));
  check(!candidateListKey(ibus::KP_1,0,false,false));
  const std::filesystem::path path="shortcut-fixture.json";
  {std::ofstream f(path);f<<R"({"languageShortcut":"ctrl_space","scriptShortcut":"ctrl_shift_f"})";}
  auto prefs=readKeyPreferences(path);check(prefs&&prefs->languageShortcut=="ctrl_space"&&prefs->scriptShortcut=="ctrl_shift_f");
  check(prefs&&prefs->aiShortcut=="f8");
  {std::ofstream f(path);f<<R"({"languageShortcut":"shift","enabled":false,"settingsRevision":3,"assistantEnabled":true,"aiShortcut":"f9","wordSegmentation":false})";}
  prefs=readKeyPreferences(path);check(prefs&&prefs->aiEnabled&&prefs->aiShortcut=="f9"&&!prefs->wordSegmentation);
  std::filesystem::remove(path);
  std::cout<<checks<<" shortcut checks passed\n";
}
