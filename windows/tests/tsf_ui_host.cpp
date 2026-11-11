#define UNICODE
#define _UNICODE
#include <windows.h>
#include <msctf.h>
#include <richedit.h>
#include <cwchar>

// A real TSF-aware Win32/RichEdit UI fixture. Keyboard input comes from a person
// or the approved Computer Use tool, never SendInput in this test program.
ITfThreadMgr* manager=nullptr;ITfKeystrokeMgr* keys=nullptr;ITfInputProcessorProfileMgr* profiles=nullptr;ITfMessagePump* pump=nullptr;
HFONT font;HWND first,second,password,status;
LRESULT CALLBACK proc(HWND window,UINT msg,WPARAM w,LPARAM l) {
  if(msg==WM_CREATE) {
    font=CreateFontW(-20,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Microsoft YaHei UI");
    auto make=[&](LPCWSTR cls,LPCWSTR text,DWORD style,int x,int y,int width,int height,int id) {
      HWND c=CreateWindowExW(0,cls,text,WS_CHILD|WS_VISIBLE|style,x,y,width,height,window,(HMENU)(INT_PTR)id,GetModuleHandle(nullptr),nullptr);
      SendMessage(c,WM_SETFONT,(WPARAM)font,TRUE);return c;
    };
    make(L"STATIC",L"Zephyr Input: real TSF / Win32 Edit / RichEdit integration",0,20,15,820,30,0);
    make(L"STATIC",L"A: Win32 Edit — pending input stays in the candidate panel",0,20,60,820,30,0);
    first=make(L"EDIT",L"",WS_BORDER|WS_TABSTOP|ES_MULTILINE|ES_AUTOVSCROLL,20,95,820,125,101);
    make(L"STATIC",L"B: RichEdit — use to check focus changes",0,20,235,820,30,0);
    second=make(MSFTEDIT_CLASS,L"",WS_BORDER|WS_TABSTOP|ES_MULTILINE|ES_AUTOVSCROLL,20,270,820,110,102);
    make(L"STATIC",L"C: Password — type only synthetic test data",0,20,395,820,30,0);
    password=make(L"EDIT",L"",WS_BORDER|WS_TABSTOP|ES_PASSWORD,20,430,820,40,103);
    status=make(L"STATIC",L"Initializing TSF…",0,20,490,820,35,0);return 0;
  }
  if(msg==WM_DESTROY){PostQuitMessage(0);return 0;}
  return DefWindowProc(window,msg,w,l);
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,LPWSTR,int) {
  CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);LoadLibraryW(L"Msftedit.dll");
  WNDCLASSW wc{};wc.hInstance=instance;wc.lpfnWndProc=proc;wc.lpszClassName=L"ZephyrTsfTestHost";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);wc.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);RegisterClassW(&wc);
  HWND window=CreateWindowExW(0,wc.lpszClassName,L"Zephyr TSF Test Host",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,885,585,nullptr,nullptr,instance,nullptr);
  HRESULT hr=CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_ITfThreadMgr,(void**)&manager);TfClientId client=TF_CLIENTID_NULL;
  if(SUCCEEDED(hr))hr=manager->Activate(&client);
  if(SUCCEEDED(hr))hr=manager->QueryInterface(IID_ITfKeystrokeMgr,(void**)&keys);
  if(SUCCEEDED(hr))hr=manager->QueryInterface(IID_ITfMessagePump,(void**)&pump);
  if(SUCCEEDED(hr))hr=CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_ITfInputProcessorProfileMgr,(void**)&profiles);
  CLSID clsid={0x652d71c8,0xb1e9,0x41ee,{0x9c,0xa6,0x7b,0x4d,0x0d,0xe6,0xcb,0x0a}};
  GUID profile={0x91ebc2a4,0x2b8e,0x4781,{0xba,0x20,0x1c,0x92,0x67,0x52,0x94,0x67}};
  if(SUCCEEDED(hr))hr=profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,0x0804,clsid,profile,nullptr,TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE|TF_IPPMF_FORPROCESS);
  wchar_t message[128];swprintf_s(message,L"TSF profile activation: 0x%08lx · Tap Shift changes language (default)",hr);SetWindowTextW(status,message);
  ShowWindow(window,SW_SHOW);UpdateWindow(window);SetFocus(first);
  MSG msg;BOOL more=TRUE;
  while(pump&&SUCCEEDED(pump->GetMessageW(&msg,nullptr,0,0,&more))&&more) {
    BOOL eaten=FALSE;
    if(keys&&(msg.message==WM_KEYDOWN||msg.message==WM_KEYUP||msg.message==WM_SYSKEYDOWN||msg.message==WM_SYSKEYUP)) {
      bool down=msg.message==WM_KEYDOWN||msg.message==WM_SYSKEYDOWN;
      if(down)keys->TestKeyDown(msg.wParam,msg.lParam,&eaten);else keys->TestKeyUp(msg.wParam,msg.lParam,&eaten);
      if(eaten){if(down)keys->KeyDown(msg.wParam,msg.lParam,&eaten);else keys->KeyUp(msg.wParam,msg.lParam,&eaten);}
    }
    if(!eaten){TranslateMessage(&msg);DispatchMessage(&msg);}
  }
  if(pump)pump->Release();if(profiles)profiles->Release();if(keys)keys->Release();if(manager){manager->Deactivate();manager->Release();}DeleteObject(font);CoUninitialize();return 0;
}
