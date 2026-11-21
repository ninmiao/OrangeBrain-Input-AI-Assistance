// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <windows.h>
#include <fstream>
#include <filesystem>
#include <optional>
#include <mutex>
#include <cstdint>
#include <algorithm>
#include <boost/property_tree/ptree.hpp>
#include <boost/property_tree/json_parser.hpp>
namespace orangecell {
struct KeyPreferences { bool enterOriginal=true,spaceOriginal=false; std::string languageShortcut="shift",scriptShortcut="ctrl_shift_t"; bool contextEnabled=true,aiEnabled=false; int beforeLength=50,afterLength=0; uint64_t revision=0; std::string aiShortcut="f8"; bool wordSegmentation=true; };
inline std::optional<KeyPreferences> readKeyPreferences(const std::filesystem::path& path) {
  try {
    std::ifstream input(path);if(!input)return {};
    boost::property_tree::ptree tree;boost::property_tree::read_json(input,tree);
    auto enter=tree.get_optional<bool>("enterOriginal"),space=tree.get_optional<bool>("spaceOriginal");
    auto language=tree.get_optional<std::string>("languageShortcut"),script=tree.get_optional<std::string>("scriptShortcut");
    if(!enter&&!space&&!language&&!script)return {};
    const bool correction = tree.get<bool>("enabled", false);
    const bool assistant = tree.get<int>("settingsRevision", 0) >= 3 &&
                           tree.get<bool>("assistantEnabled", false);
    return KeyPreferences{enter.value_or(true),space.value_or(false),language.value_or("shift"),script.value_or("ctrl_shift_t"),tree.get<bool>("contextEnabled",true),correction||assistant,std::clamp(tree.get<int>("beforeLength",50),0,500),std::clamp(tree.get<int>("afterLength",0),0,500),0,tree.get<std::string>("aiShortcut","f8"),tree.get<bool>("wordSegmentation",true)};
  } catch(...) { return {}; }
}
// Read settings independently of cloud latency. The serialized input-service thread
// checks only file metadata on ordinary keystrokes; JSON is parsed after atomic saves.
inline std::optional<KeyPreferences> currentKeyPreferences() {
  static std::mutex guard;std::lock_guard<std::mutex> lock(guard);
  static std::filesystem::path path=[] {
    wchar_t appdata[32768];DWORD n=GetEnvironmentVariableW(L"APPDATA",appdata,32768);
    return n&&n<32768?std::filesystem::path(appdata)/L"OrangeCell"/L"settings.json":std::filesystem::path();
  }();
  static std::optional<KeyPreferences> value;
  static FILETIME previous{};static bool initialized=false;
  WIN32_FILE_ATTRIBUTE_DATA info{};
  if(path.empty()||!GetFileAttributesExW(path.c_str(),GetFileExInfoStandard,&info)){initialized=false;value.reset();return value;}
  if(!initialized||CompareFileTime(&previous,&info.ftLastWriteTime)!=0) {
    initialized=true;previous=info.ftLastWriteTime;value=readKeyPreferences(path);if(value)value->revision=(uint64_t(info.ftLastWriteTime.dwHighDateTime)<<32)|info.ftLastWriteTime.dwLowDateTime;
  }
  return value;
}
}
