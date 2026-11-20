// SPDX-License-Identifier: GPL-3.0-or-later
// ARM64X TSF loader for Windows on ARM. Built twice from this file: the ARM64 half
// (used by native ARM64 apps) and the ARM64EC half (used by emulated x64 apps), each
// with ZEPHYR_TARGET naming the module it serves. A pure forwarder would make the
// loader search for the target on the default DLL path, which does not include this
// module's directory, so this loads the target by full path from its own folder.
//
// Linked with the static CRT: the ARM64EC half needs its emulation-dispatch helpers
// and load configuration. The code itself only calls kernel32.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <olectl.h>

#ifndef ZEPHYR_TARGET
#error ZEPHYR_TARGET (the target module file name) is required
#endif
#define ZEPHYR_WIDEN2(x) L##x
#define ZEPHYR_WIDEN(x) ZEPHYR_WIDEN2(x)

static HMODULE volatile target;

static HMODULE load_target(void) {
  HMODULE self = NULL, loaded;
  wchar_t path[MAX_PATH];
  const wchar_t* name = ZEPHYR_WIDEN(ZEPHYR_TARGET);
  DWORD length, slash = 0, i, j;
  if (target) return target;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          (LPCWSTR)&load_target, &self))
    return NULL;
  length = GetModuleFileNameW(self, path, MAX_PATH);
  if (!length || length >= MAX_PATH) return NULL;
  for (i = 0; i < length; ++i)
    if (path[i] == L'\\') slash = i + 1;
  if (!slash) return NULL;
  for (j = 0; name[j]; ++j) {
    if (slash + j + 1 >= MAX_PATH) return NULL;
    path[slash + j] = name[j];
  }
  path[slash + j] = 0;
  // A concurrent first call only adds one more reference to the same module, which
  // is harmless because the target stays loaded for the life of the process anyway.
  loaded = LoadLibraryExW(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (loaded) target = loaded;
  return loaded;
}

static FARPROC target_proc(const char* name) {
  HMODULE module = load_target();
  return module ? GetProcAddress(module, name) : NULL;
}

typedef HRESULT(STDAPICALLTYPE* ClassObjectFn)(REFCLSID, REFIID, void**);
typedef HRESULT(STDAPICALLTYPE* NoArgumentFn)(void);

HRESULT STDAPICALLTYPE DllGetClassObject(REFCLSID clsid, REFIID iid, void** out) {
  ClassObjectFn fn = (ClassObjectFn)target_proc("DllGetClassObject");
  if (!fn) {
    if (out) *out = NULL;
    return CLASS_E_CLASSNOTAVAILABLE;
  }
  return fn(clsid, iid, out);
}

// The target stays loaded for the life of the process, so this module never needs to
// be unloaded either.
HRESULT STDAPICALLTYPE DllCanUnloadNow(void) { return S_FALSE; }

HRESULT STDAPICALLTYPE DllRegisterServer(void) {
  NoArgumentFn fn = (NoArgumentFn)target_proc("DllRegisterServer");
  return fn ? fn() : SELFREG_E_CLASS;
}

HRESULT STDAPICALLTYPE DllUnregisterServer(void) {
  NoArgumentFn fn = (NoArgumentFn)target_proc("DllUnregisterServer");
  return fn ? fn() : SELFREG_E_CLASS;
}
