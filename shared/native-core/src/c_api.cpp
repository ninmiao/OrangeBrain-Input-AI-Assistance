// SPDX-License-Identifier: GPL-3.0-or-later
#include "c_api.h"

#include <cstdlib>
#include <cstring>
#include <string>

#include "core.h"

extern "C" char* oc_invoke(const char* command) {
  std::string out;
  try {
    out = command ? orangecell::invoke(command)
                  : std::string(R"({"error":"invalid"})");
  } catch (...) {
    out = R"({"error":"response"})";
  }
  char* result = static_cast<char*>(std::malloc(out.size() + 1));
  if (!result) return nullptr;
  std::memcpy(result, out.c_str(), out.size() + 1);
  return result;
}

extern "C" void oc_free(char* p) { std::free(p); }
