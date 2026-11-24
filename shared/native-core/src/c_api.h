// SPDX-License-Identifier: GPL-3.0-or-later
// Plain C entry points for hosts that cannot use C++ or JNI (iOS / Swift).
// Input and output are UTF-8 JSON, exactly as for orangecell::invoke.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Runs one native-core command. Returns a heap string that the caller must
// release with oc_free. Returns NULL only when memory is exhausted.
// A NULL command yields {"error":"invalid"}.
char* oc_invoke(const char* command);

// Releases a string returned by oc_invoke. NULL is accepted.
void oc_free(char* p);

#ifdef __cplusplus
}
#endif
