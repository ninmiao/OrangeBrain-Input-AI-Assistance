// SPDX-License-Identifier: GPL-3.0-or-later
#include "dictionary.h"

#include <iostream>
using namespace zw;
int main(int argc, char** argv) {
  try {
    require(argc == 3 || argc == 4,
            "dictionary_test image isolated-user-dir [cached-model-user-dir]");
    fs::path image = fs::u8path(argv[1]), user = fs::u8path(argv[2]);
    require(!fs::exists(user), "Use a fresh test directory");
    fs::create_directories(user);
    atomicWrite(user / L"personal-note.txt", "preserved");
    Dictionary d(user, image,
                 [](const Progress& p) { std::cout << p.message << "\n"; });
    auto initial = d.state();
    require(
        !initial["dictionary"].is_null() && !initial["iceDictionary"].is_null(),
        "Bundled dictionaries present");
    d.select(true, false);
    require(d.state()["enabled"] == true && d.state()["grammar"] == false,
            "Wanxiang selected");
    auto compiled = readFile(user / L"build/orangecell_wanxiang.schema.yaml");
    require(
        compiled.find("grammar:") == compiled.npos &&
            compiled.find("dictionary: orangecell_wanxiang_d_") != compiled.npos,
        "Wanxiang schema compiled without model");
    d.select(false, true);
    require(d.state()["enabled"] == false && d.state()["grammar"] == true,
            "Ice preserves grammar preference");
    require(fs::is_regular_file(user / L"build/rime_ai_simp.schema.yaml"),
            "Ice schema compiled");
    if (argc == 4) {
      auto source = fs::u8path(argv[3]);
      auto model = J::parse(readFile(source / L".orangecell-wanxiang/state.json"))
                       .at("model");
      require(!model.is_null(), "Cached model unavailable");
      auto file = wide(
          "orangecell_wanxiang_m_" +
          model["asset"]["sha256"].get<std::string>().substr(0, 12) + ".gram");
      fs::create_hard_link(source / file, user / file);
      auto state = d.state();
      state["model"] = model;
      atomicWrite(user / L".orangecell-wanxiang/state.json", state.dump(2));
    }
    d.select(true, true);
    require(d.state()["enabled"] == true && d.state()["grammar"] == true,
            "Switch back preserves preference");
    if (argc == 4)
      require(readFile(user / L"build/orangecell_wanxiang.schema.yaml")
                      .find("grammar:") != std::string::npos,
              "Downloaded grammar enabled in Rime");
    require(readFile(user / L"personal-note.txt") == "preserved",
            "User files preserved");
    require(!fs::exists(user / L".orangecell-wanxiang/transaction/pending.json"),
            "Transaction committed");
    std::cout << "PASS: real Rime deployment, dictionary switches"
              << (argc == 4 ? ", cached grammar model" : "") << "\n";
    return 0;
  } catch (const std::exception& e) {
    std::cerr << errorText(e) << "\n";
    return 1;
  }
}
