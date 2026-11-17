// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <set>

#include "network.h"
namespace zw {
struct Progress {
  std::string message;
  uint64_t done = 0, total = 0;
  bool cancelable = true;
};
using ProgressFn = std::function<void(const Progress&)>;
J parseRelease(const std::string& body, const std::string& kind);
void extractDictionaryZip(const fs::path& zip, const fs::path& destination,
                          const std::set<std::string>& required);
class Dictionary {
 public:
  explicit Dictionary(fs::path directory = rimeDirectory(),
                      fs::path image = appDirectory(), ProgressFn progress = {},
                      std::shared_ptr<Cancel> cancel = {})
      : dir_(fs::absolute(directory)),
        image_(fs::absolute(image)),
        progress_(std::move(progress)),
        cancel_(std::move(cancel)) {}
  J state() const;
  std::string summary() const;
  void select(bool wanxiang, bool grammar);
  void update(const std::string& kind);

 private:
  fs::path dir_, image_;
  ProgressFn progress_;
  std::shared_ptr<Cancel> cancel_;
  fs::path workspace() const { return dir_ / L".zephyr-wanxiang"; }
  void progress(const std::string& message, bool cancelable = true) const;
  void deploy(const std::string& schema);
  void recover();
  void activate(const J& value);
  void cacheBundle(const J& release, bool wanxiang);
  fs::path download(const J& asset);
  void installDictionary(const J& release, bool wanxiang);
};
}  // namespace zw
