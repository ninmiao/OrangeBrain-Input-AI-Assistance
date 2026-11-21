// SPDX-License-Identifier: GPL-3.0-or-later
#include "platform.h"
#include "../native/include/OrangeCellMigration.h"

#include <bcrypt.h>
#include <shlobj.h>
#include <tlhelp32.h>

#include <fstream>
#include <iomanip>
#include <sstream>

#include "core.h"
namespace zw {
void require(bool ok, const char* message) {
  if (!ok) throw Error(message);
}
std::wstring wide(const std::string& s) {
  if (s.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(),
                              int(s.size()), nullptr, 0);
  require(n > 0, "Invalid UTF-8");
  std::wstring out(n, 0);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), int(s.size()),
                      out.data(), n);
  return out;
}
std::string utf8(const std::wstring& s) {
  if (s.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, s.data(),
                              int(s.size()), nullptr, 0, nullptr, nullptr);
  require(n > 0, "Invalid Unicode");
  std::string out(n, 0);
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, s.data(), int(s.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}
std::string readFile(const fs::path& p, size_t limit) {
  require(fs::file_size(p) <= limit, "File too large");
  std::ifstream f(p, std::ios::binary);
  require(bool(f), "Cannot read file");
  return std::string(std::istreambuf_iterator<char>(f), {});
}
void atomicWrite(const fs::path& p, const std::string& data) {
  fs::create_directories(p.parent_path());
  auto temp = p.parent_path() / (L"write-" + wide(uniqueId()) + L".tmp");
  try {
    Handle h(CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                         FILE_ATTRIBUTE_NORMAL, nullptr));
    require(h.value != INVALID_HANDLE_VALUE, "Cannot create settings file");
    DWORD written = 0;
    require(
        data.size() < MAXDWORD &&
            WriteFile(h, data.data(), DWORD(data.size()), &written, nullptr) &&
            written == data.size() && FlushFileBuffers(h),
        "Cannot save settings");
    CloseHandle(h.value);
    h.value = nullptr;
    require(
        MoveFileExW(temp.c_str(), p.c_str(),
                    MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0,
        "Cannot replace settings file");
  } catch (...) {
    std::error_code e;
    fs::remove(temp, e);
    throw;
  }
}
fs::path appDirectory() {
  std::wstring path(32768, 0);
  DWORD n = GetModuleFileNameW(nullptr, path.data(), DWORD(path.size()));
  require(n && n < path.size(), "Cannot locate application");
  path.resize(n);
  return fs::path(path).parent_path();
}
fs::path userDirectory() {
  orangecell::MigrateLegacyUserData();
  PWSTR p = nullptr;
  require(
      SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &p)),
      "Cannot find AppData");
  fs::path dir = fs::path(p) / L"OrangeCell";
  CoTaskMemFree(p);
  return dir;
}
fs::path rimeDirectory() {
  wchar_t data[32768];
  DWORD size = sizeof(data);
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\OrangeCell", L"RimeUserDir",
                   RRF_RT_REG_SZ, nullptr, data, &size) == ERROR_SUCCESS &&
      data[0])
    return data;
  return userDirectory() / L"rime";
}
std::string uniqueId() {
  GUID id;
  require(SUCCEEDED(CoCreateGuid(&id)), "Cannot create identifier");
  wchar_t text[40];
  StringFromGUID2(id, text, 40);
  std::wstring s(text);
  return utf8(s.substr(1, s.size() - 2));
}
std::string hex(const std::string& s) {
  static const char* digits = "0123456789abcdef";
  std::string out;
  out.reserve(s.size() * 2);
  for (unsigned char c : s) {
    out += digits[c >> 4];
    out += digits[c & 15];
  }
  return out;
}
std::string unhex(const std::string& s) {
  require(s.size() % 2 == 0 && s.size() <= 12000, "Invalid pipe input");
  auto val = [](char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    throw Error("Invalid pipe input");
  };
  std::string out;
  for (size_t i = 0; i < s.size(); i += 2)
    out += char(val(s[i]) * 16 + val(s[i + 1]));
  wide(out);
  return out;
}
std::string sha256(const fs::path& path) {
  BCRYPT_ALG_HANDLE alg = nullptr;
  require(BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr,
                                      0) == 0,
          "SHA-256 unavailable");
  BCRYPT_HASH_HANDLE hash = nullptr;
  try {
    require(BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0) == 0,
            "SHA-256 unavailable");
    std::ifstream f(path, std::ios::binary);
    require(bool(f), "Cannot read download");
    char block[131072];
    while (f) {
      f.read(block, sizeof(block));
      require(BCryptHashData(hash, reinterpret_cast<PUCHAR>(block),
                             ULONG(f.gcount()), 0) == 0,
              "SHA-256 failed");
    }
    unsigned char out[32];
    require(BCryptFinishHash(hash, out, 32, 0) == 0, "SHA-256 failed");
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    return hex(std::string(reinterpret_cast<char*>(out), 32));
  } catch (...) {
    if (hash) BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    throw;
  }
}
std::string now() {
  SYSTEMTIME t;
  GetSystemTime(&t);
  char buf[40];
  sprintf_s(buf, "%04u-%02u-%02uT%02u:%02u:%02uZ", t.wYear, t.wMonth, t.wDay,
            t.wHour, t.wMinute, t.wSecond);
  return buf;
}
std::wstring quote(const std::wstring& s) {
  std::wstring out = L"\"";
  size_t slashes = 0;
  for (auto c : s) {
    if (c == L'\\') {
      slashes++;
      continue;
    }
    if (c == L'\"')
      out.append(slashes * 2 + 1, L'\\');
    else
      out.append(slashes, L'\\');
    slashes = 0;
    out += c;
  }
  out.append(slashes * 2, L'\\');
  return out + L"\"";
}
DWORD run(const fs::path& exe, const std::vector<std::wstring>& args,
          DWORD timeout) {
  std::wstring cmd = quote(exe.wstring());
  for (auto& a : args) cmd += L" " + quote(a);
  STARTUPINFOW si{sizeof(si)};
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION pi{};
  require(CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, FALSE,
                         CREATE_NO_WINDOW, nullptr, exe.parent_path().c_str(),
                         &si, &pi) != 0,
          "Cannot launch native helper");
  Handle process(pi.hProcess), thread(pi.hThread);
  if (!timeout) return 0;
  if (WaitForSingleObject(process, timeout) != WAIT_OBJECT_0) {
    TerminateProcess(process, 1);
    WaitForSingleObject(process, 5000);
    throw Error("Native helper timed out");
  }
  DWORD code;
  GetExitCodeProcess(process, &code);
  return code;
}
bool processRunning(const fs::path& exe) {
  Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  PROCESSENTRY32W e{sizeof(e)};
  if (Process32FirstW(snap, &e)) do {
      if (_wcsicmp(e.szExeFile, exe.filename().c_str())) continue;
      Handle p(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                           e.th32ProcessID));
      wchar_t path[32768];
      DWORD n = 32768;
      if (p.value && QueryFullProcessImageNameW(p, 0, path, &n) &&
          !_wcsicmp(path, exe.c_str()))
        return true;
    } while (Process32NextW(snap, &e));
  return false;
}
void stopUserProcess(const fs::path& exe) {
  DWORD session=0;ProcessIdToSessionId(GetCurrentProcessId(),&session);
  Handle snap(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0));PROCESSENTRY32W e{sizeof(e)};
  if(Process32FirstW(snap,&e))do {
    DWORD other=0;
    if(_wcsicmp(e.szExeFile,exe.filename().c_str()) || !ProcessIdToSessionId(e.th32ProcessID,&other) || other!=session)continue;
    Handle p(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|PROCESS_TERMINATE|SYNCHRONIZE,FALSE,e.th32ProcessID));
    wchar_t path[32768];DWORD n=32768;
    if(p.value && QueryFullProcessImageNameW(p,0,path,&n) && !_wcsicmp(path,exe.c_str())) {
      require(TerminateProcess(p,0)!=0,"Cannot stop input service");
      require(WaitForSingleObject(p,5000)==WAIT_OBJECT_0,"Input service did not stop");
    }
  }while(Process32NextW(snap,&e));
}
J core(const std::string& op, const J& args) {
  auto response =
      J::parse(orangecell::invoke(J{{"op", op}, {"args", args}}.dump()));
  if (response.contains("error"))
    throw Error(response["error"], response.value("status", 0));
  return response.at("ok");
}
std::string errorText(const std::exception& e) {
  auto err = dynamic_cast<const Error*>(&e);
  if (err) {
    if (err->code == "HTTP") return "HTTP " + std::to_string(err->status);
    if (err->code == "cancelled") return u8"已取消 / Cancelled";
    if (err->code == "timeout") {
      switch (TimeoutPhase(err->status)) {
        case TimeoutPhase::Send: return u8"连接或发送超时 / Connection or send timed out";
        case TimeoutPhase::Headers: return u8"等待响应头超时 / Response headers timed out";
        case TimeoutPhase::Body: return u8"读取模型输出超时 / Model response timed out";
      }
      return u8"请求超时 / Request timed out";
    }
    if (err->code == "truncated")
      return u8"模型输出截断 / Truncated model output";
    if (err->code == "response")
      return u8"模型返回格式无效 / Invalid response format";
    if (err->code == "network")
      return u8"网络请求失败 / Network error " + std::to_string(err->status);
    return err->code;
  }
  return u8"操作失败 / Operation failed";
}
}  // namespace zw
