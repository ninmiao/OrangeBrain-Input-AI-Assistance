// SPDX-License-Identifier: GPL-3.0-or-later
#include "configuration.h"

#include <wincrypt.h>
#include <winhttp.h>

#include <algorithm>
#include <regex>
#include <set>
namespace zw {
J defaultPolicy(const std::string& type) {
  J p = {{"id", type},
         {"name", u8"OpenAI · 6.1 Terra"},
         {"endpoint", OPENAI},
         {"model", "gpt-6.1-terra"},
         {"provider", ""},
         {"reasoning", "low"},
         {"speed", "priority"},
         {"chinesePrompt", ""},
         {"englishPrompt", ""},
         {"catalog",
          {{"schema_version", 1},
           {"version", "local-1"},
           {"models", J::array()}}}};
  if (type == "openrouter") {
    p.update(J{{"name", u8"OpenRouter · DeepSeek Flash"},
               {"endpoint", OPENROUTER},
               {"model", "deepseek/deepseek-v4-flash-0731"},
               {"provider", "wafer/us"},
               {"reasoning", "none"},
               {"speed", "default"}});
  } else if (type == "gemini")
    p.update(J{{"name", u8"Gemini · Hydrogen"},
               {"endpoint", GEMINI},
               {"model", "gemini-4-hydrogen"},
               {"reasoning", "low"},
               {"speed", "default"}});
  return p;
}
J defaultConfiguration() {
  return J{{"settingsRevision", 2},
           {"enabled", false},
           {"assistantEnabled", true},
           {"selectedPolicy", "openai"},
           {"candidateCount", 1},
           {"completion", false},
           {"languageShortcut", "shift"},
           {"scriptShortcut", "ctrl_shift_t"},
           {"enterOriginal", true},
           {"spaceOriginal", false},
           {"wordSegmentation", true},
           {"debounceMs", 200},
           {"timeoutMs", 10000},
           {"contextEnabled", true},
           {"beforeLength", 50},
           {"afterLength", 0},
           {"outputTokenBudget", 256},
           {"policies", J::array({defaultPolicy(), defaultPolicy("openrouter"),
                                  defaultPolicy("gemini")})}};
}
J normalizeConfiguration(J c) {
  require(c.is_object(), "Invalid settings");
  int revision = c.value("settingsRevision", 0);
  auto defaults = defaultConfiguration();
  for (auto it = defaults.begin(); it != defaults.end(); ++it)
    if (!c.contains(it.key())) c[it.key()] = it.value();
  require(c["policies"].is_array(), "Invalid policies");
  for (auto& p : c["policies"]) {
    auto d = defaultPolicy();
    d["id"] = uniqueId();
    for (auto it = d.begin(); it != d.end(); ++it)
      if (!p.contains(it.key())) p[it.key()] = it.value();
    for (auto key : {"presetEnabled", "presets", "presetChineseSimplified",
                     "presetChineseTraditional", "presetEnglish"})
      p.erase(key);
    if (revision < 1 &&
        (p["endpoint"] == OPENAI ||
         p["endpoint"] == "https://api.openai.com/v1/chat/completions") &&
        p["model"] == "gpt-6-luna" && p["reasoning"] == "none" &&
        p["speed"] == "default") {
      p["model"] = "gpt-6.1-terra";
      p["reasoning"] = "low";
      p["speed"] = "priority";
    }
  }
  if (revision < 2 && c["policies"].size() < 32) {
    bool exists = false;
    for (auto& p : c["policies"])
      if (core("routing", {{"endpoint", p["endpoint"]}})["api"] == "gemini")
        exists = true;
    if (!exists) {
      auto p = defaultPolicy("gemini");
      for (auto& old : c["policies"])
        if (old["id"] == p["id"]) p["id"] = uniqueId();
      c["policies"].push_back(p);
    }
  }
  c["settingsRevision"] = 2;
  c["candidateCount"] = 1;
  c["completion"] = false;
  return c;
}
std::vector<std::string> reasoningOptions(const J& p) {
  auto catalog = p.value(
      "catalog",
      J{{"schema_version", 1}, {"version", "local-1"}, {"models", J::array()}});
  auto cache = p.value("modelList", J());
  if (cache.is_object() && cache.value("endpoint", "") == p.at("endpoint"))
    catalog = cache.value("catalog", catalog);
  auto definition = core("modelDefinition", {{"endpoint", p.at("endpoint")},
                                             {"model", p.at("model")},
                                             {"catalog", catalog}});
  std::vector<std::string> out = {"omit"};
  if (definition.is_object())
    for (auto& parameter : definition.value("parameters", J::array()))
      if (parameter.value("key", "") == "reasoning_effort")
        for (auto& choice : parameter["choices"])
          out.push_back(choice["value"]);
  return out;
}
J& activePolicy(J& c) {
  for (auto& p : c["policies"])
    if (p["id"] == c["selectedPolicy"]) return p;
  throw Error("Selected policy not found");
}
const J& activePolicy(const J& c) {
  for (auto& p : c.at("policies"))
    if (p.at("id") == c.at("selectedPolicy")) return p;
  throw Error("Selected policy not found");
}
std::string origin(const std::string& e) {
  auto w = wide(e);
  URL_COMPONENTS u{};
  u.dwStructSize = sizeof(u);
  u.dwSchemeLength = u.dwHostNameLength = u.dwUserNameLength =
      u.dwPasswordLength = u.dwUrlPathLength = u.dwExtraInfoLength = DWORD(-1);
  require(WinHttpCrackUrl(w.c_str(), DWORD(w.size()), 0, &u) &&
              u.nScheme == INTERNET_SCHEME_HTTPS && u.dwHostNameLength > 0 &&
              !u.dwUserNameLength && !u.dwPasswordLength &&
              !u.dwExtraInfoLength,
          "Use a complete HTTPS API endpoint without credentials, query or "
          "fragment");
  std::wstring host(u.lpszHostName, u.dwHostNameLength);
  std::transform(host.begin(), host.end(), host.begin(), ::towlower);
  return "https://" + utf8(host) + ":" + std::to_string(u.nPort);
}
void validateConfiguration(const J& c) {
  require(c.is_object(), "Invalid settings");
  for (auto key : {"enabled", "assistantEnabled", "enterOriginal", "spaceOriginal",
                   "wordSegmentation", "contextEnabled"})
    require(c.at(key).is_boolean(), "Invalid switch");
  require(c.at("candidateCount") == 1 && c.at("completion") == false,
          "Only one candidate is requested");
  auto range = [&](const char* key, int low, int high) {
    require(c.at(key).is_number_integer() && c.at(key).get<int>() >= low &&
                c.at(key).get<int>() <= high,
            "Numeric setting is out of range");
  };
  range("debounceMs", 50, 2000);
  range("timeoutMs", 1000, 60000);
  range("beforeLength", 0, 500);
  range("afterLength", 0, 500);
  range("outputTokenBudget", 1, 65536);
  std::set<std::string> language = {"shift",
                                    "shift_left",
                                    "shift_right",
                                    "ctrl_space",
                                    "ctrl_shift_space",
                                    "disabled"},
                        script = {"ctrl_shift_t", "ctrl_shift_f",
                                  "ctrl_shift_c", "disabled"};
  require(language.count(c.at("languageShortcut")) &&
              script.count(c.at("scriptShortcut")),
          "Invalid keyboard shortcut");
  require(c.at("policies").is_array() && !c["policies"].empty() &&
              c["policies"].size() <= 32,
          "Keep 1 to 32 policies");
  std::set<std::string> ids;
  for (auto& p : c.at("policies")) {
    std::string id = p.at("id");
    require(std::regex_match(id, std::regex("[A-Za-z0-9-]{1,64}")) &&
                ids.insert(id).second,
            "Invalid policy ID");
    require(!p.at("name").get<std::string>().empty() &&
                !p.at("model").get<std::string>().empty(),
            "Name and model cannot be empty");
    origin(p.at("endpoint"));
    auto levels = reasoningOptions(p);
    require(std::find(levels.begin(), levels.end(), p.at("reasoning")) !=
                levels.end(),
            "Select a supported reasoning level");
    require(p.at("speed") == "default" || p.at("speed") == "priority",
            "Invalid speed mode");
    require(core("routing", {{"endpoint", p["endpoint"]}})["api"] != "gemini" ||
                p["speed"] == "default",
            "Gemini uses default speed");
    require(p.at("chinesePrompt").get<std::string>().size() <= 32768 &&
                p.at("englishPrompt").get<std::string>().size() <= 32768,
            "Prompt too long");
    core("validateCatalog", p.at("catalog"));
  }
  activePolicy(c);
}
J Store::load() const {
  auto p = directory_ / L"settings.json";
  auto c = normalizeConfiguration(fs::exists(p) ? J::parse(readFile(p))
                                                : defaultConfiguration());
  validateConfiguration(c);
  return c;
}
void Store::save(const J& value) const {
  auto c = normalizeConfiguration(value);
  validateConfiguration(c);
  atomicWrite(directory_ / L"settings.json", c.dump(2));
}
fs::path Store::keyPath(const std::string& id) const {
  require(std::regex_match(id, std::regex("[A-Za-z0-9-]{1,64}")),
          "Invalid policy ID");
  return directory_ / wide("credential-" + id + ".bin");
}
bool Store::hasKey(const std::string& id) const {
  return fs::is_regular_file(keyPath(id));
}
void Store::saveKey(const std::string& id, const std::string& key,
                    const std::string& endpoint) const {
  require(!key.empty() && key.size() < 8192 &&
              key.find_first_of("\r\n") == std::string::npos,
          "Invalid API key");
  auto raw = J{{"origin", origin(endpoint)}, {"key", key}}.dump();
  DATA_BLOB in{DWORD(raw.size()), reinterpret_cast<BYTE*>(raw.data())}, out{};
  bool ok = CryptProtectData(&in, L"Zephyr Input", nullptr, nullptr, nullptr,
                             CRYPTPROTECT_UI_FORBIDDEN, &out) != 0;
  SecureZeroMemory(raw.data(), raw.size());
  require(ok, "Windows cannot encrypt this key");
  try {
    atomicWrite(keyPath(id),
                std::string(reinterpret_cast<char*>(out.pbData), out.cbData));
  } catch (...) {
    LocalFree(out.pbData);
    throw;
  }
  LocalFree(out.pbData);
}
std::string Store::key(const std::string& id,
                       const std::string& endpoint) const {
  if (!hasKey(id)) return {};
  auto bytes = readFile(keyPath(id), 32768);
  DATA_BLOB in{DWORD(bytes.size()), reinterpret_cast<BYTE*>(bytes.data())},
      out{};
  require(CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr,
                             CRYPTPROTECT_UI_FORBIDDEN, &out) != 0,
          "Key belongs to another Windows account or is damaged");
  try {
    std::string raw(reinterpret_cast<char*>(out.pbData), out.cbData);
    SecureZeroMemory(out.pbData, out.cbData);
    LocalFree(out.pbData);
    out.pbData = nullptr;
    J data;
    if (!raw.empty() && raw[0] == '{')
      data = J::parse(raw);
    else {
      require(id == "openai" || id == "openrouter",
              "Save a key for this API origin");
      data = {{"origin", origin(id == "openrouter" ? OPENROUTER : OPENAI)},
              {"key", raw}};
    }
    SecureZeroMemory(raw.data(), raw.size());
    require(data["origin"] == origin(endpoint),
            "Endpoint origin changed; enter the API key again");
    return data["key"];
  } catch (...) {
    if (out.pbData) {
      SecureZeroMemory(out.pbData, out.cbData);
      LocalFree(out.pbData);
    }
    throw;
  }
}
std::string Store::duplicate(const std::string& id) const {
  auto c = load();
  require(c["policies"].size() < 32, "At most 32 policies");
  J copy;
  for (auto& p : c["policies"])
    if (p["id"] == id) copy = p;
  require(!copy.is_null(), "Policy not found");
  std::string newId = uniqueId();
  copy["id"] = newId;
  copy["name"] = copy["name"].get<std::string>() + u8" 副本";
  auto secret = key(id, copy["endpoint"]);
  try {
    if (!secret.empty()) saveKey(newId, secret, copy["endpoint"]);
    c["policies"].push_back(copy);
    c["selectedPolicy"] = newId;
    save(c);
  } catch (...) {
    std::error_code ec;
    fs::remove(keyPath(newId), ec);
    throw;
  }
  SecureZeroMemory(secret.data(), secret.size());
  return newId;
}
J Store::remove(const std::string& id) const {
  auto c = load();
  require(c["policies"].size() > 1, "Keep at least one policy");
  auto previous = c;
  auto& p = c["policies"];
  auto found = std::find_if(p.begin(), p.end(),
                            [&](const J& v) { return v["id"] == id; });
  require(found != p.end(), "Policy not found");
  p.erase(found);
  if (c["selectedPolicy"] == id) c["selectedPolicy"] = p[0]["id"];
  save(c);
  try {
    fs::remove(keyPath(id));
  } catch (...) {
    save(previous);
    throw;
  }
  return c;
}
void Store::eraseKey(const std::string& id) const { fs::remove(keyPath(id)); }
void Store::requestStatus(const std::string& state) const {
  atomicWrite(directory_ / L"last-request-status.json",
              J{{"time", now()}, {"state", state}}.dump());
}
}  // namespace zw
