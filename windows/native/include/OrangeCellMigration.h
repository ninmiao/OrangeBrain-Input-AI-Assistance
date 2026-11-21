// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
// One-time move of user data written under the product's former name (Zephyr Input).
//
// %APPDATA%\ZephyrInput            -> %APPDATA%\OrangeCell
// HKCU\Software\ZephyrInput        -> HKCU\Software\OrangeCell
// rime\zephyr_* and .zephyr-*      -> orangecell_* and .orangecell-* (user dictionary, downloaded
//                                     dictionaries, updater state); identifiers inside the
//                                     schema, dictionary and state files are renamed the same way;
//                                     compiled zephyr_* files in build\ are dropped and rebuilt.
//
// Android does the same in shared/ai-core LegacyRename.kt. Every step is idempotent and a marker
// file stops repeat scans, so callers can run it on each start. A named mutex keeps the broker
// and the Rime server from migrating at the same time.
#include <windows.h>

#include <cctype>
#include <filesystem>
#include <fstream>
#include <string>

namespace orangecell {

inline bool LegacyName(const std::wstring& name, std::wstring& renamed) {
  if (name.rfind(L"zephyr", 0) == 0) {
    renamed = L"orangecell" + name.substr(6);
    return true;
  }
  if (name.rfind(L".zephyr", 0) == 0) {
    renamed = L".orangecell" + name.substr(7);
    return true;
  }
  return false;
}

// "zephyr" at a word start and followed by '_' or '-' becomes "orangecell".
inline std::string ReplaceLegacyIdentifiers(const std::string& line, bool& changed) {
  std::string out;
  size_t from = 0;
  for (;;) {
    size_t at = line.find("zephyr", from);
    if (at == std::string::npos) {
      out.append(line, from, std::string::npos);
      return out;
    }
    char next = at + 6 < line.size() ? line[at + 6] : '\0';
    bool start = at == 0 || !std::isalnum(static_cast<unsigned char>(line[at - 1]));
    out.append(line, from, at - from);
    if (start && (next == '_' || next == '-')) {
      out += "orangecell";
      changed = true;
    } else {
      out += "zephyr";
    }
    from = at + 6;
  }
}

// Streams line by line so large dictionaries are never held in memory.
inline void RewriteLegacyText(const std::filesystem::path& file) {
  std::filesystem::path temp = file;
  temp += L".migrating";
  bool changed = false;
  {
    std::ifstream in(file, std::ios::binary);
    if (!in) return;
    std::ofstream out(temp, std::ios::binary | std::ios::trunc);
    if (!out) return;
    std::string line;
    while (std::getline(in, line)) out << ReplaceLegacyIdentifiers(line, changed) << '\n';
  }
  std::error_code ec;
  if (!changed ||
      !MoveFileExW(temp.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    std::filesystem::remove(temp, ec);
}

inline void MigrateLegacyRimeDirectory(const std::filesystem::path& dir) {
  namespace fs = std::filesystem;
  std::error_code ec;
  if (!fs::is_directory(dir, ec) || fs::exists(dir / L".orangecell-migrated", ec)) return;
  auto renameChildren = [](const fs::path& parent) {
    std::error_code e;
    for (auto& entry : fs::directory_iterator(parent, e)) {
      std::wstring renamed;
      if (!LegacyName(entry.path().filename().wstring(), renamed)) continue;
      fs::path target = parent / renamed;
      if (!fs::exists(target, e)) MoveFileExW(entry.path().c_str(), target.c_str(), 0);
    }
  };
  renameChildren(dir);
  for (auto& entry : fs::directory_iterator(dir / L"sync", ec))
    if (entry.is_directory(ec)) renameChildren(entry.path());
  for (auto& entry : fs::directory_iterator(dir / L"build", ec)) {
    std::error_code e;
    if (entry.path().filename().wstring().rfind(L"zephyr", 0) == 0) fs::remove_all(entry.path(), e);
  }
  for (auto& entry : fs::directory_iterator(dir, ec)) {
    auto ext = entry.path().extension().wstring();
    if (entry.is_regular_file(ec) && (ext == L".yaml" || ext == L".json" || ext == L".txt"))
      RewriteLegacyText(entry.path());
  }
  for (auto& entry : fs::recursive_directory_iterator(dir / L".orangecell-wanxiang", ec))
    if (entry.is_regular_file(ec)) RewriteLegacyText(entry.path());
  std::ofstream(dir / L".orangecell-migrated") << "Renamed from Zephyr Input data.\n";
}

inline void MigrateLegacyUserData() {
  static bool done = false;
  if (done) return;
  done = true;
  HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\OrangeCellLegacyMigration");
  if (mutex) WaitForSingleObject(mutex, 60000);

  wchar_t appdata[MAX_PATH] = {0};
  ExpandEnvironmentStringsW(L"%AppData%", appdata, MAX_PATH);
  std::filesystem::path root(appdata);
  std::filesystem::path former = root / L"ZephyrInput", current = root / L"OrangeCell";
  std::error_code ec;
  if (appdata[0] && !std::filesystem::exists(current, ec) && std::filesystem::exists(former, ec))
    MoveFileExW(former.c_str(), current.c_str(), 0);

  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\OrangeCell", 0, KEY_READ, &key) == ERROR_SUCCESS) {
    RegCloseKey(key);
  } else if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\ZephyrInput", 0, KEY_READ, &key) ==
             ERROR_SUCCESS) {
    HKEY created = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\OrangeCell", 0, nullptr, 0, KEY_ALL_ACCESS,
                        nullptr, &created, nullptr) == ERROR_SUCCESS) {
      RegCopyTreeW(key, nullptr, created);
      wchar_t dir[MAX_PATH] = {0};
      DWORD size = sizeof(dir);
      if (RegGetValueW(created, nullptr, L"RimeUserDir", RRF_RT_REG_SZ, nullptr, dir, &size) ==
          ERROR_SUCCESS) {
        std::wstring value(dir);
        auto at = value.find(L"\\ZephyrInput\\");
        if (at != std::wstring::npos) {
          value.replace(at, 13, L"\\OrangeCell\\");
          RegSetValueExW(created, L"RimeUserDir", 0, REG_SZ,
                         reinterpret_cast<const BYTE*>(value.c_str()),
                         DWORD((value.size() + 1) * sizeof(wchar_t)));
        }
      }
      RegCloseKey(created);
    }
    RegCloseKey(key);
  }

  std::filesystem::path rime = current / L"rime";
  wchar_t custom[MAX_PATH] = {0};
  DWORD size = sizeof(custom);
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\OrangeCell", L"RimeUserDir", RRF_RT_REG_SZ,
                   nullptr, custom, &size) == ERROR_SUCCESS && custom[0])
    rime = custom;
  MigrateLegacyRimeDirectory(rime);

  if (mutex) {
    ReleaseMutex(mutex);
    CloseHandle(mutex);
  }
}

}  // namespace orangecell
