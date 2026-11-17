// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <string>
#include <vector>
#include <algorithm>
#include <cstdint>
#include "ZephyrShortcuts.h"

namespace zephyr {
// Both language modes share this buffer. Space is a boundary, not a commit.
struct Composition {
  std::string input,before,after;
  std::string languageShortcut="shift",scriptShortcut="ctrl_shift_t";
  ShortcutState shortcuts;
  size_t caret = 0, selected = 0, page = 0;
  uint64_t revision = 0, configurationRevision = 0;
  bool chinese = true, traditional = false, segmentation = true, enterOriginal = true, spaceOriginal = false;
  std::vector<std::wstring> candidates;
  std::vector<std::wstring> comments;
  std::vector<int> rimeIndices;
  bool partialSelection = false;
  bool refreshPending = false;
  std::wstring preedit;
  size_t preeditCaret = 0;
  std::wstring commit;
  std::wstring aiError,aiStatus=L"待请求";
  void changed() { aiError.clear(); ++revision; selected = page = 0; candidates.clear(); comments.clear(); rimeIndices.clear(); }
  bool insert(char ch) {
    if (ch < 32 || ch > 126 || input.size() >= 300) return false;
    input.insert(caret++, 1, ch); changed(); return true;
  }
  void backspace() { if(caret) { input.erase(--caret, 1); changed(); } }
  void erase() { if(caret<input.size()) { input.erase(caret,1); changed(); } }
  void clear() { shortcuts.reset(); input.clear(); caret=0; partialSelection=false; preedit.clear(); changed(); }
  void language() { chinese=!chinese;changed(); }
  void add(const std::wstring& text,const std::wstring& source, int rimeIndex = -1) {
    if(!text.empty() && std::find(candidates.begin(),candidates.end(),text)==candidates.end()) {
      candidates.push_back(text);comments.push_back(source);rimeIndices.push_back(rimeIndex);
    }
  }
  bool adopt(uint64_t expected, const std::vector<std::wstring>& values, bool assistant = false, bool streaming = false) {
    if(expected!=revision || input.empty()) return false;
    auto old=candidates, labels=comments;auto indices=rimeIndices;
    candidates.clear(); comments.clear(); rimeIndices.clear();
    for(size_t i=0;i<values.size();++i) if(!values[i].empty()) {
      if(!assistant) { add(values[i],L"AI"); continue; }
      candidates.push_back(values[i]);
      comments.push_back(assistant ? (i==0 ? L"AI 纠错" : L"AI 助手") : L"AI");
      rimeIndices.push_back(-1);
    }
    if(assistant && values.size()==1) {
      candidates.push_back(streaming?L"助手生成中…":L"助手未完成");comments.push_back(L"AI 助手");rimeIndices.push_back(-2);
    }
    for(size_t i=0;i<old.size();++i) if(labels[i].rfind(L"AI",0)!=0) add(old[i],labels[i],indices[i]);
    // A later streaming update must not reset a user's highlighted slot.
    bool updating=!labels.empty()&&labels[0].rfind(L"AI",0)==0&&!values.empty();
    if(!updating)selected=page=0;
    if(selected>=candidates.size())selected=0;
    page=selected/5;return true;
  }
  bool applyConfiguration(uint64_t value) {
    if(value==configurationRevision)return false;
    configurationRevision=value;++revision;adopt(revision,{});aiError.clear();refreshPending=true;return true;
  }
  bool chooseDigit(int digit) {
    if (input.empty() || digit < 1 || digit > 5) return false;
    const size_t index = page * 5 + size_t(digit - 1);
    if (index >= candidates.size()) return false;
    choose(index);
    return true;
  }
  bool originalKey(bool enter, bool space) const {
    return !input.empty() && ((enter && enterOriginal) || (space && spaceOriginal));
  }
  void choose(size_t index) {
    if(index>=candidates.size() || (index<rimeIndices.size() && rimeIndices[index]==-2)) return;
    commit=candidates[index];clear();
  }
};
}
