// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "platform.h"
namespace zw {
struct Cancel {
  std::atomic<bool> cancelled{false};
  void check() const {
    if (cancelled.load()) throw Error("cancelled");
  }
};
struct HttpResponse {
  unsigned status = 0;
  std::string body, location, contentRange;
};
struct HttpOptions {
  std::string url, method = "GET", body;
  std::vector<std::pair<std::string, std::string>> headers;
  int timeoutMs = 10000;
  size_t limit = 65536;
  std::shared_ptr<Cancel> cancel;
  // Returning false cancels a disconnected pipe client immediately.
  std::function<bool()> connected;
  // Streaming consumer for large, resumable dictionary downloads.
  std::function<void(const HttpResponse&)> receivedHeaders;
  std::function<void(const char*, size_t)> consume;
  std::function<bool()> complete;
  bool testLoopbackHttp = false;
  bool lowLatency = false;
};
HttpResponse http(const HttpOptions& options);
std::string urlEncode(const std::string& value);
J discoverModels(const J& policy, const std::string& key,
                 std::shared_ptr<Cancel> cancel);
J discoverProviders(const std::string& model, std::shared_ptr<Cancel> cancel);
}  // namespace zw
