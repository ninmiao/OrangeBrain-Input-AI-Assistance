// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <string>
#include <vector>
#include <algorithm>
#include <cstdint>

namespace zephyr {
// Both language modes share this buffer. Space is a boundary, not a commit.
struct Composition {
  std::string input;
  size_t caret = 0, selected = 0, page = 0;
  uint64_t revision = 0;
  bool chinese = true, traditional = false, segmentation = true, enterOriginal = true, spaceOriginal = false;
  std::vector<std::wstring> candidates;
  std::vector<std::wstring> comments;
  std::wstring commit;
  void changed() { ++revision; selected = page = 0; candidates.clear(); comments.clear(); }
  bool insert(char ch) {
    if (ch < 32 || ch > 126 || input.size() >= 300) return false;
    input.insert(caret++, 1, ch); changed(); return true;
  }
  void backspace() { if(caret) { input.erase(--caret, 1); changed(); } }
  void erase() { if(caret<input.size()) { input.erase(caret,1); changed(); } }
  void clear() { input.clear(); caret=0; changed(); }
  void language() { chinese=!chinese;changed(); }
  void add(const std::wstring& text,const std::wstring& source) {
    if(!text.empty() && std::find(candidates.begin(),candidates.end(),text)==candidates.end()) {
      candidates.push_back(text);comments.push_back(source);
    }
  }
  bool adopt(uint64_t expected, const std::vector<std::wstring>& values) {
    if(expected!=revision || input.empty()) return false;
    auto old=candidates, labels=comments;
    candidates.clear(); comments.clear();
    for(const auto& v:values) add(v,L"AI");
    for(size_t i=0;i<old.size();++i) if(labels[i]!=L"AI") add(old[i],labels[i]);
    selected=page=0;return true;
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
    if(index>=candidates.size()) return;
    commit=candidates[index];clear();
  }
};
}
