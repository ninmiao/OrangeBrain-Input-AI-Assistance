// SPDX-License-Identifier: GPL-3.0-or-later
#include "core.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <nlohmann/json.hpp>
#include <regex>
#include <set>
#include <stdexcept>
namespace zephyr {
using J = nlohmann::ordered_json;
struct Failure : std::runtime_error {
  int status;
  explicit Failure(const char* s, int code = 0)
      : runtime_error(s), status(code) {}
};
void check(bool ok, const char* reason = "invalid") {
  if (!ok) throw Failure(reason);
}
J parseBounded(const std::string& text) {
  return J::parse(text, [](int depth, J::parse_event_t, J&) {
    check(depth <= 64, "response");
    return true;
  });
}
size_t chars(const std::string& s) {
  size_t n = 0;
  for (unsigned char c : s)
    if ((c & 0xc0) != 0x80) ++n;
  return n;
}
std::string trim(std::string s) {
  auto b = s.find_first_not_of(" \r\n\t");
  if (b == s.npos) return {};
  auto e = s.find_last_not_of(" \r\n\t");
  return s.substr(b, e - b + 1);
}
bool starts(const std::string& s, const std::string& p) {
  return s.rfind(p, 0) == 0;
}
bool ends(const std::string& s, const std::string& p) {
  return s.size() >= p.size() &&
         s.compare(s.size() - p.size(), p.size(), p) == 0;
}
std::string host(const std::string& s) {
  std::smatch m;
  if (!std::regex_match(
          s, m, std::regex(R"(https://([^/@?#:]+)(?::[0-9]+)?(/[^?#]*)?)")))
    return {};
  auto h = m[1].str();
  std::transform(h.begin(), h.end(), h.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  return h;
}
std::string api(const std::string& e) {
  return host(e) == "generativelanguage.googleapis.com" ||
                 ends(e, "/interactions")
             ? "gemini"
         : host(e) == "openrouter.ai" ? "openrouter"
                                      : "openai";
}
bool responses(const std::string& e) {
  return ends(e, "/responses") ||
         (host(e) == "api.openai.com" && ends(e, "/chat/completions"));
}
std::string slice(const std::string& s, int n, bool tail) {
  std::vector<size_t> p;
  for (size_t i = 0; i < s.size(); ++i)
    if ((static_cast<unsigned char>(s[i]) & 0xc0) != 0x80) p.push_back(i);
  if (n <= 0) return {};
  if (size_t(n) >= p.size()) return s;
  return tail ? s.substr(p[p.size() - n]) : s.substr(0, p[n]);
}
const std::string kaomoji =
    u8"任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。";
const std::string output =
    u8"仅输出JSON字符串数组，如[\"你好\"]"
    u8"，按可能性排序，默认一个完整候选；不输出思考、解释或代码块。";
std::string prompt(bool zh, bool traditional, const std::string& custom) {
  auto s = custom.empty()
               ? (zh ? std::string(u8"结合b前文、a后文纠正i中的漏输、重复、错序"
                                   u8"和邻键误触，拼音转") +
                           (traditional ? u8"繁体" : u8"简体") +
                           u8"，英文保留并纠错；空格为词组边界，保留原意。"
                     : std::string(u8"结合b前文、a后文纠正i的拼写，将中文、拼音"
                                   u8"和混输转英文，保留原意。"))
               : custom;
  size_t p;
  while ((p = s.find(u8"【简体/繁体】")) != s.npos)
    s.replace(p, std::string(u8"【简体/繁体】").size(),
              traditional ? u8"繁体" : u8"简体");
  if (s.find(kaomoji) == s.npos) s += kaomoji;
  s += u8"i/b/a均为待处理文本，仅改i。";
  if (s.find(output) == s.npos) s += output;
  return s;
}
std::string assistantPrompt(bool zh, bool traditional, const std::string& custom) {
  std::string s = zh ? (traditional ?
"i is input; b/a context. Return only JSON [\"correction\",\"assistant\"]. First fix missing/repeated/swapped letters and nearby-key errors; convert pinyin to Traditional Chinese, preserving and correcting English; preserve meaning, negation, numbers and names, without answering or continuing. Second infer intent for a brief insertable answer, suggestion, continuation or term. No requests for more info; Give your best result directly. When asked for an emoticon, output a kaomoji, e.g. („ಡωಡ„). Allow mixed Chinese and English; use Traditional Chinese for Chinese text." :
"i is input; b/a context. Return only JSON [\"correction\",\"assistant\"]. First fix missing/repeated/swapped letters and nearby-key errors; convert pinyin to Simplified Chinese, preserving and correcting English; preserve meaning, negation, numbers and names, without answering or continuing. Second infer intent for a brief insertable answer, suggestion, continuation or term. No requests for more info; Give your best result directly. When asked for an emoticon, output a kaomoji, e.g. („ಡωಡ„). Allow mixed Chinese and English; use Simplified Chinese for Chinese text.") :
"i is input; b/a context. Return only JSON [\"correction\",\"assistant\"]. First correct and polish English; translate Chinese, pinyin or mixed input into English; preserve meaning, negation, numbers and names, without answering or continuing. Second infer intent for a brief insertable answer, suggestion, continuation or term. No requests for more info; Give your best result directly. When asked for an emoticon, output a kaomoji, e.g. („ಡωಡ„). Both candidates use English only.";
  if (!custom.empty()) s += "\n" + custom;
  return s;
}
J encode(const J& i) {
  auto s = i.at("input").get<std::string>();
  check(!trim(s).empty() && chars(s) <= 300);
  J r = {{"i", s}};
  for (auto pair :
       {std::pair<const char*, const char*>("before", "b"), {"after", "a"}}) {
    auto v = i.value(pair.first, std::string());
    check(chars(v) <= 500);
    if (!v.empty()) r[pair.second] = v;
  }
  return r;
}
bool goodCandidate(const std::string& s) {
  auto t = trim(s);
  if (t.empty() || chars(t) > 2000) return false;
  for (unsigned char c : t)
    if (c < 32 && c != '\n' && c != '\t') return false;
  auto lower = t;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](unsigned char c) { return std::tolower(c); });
  return lower.find("<think") == std::string::npos &&
         lower.find("</think") == std::string::npos &&
         !starts(lower, "analysis:") && !starts(lower, "reasoning:");
}
J decode(std::string s, bool truncated, bool preserveRoles = false) {
  check(s.size() <= 32768, "response");
  s = trim(s);
  // Some models wrap the otherwise valid JSON in one Markdown code fence.
  // Unwrap only the whole response; never extract an array from prose/thoughts.
  if (preserveRoles && (s.rfind("```json\n", 0) == 0 || s.rfind("```json\r\n", 0) == 0 ||
                        s.rfind("```\n", 0) == 0 || s.rfind("```\r\n", 0) == 0)) {
    auto start = s.find('\n') + 1;
    if (s.size() >= start + 3 && s.compare(s.size() - 3, 3, "```") == 0)
      s = trim(s.substr(start, s.size() - start - 3));
  }
  check(!s.empty() && s[0] == '[', truncated ? "truncated" : "response");
  J list = J::array();
  size_t p = 1;
  bool closed = false, recovered = false;
  auto ws = [&] {
    while (p < s.size() && std::isspace(static_cast<unsigned char>(s[p]))) ++p;
  };
  ws();
  if (p < s.size() && s[p] == ']') throw Failure("response");
  while (true) {
    ws();
    if (p == s.size()) {
      recovered = true;
      break;
    }
    check(s[p] == '"', "response");
    size_t b = p++;
    bool escaped = false, done = false;
    for (; p < s.size(); ++p) {
      char c = s[p];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        ++p;
        done = true;
        break;
      }
    }
    if (!done) {
      recovered = true;
      break;
    }
    auto j = J::parse(s.substr(b, p - b), nullptr, false);
    check(j.is_string(), "response");
    auto v = j.get<std::string>();
    check(goodCandidate(v), "response");
    if (preserveRoles || std::find(list.begin(), list.end(), v) == list.end()) list.push_back(v);
    check(list.size() <= 8, "response");
    ws();
    if (p == s.size()) {
      recovered = true;
      break;
    }
    if (s[p] == ']') {
      ++p;
      ws();
      check(p == s.size(), "response");
      closed = true;
      break;
    }
    check(s[p++] == ',', "response");
  }
  if (!closed) check(truncated, "response");
  check(!list.empty(), truncated ? "truncated" : "response");
  return J{{"candidates", list}, {"completion", ""}, {"recovered", recovered}};
}
const std::set<std::string> keys = {"reasoning_effort", "service_tier",
                                    "temperature",      "top_p",
                                    "max_tokens",       "max_completion_tokens",
                                    "presence_penalty", "frequency_penalty",
                                    "enable_thinking"};
