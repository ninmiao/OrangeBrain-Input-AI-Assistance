// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "platform.h"
namespace zw {
inline constexpr char OPENAI[] = "https://api.openai.com/v1/responses";
inline constexpr char OPENROUTER[] =
    "https://openrouter.ai/api/v1/chat/completions";
inline constexpr char GEMINI[] =
    "https://generativelanguage.googleapis.com/v1beta/interactions";
J defaultPolicy(const std::string& type = "openai");
J defaultConfiguration();
J normalizeConfiguration(J value);
void validateConfiguration(const J& value);
std::vector<std::string> reasoningOptions(const J& policy);
J& activePolicy(J& config);
const J& activePolicy(const J& config);
std::string origin(const std::string& endpoint);
class Store {
 public:
  explicit Store(fs::path directory = userDirectory())
      : directory_(std::move(directory)) {
    fs::create_directories(directory_);
  }
  const fs::path& directory() const { return directory_; }
  J load() const;
  void save(const J& config) const;
  bool hasKey(const std::string& id) const;
  std::string key(const std::string& id, const std::string& endpoint) const;
  void saveKey(const std::string& id, const std::string& key,
               const std::string& endpoint) const;
  std::string duplicate(const std::string& id) const;
  J remove(const std::string& id) const;
  void eraseKey(const std::string& id) const;
  void requestStatus(const std::string& status) const;

 private:
  fs::path directory_;
  fs::path keyPath(const std::string& id) const;
};
}  // namespace zw
