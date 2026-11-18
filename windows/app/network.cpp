// SPDX-License-Identifier: GPL-3.0-or-later
#include "network.h"

#include <winhttp.h>

#include <condition_variable>
#include <set>
namespace zw {
namespace {
struct Internet {
  HINTERNET h = nullptr;
  explicit Internet(HINTERNET value = nullptr) : h(value) {}
  ~Internet() {
    if (h) WinHttpCloseHandle(h);
  }
  Internet(const Internet&) = delete;
};
struct State {
  std::mutex mutex;
  std::condition_variable cv;
  bool ready = false;
  DWORD error = 0, size = 0;
  std::string body;
  std::wstring headers;
  std::vector<char> buffer = std::vector<char>(65536);
};
void CALLBACK callback(HINTERNET, DWORD_PTR context, DWORD status, LPVOID info,
                       DWORD length) {
  if (!context) return;
  auto holder = reinterpret_cast<std::shared_ptr<State>*>(context);
  auto s = *holder;
  if (status == WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING) {
    delete holder;
    return;
  }
  std::lock_guard<std::mutex> lock(s->mutex);
  if (status == WINHTTP_CALLBACK_STATUS_REQUEST_ERROR) {
    s->error = static_cast<WINHTTP_ASYNC_RESULT*>(info)->dwError;
    s->ready = true;
  } else if (status == WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE) {
    s->ready = true;
    s->size = *static_cast<DWORD*>(info);
  } else if (status == WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE ||
             status == WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE ||
             status == WINHTTP_CALLBACK_STATUS_READ_COMPLETE) {
    s->ready = true;
    s->size = status == WINHTTP_CALLBACK_STATUS_READ_COMPLETE ? length : 0;
  }
  s->cv.notify_one();
}
HINTERNET session() {
  static Internet s(WinHttpOpen(
      L"Zephyr-Input/1.12.3", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, WINHTTP_FLAG_ASYNC));
  require(s.h != nullptr, "Cannot initialize WinHTTP");
  return s.h;
}
std::string header(HINTERNET h, DWORD name) {
  DWORD n = 0;
  WinHttpQueryHeaders(h, name, WINHTTP_HEADER_NAME_BY_INDEX, nullptr, &n,
                      WINHTTP_NO_HEADER_INDEX);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) return {};
  std::wstring s(n / sizeof(wchar_t), 0);
  if (!WinHttpQueryHeaders(h, name, WINHTTP_HEADER_NAME_BY_INDEX, s.data(), &n,
                           WINHTTP_NO_HEADER_INDEX))
    return {};
  s.resize(n / sizeof(wchar_t));
  return utf8(s);
}
}  // namespace
HttpResponse http(const HttpOptions& o) {
  auto url = wide(o.url);
  URL_COMPONENTS u{};
  u.dwStructSize = sizeof(u);
  u.dwSchemeLength = u.dwHostNameLength = u.dwUrlPathLength =
      u.dwExtraInfoLength = u.dwUserNameLength = u.dwPasswordLength = DWORD(-1);
  require(WinHttpCrackUrl(url.c_str(), DWORD(url.size()), 0, &u) != 0,
          "Invalid URL");
  std::wstring host(u.lpszHostName, u.dwHostNameLength),
      path(u.lpszUrlPath, u.dwUrlPathLength);
  if (u.dwExtraInfoLength) path.append(u.lpszExtraInfo, u.dwExtraInfoLength);
  if (path.empty()) path = L"/";
  require((u.nScheme == INTERNET_SCHEME_HTTPS ||
           (o.testLoopbackHttp && u.nScheme == INTERNET_SCHEME_HTTP &&
            (host == L"127.0.0.1" || host == L"localhost"))) &&
              !u.dwUserNameLength && !u.dwPasswordLength &&
              path.find(L'#') == path.npos,
          "HTTPS is required");
  Internet connection(WinHttpConnect(session(), host.c_str(), u.nPort, 0));
  require(connection.h != nullptr, "network");
  auto state = std::make_shared<State>();
  Internet request(WinHttpOpenRequest(
      connection.h, wide(o.method).c_str(), path.c_str(), nullptr,
      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
      u.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0));
  require(request.h != nullptr, "network");
  DWORD redirects = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
  WinHttpSetOption(request.h, WINHTTP_OPTION_REDIRECT_POLICY, &redirects,
                   sizeof(redirects));
  DWORD disable = WINHTTP_DISABLE_COOKIES;
  WinHttpSetOption(request.h, WINHTTP_OPTION_DISABLE_FEATURE, &disable,
                   sizeof(disable));
  WinHttpSetTimeouts(request.h, o.timeoutMs, o.timeoutMs, o.timeoutMs,
                     o.timeoutMs);
  require(WinHttpSetStatusCallback(request.h, callback,
                                   WINHTTP_CALLBACK_FLAG_ALL_COMPLETIONS |
                                       WINHTTP_CALLBACK_FLAG_HANDLES,
                                   0) != WINHTTP_INVALID_STATUS_CALLBACK,
          "network");
  auto holder = new std::shared_ptr<State>(state);
  DWORD_PTR context = reinterpret_cast<DWORD_PTR>(holder);
  if (!WinHttpSetOption(request.h, WINHTTP_OPTION_CONTEXT_VALUE, &context,
                        sizeof(context))) {
    delete holder;
    throw Error("network");
  }
  auto deadline = Clock::now() + std::chrono::milliseconds(o.timeoutMs);
  auto guard = [&] {
    if (o.cancel) o.cancel->check();
    if (o.connected && !o.connected()) throw Error("cancelled");
    if (Clock::now() >= deadline) throw Error("timeout");
  };
  auto start = [&] {
    guard();
    std::lock_guard<std::mutex> lock(state->mutex);
    state->ready = false;
    state->error = 0;
  };
  auto wait = [&](BOOL ok) {
    if (!ok && GetLastError() != ERROR_IO_PENDING)
      throw Error("network", int(GetLastError()));
    std::unique_lock<std::mutex> lock(state->mutex);
    while (!state->ready) {
      state->cv.wait_for(lock, std::chrono::milliseconds(20));
      guard();
    }
    if (state->error) {
      if (state->error == ERROR_WINHTTP_TIMEOUT) throw Error("timeout");
      throw Error("network", int(state->error));
    }
    guard();
    return state->size;
  };
  std::wstring headers = L"Accept-Encoding: identity\r\n";
  if (!o.body.empty())
    headers += L"Content-Type: application/json; charset=utf-8\r\n";
  for (auto& p : o.headers) {
    require(p.first.find_first_of("\r\n:") == p.first.npos &&
                p.second.find_first_of("\r\n") == p.second.npos,
            "Invalid HTTP header");
    headers += wide(p.first) + L": " + wide(p.second) + L"\r\n";
  }
  // Buffers survive cancellation until WinHTTP delivers its final
  // HANDLE_CLOSING callback.
  state->body = o.body;
  state->headers = std::move(headers);
  start();
  wait(WinHttpSendRequest(
      request.h, state->headers.c_str(), DWORD(state->headers.size()),
      state->body.empty() ? WINHTTP_NO_REQUEST_DATA : state->body.data(),
      DWORD(state->body.size()), DWORD(state->body.size()), context));
  start();
  wait(WinHttpReceiveResponse(request.h, nullptr));
  HttpResponse response;
  DWORD size = sizeof(response.status);
  require(WinHttpQueryHeaders(
              request.h, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
              WINHTTP_HEADER_NAME_BY_INDEX, &response.status, &size,
              WINHTTP_NO_HEADER_INDEX) != 0,
          "network");
  response.location = header(request.h, WINHTTP_QUERY_LOCATION);
  response.contentRange = header(request.h, WINHTTP_QUERY_CONTENT_RANGE);
  if (o.receivedHeaders) o.receivedHeaders(response);
  size_t count = 0;
  for (;;) {
    DWORD requested=DWORD(state->buffer.size());
    if(o.lowLatency) {
      start();
      auto available=wait(WinHttpQueryDataAvailable(request.h,nullptr));
      // ReadData otherwise tries to fill the large download buffer, delaying SSE.
      requested=available ? std::min(available,requested) : 1;
    }
    start();
    auto n = wait(WinHttpReadData(request.h, state->buffer.data(),
                                  requested, nullptr));
    if (!n) break;
    count += n;
    require(count <= o.limit, "Response too large");
    if (o.consume)
      o.consume(state->buffer.data(), n);
    else
      response.body.append(state->buffer.data(), n);
  }
  return response;
}
std::string urlEncode(const std::string& v) {
  std::string out;
  for (unsigned char c : v)
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~')
      out += char(c);
    else
      out += "%" + hex(std::string(1, char(c)));
  return out;
}
J discoverModels(const J& p, const std::string& key,
                 std::shared_ptr<Cancel> cancel) {
  std::string endpoint = p.at("endpoint"), base = endpoint;
  bool gemini = core("routing", {{"endpoint", endpoint}})["api"] == "gemini";
  bool matched = false;
  for (auto suffix : {"chat/completions", "responses", "interactions"}) {
    size_t n = strlen(suffix);
    if (base.size() >= n && base.compare(base.size() - n, n, suffix) == 0) {
      base.resize(base.size() - n);
      matched = true;
      break;
    }
  }
  require(matched, "Use a standard API endpoint");
  base += "models";
  J rows = J::array();
  std::set<std::string> seen;
  std::string page;
  size_t total = 0;
  do {
    HttpOptions o;
    o.url = base + (page.empty() ? "" : "?pageToken=" + urlEncode(page));
    o.headers = {{gemini ? "x-goog-api-key" : "Authorization",
                  gemini ? key : "Bearer " + key}};
    o.limit = 8 * 1024 * 1024 - total;
    o.cancel = cancel;
    auto r = http(o);
    if (r.status != 200) throw Error("HTTP", r.status);
    total += r.body.size();
    if (!gemini) {
      auto ids = core("modelsDecode", {{"body", r.body}, {"gemini", false}});
      require(!ids.empty(), "No models returned; previous list retained");
      auto catalog = p.at("catalog");
      if (core("routing", {{"endpoint", endpoint}})["api"] == "openrouter")
        catalog = {{"schema_version", 1},
                   {"version", "models-api"},
                   {"models", core("modelsReasoning", {{"body", r.body}})}};
      return J{{"endpoint", endpoint},
               {"ids", ids},
               {"catalog", catalog}};
    }
    auto body = J::parse(r.body);
    for (auto& row : body.at("models")) rows.push_back(row);
    require(rows.size() <= 2000, "Too many models");
    page = body.value("nextPageToken", "");
    require(page.size() <= 4096 && (page.empty() || (seen.insert(page).second &&
                                                     seen.size() <= 20)),
            "Invalid pagination");
  } while (!page.empty());
  auto ids = core("modelsDecode",
                  {{"envelope", {{"models", rows}}}, {"gemini", true}});
  require(!ids.empty(), "No models returned");
  return J{{"endpoint", endpoint},
           {"ids", ids},
           {"catalog", {{"schema_version", 1},
                        {"version", "models-gemini"},
                        {"models", core("modelsReasoning", {{"models", rows}, {"gemini", true}})}}}};
}
J discoverProviders(const std::string& model, std::shared_ptr<Cancel> cancel) {
  require(model.find('/') != model.npos && model.size() <= 256,
          "Use provider/model as the model ID");
  std::string path, part;
  for (size_t i = 0; i <= model.size(); i++) {
    if (i == model.size() || model[i] == '/') {
      require(!part.empty() && part != "." && part != "..", "Invalid model ID");
      if (!path.empty()) path += '/';
      path += urlEncode(part);
      part.clear();
    } else
      part += model[i];
  }
  HttpOptions o;
  o.url = "https://openrouter.ai/api/v1/models/" + path + "/endpoints";
  o.limit = 2 * 1024 * 1024;
  o.cancel = cancel;
  auto r = http(o);
  if (r.status != 200) throw Error("HTTP", r.status);
  return core("providersDecode", {{"body", r.body}});
}
}  // namespace zw