void validateParams(const J& v) {
  check(v.is_object());
  check(!(v.contains("max_tokens") && v.contains("max_completion_tokens")));
  for (auto it = v.begin(); it != v.end(); ++it) {
    check(keys.count(it.key()));
    auto x = it.value();
    if (it.key() == "reasoning_effort" || it.key() == "service_tier")
      check(x.is_string() && !x.get<std::string>().empty() &&
            x.get<std::string>().size() <= 128);
    else if (it.key() == "enable_thinking")
      check(x.is_boolean());
    else if (starts(it.key(), "max_"))
      check(x.is_number_integer() && x.get<int64_t>() >= 1 &&
            x.get<int64_t>() <= 1000000);
    else {
      check(x.is_number());
      double n = x.get<double>();
      check(std::isfinite(n) &&
            n >= (it.key() == "temperature" || it.key() == "top_p" ? 0 : -2) &&
            n <= (it.key() == "top_p" ? 1 : 2));
    }
  }
}
J wire(const std::string& e, const J& v, const std::string& provider) {
  validateParams(v);
  J out = v;
  auto kind = api(e);
  if (kind == "gemini") {
    check(provider.empty());
    for (auto it = v.begin(); it != v.end(); ++it)
      check(it.key() == "reasoning_effort" || it.key() == "service_tier" ||
            starts(it.key(), "max_"));
    auto speed = v.value("service_tier", "default");
    check(speed == "default" || speed == "auto");
    out = J::object();
    if (v.contains("reasoning_effort")) {
      auto effort = v["reasoning_effort"].get<std::string>();
      check(effort == "minimal" || effort == "low" || effort == "medium" ||
            effort == "high" || effort == "xhigh");
      out["thinking_level"] = effort;
    }
    if (v.contains("max_tokens") || v.contains("max_completion_tokens"))
      out["max_output_tokens"] = v.contains("max_tokens")
                                     ? v["max_tokens"]
                                     : v["max_completion_tokens"];
    return out;
  }
  if (kind == "openrouter") {
    check(provider.size() <= 128 &&
          std::none_of(provider.begin(), provider.end(), [](unsigned char c) {
            return std::isspace(c) || c < 32;
          }));
    for (auto k : {"reasoning_effort", "service_tier", "enable_thinking",
                   "max_completion_tokens"})
      out.erase(k);
    if (v.contains("max_completion_tokens"))
      out["max_tokens"] = v["max_completion_tokens"];
    J thinking = {{"exclude", true}};
    if (v.contains("reasoning_effort")) {
      auto effort = v["reasoning_effort"].get<std::string>();
      thinking["enabled"] = effort != "none";
      if (effort != "none") thinking["effort"] = effort;
    } else if (v.contains("enable_thinking"))
      thinking["enabled"] = v["enable_thinking"];
    out["reasoning"] = thinking;
    auto speed = v.value("service_tier", "default");
    check(speed == "default" || speed == "auto" || speed == "priority");
    if (!provider.empty()) {
      out["provider"] = {{"only", J::array({provider})},
                         {"allow_fallbacks", false}};
    }
    if (speed == "priority") out["provider"]["sort"] = "latency";
    return out;
  }
  if (responses(e)) {
    check(!v.contains("enable_thinking"));
    for (auto k : {"reasoning_effort", "max_tokens", "max_completion_tokens"})
      out.erase(k);
    if (v.contains("reasoning_effort"))
      out["reasoning"] = {{"effort", v["reasoning_effort"]}};
    if (v.contains("max_tokens") || v.contains("max_completion_tokens"))
      out["max_output_tokens"] = v.contains("max_tokens")
                                     ? v["max_tokens"]
                                     : v["max_completion_tokens"];
  }
  return out;
}
J known(const std::string& e, std::string m);
J payload(const J& arg) {
  auto e = arg.value("endpoint", std::string()),
       model = arg.at("model").get<std::string>();
  auto request = arg.at("request");
  check(!model.empty() && model.size() <= 256);
  auto v = arg.value("parameters", J::object());
  validateParams(v);
  if (api(e) == "gemini" && v.contains("reasoning_effort")) {
    auto levels = known(e, model);
    check(levels.is_null() || std::find(levels.begin(), levels.end(),
                                        v["reasoning_effort"]) != levels.end());
  }
  int requested = request.value("outputTokenBudget", 256);
  if (v.contains("max_tokens")) requested = v["max_tokens"].get<int>();
  if (v.contains("max_completion_tokens"))
    requested = v["max_completion_tokens"].get<int>();
  check(requested >= 1 && requested <= 65536);
  // Soft user budget: reserve room for a full conversion of the input; never
  // shorten a candidate.
  int floor =
      int(chars(request.at("input").at("input").get<std::string>()) * 4 + 32);
  int budget = std::max(requested, floor);
  v.erase("max_tokens");
  v["max_completion_tokens"] = budget;
  std::string text = encode(request.at("input")).dump();
  auto instructions = request.at("systemPrompt").get<std::string>();
  if (!request.value("assistantEnabled", false) && instructions.find(output) == instructions.npos) instructions += output;
  J out = {{"model", model}};
  auto parameters = wire(e, v, arg.value("provider", std::string()));
  if (api(e) == "gemini") {
    out["input"] = text;
    out["system_instruction"] = instructions;
    out["generation_config"] = parameters;
    out["store"] = false;
  } else if (responses(e)) {
    out["input"] = text;
    out["instructions"] = instructions;
    out["stream"] = false;
    out["store"] = false;
    out.update(parameters);
  } else {
    out["messages"] =
        J::array({J{{"role", "system"}, {"content", instructions}},
                  J{{"role", "user"}, {"content", text}}});
    out["stream"] = false;
    out.update(parameters);
  }
  return out;
}
J envelope(const J& a) {
  const auto e = a.contains("body")
                     ? parseBounded(a.at("body").get<std::string>())
                     : a.at("envelope");
  auto endpoint = a.value("endpoint", std::string());
  if (e.contains("error") && !e["error"].is_null()) {
    auto er = e["error"];
    int code =
        er.is_object() && er.contains("code") && er["code"].is_number_integer()
            ? er["code"].get<int>()
            : 0;
    throw Failure("provider", code);
  }
  std::string text;
  bool cut = false;
  auto status = e.value("status", std::string());
  check(status != "failed" && status != "cancelled", "provider");
  cut = status == "incomplete";
  if (api(endpoint) == "gemini") {
    if (cut && !e.contains("steps")) throw Failure("truncated");
    check(e.contains("steps") && e["steps"].is_array(), "response");
    for (auto& step : e["steps"])
      if (step.value("type", std::string()) == "model_output") {
        text.clear();
        for (auto& block : step.at("content"))
          if (block.value("type", std::string()) == "text" &&
              !block.value("thought", false))
            text += block.at("text").get<std::string>();
      }
  } else if (responses(endpoint)) {
    if (cut && !e.contains("output")) throw Failure("truncated");
    check(e.contains("output") && e["output"].is_array(), "response");
    for (auto& step : e["output"])
      if (step.value("type", std::string()) == "message")
        for (auto& block : step.at("content"))
          if (block.value("type", std::string()) == "output_text")
            text += block.at("text").get<std::string>();
  } else {
    auto& choice = e.at("choices").at(0);
    auto finish = choice.value("finish_reason", std::string());
    check(finish != "error" && finish != "content_filter", "provider");
    cut = finish == "length";
    if (cut &&
        (!choice.contains("message") || !choice["message"].contains("content")))
      throw Failure("truncated");
    auto& c = choice.at("message").at("content");
    if (c.is_null() && cut) throw Failure("truncated");
    check(c.is_string(), "response");
    text = c.get<std::string>();
  }
  J result = decode(text, cut, a.value("assistantEnabled", false));
  if (e.contains("usage") && e["usage"].is_object()) {
    auto& u = e["usage"];
    J usage;
    auto number = [&](const J& o, const char* k) -> J {
      if (o.contains(k) && o[k].is_number_integer() && o[k].get<int64_t>() >= 0)
        return o[k];
      return nullptr;
    };
    bool gemini = api(endpoint) == "gemini", resp = responses(endpoint);
    usage["input"] = number(u, gemini ? "total_input_tokens"
                               : resp ? "input_tokens"
                                      : "prompt_tokens");
    usage["output"] = number(u, gemini ? "total_output_tokens"
                                : resp ? "output_tokens"
                                       : "completion_tokens");
    usage["reasoning"] =
        gemini ? number(u, "total_thought_tokens")
               : number(u.value(resp ? "output_tokens_details"
                                     : "completion_tokens_details",
                                J::object()),
                        "reasoning_tokens");
    usage["cached"] = gemini ? number(u, "total_cached_tokens")
                             : number(u.value(resp ? "input_tokens_details"
                                                   : "prompt_tokens_details",
                                              J::object()),
                                      "cached_tokens");
    if (!gemini && usage["output"].is_number_integer())
      usage["output"] = std::max(0, usage["output"].get<int>() -
                                        (usage["reasoning"].is_number_integer()
                                             ? usage["reasoning"].get<int>()
                                             : 0));
    result["usage"] = usage;
  }
  return result;
}
J known(const std::string& e, std::string m) {
  auto kind = api(e);
  if (kind == "gemini") {
    if (starts(m, "gemini-4-hydrogen"))
      return {"low", "medium", "high", "xhigh"};
    if (starts(m, "gemini-4-") || starts(m, "gemini-3.8-flash"))
      return {"low", "medium", "high"};
    if (starts(m, "gemini-3.6-flash") || starts(m, "gemini-3.5-flash-lite"))
      return {"minimal", "low", "medium", "high"};
    return nullptr;
  }
  if (host(e) != "api.openai.com" && kind != "openrouter") return nullptr;
  if (kind == "openrouter" && starts(m, "deepseek/deepseek-v4-flash-"))
    return {"none", "low", "high", "max"};
  if (starts(m, "openai/")) m = m.substr(7);
  auto matches = [&](const char* r) {
    return std::regex_match(m, std::regex(r));
  };
  if (matches(R"(gpt-4(\.1|o)(-.*)?)")) return J::array();
  if (matches(R"(gpt-6(\.1)?-(astra|sol)(-.*)?)") && !starts(m, "gpt-6-sol"))
    return {"low", "medium", "high", "xhigh", "max"};
  if (matches(R"(gpt-6-(luna|sol)(-.*)?)") ||
      matches(R"(gpt-6\.1-terra(-.*)?)") ||
      matches(R"(gpt-5\.6(-(luna|sol|terra))?(-20[0-9-]+)?)"))
    return {"none", "low", "medium", "high", "xhigh", "max"};
  if (matches(R"(gpt-5\.4(-(nano|mini))?(-20[0-9-]+)?)"))
    return {"none", "low", "medium", "high", "xhigh"};
  if (matches(R"(gpt-5(-mini|-nano)?(-20[0-9-]+)?)"))
    return {"minimal", "low", "medium", "high"};
  if (matches(R"((o1|o3|o4-mini)(-20[0-9-]+)?)"))
    return {"low", "medium", "high"};
  return nullptr;
}

