// SPDX-License-Identifier: GPL-3.0-or-later
// Public C interface of the shared native core. The declarations live in
// shared/native-core/src/c_api.h (also compiled into the shim next to this
// directory, so a mismatch is a compile error); they are repeated here because a
// module header must stay inside the package.
#ifndef CNATIVECORE_H
#define CNATIVECORE_H

#ifdef __cplusplus
extern "C" {
#endif

char* oc_invoke(const char* command);
void oc_free(char* p);

#ifdef __cplusplus
}
#endif

#endif
