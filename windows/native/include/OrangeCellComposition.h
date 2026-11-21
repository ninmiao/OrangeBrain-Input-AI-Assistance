// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <string>
#include <vector>
#include <algorithm>
#include <cstdint>
#include "OrangeCellShortcuts.h"

namespace orangecell {
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
  bool manualAi = false;
  std::wstring preedit;
  size_t preeditCaret = 0;
  std::wstring commit;
  std::wstring aiError,aiStatus=L"待请求";
  void changed() { manualAi=false; aiError.clear(); ++revision; selected = page = 0; candidates.clear(); comments.clear(); rimeIndices.clear(); }
  void retryAi() { manualAi=true; ++revision; aiError.clear(); adopt(revision,{}); }
  bool insert(char ch) {
    if (ch < 32 || ch > 126 || input.size() >= 300) return false;
    input.insert(caret++, 1, ch); changed(); return true;
  }
  void backspace() { if(caret) { input.erase(--caret, 1); changed(); } }
  void erase() { if(caret<input.size()) { input.erase(caret,1); changed(); } }
  void clear() {
    shortcuts.reset();
    input.clear();
    before.clear();
    after.clear();
    caret = 0;
    partialSelection = false;
    preedit.clear();
    changed();
  }
  void cancel() {
    clear();
    commit.clear();
    refreshPending = false;
  }
  void language() { chinese=!chinese;changed(); }
  void add(const std::wstring& text,const std::wstring& source, int rimeIndex = -1) {
    if(!text.empty() && std::find(candidates.begin(),candidates.end(),text)==candidates.end()) {
      candidates.push_back(text);comments.push_back(source);rimeIndices.push_back(rimeIndex);
    }
  }
  bool adopt(uint64_t expected, const std::vector<std::wstring>& values, bool assistant = false) {
    if (expected != revision || input.empty()) return false;
    const auto firstLocal = std::find_if(comments.begin(), comments.end(), [](const auto& label) {
      return label.rfind(L"AI", 0) != 0;
    });
    const size_t published = firstLocal - comments.begin();
    if (values.empty()) {
      candidates.erase(candidates.begin(), candidates.begin() + published);
      comments.erase(comments.begin(), firstLocal);
      rimeIndices.erase(rimeIndices.begin(), rimeIndices.begin() + published);
      selected = selected >= published ? selected - published : 0;
      page = selected / 5;
      return true;
    }
    // Only completed AI suggestions precede the native choices. Preserve each
    // choice's action, even if a Rime prefix and an AI result have the same text.
    const bool localSelected = selected >= published && selected < candidates.size();
    size_t slot = 0;
    size_t inserted = 0;
    for (size_t i = 0; i < values.size(); ++i) {
      const auto& text = values[i];
      if (text.empty() || (!assistant && std::find(values.begin(), values.begin() + i, text) != values.begin() + i))
        continue;
      if (slot++ < published) continue;
      const auto position = published + inserted++;
      candidates.insert(candidates.begin() + position, text);
      comments.insert(comments.begin() + position, assistant ? (i == 0 ? L"AI 纠错" : L"AI 助手") : L"AI");
      rimeIndices.insert(rimeIndices.begin() + position, -1);
    }
    if (localSelected) selected += inserted;
    page = selected / 5;
    return true;
  }
  bool applyConfiguration(uint64_t value) {
    if(value==configurationRevision)return false;
    configurationRevision=value;manualAi=false;++revision;adopt(revision,{});aiError.clear();refreshPending=true;return true;
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
