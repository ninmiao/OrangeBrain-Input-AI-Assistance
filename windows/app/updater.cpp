// SPDX-License-Identifier: GPL-3.0-or-later
#include "updater.h"

#include <fstream>
#include <regex>
#include <sstream>
namespace zw {
namespace {
const char* kDist =
    "https://raw.githubusercontent.com/ninmiao/OrangeBrain-Input-AI-Assistance/main/dist/";
constexpr uint64_t kMaxInstaller = 300ull * 1024 * 1024;
std::vector<int> parts(const std::string& v) {
  std::vector<int> out;
  std::stringstream s(v);
  std::string item;
  while (std::getline(s, item, '.')) out.push_back(std::stoi(item));
  return out;
}
fs::path updateFolder() {
  wchar_t buffer[MAX_PATH];
  DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, MAX_PATH);
  require(n > 0 && n < MAX_PATH, "LOCALAPPDATA is unavailable");
  return fs::path(buffer) / L"OrangeCell" / L"updates";
}
}  // namespace
int compareVersions(const std::string& a, const std::string& b) {
  auto x = parts(a), y = parts(b);
  for (size_t i = 0; i < std::max(x.size(), y.size()); i++) {
    int l = i < x.size() ? x[i] : 0, r = i < y.size() ? y[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}
UpdateInfo parseUpdate(const std::string& sums, const std::string& current) {
  static const std::regex line(
      "^([0-9a-f]{64})  (OrangeCell-Windows-([0-9]+\\.[0-9]+\\.[0-9]+)-Setup-x86-arm64\\.exe)\\r?$");
  UpdateInfo best;
  std::stringstream s(sums);
  std::string row;
  while (std::getline(s, row)) {
    std::smatch m;
    if (!std::regex_match(row, m, line)) continue;
    if (best.version.empty() || compareVersions(m[3], best.version) > 0)
      best = {m[3], m[2], m[1], std::string(kDist) + m[2].str(), false};
  }
  require(!best.version.empty(), "No Windows installer listed in dist/SHA256SUMS");
  best.newer = compareVersions(best.version, current) > 0;
  return best;
}
UpdateInfo checkUpdate(const std::string& current, std::shared_ptr<Cancel> cancel) {
  HttpOptions o;
  o.url = std::string(kDist) + "SHA256SUMS";
  o.headers.emplace_back("User-Agent", "OrangeCell/" + current);
  o.headers.emplace_back("Cache-Control", "no-cache");
  o.timeoutMs = 15000;
  o.cancel = cancel;
  auto r = http(o);
  if (r.status != 200) throw Error("HTTP", r.status);
  return parseUpdate(r.body, current);
}
fs::path downloadUpdate(const UpdateInfo& update,
                        std::function<void(uint64_t)> progress,
                        std::shared_ptr<Cancel> cancel) {
  require(std::regex_match(update.sha256, std::regex("[0-9a-f]{64}")) &&
              update.url.rfind(kDist, 0) == 0,
          "Invalid update");
  auto folder = updateFolder() / wide(update.sha256.substr(0, 16));
  fs::create_directories(folder);
  auto target = folder / wide(update.file), part = folder / L"download.part";
  if (fs::exists(target) && sha256(target) == update.sha256) return target;
  std::ofstream stream;
  uint64_t count = 0;
  HttpOptions o;
  o.url = update.url;
  o.headers.emplace_back("User-Agent", "OrangeCell/updater");
  o.timeoutMs = 30 * 60 * 1000;
  o.limit = size_t(kMaxInstaller);
  o.cancel = cancel;
  o.receivedHeaders = [&](const HttpResponse& r) {
    if (r.status != 200) return;
    stream.open(part, std::ios::binary | std::ios::trunc);
    require(bool(stream), "Cannot save update");
  };
  auto last = Clock::now();
  o.consume = [&](const char* data, size_t n) {
    if (!stream.is_open()) return;
    require(count + n <= kMaxInstaller, "Update is larger than expected");
    stream.write(data, std::streamsize(n));
    require(bool(stream), "Cannot write update");
    count += n;
    if (progress && Clock::now() - last > std::chrono::milliseconds(250)) {
      progress(count);
      last = Clock::now();
    }
  };
  auto r = http(o);
  stream.close();
  if (r.status != 200) {
    fs::remove(part);
    throw Error("HTTP", r.status);
  }
  if (sha256(part) != update.sha256) {
    fs::remove(part);
    throw Error("SHA-256 mismatch; update discarded");
  }
  fs::remove(target);
  fs::rename(part, target);
  return target;
}
}  // namespace zw
