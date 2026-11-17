// SPDX-License-Identifier: GPL-3.0-or-later
#include <windows.h>

#include <objbase.h>
#include <shellapi.h>

#include "service.h"
namespace zw {
int settings(HINSTANCE, const Store&, bool smoke = false);
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int) {
  using namespace zw;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  try {
    int argc = 0;
    auto argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::vector<std::wstring> args;
    for (int i = 1; i < argc; i++) args.emplace_back(argv[i]);
    LocalFree(argv);
    fs::path data = userDirectory();
    auto directory = std::find(args.begin(), args.end(), L"--data-dir");
    if (directory != args.end()) {
      require(directory + 1 != args.end(), "Missing data directory");
      data = *(directory + 1);
      args.erase(directory, directory + 2);
    }
    Store store(data);
    if (!args.empty() && args[0] == L"--evaluate") {
      args.erase(args.begin());
      evaluate(store, args);
      return 0;
    }
    if (!args.empty() && args[0] == L"--inspect") {
      require(args.size() == 2, "--inspect output.json");
      auto c = store.load();
      J keys = J::object();
      for (auto& p : c["policies"])
        keys[p["id"].get<std::string>()] = store.hasKey(p["id"]);
      atomicWrite(args[1], J{{"runtime", "native C++17"},
                             {"version", "1.9.1"},
                             {"policyCount", c["policies"].size()},
                             {"selectedPolicy", c["selectedPolicy"]},
                             {"savedKeys", keys}}
                               .dump(2));
      return 0;
    }
#ifdef ZEPHYR_BROKER
    std::wstring testPipe;
    if (args.size() == 2 && args[0] == L"--test-pipe") testPipe = args[1];
    runBroker(store, testPipe.empty(), testPipe);
    return 0;
#else
    if (!args.empty() && args[0] == L"--broker") {
      runBroker(store);
      return 0;
    }
    return settings(instance, store, !args.empty() && args[0] == L"--ui-smoke");
#endif
  } catch (const std::exception& e) {
#ifndef ZEPHYR_BROKER
    MessageBoxW(nullptr, wide(errorText(e)).c_str(), L"Zephyr Input",
                MB_OK | MB_ICONERROR);
#endif
    return 1;
  }
}
