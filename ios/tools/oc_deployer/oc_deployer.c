// SPDX-License-Identifier: GPL-3.0-or-later
//
// oc_deployer: compiles the Rime schemas and dictionaries that ship inside the iOS
// app (docs/IOS_PLAN.md section 4.4). It is linked against the arm64 macOS librime
// of the same fcitx5-prebuilder batch family as the iOS libraries (both pinned in
// ios/deps.lock.json), so the keyboard never has to deploy anything itself.
//
//   oc_deployer <shared_data_dir> <user_data_dir> <staging_dir>
//
// shared_data_dir  schema and dictionary sources (default.yaml, *.schema.yaml, ...)
// user_data_dir    customizations (default.custom.yaml); scratch files land here
// staging_dir      output: build/*.yaml, *.table.bin, *.prism.bin, *.reverse.bin
//
// It performs the same work as `rime_deployer --build`: installation update,
// workspace update (all schemas of schema_list), user dictionary upgrade, cleanup.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <rime_api.h>

// The prebuilt macOS librime carries patches for fcitx5-macos that call back into
// that application. The deployer has no UI, so the answers are fixed.
int f5m_is_linear_layout(void) { return 0; }
int f5m_is_vertical_lr(void) { return 0; }
int f5m_is_vertical_rl(void) { return 0; }

int main(int argc, char** argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s <shared_data_dir> <user_data_dir> <staging_dir>\n", argv[0]);
    return 2;
  }
  RimeApi* rime = rime_get_api();
  if (!rime) {
    fprintf(stderr, "rime_get_api() returned NULL\n");
    return 2;
  }
  RimeTraits traits;
  memset(&traits, 0, sizeof(traits));
  traits.data_size = (int)(sizeof(RimeTraits) - sizeof(traits.data_size));
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.prebuilt_data_dir = argv[3];
  traits.staging_dir = argv[3];
  traits.distribution_name = "OrangeCell";
  traits.distribution_code_name = "OrangeCell";
  traits.distribution_version = "ios";
  traits.app_name = "rime.oc_deployer";
  traits.min_log_level = 0;
  traits.log_dir = "";  // glog to stderr only

  printf("oc_deployer: librime %s\n", rime->get_version());
  rime->setup(&traits);
  rime->deployer_initialize(&traits);
  Bool ok = rime->deploy();
  rime->finalize();
  printf("oc_deployer: deploy %s\n", ok ? "succeeded" : "FAILED");
  return ok ? 0 : 1;
}
