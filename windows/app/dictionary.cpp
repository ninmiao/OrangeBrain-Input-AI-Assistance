// SPDX-License-Identifier: GPL-3.0-or-later
#include "dictionary.h"

#include <fstream>
#include <regex>
#include <thread>

#include "miniz_tinfl.h"
namespace zw {
namespace {
const std::vector<std::string> wanxiangTables = {"zi",     "jichu",  "cuoyin",
                                                 "duoyin", "diming", "mingren",
                                                 "yiren"},
                               iceTables = {"8105", "base", "ext", "tencent",
                                            "others"};
const std::vector<std::string> snapshots = {
    "default.custom.yaml", "user.yaml", "zephyr_wanxiang.schema.yaml",
    ".zephyr-wanxiang/state.json", "rime_ai_simp.schema.yaml"};
std::string name(const J& release, const std::string& prefix) {
  return "zephyr_" + prefix + "_" +
         release.at("asset").at("sha256").get<std::string>().substr(0, 12);
}
std::string replace(std::string s, const std::string& before,
                    const std::string& after) {
  size_t pos = 0;
  while ((pos = s.find(before, pos)) != s.npos) {
    s.replace(pos, before.size(), after);
    pos += after.size();
  }
  return s;
}
void assetValid(const J& a) {
  require(std::regex_match(a.at("sha256").get<std::string>(),
                           std::regex("[0-9a-f]{64}")) &&
              a.at("size").get<int64_t>() > 0 &&
              a.at("size").get<int64_t>() <= 800000000,
          "Invalid GitHub asset digest or size");
}
bool allowed(const std::string& url) {
  return std::regex_match(
      url, std::regex("https://"
                      "(github.com|api.github.com|objects.githubusercontent."
                      "com|release-assets.githubusercontent.com|github-"
                      "releases.githubusercontent.com)/[^\\r\\n]*"));
}
HttpResponse github(HttpOptions options) {
  options.headers.emplace_back("User-Agent", "Zephyr-Input/1.9.1");
  for (int i = 0; i < 6; i++) {
    require(allowed(options.url), "Unexpected GitHub download host");
    auto r = http(options);
    if (r.status == 301 || r.status == 302 || r.status == 303 ||
        r.status == 307 || r.status == 308) {
      require(!r.location.empty(), "Invalid GitHub redirect");
      options.url = r.location;
      continue;
    }
    if (r.status < 200 || r.status >= 300) throw Error("HTTP", r.status);
    return r;
  }
  throw Error("Too many GitHub redirects");
}
std::string manifest(const std::string& dictionary, bool wanxiang,
                     const fs::path& image) {
  std::string out = "---\nname: " + dictionary +
                    "\nversion: '1'\nsort: by_weight\nuse_preset_vocabulary: "
                    "false\nimport_tables:\n";
  for (auto& table : wanxiang ? wanxiangTables : iceTables)
    out += "  - " + dictionary + "_data/" +
           (wanxiang ? "dicts/" : "cn_dicts/") + table + "\n";
  out += "...\n";
  if (!wanxiang)
    out += readFile(image / L"resources/rime/ice-extra-entries.txt");
  return out;
}
struct UpdateLock {
  Handle file;
  OVERLAPPED ov{};
  explicit UpdateLock(const fs::path& workspace) {
    fs::create_directories(workspace);
    file.value = CreateFileW((workspace / L"update.lock").c_str(),
                             GENERIC_READ | GENERIC_WRITE,
                             FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                             OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    require(file.value != INVALID_HANDLE_VALUE &&
                LockFileEx(file,
                           LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY,
                           0, 1, 0, &ov),
            "Another dictionary update is running");
  }
  ~UpdateLock() { UnlockFileEx(file, 0, 1, 0, &ov); }
};
uint16_t u16(const std::string& s, size_t p) {
  require(p + 2 <= s.size(), "Invalid ZIP");
  return uint8_t(s[p]) | (uint16_t(uint8_t(s[p + 1])) << 8);
}
uint32_t u32(const std::string& s, size_t p) {
  return u16(s, p) | (uint32_t(u16(s, p + 2)) << 16);
}
uint32_t crc32(const std::string& s) {
  uint32_t crc = 0xffffffff;
  for (unsigned char c : s) {
    crc ^= c;
    for (int i = 0; i < 8; i++)
      crc = (crc >> 1) ^ (0xedb88320 & -(int(crc & 1)));
  }
  return ~crc;
}
}  // namespace
J parseRelease(const std::string& body, const std::string& kind) {
  auto root = J::parse(body);
  require(!root.value("draft", false) && !root.value("prerelease", false),
          "Only stable dictionary releases are supported");
  std::string expected = kind == "ice"     ? "cn_dicts.zip"
                         : kind == "model" ? "wanxiang-lts-zh-hans.gram"
                                           : "rime-wanxiang-base.zip";
  std::string repo = kind == "ice"     ? "iDvel/rime-ice"
                     : kind == "model" ? "amzxyz/rime-wanxiang-data"
                                       : "amzxyz/rime-wanxiang";
  J asset;
  for (auto& a : root.at("assets"))
    if (a.at("name") == expected) {
      require(asset.is_null(), "Duplicate GitHub asset");
      asset = a;
    }
  require(asset.is_object(), "Required dictionary asset missing in release");
  std::string url = asset.at("browser_download_url"),
              hash = asset.value("digest", "");
  require(
      url.rfind("https://github.com/" + repo + "/releases/download/", 0) == 0 &&
          hash.rfind("sha256:", 0) == 0,
      "Missing GitHub checksum or unexpected download URL");
  J result = {{"name", expected},
              {"url", url},
              {"size", asset.at("size")},
              {"sha256", hash.substr(7)}};
  assetValid(result);
  return J{{"version", root.at("tag_name").get<std::string>().substr(0, 100)},
           {"asset", result}};
}
void extractDictionaryZip(const fs::path& file, const fs::path& dest,
                          const std::set<std::string>& required) {
  auto bytes = readFile(file, 200000000);
  require(bytes.size() >= 22, "Invalid ZIP");
  size_t end = bytes.size() - 22;
  for (;;) {
    if (u32(bytes, end) == 0x06054b50) break;
    require(end > 0 && bytes.size() - end < 65558, "ZIP directory missing");
    end--;
  }
  require(u16(bytes, end + 4) == 0 && u16(bytes, end + 6) == 0,
          "Multipart ZIP not supported");
  size_t count = u16(bytes, end + 10), pos = u32(bytes, end + 16), expanded = 0;
  require(count < 50000 && pos < bytes.size(), "Invalid ZIP directory");
  std::set<std::string> found;
  fs::create_directories(dest);
  for (size_t i = 0; i < count; i++) {
    require(u32(bytes, pos) == 0x02014b50, "Invalid ZIP directory");
    size_t length = u16(bytes, pos + 28), extra = u16(bytes, pos + 30),
           comment = u16(bytes, pos + 32);
    require(pos + 46 + length + extra + comment <= bytes.size(),
            "Invalid ZIP entry");
    auto path = bytes.substr(pos + 46, length);
    require(path.find('\\') == path.npos && path.find(':') == path.npos &&
                !path.empty() && path[0] != '/' &&
                path.find("../") == path.npos && path != ".." &&
                path.find('\0') == path.npos,
            "Unsafe archive path");
    if (required.count(path)) {
      require(found.insert(path).second, "Duplicate dictionary file");
      uint32_t compressed = u32(bytes, pos + 20), size = u32(bytes, pos + 24),
               offset = u32(bytes, pos + 42), crc = u32(bytes, pos + 16);
      uint16_t method = u16(bytes, pos + 10);
      require(!(u16(bytes, pos + 8) & 1) && (method == 0 || method == 8) &&
                  size > 0 && size < 200000000 && expanded + size < 200000000,
              "Unsupported ZIP entry or oversized dictionary");
      expanded += size;
      require(u32(bytes, offset) == 0x04034b50, "Invalid ZIP local entry");
      size_t start =
          offset + 30 + u16(bytes, offset + 26) + u16(bytes, offset + 28);
      require(start <= bytes.size() && compressed <= bytes.size() - start,
              "Invalid ZIP data range");
      std::string output(size, 0);
      if (method == 0) {
        require(compressed == size, "Invalid ZIP stored size");
        output = bytes.substr(start, size);
      } else
        require(tinfl_decompress_mem_to_mem(output.data(), output.size(),
                                            bytes.data() + start, compressed,
                                            0) == size,
                "Cannot inflate dictionary");
      require(crc32(output) == crc, "ZIP checksum failed");
      atomicWrite(dest / wide(path), output);
    }
    pos += 46 + length + extra + comment;
  }
  require(found == required, "Archive is missing dictionary files");
}
void Dictionary::progress(const std::string& message, bool canCancel) const {
  if (progress_) progress_({message, 0, 0, canCancel});
  if (canCancel && cancel_) cancel_->check();
}
J Dictionary::state() const {
  J bundled = {{"enabled", true},
               {"grammar", true},
               {"dictionary", nullptr},
               {"model", nullptr},
               {"iceDictionary", nullptr}};
  auto bp = image_ / L"data/zephyr-dictionaries.json";
  if (fs::exists(bp)) bundled.update(J::parse(readFile(bp)));
  auto sp = workspace() / L"state.json";
  if (!fs::exists(sp) && fs::exists(sp.wstring() + L".bak")) sp += L".bak";
  J saved = bundled;
  if (fs::exists(sp))
    saved.update(J::parse(readFile(sp)));
  else {
    auto user = dir_ / L"user.yaml";
    if (fs::exists(user) &&
        readFile(user).find("previously_selected_schema: rime_ai_simp") !=
            std::string::npos)
      saved["enabled"] = false;
    auto custom = dir_ / L"default.custom.yaml";
    if (!fs::exists(user) && fs::exists(custom)) {
      auto text = readFile(custom);
      if (text.find("schema: rime_ai_simp") != text.npos &&
          text.find("schema: zephyr_wanxiang") == text.npos)
        saved["enabled"] = false;
    }
  }
  for (auto key : {"dictionary", "iceDictionary"})
    if (saved[key].is_null()) saved[key] = bundled[key];
  return saved;
}
std::string Dictionary::summary() const {
  auto s = state();
  auto version = [&](const char* key) {
    return s[key].is_null() ? u8"未下载 / Not downloaded"
                            : s[key].at("version").get<std::string>();
  };
  return std::string(u8"当前 / Selected: ") +
         (s["enabled"].get<bool>() ? u8"万象 / Wanxiang"
                                   : u8"雾凇 / Rime Ice") +
         u8"\n万象词表: " + version("dictionary") + u8"\n雾凇词表: " +
         version("iceDictionary") + u8"\n万象语法模型: " + version("model") +
         (s["enabled"].get<bool>() && s["grammar"].get<bool>()
              ? (s["model"].is_null() ? u8" · 下载后启用" : u8" · 已启用 / ON")
              : u8" · 当前停用");
}
void Dictionary::deploy(const std::string& schema) {
  auto helper = image_ / L"ZephyrDataDeploy.exe",
       server = image_ / L"ZephyrServer.exe";
  require(fs::exists(helper), "Native dictionary deployer is missing");
  Handle gate(CreateMutexW(nullptr, FALSE, L"ZephyrDeployerExclusiveMutex"));
  require(gate.value && GetLastError() != ERROR_ALREADY_EXISTS,
          "Another installation or deployment is running");
  bool running = processRunning(server);
  try {
    if (running) {
      run(server, {L"/quit"}, 10000);
      for (int i = 0; i < 50 && processRunning(server); i++)
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
      require(!processRunning(server),
              "Finish current input and retry dictionary deployment");
    }
    require(run(helper,
                {(image_ / L"rime.dll").wstring(), (image_ / L"data").wstring(),
                 dir_.wstring(), wide(schema)},
                15 * 60 * 1000) == 0,
            "Rime dictionary deployment failed");
  } catch (...) {
    CloseHandle(gate.value);
    gate.value = nullptr;
    if (running && !processRunning(server)) run(server, {});
    throw;
  }
  CloseHandle(gate.value);
  gate.value = nullptr;
  if (running && !processRunning(server)) run(server, {});
}
void Dictionary::recover() {
  auto journal = workspace() / L"transaction",
       pending = journal / L"pending.json";
  if (!fs::exists(pending)) return;
  progress(u8"恢复上次配置 / Restoring previous configuration", false);
  auto t = J::parse(readFile(pending));
  auto paths = t.value(
      "paths", std::vector<std::string>{"default.custom.yaml", "user.yaml",
                                        "zephyr_wanxiang.schema.yaml",
                                        ".zephyr-wanxiang/state.json"});
  for (size_t i = 0; i < paths.size(); i++) {
    require(std::find(snapshots.begin(), snapshots.end(), paths[i]) !=
                snapshots.end(),
            "Invalid recovery path");
    if (std::find(t["existing"].begin(), t["existing"].end(), paths[i]) !=
        t["existing"].end())
      atomicWrite(dir_ / wide(paths[i]),
                  readFile(journal / wide(std::to_string(i) + ".backup")));
    else
      fs::remove(dir_ / wide(paths[i]));
  }
  for (auto id : {L"zephyr_wanxiang", L"rime_ai_simp"})
    fs::remove(dir_ / L"build" / (std::wstring(id) + L".schema.yaml"));
  std::string schema = t.at("previousSchema");
  require(schema == "zephyr_wanxiang" || schema == "rime_ai_simp",
          "Invalid recovery schema");
  deploy(schema);
  fs::remove(pending);
}
void Dictionary::cacheBundle(const J& r, bool wanxiang) {
  if (r.is_null()) return;
  auto n = name(r, wanxiang ? "wanxiang_d" : "ice_d");
  if (fs::exists(dir_ / wide(n + ".dict.yaml"))) return;
  require(fs::exists(image_ / L"data" / wide(n + ".dict.yaml")),
          "Selected dictionary data is missing");
  for (auto& table : wanxiang ? wanxiangTables : iceTables) {
    auto relative = (wanxiang ? "dicts/" : "cn_dicts/") + table + ".dict.yaml";
    auto source =
        image_ / L"data" / wide((wanxiang ? n + "_data/" : "") + relative);
    auto target = dir_ / wide(n + "_data/" + relative);
    fs::create_directories(target.parent_path());
    fs::copy_file(source, target, fs::copy_options::overwrite_existing);
  }
  if (wanxiang)
    atomicWrite(dir_ / wide(n + "_algebra.yaml"),
                readFile(image_ / L"data" / wide(n + "_algebra.yaml")));
  atomicWrite(dir_ / wide(n + ".dict.yaml"), manifest(n, wanxiang, image_));
}
void Dictionary::activate(const J& next) {
  auto previous = state();
  progress(u8"部署词库 / Deploying… 首次可能需几分钟", false);
  cacheBundle(next["dictionary"], true);
  cacheBundle(next["iceDictionary"], false);
  auto journal = workspace() / L"transaction";
  J existing = J::array();
  for (size_t i = 0; i < snapshots.size(); i++) {
    auto f = dir_ / wide(snapshots[i]);
    if (fs::exists(f)) {
      existing.push_back(snapshots[i]);
      atomicWrite(journal / wide(std::to_string(i) + ".backup"), readFile(f));
    }
  }
  atomicWrite(
      journal / L"pending.json",
      J{{"previousSchema",
         previous["enabled"].get<bool>() ? "zephyr_wanxiang" : "rime_ai_simp"},
        {"existing", existing},
        {"paths", snapshots}}
          .dump());
  try {
    if (!next["dictionary"].is_null()) {
      auto schema =
          readFile(image_ / L"resources/rime/zephyr_wanxiang.schema.yaml");
      schema = replace(
          replace(schema, "@@DICT@@", name(next["dictionary"], "wanxiang_d")),
          "@@VERSION@@", "1000.0");
      if (next["enabled"].get<bool>() && next["grammar"].get<bool>() &&
          !next["model"].is_null()) {
        auto m = name(next["model"], "wanxiang_m");
        auto model = dir_ / wide(m + ".gram");
        if (fs::exists(model) &&
            fs::file_size(model) ==
                next["model"]["asset"]["size"].get<uint64_t>())
          schema +=
              "\ngrammar:\n  language: " + m +
              "\n  collocation_max_length: 6\n  collocation_min_length: 2\n  "
              "collocation_penalty: -14\n  non_collocation_penalty: -6\n  "
              "weak_collocation_penalty: -100\n  rear_penalty: -18\n";
      }
      atomicWrite(dir_ / L"zephyr_wanxiang.schema.yaml", schema);
    }
    if (!next["iceDictionary"].is_null()) {
      auto schema = readFile(image_ / L"resources/rime/zephyr_ice.schema.yaml");
      atomicWrite(dir_ / L"rime_ai_simp.schema.yaml",
                  replace(replace(schema, "@@DICT@@",
                                  name(next["iceDictionary"], "ice_d")),
                          "@@VERSION@@", "1000.0"));
    }
    for (auto id : {L"zephyr_wanxiang", L"rime_ai_simp"})
      fs::remove(dir_ / L"build" / (std::wstring(id) + L".schema.yaml"));
    deploy(next["enabled"].get<bool>() ? "zephyr_wanxiang" : "rime_ai_simp");
    atomicWrite(workspace() / L"state.json", next.dump(2));
    fs::remove(journal / L"pending.json");
    progress(u8"已启用 / Ready\n" + summary(), false);
  } catch (...) {
    recover();
    throw;
  }
}
fs::path Dictionary::download(const J& asset) {
  assetValid(asset);
  auto folder = workspace() / L"downloads";
  fs::create_directories(folder);
  std::string hash = asset["sha256"];
  auto complete = folder / wide(hash + ".download"),
       part = folder / wide(hash + ".part");
  uint64_t expected = asset["size"];
  if (fs::exists(complete) && fs::file_size(complete) == expected &&
      sha256(complete) == hash)
    return complete;
  if (fs::exists(complete)) fs::remove(complete);
  if (fs::exists(part) && fs::file_size(part) > expected) fs::remove(part);
  uint64_t offset = fs::exists(part) ? fs::file_size(part) : 0;
  if (offset < expected) {
    require(fs::space(folder).available > expected - offset + 32000000,
            "Not enough disk space for download");
    uint64_t count = offset;
    std::ofstream stream;
    HttpOptions o;
    o.url = asset["url"];
    o.timeoutMs = 30 * 60 * 1000;
    o.limit = size_t(expected) + 1024 * 1024;
    o.cancel = cancel_;
    if (offset)
      o.headers.emplace_back("Range", "bytes=" + std::to_string(offset) + "-");
    o.receivedHeaders = [&](const HttpResponse& r) {
      if (r.status != 200 && r.status != 206) return;
      if (r.status == 206)
        require(r.contentRange == "bytes " + std::to_string(offset) + "-" +
                                      std::to_string(expected - 1) + "/" +
                                      std::to_string(expected),
                "Invalid download resume range");
      else
        count = 0;
      stream.open(part, std::ios::binary | (r.status == 206 ? std::ios::app
                                                            : std::ios::trunc));
      require(bool(stream), "Cannot save download");
    };
    auto last = Clock::now();
    o.consume = [&](const char* data, size_t n) {
      if (!stream.is_open()) return;
      require(count + n <= expected, "Download exceeds expected size");
      stream.write(data, std::streamsize(n));
      require(bool(stream), "Cannot write download");
      count += n;
      if (progress_ && Clock::now() - last > std::chrono::milliseconds(200)) {
        progress_({u8"下载 / Downloading " + asset["name"].get<std::string>(),
                   count, expected, true});
        last = Clock::now();
      }
    };
    github(o);
    stream.close();
    require(count == expected, "Download interrupted; click again to resume");
  }
  progress(u8"校验 SHA-256 / Verifying download");
  if (sha256(part) != hash) {
    fs::remove(part);
    throw Error("SHA-256 mismatch; active dictionary unchanged");
  }
  fs::rename(part, complete);
  return complete;
}
void Dictionary::installDictionary(const J& release, bool wanxiang) {
  auto n = name(release, wanxiang ? "wanxiang_d" : "ice_d");
  if (fs::exists(dir_ / wide(n + ".dict.yaml"))) return;
  auto zip = download(release["asset"]);
  auto staging = workspace() / wide("extract-" + uniqueId());
  std::set<std::string> files;
  for (auto& table : wanxiang ? wanxiangTables : iceTables)
    files.insert((wanxiang ? "dicts/" : "cn_dicts/") + table + ".dict.yaml");
  if (wanxiang) files.insert("wanxiang_algebra.yaml");
  try {
    extractDictionaryZip(zip, staging, files);
    auto target = dir_ / wide(n + "_data");
    fs::create_directories(target);
    for (auto& relative : files) {
      auto destination = target / wide(relative);
      fs::create_directories(destination.parent_path());
      fs::copy_file(staging / wide(relative), destination,
                    fs::copy_options::overwrite_existing);
    }
    if (wanxiang)
      atomicWrite(dir_ / wide(n + "_algebra.yaml"),
                  readFile(staging / L"wanxiang_algebra.yaml"));
    atomicWrite(dir_ / wide(n + ".dict.yaml"), manifest(n, wanxiang, image_));
    fs::remove_all(staging);
  } catch (...) {
    std::error_code e;
    fs::remove_all(staging, e);
    throw;
  }
}
void Dictionary::select(bool wanxiang, bool grammar) {
  UpdateLock lock(workspace());
  recover();
  auto s = state();
  require(!wanxiang || !s["dictionary"].is_null(),
          "Bundled Wanxiang dictionary missing");
  s["enabled"] = wanxiang;
  s["grammar"] = grammar;
  activate(s);
}
void Dictionary::update(const std::string& kind) {
  require(kind == "wanxiang" || kind == "ice" || kind == "model",
          "Invalid dictionary kind");
  UpdateLock lock(workspace());
  recover();
  progress(u8"检查 GitHub 更新 / Checking GitHub release");
  HttpOptions o;
  o.url =
      kind == "ice"
          ? "https://api.github.com/repos/iDvel/rime-ice/releases/latest"
      : kind == "model"
          ? "https://api.github.com/repos/amzxyz/rime-wanxiang-data/releases/"
            "tags/LTS"
          : "https://api.github.com/repos/amzxyz/rime-wanxiang/releases/latest";
  o.limit = 2000000;
  o.timeoutMs = 20000;
  o.cancel = cancel_;
  auto release = parseRelease(github(o).body, kind);
  auto s = state();
  if (kind == "model") {
    auto target = dir_ / wide(name(release, "wanxiang_m") + ".gram");
    if (!fs::exists(target) ||
        fs::file_size(target) != release["asset"]["size"].get<uint64_t>() ||
        sha256(target) != release["asset"]["sha256"]) {
      auto file = download(release["asset"]);
      require(!fs::exists(target),
              "Installed grammar checksum failed; restore that model before "
              "updating");
      fs::rename(file, target);
    }
    s["model"] = release;
    s["grammar"] = true;
  } else {
    installDictionary(release, kind == "wanxiang");
    s[kind == "wanxiang" ? "dictionary" : "iceDictionary"] = release;
  }
  activate(s);
}
}  // namespace zw
