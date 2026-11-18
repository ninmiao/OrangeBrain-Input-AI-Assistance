// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <windows.h>
#include <KeyEvent.h>
#include <string>
namespace zephyr {
inline bool candidateListKey(int key, int mask, bool enterOriginal, bool spaceIsLiteral) {
  if (mask & (ibus::RELEASE_MASK | ibus::CONTROL_MASK | ibus::SUPER_MASK))
    return false;
  if (key >= '1' && key <= '5') return !(mask & ibus::SHIFT_MASK);
  if (mask & ibus::ALT_MASK) return false;
  return key == ibus::Up || key == ibus::Down || key == ibus::Tab ||
         (key == ibus::Return && !enterOriginal) || (key == ' ' && !spaceIsLiteral);
}

inline bool shortcutChord(const std::string& name, int key, int mask) {
  int mods=mask & (ibus::SHIFT_MASK|ibus::CONTROL_MASK|ibus::ALT_MASK|ibus::SUPER_MASK);
  if(mask&ibus::RELEASE_MASK)return false;
  if(name=="ctrl_space")return key==' '&&mods==ibus::CONTROL_MASK;
  if(name=="ctrl_shift_space")return key==' '&&mods==(ibus::CONTROL_MASK|ibus::SHIFT_MASK);
  if(name=="f8")return key==ibus::F8&&mods==0;
  if(name=="f9")return key==ibus::F9&&mods==0;
  if(name=="f10")return key==ibus::F10&&mods==0;
  if(name=="ctrl_shift_f8")return key==ibus::F8&&mods==(ibus::CONTROL_MASK|ibus::SHIFT_MASK);
  if(mods!=(ibus::CONTROL_MASK|ibus::SHIFT_MASK))return false;
  if(key>='a'&&key<='z')key-=32;
  return (name=="ctrl_shift_t"&&key=='T')||(name=="ctrl_shift_f"&&key=='F')||(name=="ctrl_shift_c"&&key=='C');
}
inline std::wstring shortcutLabel(const std::string& name) {
  if(name=="shift")return L"Shift";
  if(name=="shift_left")return L"Left Shift";
  if(name=="shift_right")return L"Right Shift";
  if(name=="ctrl_space")return L"Ctrl+Space";
  if(name=="ctrl_shift_space")return L"Ctrl+Shift+Space";
  if(name=="f8")return L"F8";
  if(name=="f9")return L"F9";
  if(name=="f10")return L"F10";
  if(name=="ctrl_shift_f8")return L"Ctrl+Shift+F8";
  return L"";
}
enum class ShortcutAction { None, Language, Script };
struct ShortcutState {
  int pendingShift=0;ULONGLONG started=0;
  void reset(){pendingShift=0;}
  ShortcutAction process(int key,int mask,ULONGLONG now,const std::string& language,const std::string& script) {
    if(key==0)return ShortcutAction::None; // AI polling is not a physical key.
    bool up=(mask&ibus::RELEASE_MASK)!=0;
    bool shift=key==ibus::Shift_L||key==ibus::Shift_R;
    int forbidden=mask&(ibus::CONTROL_MASK|ibus::ALT_MASK|ibus::SUPER_MASK);
    if(shift&&up) {
      bool tap=pendingShift==key&&!forbidden&&now>=started&&now-started<=500;
      reset();
      bool selected=language=="shift"||(language=="shift_left"&&key==ibus::Shift_L)||(language=="shift_right"&&key==ibus::Shift_R);
      return tap&&selected?ShortcutAction::Language:ShortcutAction::None;
    }
    if(!up) {
      if(shift&&!forbidden) {
        if(!pendingShift){pendingShift=key;started=now;}else reset();
      } else reset();
      if(shortcutChord(language,key,mask))return ShortcutAction::Language;
      if(shortcutChord(script,key,mask))return ShortcutAction::Script;
    }
    return ShortcutAction::None;
  }
};
}
