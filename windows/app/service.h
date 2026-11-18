// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "configuration.h"
#include "network.h"
namespace zw {
struct Input {
  bool chinese = true, traditional = false;
  std::string input, before, after;
  bool manual = false;
};
Input decodeWire(const std::string& text);
std::string responseWire(const J& config, const J& result = J(),
                         const std::string& error = {});
Input latencySample(bool chinese);
J requestPayload(const J& config, const J& policy, const Input& input,
                 int budget = -1);
J requestAi(const Store& store, const J& config, const J& policy,
            const Input& input, std::shared_ptr<Cancel> cancel = {},
            std::function<bool()> connected = {},
            std::function<HttpResponse(const HttpOptions&)> transport = http,
            std::function<void(const J&)> partial = {});
std::string handleRequest(const Store& store, const std::string& text,
                          std::shared_ptr<Cancel> cancel = {},
                          std::function<bool()> connected = {},
                          std::function<void(const J&)> partial = {});
void runBroker(const Store& store, bool startServer = true,
               const std::wstring& testPipe = {});
void evaluate(const Store& store, const std::vector<std::wstring>& arguments);
}  // namespace zw
