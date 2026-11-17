// SPDX-License-Identifier: GPL-3.0-or-later
#include <jni.h>

#include <codecvt>
#include <locale>

#include "core.h"
extern "C" JNIEXPORT jstring JNICALL
Java_com_osfans_trime_ai_NativeCore_call(JNIEnv* env, jobject, jstring input) {
  try {
    if (!input) return nullptr;
    auto size = env->GetStringLength(input);
    const jchar* data = env->GetStringChars(input, nullptr);
    if (!data) return nullptr;
    std::u16string u(reinterpret_cast<const char16_t*>(data), size);
    env->ReleaseStringChars(input, data);
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> cv;
    auto out = cv.from_bytes(zephyr::invoke(cv.to_bytes(u)));
    return env->NewString(reinterpret_cast<const jchar*>(out.data()),
                          static_cast<jsize>(out.size()));
  } catch (...) {
    return env->NewStringUTF("{\"error\":\"response\"}");
  }
}
