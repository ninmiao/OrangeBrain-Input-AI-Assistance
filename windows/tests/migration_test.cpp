// SPDX-License-Identifier: GPL-3.0-or-later
// Renaming Rime user data from the former product name (Zephyr Input) to OrangeCell.
#include <OrangeCellMigration.h>

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>

namespace fs = std::filesystem;

static int failures = 0;
#define CHECK(x)                                                   \
  do {                                                             \
    if (!(x)) {                                                    \
      std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #x);      \
      failures++;                                                  \
    }                                                              \
  } while (0)

static void write(const fs::path& p, const std::string& text) {
  fs::create_directories(p.parent_path());
  std::ofstream(p, std::ios::binary) << text;
}
static std::string read(const fs::path& p) {
  std::ifstream in(p, std::ios::binary);
  std::stringstream s;
  s << in.rdbuf();
  return s.str();
}

int main() {
  bool changed = false;
  CHECK(orangecell::ReplaceLegacyIdentifiers("schema: zephyr_wanxiang", changed) ==
        "schema: orangecell_wanxiang");
  CHECK(changed);
  changed = false;
  CHECK(orangecell::ReplaceLegacyIdentifiers("a zephyr wind; myzephyr_x", changed) ==
        "a zephyr wind; myzephyr_x");
  CHECK(!changed);
  CHECK(orangecell::ReplaceLegacyIdentifiers(".zephyr-wanxiang/state.json", changed) ==
        ".orangecell-wanxiang/state.json");

  wchar_t temp[MAX_PATH];
  GetTempPathW(MAX_PATH, temp);
  fs::path dir = fs::path(temp) / L"orangecell-migration-test";
  std::error_code ec;
  fs::remove_all(dir, ec);
  write(dir / L"zephyr_wanxiang.userdb" / L"CURRENT", "MANIFEST-000001\n");
  write(dir / L"zephyr_wanxiang_d_2a94c48aa51e.dict.yaml",
        "---\r\nname: zephyr_wanxiang_d_2a94c48aa51e\r\nimport_tables:\r\n"
        "  - zephyr_wanxiang_d_2a94c48aa51e_data/dicts/zi\r\n...\r\n\xE4\xBD\xA0\tni\t1\r\n");
  fs::create_directories(dir / L"zephyr_wanxiang_d_2a94c48aa51e_data" / L"dicts");
  write(dir / L"user.yaml", "var:\n  previously_selected_schema: zephyr_wanxiang\n");
  write(dir / L".zephyr-wanxiang" / L"state.json", "{\"dictionary\":\"zephyr_wanxiang_d_2a94c48aa51e\"}");
  write(dir / L"build" / L"zephyr_wanxiang.schema.yaml", "old");
  write(dir / L"build" / L"rime_ice.table.bin", "keep");
  write(dir / L"sync" / L"device" / L"zephyr_wanxiang.userdb.txt", "# snapshot\n");

  orangecell::MigrateLegacyRimeDirectory(dir);

  CHECK(read(dir / L"orangecell_wanxiang.userdb" / L"CURRENT") == "MANIFEST-000001\n");
  CHECK(!fs::exists(dir / L"zephyr_wanxiang.userdb"));
  CHECK(read(dir / L"orangecell_wanxiang_d_2a94c48aa51e.dict.yaml") ==
        "---\r\nname: orangecell_wanxiang_d_2a94c48aa51e\r\nimport_tables:\r\n"
        "  - orangecell_wanxiang_d_2a94c48aa51e_data/dicts/zi\r\n...\r\n\xE4\xBD\xA0\tni\t1\r\n");
  CHECK(fs::is_directory(dir / L"orangecell_wanxiang_d_2a94c48aa51e_data" / L"dicts"));
  CHECK(read(dir / L"user.yaml") == "var:\n  previously_selected_schema: orangecell_wanxiang\n");
  CHECK(read(dir / L".orangecell-wanxiang" / L"state.json") ==
        "{\"dictionary\":\"orangecell_wanxiang_d_2a94c48aa51e\"}\n");
  CHECK(!fs::exists(dir / L"build" / L"zephyr_wanxiang.schema.yaml"));
  CHECK(fs::exists(dir / L"build" / L"rime_ice.table.bin"));
  CHECK(fs::exists(dir / L"sync" / L"device" / L"orangecell_wanxiang.userdb.txt"));
  CHECK(fs::exists(dir / L".orangecell-migrated"));

  // The marker stops repeat scans.
  write(dir / L"zephyr_ice.custom.yaml", "x");
  orangecell::MigrateLegacyRimeDirectory(dir);
  CHECK(fs::exists(dir / L"zephyr_ice.custom.yaml"));

  fs::remove_all(dir, ec);
  if (failures) return 1;
  std::printf("migration_test passed\n");
  return 0;
}
