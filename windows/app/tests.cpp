// SPDX-License-Identifier: GPL-3.0-or-later
#include <windows.h>

#include <wincrypt.h>

#include <fstream>
#include <iostream>
#include <thread>

#include "dictionary.h"
#include "service.h"
using namespace zw;
int main(int argc, char** argv) {
  int checks = 0;
  auto check = [&](bool ok, const char* label) {
    if (!ok) throw std::runtime_error(label);
    checks++;
  };
  auto rejects = [&](auto fn, const char* label) {
    bool rejected = false;
    try {
      fn();
    } catch (...) {
      rejected = true;
    }
    check(rejected, label);
  };
  auto dir =
      fs::temp_directory_path() / wide("zephyr-native-test-" + uniqueId());
  try {
    Store store(dir);
    auto c = store.load();
    check(c["policies"].size() == 3, "Default policies");
    check(c["beforeLength"] == 50 && c["afterLength"] == 0 &&
              c["contextEnabled"] == true,
          "Context defaults");
    store.save(c);
    check(store.load() == c, "Configuration round trip");
    auto source = c;
    source.erase("settingsRevision");
    source["policies"].erase(2);
    source["candidateCount"] = 5;
    source["completion"] = true;
    auto migrated = normalizeConfiguration(source);
    check(migrated["policies"].size() == 3 && migrated["candidateCount"] == 1 &&
              !migrated["completion"].get<bool>(),
          "Legacy migration");
    for (auto pair : {std::pair<const char*, int>{"timeoutMs", 0},
                      {"beforeLength", 501},
                      {"outputTokenBudget", 0},
                      {"afterLength", -1}}) {
      auto bad = c;
      bad[pair.first] = pair.second;
      rejects([&] { validateConfiguration(bad); }, "Invalid settings rejected");
    }
    check(origin("https://API.OPENAI.COM/v1/responses") ==
              "https://api.openai.com:443",
          "Canonical origin");
    for (auto endpoint : {"http://api.openai.com/v1/responses",
                          "https://key@api.openai.com/v1/responses",
                          "https://api.openai.com/v1/responses?x=1",
                          "https://api.openai.com/v1/responses#fragment"})
      rejects([&] { origin(endpoint); }, "Unsafe endpoint rejected");
    store.saveKey("openai", "fixture-secret", OPENAI);
    check(store.key("openai", OPENAI) == "fixture-secret", "DPAPI round trip");
    check(readFile(dir / L"credential-openai.bin").find("fixture-secret") ==
              std::string::npos,
          "Credential encrypted at rest");
    rejects([&] { store.key("openai", OPENROUTER); },
            "Credential origin binding");
    rejects([&] { store.saveKey("../other", "secret", OPENAI); },
            "Credential path bounded");
    rejects([&] { store.saveKey("openai", "bad\r\nkey", OPENAI); },
            "Header injection rejected");
    std::string legacy =
        J{{"origin", origin(OPENROUTER)}, {"key", "old-jna-dpapi"}}.dump();
    DATA_BLOB in{DWORD(legacy.size()), reinterpret_cast<BYTE*>(legacy.data())},
        out{};
    check(
        CryptProtectData(&in, nullptr, nullptr, nullptr, nullptr, 0, &out) != 0,
        "Legacy DPAPI fixture");
    atomicWrite(dir / L"credential-openrouter.bin",
                std::string(reinterpret_cast<char*>(out.pbData), out.cbData));
    LocalFree(out.pbData);
    check(store.key("openrouter", OPENROUTER) == "old-jna-dpapi",
          "Existing JVM credential format");
    auto copy = store.duplicate("openai");
    check(store.key(copy, OPENAI) == "fixture-secret", "Copy policy key");
    store.saveKey(copy, "independent", OPENAI);
    check(store.key("openai", OPENAI) == "fixture-secret",
          "Copied key independent");
    auto remaining = store.remove(copy);
    check(!store.hasKey(copy) && remaining["selectedPolicy"] == "openai",
          "Delete active policy and key");
    auto raw = latencySample(true);
    check(raw.input.size() > 100 && !raw.before.empty() && !raw.after.empty(),
          "Long benchmark has context");
    auto wire = "Z2\tzh\t0\t" + hex(raw.input) + "\t" + hex(raw.before) + "\t" +
                hex(raw.after);
    auto decoded = decodeWire(wire);
    check(decoded.input == raw.input && decoded.before == raw.before &&
              decoded.after == raw.after,
          "Z2 wire Unicode");
    check(decodeWire("Z1\ten\t0\t6869").input == "hi",
          "Legacy wire compatible");
    rejects([&] { decodeWire("Z2\tzh\t0\txx\t\t"); },
            "Invalid wire hex rejected");
    rejects([&] { decodeWire("Z1\tzh\t0\t6869\t\t"); },
            "Invalid framing rejected");
    auto p = defaultPolicy();
    auto payload = requestPayload(c, p, raw);
    auto compact = J::parse(payload["input"].get<std::string>());
    check(compact.contains("b") && !compact.contains("a"),
          "Context defaults in request");
    check(payload["max_output_tokens"].get<int>() >=
              int(raw.input.size()) * 4 + 32,
          "Soft budget full candidate reserve");
    check(payload["instructions"].get<std::string>().find(
              "No requests for more info; Give your best result directly.") != std::string::npos,
          "Strict output contract");
    c["contextEnabled"] = false;
    payload = requestPayload(c, p, raw);
    compact = J::parse(payload["input"].get<std::string>());
    check(!compact.contains("b") && !compact.contains("a"), "Context disabled");
    c["contextEnabled"] = true;
    c["afterLength"] = 5;
    compact = J::parse(requestPayload(c, p, raw)["input"].get<std::string>());
    check(compact.contains("a"), "After context enabled");
    auto router = defaultPolicy("openrouter");
    auto rp = requestPayload(c, router, raw);
    check(rp.contains("messages") && !rp.contains("preset") &&
              rp["reasoning"]["exclude"] == true,
          "OpenRouter full prompt without presets");
    auto gemini = defaultPolicy("gemini");
    auto gp = requestPayload(c, gemini, raw);
    check(gp.contains("system_instruction") && gp["store"] == false,
          "Gemini request");
    check(utf8(wide(u8"你好😀 café")) == u8"你好😀 café", "Unicode round trip");
    int attempts = 0;
    auto transport = [&](const HttpOptions& options) {
      auto body = J::parse(options.body);
      check(options.url == OPENAI, "Responses endpoint");
      check(options.headers[0].second == "Bearer fixture-secret",
            "Authorization header");
      attempts++;
      if (attempts == 1)
        return HttpResponse{200, R"({"status":"incomplete","output":[]})"};
      return HttpResponse{
          200,
          R"({"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"[\"你好\"]"}]}]})"};
    };
    auto result = requestAi(store, c, p, raw, {}, {}, transport);
    check(attempts == 2 && result["candidates"][0] == u8"你好",
          "One truncation retry");
    attempts = 0;
    rejects(
        [&] {
          requestAi(store, c, p, raw, {}, {}, [&](const HttpOptions&) {
            attempts++;
            return HttpResponse{200, R"({"status":"incomplete","output":[]})"};
          });
        },
        "Repeated truncation bounded");
    check(attempts == 2, "Retry at most once");
    attempts = 0;
    rejects(
        [&] {
          requestAi(store, c, p, raw, {}, {}, [&](const HttpOptions&) {
            attempts++;
            return HttpResponse{401, ""};
          });
        },
        "HTTP failure surfaced");
    check(attempts == 1, "HTTP error not retried");
    std::ifstream corpus(argc > 1 ? argv[1] : "");
    check(bool(corpus), "Truncation corpus available");
    std::string line;
    int corpusCount = 0;
    while (std::getline(corpus, line)) {
      if (line.empty()) continue;
      auto row = J::parse(line);
      bool error = false;
      J actual;
      try {
        actual = core("decode", {{"text", row.at("text")},
                                 {"truncated", row.value("truncated", false)}});
      } catch (...) {
        error = true;
      }
      if (!row.at("expected").empty())
        check(!error && actual["candidates"] == row["expected"],
              "Truncation corpus candidate");
      else
        check(error, "Truncation corpus rejection");
      corpusCount++;
    }
    check(corpusCount >= 24, "All truncation fixtures exercised");
    if (argc > 2) {
      std::string base = argv[2];
      HttpOptions o;
      o.url = base + "/ok";
      o.testLoopbackHttp = true;
      o.limit = 65536;
      auto r = http(o);
      check(r.status == 200 && r.body == "fixture-ok", "WinHTTP async receive");
      o.url = base + "/redirect";
      r = http(o);
      check(r.status == 302, "Credential redirects disabled");
      o.url = base + "/slow";
      o.timeoutMs = 120;
      auto start = Clock::now();
      rejects([&] { http(o); }, "Total network deadline");
      check(Clock::now() - start < std::chrono::seconds(2),
            "Deadline cancels connection");
      o.timeoutMs = 5000;
      o.cancel = std::make_shared<Cancel>();
      std::thread cancel([c = o.cancel] {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        c->cancelled = true;
      });
      rejects([&] { http(o); }, "Cancel in-flight request");
      cancel.join();
      o.cancel.reset();
      o.url = base + "/body-slow";
      o.timeoutMs = 150;
      rejects([&] { http(o); }, "Cancel during body read");
      o.url = base + "/huge";
      o.timeoutMs = 3000;
      o.limit = 10;
      rejects([&] { http(o); }, "Bounded response size");
      o.url = base + "/slow";
      o.limit = 65536;
      o.connected = [] { return false; };
      rejects([&] { http(o); }, "Disconnected input client cancelled");
    }
    wchar_t zipEnv[32768];
    if (GetEnvironmentVariableW(L"ZEPHYR_TEST_ZIPS", zipEnv, 32768)) {
      fs::path fixtures(zipEnv);
      extractDictionaryZip(fixtures / L"good.zip", dir / L"zip-good",
                           {"dicts/zi.dict.yaml"});
      check(readFile(dir / L"zip-good/dicts/zi.dict.yaml") == u8"词库测试\n",
            "Deflate ZIP extraction");
      rejects(
          [&] {
            extractDictionaryZip(fixtures / L"unsafe.zip", dir / L"zip-unsafe",
                                 {"dicts/zi.dict.yaml"});
          },
          "ZIP traversal rejected");
      rejects(
          [&] {
            extractDictionaryZip(fixtures / L"missing.zip",
                                 dir / L"zip-missing", {"dicts/zi.dict.yaml"});
          },
          "Missing ZIP table rejected");
      rejects(
          [&] {
            extractDictionaryZip(fixtures / L"bad-crc.zip", dir / L"zip-crc",
                                 {"dicts/zi.dict.yaml"});
          },
          "ZIP CRC rejected");
    }
    check(sha256(dir / L"settings.json").size() == 64,
          "SHA256 native implementation");
    std::cout << "PASS: " << checks << " Windows native checks\n";
    fs::remove_all(dir);
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "FAIL after " << checks << ": " << e.what()
              << "\nFixtures: " << dir.u8string() << "\n";
    return 1;
  }
}
