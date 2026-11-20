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
  if(argc==2 && std::string(argv[1])=="--lifetime-fixture"){Sleep(30000);return 0;}
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
    auto legacyModes=c;
    legacyModes["settingsRevision"]=2;
    legacyModes["assistantEnabled"]=true;
    check(normalizeConfiguration(legacyModes)["assistantEnabled"]==false,
          "Legacy disabled AI stays off automatically");
    legacyModes["enabled"]=true;
    check(normalizeConfiguration(legacyModes)["assistantEnabled"]==true,
          "Legacy enabled assistant stays enabled");
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
    auto manual = decodeWire("Z4\ten\t0\t6869\t\t\tassistant");
    check(manual.manual && manual.input == "hi", "Explicit retry wire");
    rejects([&] { decodeWire("Z4\ten\t0\t6869\t\t\tretry"); },
            "Invalid explicit request mode");
    check(handleRequest(store,"Z4\ten\t0\t6869\t\t") == responseWire(c),
          "Both modes off suppresses automatic requests");
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
    auto single=payload["instructions"].get<std::string>();
    check(single.find(u8"只含一个完整候选")!=single.npos && single.find(u8"颜表情")==single.npos,
          "Automatic correction uses the correction-only prompt");
    check(requestPayload(c,p,manual)["instructions"].get<std::string>().find(
              "No requests for more info; Give your best result directly.") != std::string::npos,
          "Manual request uses assistant prompt with both automatic modes off");
    c["assistantEnabled"]=true;
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
    check(gp["generation_config"]["max_output_tokens"].get<int>() >=
              int(raw.input.size()) * 4 + 32 + 768,
          "Gemini thinking does not consume the long correction reserve");
    p["model"] = "gpt-6.2-sol";
    check(reasoningOptions(p) == std::vector<std::string>{"omit","low","medium","high","xhigh","max"},
          "GPT-6.2 Sol exposes supported reasoning options");
    p = defaultPolicy();
    check(utf8(wide(u8"你好😀 café")) == u8"你好😀 café", "Unicode round trip");
    int attempts = 0,updates=0;
    auto result = requestAi(store,c,p,raw,{}, {},[&](const HttpOptions& o) {
      attempts++;
      check(J::parse(o.body)["stream"]==true,"Streaming enabled");
      auto send=[&](const J& e){auto bytes="data: "+e.dump()+"\n\n";o.consume(bytes.data(),bytes.size());};
      send({{"type","response.output_text.delta"},{"delta",u8"[\"你好\""}});
      check(updates==1,"Correction delivered before assistant");
      send({{"type","response.output_text.delta"},{"delta",u8",\"你好呀\"]"}});
      send({{"type","response.completed"},{"response",{{"usage",J::object()}}}});
      check(o.complete && o.complete(), "Terminal SSE event releases the transport");
      return HttpResponse{200,""};
    },[&](const J& r){updates++;check(r["candidates"].size()==updates,"Stable stream slots");});
    check(attempts==1 && updates==2 && result["candidates"].size()==2,"One request both candidates");
    rejects([&]{requestAi(store,c,p,raw,{}, {},[&](const HttpOptions&) {
      return HttpResponse{200,R"({"status":"incomplete","output":[]})"};
    });},"Truncated stream never silently doubles requests");
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
    {
      auto ok=[&](const HttpOptions& o){
        auto send=[&](const J& e){auto bytes="data: "+e.dump()+"\n\n";o.consume(bytes.data(),bytes.size());};
        send({{"type","response.output_text.delta"},{"delta",u8"[\"你好\"]"}});
        send({{"type","response.completed"},{"response",{{"usage",J::object()}}}});
        return HttpResponse{200,""};};
      attempts = 0;
      auto retried = requestAi(store, c, p, raw, {}, {}, [&](const HttpOptions& o) {
        return ++attempts == 1 ? HttpResponse{503, ""} : ok(o);
      });
      check(attempts == 2 && retried["candidates"].size() == 1, "Gateway 503 retried once");
      attempts = 0;
      requestAi(store, c, p, raw, {}, {}, [&](const HttpOptions& o) -> HttpResponse {
        if (++attempts == 1) throw Error("network", 12030);
        return ok(o);
      });
      check(attempts == 2, "Connection failure before headers retried once");
      attempts = 0;
      rejects([&] { requestAi(store, c, p, raw, {}, {}, [&](const HttpOptions&) {
        attempts++; return HttpResponse{502, ""}; }); }, "Repeated gateway failure surfaced");
      check(attempts == 2, "Gateway failure retried at most once");
      attempts = 0;
      rejects([&] { requestAi(store, c, p, raw, {}, {}, [&](const HttpOptions&) {
        attempts++; return HttpResponse{429, ""}; }); }, "Rate limit surfaced");
      check(attempts == 1, "Rate limit never retried");
      attempts = 0;
      rejects([&] { requestAi(store, c, p, raw, {}, {}, [&](const HttpOptions& o) -> HttpResponse {
        attempts++; HttpResponse h{200, ""}; o.receivedHeaders(h); throw Error("network", 12030); }); },
        "Failure after response headers surfaced");
      check(attempts == 1, "Failure after headers not retried (provider may have billed)");
      attempts = 0; int probes = 0;
      try {
        requestAi(store, c, p, raw, {}, [&] { return ++probes < 3; }, [&](const HttpOptions&) {
          attempts++; return HttpResponse{503, ""}; });
        check(false, "Cancelled retry must throw");
      } catch (const Error& e) { check(e.code == "cancelled", "Typing during backoff cancels the retry"); }
      check(attempts == 1, "No retry after the client disconnects");
    }
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
      try {
        http(o);
        check(false, "Body deadline expected");
      } catch (const Error& e) {
        check(e.code == "timeout" && e.status == int(TimeoutPhase::Body),
              "Timeout identifies the body phase");
      }
      o.url = base + "/huge";
      o.timeoutMs = 3000;
      o.limit = 10;
      rejects([&] { http(o); }, "Bounded response size");
      o.url = base + "/slow";
      o.limit = 65536;
      o.connected = [] { return false; };
      rejects([&] { http(o); }, "Disconnected input client cancelled");
      o.connected={};o.lowLatency=true;o.url=base+"/stream";o.timeoutMs=4000;
      auto streamStart=Clock::now();std::string streamed;int firstMs=-1;
      o.consume=[&](const char* data,size_t length) {
        if(firstMs<0)firstMs=int(std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now()-streamStart).count());
        streamed.append(data,length);
      };
      http(o);
      check(firstMs>=0 && firstMs<1000,"WinHTTP does not wait to fill its buffer");
      check(streamed=="data: first\n\ndata: second\n\n","All stream chunks received");
      streamed.clear();
      o.timeoutMs = 1000;
      o.complete = [&] { return streamed == "data: first\n\n"; };
      http(o);
      check(streamed == "data: first\n\n", "Completed stream stops before waiting for more bytes");
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
    auto first=dir/L"one"/L"service-fixture.exe",second=dir/L"two"/L"service-fixture.exe";
    fs::create_directories(first.parent_path());fs::create_directories(second.parent_path());
    wchar_t current[32768];GetModuleFileNameW(nullptr,current,32768);
    fs::copy_file(current,first);fs::copy_file(current,second);
    run(first,{L"--lifetime-fixture"});run(second,{L"--lifetime-fixture"});
    check(processRunning(first)&&processRunning(second),"Restart fixtures started");
    stopUserProcess(first);
    check(!processRunning(first)&&processRunning(second),"Restart targets exact path only");
    stopUserProcess(second);check(!processRunning(second),"Restart waits for exit");
    std::cout << "PASS: " << checks << " Windows native checks\n";
    fs::remove_all(dir);
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "FAIL after " << checks << ": " << e.what()
              << "\nFixtures: " << dir.u8string() << "\n";
    return 1;
  }
}
