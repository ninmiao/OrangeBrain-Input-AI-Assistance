// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <windows.h>

#include <atomic>
#include <chrono>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>
#include <vector>
namespace zw {
using J = nlohmann::json;
namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
struct Error : std::runtime_error {
  std::string code;
  int status;
  Error(std::string c, int s = 0)
      : std::runtime_error(c), code(std::move(c)), status(s) {}
};
void require(bool ok, const char* message);
std::wstring wide(const std::string& text);
std::string utf8(const std::wstring& text);
std::string readFile(const fs::path& path, size_t limit = 8 * 1024 * 1024);
void atomicWrite(const fs::path& path, const std::string& data);
fs::path appDirectory();
fs::path userDirectory();
fs::path rimeDirectory();
std::string uniqueId();
std::string sha256(const fs::path& path);
std::string hex(const std::string& value);
std::string unhex(const std::string& value);
std::string now();
std::wstring quote(const std::wstring& s);
DWORD run(const fs::path& exe, const std::vector<std::wstring>& args,
          DWORD timeout = 0);
bool processRunning(const fs::path& executable);
void stopUserProcess(const fs::path& executable);
J core(const std::string& op, const J& args = J::object());
std::string errorText(const std::exception& error);
struct Handle {
  HANDLE value = nullptr;
  explicit Handle(HANDLE h = nullptr) : value(h) {}
  ~Handle() {
    if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value);
  }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  operator HANDLE() const { return value; }
};
}  // namespace zw
