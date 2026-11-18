// SPDX-License-Identifier: GPL-3.0-or-later
#include "service.h"

#include <sddl.h>

#include <algorithm>
#include <condition_variable>
#include <fstream>
#include <string_view>
#include <thread>
namespace zw {
Input decodeWire(const std::string& text) {
  require(text.size() <= 15000, "Invalid pipe request");
  std::vector<std::string> fields;
  size_t start = 0;
  for (size_t i = 0; i <= text.size(); i++)
    if (i == text.size() || text[i] == '\t') {
      fields.push_back(text.substr(start, i - start));
      start = i + 1;
    }
  require((fields.size() == 4 && fields[0] == "Z1") ||
              (fields.size() == 6 && (fields[0] == "Z2" || fields[0] == "Z4")) ||
              (fields.size() == 7 && fields[0] == "Z4" && fields[6] == "assistant"),
          "Invalid pipe version");
  require((fields[1] == "zh" || fields[1] == "en") &&
              (fields[2] == "0" || fields[2] == "1"),
          "Invalid input mode");
  Input r{fields[1] == "zh", fields[2] == "1", unhex(fields[3])};
  if (fields.size() >= 6) {
    r.before = unhex(fields[4]);
    r.after = unhex(fields[5]);
  }
  r.manual = fields.size() == 7;
  require(!r.input.empty() && wide(r.input).size() <= 600 &&
              std::none_of(r.input.begin(), r.input.end(),
                           [](unsigned char c) { return c < 32 || c == 127; }),
          "Invalid input text");
  core("encode", {{"input", r.input}});
  return r;
}
std::string responseWire(const J& c, const J& result,
                         const std::string& error) {
  auto b = [&](const char* key) { return c.at(key).get<bool>() ? "1" : "0"; };
  const bool assistant = result.is_object()
      ? result.value("assistantEnabled", c.value("assistantEnabled", false))
      : c.value("assistantEnabled", false);
  std::string out = "Z1\t" + std::string(b("wordSegmentation")) + "\t" +
                    std::to_string(c.at("debounceMs").get<int>()) + "\t" +
                    b("enterOriginal") + "\t" + b("spaceOriginal") + "\t" +
                      (assistant ? "1" : "0") + "\t" +
                      (result.is_object() && result.value("streaming",false) ? "1" : "0") + "\n";
  if (!error.empty()) out += "E\t" + hex(error) + "\n";
  if (result.is_object())
    for (auto& s : result.value("candidates", J::array()))
      out += hex(s.get<std::string>()) + "\n";
  return out;
}
Input latencySample(bool chinese) {
  return {
      chinese, false,
      chinese
          ? "jintianxiawuwomenyaoheteamyiqitaolunxiangmujindu hexiayibujihua "
            "qingbamingtianzaoshangjiudianhuiyixuyaodewenjianzhenglihaofageiwo"
          : "Tomorrow morning we have a meeting with the team to discuss "
            "project progress and next week's plan. Pleaes send me teh updated "
            "documents before nine and keep the 123 test results.",
      chinese ? u8"我们正在讨论周末聚餐，大家想吃清淡一点，也有人需要提前安排工"
                u8"作时间。接下来我想补充："
              : "We are planning the weekend dinner and arranging the meeting "
                "schedule. Here is my suggestion: ",
      chinese ? u8"，请大家确认时间。" : ", please confirm the time."};
}
J requestPayload(const J& c, const J& p, const Input& raw, int budget) {
  const bool assistant = raw.manual || c.at("assistantEnabled").get<bool>();
  auto context = core("context", {{"input", raw.input},
                                  {"before", raw.before},
                                  {"after", raw.after},
                                  {"enabled", c.at("contextEnabled")},
                                  {"beforeLimit", c.at("beforeLength")},
                                  {"afterLimit", c.at("afterLength")}});
  context["input"] = raw.input;
  std::string prompt = core(
      "prompt", {{"chinese", raw.chinese}, {"traditional", raw.traditional}, {"assistantEnabled", assistant}});
  auto custom = p.value(raw.chinese ? "chinesePrompt" : "englishPrompt", "");
  if (!custom.empty()) {
    auto pos = prompt.find(u8"仅输出JSON字符串数组");
    prompt.insert(pos == std::string::npos ? prompt.size() : pos,
                  "\n" + custom + "\n");
  }
  J parameters = {{"service_tier", p.at("speed")}};
  if (p.at("reasoning") != "omit")
    parameters["reasoning_effort"] = p.at("reasoning");
  return core(
      "payload",
      {{"endpoint", p.at("endpoint")},
       {"model", p.at("model")},
       {"provider", p.at("provider")},
       {"parameters", parameters},
       {"request",
        {{"input", context},
         {"systemPrompt", prompt},
         {"assistantEnabled", assistant},
         {"outputTokenBudget",
          budget < 0 ? c.at("outputTokenBudget").get<int>() : budget}}}});
}
J requestAi(const Store& store, const J& c, const J& p, const Input& raw,
            std::shared_ptr<Cancel> cancel, std::function<bool()> connected,
            std::function<HttpResponse(const HttpOptions&)> transport,
            std::function<void(const J&)> partial) {
  validateConfiguration(c);
  auto key = store.key(p.at("id"), p.at("endpoint"));
  require(!key.empty(), "No API key saved for this policy");
  auto routing = core("routing", {{"endpoint", p.at("endpoint")}});
  HttpOptions o;
  o.url = routing.at("url"); o.method = "POST";
  o.body = requestPayload(c, p, raw).dump();
  o.timeoutMs = c.at("timeoutMs"); o.limit = 1048576; o.lowLatency=true;
  o.cancel = cancel; o.connected = connected;
  if (routing["api"] == "gemini")
    o.headers = {{"x-goog-api-key", key}, {"Api-Revision", "2026-05-20"}};
  else o.headers = {{"Authorization", "Bearer " + key}};
  J state=J::object(), latest, published;
  auto feed=[&](const std::string& bytes,bool finish) {
    auto r=core("stream",{{"endpoint",p.at("endpoint")},{"assistantEnabled",raw.manual || c.at("assistantEnabled").get<bool>()},
                          {"state",state},{"chunkHex",hex(bytes)},{"finish",finish}});
    state=r.at("state");latest=r.at("result");
    if(latest.is_object() && latest.at("candidates")!=published) {
      if(cancel)cancel->check();
      if(connected && !connected())throw Error("cancelled");
      published=latest.at("candidates");
      if(partial)partial(latest);
    }
  };
  o.receivedHeaders=[](const HttpResponse& r) {
    if(r.status<200 || r.status>=300)throw Error("HTTP",r.status);
  };
  o.consume=[&](const char* bytes,size_t count){feed(std::string(bytes,count),false);};
  try {
    auto response=transport(o);
    if(response.status<200 || response.status>=300)throw Error("HTTP",response.status);
    // Injected test transports and compatible gateways may buffer a JSON body.
    if(!response.body.empty())feed(response.body,false);
    feed({},true);
    return latest;
  } catch(const Error& e) {
    if(e.code=="cancelled" || !latest.is_object())throw;
    if(cancel)cancel->check();
    if(connected && !connected())throw Error("cancelled");
    latest["streaming"]=false;latest["streamError"]=e.code;latest["recovered"]=true;
    return latest;
  }
}

std::string handleRequest(const Store& store, const std::string& text,
                          std::shared_ptr<Cancel> cancel,
                          std::function<bool()> connected,
                          std::function<void(const J&)> partial) {
  auto input = decodeWire(text);
  auto config = store.load();
  J result;
  std::string failure;
  if (input.manual || config.at("enabled").get<bool>() || config.at("assistantEnabled").get<bool>()) {
    try {
      result = requestAi(store, config, activePolicy(config), input, cancel,
                         connected, http, [&](const J& r) {
                           if(partial && store.load()==config) {
                             auto progress=r;
                             progress["streaming"]=true;
                             progress["assistantEnabled"]=input.manual || config.at("assistantEnabled").get<bool>();
                             partial(progress);
                           }
                         });
      store.requestStatus(result.value("streamError",std::string()).empty()?"OK":"partial: "+result.at("streamError").get<std::string>());
    } catch (const Error& e) {
      if (e.code == "cancelled") throw;
      failure = errorText(e);
      try {
        store.requestStatus(
            e.code == "HTTP" ? "HTTP " + std::to_string(e.status) : e.code);
      } catch (...) {
      }
    }
  }
  auto latest = store.load();
  if (latest != config) return responseWire(latest);
  if (input.manual) latest["assistantEnabled"] = true;
  return responseWire(latest, result, failure);
}
namespace {
bool pipeOperation(HANDLE pipe, bool writing, void* buffer, DWORD count,
                   DWORD& transferred) {
  Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  OVERLAPPED ov{};
  ov.hEvent = event;
  BOOL done = writing ? WriteFile(pipe, buffer, count, &transferred, &ov)
                      : ReadFile(pipe, buffer, count, &transferred, &ov);
  if (done) return true;
  if (GetLastError() != ERROR_IO_PENDING) return false;
  if (WaitForSingleObject(event, 5000) != WAIT_OBJECT_0) {
    CancelIoEx(pipe, &ov);
    GetOverlappedResult(pipe, &ov, &transferred, TRUE);
    return false;
  }
  return GetOverlappedResult(pipe, &ov, &transferred, FALSE) != 0;
}
void drainPipe(HANDLE pipe) {
  Handle worker;
  require(DuplicateHandle(GetCurrentProcess(), GetCurrentThread(),
                          GetCurrentProcess(), &worker.value, 0, FALSE,
                          DUPLICATE_SAME_ACCESS) != 0,
          "Cannot bound pipe drain");
  std::mutex mutex;
  std::condition_variable cv;
  bool done = false;
  std::thread deadline([&] {
    std::unique_lock<std::mutex> lock(mutex);
    if (!cv.wait_for(lock, std::chrono::seconds(2), [&] { return done; })) {
      CancelSynchronousIo(worker);
      CancelIoEx(pipe, nullptr);
    }
  });
  FlushFileBuffers(pipe);
  {
    std::lock_guard<std::mutex> lock(mutex);
    done = true;
  }
  cv.notify_all();
  deadline.join();
}
}  // namespace
void runBroker(const Store& store, bool startServer,
               const std::wstring& testPipe) {
  Handle lock(CreateFileW((store.directory() / L"broker.lock").c_str(),
                          GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                          OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr));
  require(lock.value != INVALID_HANDLE_VALUE, "Cannot open broker lock");
  OVERLAPPED ov{};
  if (!LockFileEx(lock, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0,
                  1, 0, &ov))
    return;
  auto server = appDirectory() / L"ZephyrServer.exe";
  if (startServer && fs::exists(server) && !processRunning(server))
    run(server, {});
  Handle token;
  require(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token.value) != 0,
          "Cannot read current user");
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> tokenInfo(size);
  require(
      GetTokenInformation(token, TokenUser, tokenInfo.data(), size, &size) != 0,
      "Cannot read current user");
  LPWSTR sid = nullptr;
  require(
      ConvertSidToStringSidW(
          reinterpret_cast<TOKEN_USER*>(tokenInfo.data())->User.Sid, &sid) != 0,
      "Cannot read user SID");
  std::wstring acl = L"D:P(A;;GA;;;" + std::wstring(sid) + L")";
  LocalFree(sid);
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  require(ConvertStringSecurityDescriptorToSecurityDescriptorW(
              acl.c_str(), SDDL_REVISION_1, &descriptor, nullptr) != 0,
          "Cannot protect pipe");
  wchar_t username[256];
  DWORD length = 256;
  require(GetUserNameW(username, &length) != 0, "Cannot read username");
  std::wstring name = testPipe.empty()
                          ? L"\\\\.\\pipe\\ZephyrAI-" + std::wstring(username)
                          : testPipe;
  // Four bounded workers; each request is cancelled when its TSF client
  // disconnects.
  std::vector<std::thread> workers;
  for (int i = 0; i < 4; i++)
    workers.emplace_back([&, descriptor] {
      SECURITY_ATTRIBUTES sa{sizeof(sa), descriptor, FALSE};
      for (;;) {
        Handle pipe(CreateNamedPipeW(name.c_str(),
                                     PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                                     PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE |
                                         PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                                     4, 131072, 16384, 5000, &sa));
        if (pipe.value == INVALID_HANDLE_VALUE) return;
        Handle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
        OVERLAPPED connection{};
        connection.hEvent = event;
        BOOL connected = ConnectNamedPipe(pipe, &connection);
        DWORD error = GetLastError();
        if (!connected && error == ERROR_IO_PENDING) {
          WaitForSingleObject(event, INFINITE);
          DWORD count = 0;
          connected = GetOverlappedResult(pipe, &connection, &count, FALSE);
        } else if (!connected && error == ERROR_PIPE_CONNECTED)
          connected = TRUE;
        if (!connected) continue;
        try {
          char input[16384];
          DWORD count = 0;
          if (pipeOperation(pipe, false, input, sizeof(input), count)) {
            auto alive = [&] {
              return PeekNamedPipe(pipe, nullptr, 0, nullptr, nullptr,
                                   nullptr) != 0;
            };
            std::string response;
            try {
              response =
                  handleRequest(store, std::string(input, count), {}, alive,
                    [&](const J& r) {
                      if (count < 3 || std::string_view(input, 3) != "Z4\t") return;
                      auto message=responseWire(store.load(),r);DWORD written=0;
                      if(!pipeOperation(pipe,true,message.data(),DWORD(message.size()),written))
                        throw Error("cancelled");
                    });
            } catch (const Error& e) {
              if (e.code == "cancelled") {
                DisconnectNamedPipe(pipe);
                continue;
              }
              response = responseWire(store.load(), {}, errorText(e));
            }
            if (response.size() <= 131072 &&
                pipeOperation(pipe, true, response.data(),
                              DWORD(response.size()), count))
              drainPipe(pipe);
          }
        } catch (
            ...) { /* A malformed client cannot terminate the input service. */
        }
        DisconnectNamedPipe(pipe);
      }
    });
  for (auto& worker : workers) worker.join();
  LocalFree(descriptor);
}
void evaluate(const Store& store, const std::vector<std::wstring>& a) {
  require(a.size() == 3 || a.size() == 4,
          "--evaluate corpus.jsonl report.json limit [policy-id]");
  int limit = std::stoi(a[2]);
  require(limit >= 1 && limit <= 500, "Evaluation limit must be 1..500");
  auto c = store.load();
  if (a.size() == 4) c["selectedPolicy"] = utf8(a[3]);
  validateConfiguration(c);
  J rows = J::array();
  std::ifstream file{fs::path(a[0])};
  require(bool(file), "Cannot open corpus");
  std::string line;
  while (rows.size() < size_t(limit) && std::getline(file, line)) {
    if (line.empty()) continue;
    auto r = J::parse(line);
    Input in{r.at("language") == "zh", false, r.at("input"),
             r.value("before", ""), r.value("after", "")};
    auto start = Clock::now();
    J out = {{"id", r.at("id")},
             {"category", r.value("category", "")},
             {"language", r.at("language")}};
    try {
      auto result = requestAi(store, c, activePolicy(c), in);
      out["candidates"] = result["candidates"];
      out["success"] = true;
    } catch (const std::exception& e) {
      out["candidates"] = J::array();
      out["success"] = false;
      out["error"] = errorText(e);
    }
    out["top1"] = !out["candidates"].empty() &&
                  std::find(r["expected"].begin(), r["expected"].end(),
                            out["candidates"][0]) != r["expected"].end();
    out["elapsed_ms"] = std::chrono::duration_cast<std::chrono::milliseconds>(
                            Clock::now() - start)
                            .count();
    rows.push_back(out);
  }
  atomicWrite(a[1], J{{"timestamp", now()},
                      {"kind", "live-model-quality"},
                      {"model", activePolicy(c)["model"]},
                      {"count", rows.size()},
                      {"results", rows}}
                        .dump(2));
}
}  // namespace zw