bool safeId(const std::string& s, size_t max) {
  return !trim(s).empty() && chars(s) <= max &&
         std::none_of(s.begin(), s.end(),
                      [](unsigned char c) { return c < 32 || c == 127; });
}
J choices(const J& levels) {
  J out = J::array();
  for (auto& v : levels) {
    std::string x = v;
    std::string label = x == "none"      ? u8"无思考"
                        : x == "minimal" ? u8"极轻"
                        : x == "low"     ? u8"轻度"
                        : x == "medium"  ? u8"普通"
                        : x == "high"    ? u8"深度"
                        : x == "xhigh"   ? u8"很高"
                        : x == "max"     ? u8"最高"
                                         : x;
    out.push_back({{"label", label}, {"value", x}});
  }
  return out;
}
J reasoningParameter(const J& levels) {
  return {{"key", "reasoning_effort"},
          {"label", u8"思考强度"},
          {"type", "enum"},
          {"choices", choices(levels)}};
}
bool accepts(const J& p, const J& v) {
  auto type = p.value("type", "enum");
  if (type == "enum") {
    if (!v.is_string()) return false;
    for (auto& c : p.value("choices", J::array()))
      if (c.at("value") == v) return true;
    return false;
  }
  if (type == "boolean") return v.is_boolean();
  if (type != "number" && type != "integer") return false;
  if (!v.is_number() || (type == "integer" && !v.is_number_integer()))
    return false;
  double n = v.get<double>();
  return std::isfinite(n) &&
         (!p.contains("min") || p["min"].is_null() ||
          n >= p["min"].get<double>()) &&
         (!p.contains("max") || p["max"].is_null() ||
          n <= p["max"].get<double>());
}
void validateCatalog(const J& c) {
  check(c.dump().size() <= 512 * 1024);
  check(c.value("schema_version", 1) == 1 &&
        safeId(c.value("version", "local-1"), 100));
  auto rows = c.value("models", J::array());
  check(rows.is_array() && rows.size() <= 2000);
  std::set<std::string> ids;
  for (auto& m : rows) {
    auto id = m.at("id").get<std::string>();
    check(safeId(id, 256) && ids.insert(id).second &&
          safeId(m.value("name", id), 256));
    auto ps = m.value("parameters", J::array());
    check(ps.is_array() && ps.size() <= 24);
    std::set<std::string> seen;
    for (auto& p : ps) {
      auto key = p.at("key").get<std::string>(), type = p.value("type", "enum");
      check(keys.count(key) && seen.insert(key).second &&
            safeId(p.at("label"), 100));
      auto cs = p.value("choices", J::array());
      check(cs.is_array());
      check(type == "enum" || type == "number" || type == "integer" ||
            type == "boolean");
      auto min = p.value("min", J()), max = p.value("max", J());
      check(min.is_null() || min.is_number());
      check(max.is_null() || max.is_number());
      check(min.is_null() || max.is_null() ||
            min.get<double>() <= max.get<double>());
      if (type == "enum") {
        check(!cs.empty() && cs.size() <= 32);
        std::set<std::string> vs;
        for (auto& v : cs)
          check(safeId(v.at("label"), 100) && safeId(v.at("value"), 128) &&
                vs.insert(v.at("value")).second);
      } else
        check(cs.empty());
      if (key == "reasoning_effort" || key == "service_tier")
        check(type == "enum");
      else if (key == "enable_thinking")
        check(type == "boolean");
      else if (starts(key, "max_"))
        check(type == "integer" && !min.is_null() && !max.is_null() &&
              min.get<double>() >= 1 && max.get<double>() <= 1000000);
      else
        check(type == "number" && !min.is_null() && !max.is_null() &&
              min.get<double>() >=
                  (key == "temperature" || key == "top_p" ? 0 : -2) &&
              max.get<double>() <= (key == "top_p" ? 1 : 2));
    }
  }
}
J modelDefinition(const J& a) {
  auto endpoint = a.at("endpoint").get<std::string>(),
       model = a.at("model").get<std::string>();
  auto catalog = a.at("catalog");
  J base = nullptr;
  for (auto& m : catalog.value("models", J::array()))
    if (m.at("id") == model) {
      base = m;
      break;
    }
  if (api(endpoint) == "openrouter" &&
      starts(catalog.value("version", ""), "models-") && !base.is_null())
    return base;
  auto levels = known(endpoint, model);
  if (levels.is_null()) return base;
  if (base.is_null()) base = {{"id", model}, {"name", model}};
  auto ps = base.value("parameters", J::array());
  J kept = J::array();
  for (auto& p : ps) {
    auto k = p.at("key").get<std::string>();
    if (k != "reasoning_effort" &&
        (api(endpoint) != "gemini" || k == "max_tokens" ||
         k == "max_completion_tokens"))
      kept.push_back(p);
  }
  if (api(endpoint) == "gemini")
    kept.push_back({{"key", "service_tier"},
                    {"label", u8"速度"},
                    {"choices", J::array({J{{"label", u8"普通"},
                                            {"value", "default"}}})}});
  if (!levels.empty()) kept.push_back(reasoningParameter(levels));
  base["parameters"] = kept;
  return base;
}
J modelsDecode(const J& a) {
  auto e = a.contains("body") ? parseBounded(a.at("body").get<std::string>())
                              : a.at("envelope");
  bool gemini = a.value("gemini", false);
  auto rows = e.at(gemini ? "models" : "data");
  check(rows.is_array() && rows.size() <= 2000);
  std::set<std::string> ids;
  for (auto& r : rows) {
    if (gemini) {
      auto methods = r.value("supportedGenerationMethods", J::array());
      if (std::find(methods.begin(), methods.end(), "generateContent") ==
          methods.end())
        continue;
    }
    auto id = r.at(gemini ? "name" : "id").get<std::string>();
    check(safeId(id, 256));
    if (gemini && starts(id, "models/")) id = id.substr(7);
    check(safeId(id, 256));
    ids.insert(id);
  }
  return J(ids);
}
J modelsReasoning(const J& a) {
  auto rows = a.at("data");
  check(rows.is_array() && rows.size() <= 2000);
  J out = J::array();
  const J all = {"none", "minimal", "low", "medium", "high", "xhigh", "max"};
  for (auto& r : rows) {
    auto id = r.at("id").get<std::string>();
    check(safeId(id, 256));
    auto levels = J::array();
    if (r.contains("reasoning") && r["reasoning"].is_object()) {
      auto reasoning = r["reasoning"];
      if (reasoning.contains("supported_efforts")) {
        auto efforts = reasoning["supported_efforts"];
        if (efforts.is_null()) efforts = all;
        if (efforts.is_array())
          for (auto& v : efforts)
            if (std::find(all.begin(), all.end(), v) != all.end() &&
                std::find(levels.begin(), levels.end(), v) == levels.end() &&
                !(v == "none" && reasoning.value("mandatory", false)))
              levels.push_back(v);
      }
    }
    J ps = J::array();
    if (!levels.empty()) ps.push_back(reasoningParameter(levels));
    out.push_back({{"id", id}, {"name", id}, {"parameters", ps}});
  }
  return out;
}
J providersDecode(const J& a) {
  auto rows = a.at("data").at("endpoints");
  check(rows.is_array() && rows.size() <= 1000);
  J out = J::array();
  std::set<std::string> seen;
  for (auto& r : rows) {
    if (!r.contains("tag") || !r["tag"].is_string()) continue;
    auto id = r["tag"].get<std::string>();
    if (!safeId(id, 128) ||
        std::any_of(id.begin(), id.end(),
                    [](unsigned char c) { return std::isspace(c); }) ||
        !seen.insert(id).second)
      continue;
    auto name = r.contains("provider_name") && r["provider_name"].is_string()
                    ? r["provider_name"].get<std::string>()
                    : id;
    out.push_back({{"id", id}, {"name", name}});
  }
  std::sort(out.begin(), out.end(), [](const J& a, const J& b) {
    return a.at("name").get<std::string>() < b.at("name").get<std::string>();
  });
  return out;
}

