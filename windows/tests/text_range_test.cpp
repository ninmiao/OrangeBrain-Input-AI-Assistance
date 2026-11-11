#include <windows.h>
#include <WeaselIPCData.h>
#include <iostream>
#include <stdexcept>
using namespace weasel;
int main() {
  int checks = 0;
  auto check = [&](bool ok) { ++checks; if (!ok) throw std::runtime_error("highlight range regression"); };
  for (const auto* hint : {L"简 · Ctrl+Shift+Space → EN", L"繁 · Ctrl+Shift+Space → EN", L"EN · Ctrl+Shift+Space → 中"}) {
    Text auxiliary(hint);
    for (int length = 1; length <= 300; ++length) {
      Text preedit(std::wstring(length, L'n'));
      preedit.attributes.emplace_back(0, length, HIGHLIGHTED);
      auto range = preedit.highlightedRange();
      check(range.end == length);
      range = auxiliary.highlightedRange();
      check(range.start == 0 && range.end == 0);
      check(auxiliary.str.substr(range.end) == hint);
    }
  }
  Text text(L"abc");
  for (auto range : {TextRange(-1,2,0), TextRange(1,4,0), TextRange(2,1,0), TextRange(0,300,0)}) {
    text.attributes.clear(); text.attributes.emplace_back(range.start,range.end,HIGHLIGHTED);
    check(text.highlightedRange() == TextRange());
  }
  text.attributes.clear();text.attributes.emplace_back(1,2,HIGHLIGHTED);
  check(text.highlightedRange().start == 1 && text.highlightedRange().end == 2);
  std::cout << checks << " highlight range checks passed\n";
}
