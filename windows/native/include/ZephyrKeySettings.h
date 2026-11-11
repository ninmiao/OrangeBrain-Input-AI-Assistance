// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <windows.h>
#include <fstream>
#include <filesystem>
#include <optional>
#include <boost/property_tree/ptree.hpp>
#include <boost/property_tree/json_parser.hpp>
namespace zephyr {
struct KeyPreferences { bool enterOriginal=true,spaceOriginal=false; };
inline std::optional<KeyPreferences> readKeyPreferences(const std::filesystem::path& path) {
  try {
    std::ifstream input(path);if(!input)return {};
    boost::property_tree::ptree tree;boost::property_tree::read_json(input,tree);
    auto enter=tree.get_optional<bool>("enterOriginal"),space=tree.get_optional<bool>("spaceOriginal");
    if(!enter&&!space)return {}; // Legacy settings may still arrive through the pipe.
    return KeyPreferences{enter.value_or(true),space.value_or(false)};
  } catch(...) { return {}; }
}
// Read settings independently of cloud latency. The serialized input-service thread
// checks only file metadata on ordinary keystrokes; JSON is parsed after atomic saves.
inline std::optional<KeyPreferences> currentKeyPreferences() {
  static std::filesystem::path path=[] {
    wchar_t appdata[32768];DWORD n=GetEnvironmentVariableW(L"APPDATA",appdata,32768);
    return n&&n<32768?std::filesystem::path(appdata)/L"ZephyrInput"/L"settings.json":std::filesystem::path();
  }();
  static std::optional<KeyPreferences> value;
  static FILETIME previous{};static bool initialized=false;
  WIN32_FILE_ATTRIBUTE_DATA info{};
  if(path.empty()||!GetFileAttributesExW(path.c_str(),GetFileExInfoStandard,&info)){initialized=false;value.reset();return value;}
  if(!initialized||CompareFileTime(&previous,&info.ftLastWriteTime)!=0) {
    initialized=true;previous=info.ftLastWriteTime;value=readKeyPreferences(path);
  }
  return value;
}
}