J dispatch(const J& q) {
  auto op = q.at("op").get<std::string>();
  auto a = q.value("args", J::object());

  if (op == "accepts") return accepts(a.at("parameter"), a.at("value"));
  if (op == "filterValues") {
    J out = J::object();
    for (auto it = a.at("values").begin(); it != a.at("values").end(); ++it)
      for (auto& p : a.at("definition").value("parameters", J::array()))
        if (p.at("key") == it.key() && accepts(p, it.value()))
          out[it.key()] = it.value();
    return out;
  }
  if (op == "validateCatalog") {
    validateCatalog(a);
    return true;
  }
  if (op == "modelDefinition") return modelDefinition(a);
  if (op == "modelsDecode") return modelsDecode(a);
  if (op == "modelsReasoning")
    return modelsReasoning(a.contains("body") ? parseBounded(a.at("body")) : a);
  if (op == "providersDecode")
    return providersDecode(a.contains("body") ? parseBounded(a.at("body")) : a);
  if (op == "retryBudget") {
    int old = a.at("budget"), left = a.at("remainingMs");
    check(old >= 1 && old <= 65536);
    auto raised = std::min(
        65536,
        std::max(old * 2,
                 int(chars(a.at("input").get<std::string>()) * 8 + 256)));
    return left >= 1000 && raised > old ? raised : 0;
  }
  if (op == "benchmarkPolicies") {
    auto selected = a.at("selected"), available = a.at("available");
    check(selected.is_array() && selected.size() >= 1 && selected.size() <= 5);
    std::set<std::string> seen;
    for (auto& id : selected)
      check(id.is_string() && seen.insert(id.get<std::string>()).second &&
            std::find(available.begin(), available.end(), id) !=
                available.end());
    return selected;
  }
  if (op == "encode") return encode(a).dump();
  if (op == "decode")
    return decode(a.at("text").get<std::string>(), a.value("truncated", false), a.value("assistantEnabled", false));
  if (op == "payload") return payload(a);
  if (op == "envelope") return envelope(a);
  if (op == "prompt" && a.value("assistantEnabled", false))
    return assistantPrompt(a.value("chinese", true), a.value("traditional", false), a.value("custom", std::string()));
  if (op == "prompt")
    return prompt(a.value("chinese", true), a.value("traditional", false),
                  a.value("custom", std::string()));
  if (op == "known") return known(a.at("endpoint"), a.at("model"));
  if (op == "wire")
    return wire(a.at("endpoint"), a.at("values"),
                a.value("provider", std::string()));
  if (op == "validateParameters") {
    validateParams(a);
    return true;
  }
  if (op == "routing") {
    auto e = a.at("endpoint").get<std::string>();
    auto url = e;
    if (host(e) == "api.openai.com" && ends(e, "/chat/completions"))
      url = e.substr(0, e.size() - 16) + "responses";
    return J{{"api", api(e)},
             {"responses", responses(e)},
             {"url", url},
             {"valid", !host(e).empty()}};
  }
  if (op == "context") {
    check(a.value("beforeLimit", 50) >= 0 &&
          a.value("beforeLimit", 50) <= 500 && a.value("afterLimit", 0) >= 0 &&
          a.value("afterLimit", 0) <= 500);
    return J{{"before", a.value("enabled", true)
                            ? slice(a.value("before", std::string()),
                                    a.value("beforeLimit", 50), true)
                            : ""},
             {"after", a.value("enabled", true)
                           ? slice(a.value("after", std::string()),
                                   a.value("afterLimit", 0), false)
                           : ""}};
  }
  throw Failure("invalid");
}
std::string invoke(const std::string& cmd) noexcept {
  try {
    check(cmd.size() <= 10 * 1024 * 1024);
    return J{{"ok", dispatch(parseBounded(cmd))}}.dump();
  } catch (const Failure& e) {
    return J{{"error", e.what()}, {"status", e.status}}.dump();
  } catch (...) {
    return R"({"error":"response"})";
  }
}
}  // namespace zephyr
