// SPDX-License-Identifier: GPL-3.0-or-later
// App self-update from the repository's dist/ folder: dist/SHA256SUMS lists the current
// installers, so one small file gives the newest version, its file name and its digest.
#pragma once
#include "network.h"
namespace zw {
constexpr const char* kRepositoryUrl =
    "https://github.com/ninmiao/OrangeBrain-Input-AI-Assistance";
struct UpdateInfo {
  std::string version, file, sha256, url;
  bool newer = false;
};
// Negative, zero or positive like strcmp; versions are "major.minor.patch".
int compareVersions(const std::string& a, const std::string& b);
// Finds the Windows installer in SHA256SUMS text and compares it with `current`.
UpdateInfo parseUpdate(const std::string& sums, const std::string& current);
UpdateInfo checkUpdate(const std::string& current, std::shared_ptr<Cancel> cancel);
// Downloads to %LOCALAPPDATA%\OrangeCell\updates and verifies SHA-256; reuses a verified copy.
fs::path downloadUpdate(const UpdateInfo& update,
                        std::function<void(uint64_t)> progress,
                        std::shared_ptr<Cancel> cancel);
}  // namespace zw
