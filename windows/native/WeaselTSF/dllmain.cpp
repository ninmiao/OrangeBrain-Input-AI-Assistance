// dllmain.cpp : Defines the entry point for the DLL application.
#include "stdafx.h"
#include "Globals.h"
#include <stdio.h>
#include <Windows.h>
#include <DbgHelp.h>
#include <tchar.h>
#include <time.h>
#pragma comment(lib, "DbgHelp.lib")

BOOL WINAPI DllMain(HINSTANCE hInstance, DWORD dwReason, LPVOID pvReserved) {
  switch (dwReason) {
    case DLL_PROCESS_ATTACH:
      g_hInst = hInstance;
      if (!InitializeCriticalSectionAndSpinCount(&g_cs, 0))
        return FALSE;
      break;
    case DLL_PROCESS_DETACH:
      DeleteCriticalSection(&g_cs);
      break;
  }
  return TRUE;
}
