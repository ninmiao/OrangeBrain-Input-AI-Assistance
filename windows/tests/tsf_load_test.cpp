#define UNICODE
#define _UNICODE
#include <windows.h>
#include <msctf.h>
#include <iostream>
#include <string>

// --registered exercises OS-managed activation in THIS process. A fabricated
// client ID cannot activate a foreground key sink for an unregistered TIP.
int wmain(int argc,wchar_t** argv) {
  if(argc<2)return 2;
  HRESULT hr=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);if(FAILED(hr))return 3;
  HMODULE module=LoadLibraryW(argv[1]);if(!module){std::cerr<<"LoadLibrary: "<<GetLastError()<<"\n";return 4;}
  using Factory=HRESULT(STDAPICALLTYPE*)(REFCLSID,REFIID,void**);
  auto factory=reinterpret_cast<Factory>(GetProcAddress(module,"DllGetClassObject"));
  CLSID clsid={0x652d71c8,0xb1e9,0x41ee,{0x9c,0xa6,0x7b,0x4d,0x0d,0xe6,0xcb,0x0a}};
  GUID profile={0x91ebc2a4,0x2b8e,0x4781,{0xba,0x20,0x1c,0x92,0x67,0x52,0x94,0x67}};
  IClassFactory* creator=nullptr;ITfTextInputProcessorEx* service=nullptr;
  if(!factory||FAILED(factory(clsid,IID_IClassFactory,reinterpret_cast<void**>(&creator))))return 5;
  // Report which module really serves the class. Through the ARM64X forwarder this is
  // the ARM64 module in an ARM64 process and the x64 module in an x64 process.
  HMODULE owner=nullptr;wchar_t ownerPath[MAX_PATH]{};
  if(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                        reinterpret_cast<LPCWSTR>(factory),&owner)&&GetModuleFileNameW(owner,ownerPath,MAX_PATH))
    std::wcout<<L"Class served by: "<<ownerPath<<L"\n";
  hr=creator->CreateInstance(nullptr,IID_ITfTextInputProcessorEx,reinterpret_cast<void**>(&service));creator->Release();if(FAILED(hr))return 6;
  ITfKeyEventSink* sink=nullptr;hr=service->QueryInterface(IID_ITfKeyEventSink,reinterpret_cast<void**>(&sink));if(FAILED(hr))return 7;
  sink->Release();service->Release();
  if(argc>2&&std::wstring(argv[2])==L"--registered") {
    ITfThreadMgr* manager=nullptr;ITfInputProcessorProfileMgr* profiles=nullptr;
    hr=CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_ITfThreadMgr,reinterpret_cast<void**>(&manager));if(FAILED(hr))return 8;
    TfClientId id;hr=manager->Activate(&id);if(FAILED(hr))return 9;
    hr=CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_ITfInputProcessorProfileMgr,reinterpret_cast<void**>(&profiles));if(FAILED(hr))return 10;
    TF_INPUTPROCESSORPROFILE previous{},active{};bool restore=SUCCEEDED(profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD,&previous));
    hr=profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,0x0804,clsid,profile,nullptr,TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE|TF_IPPMF_FORPROCESS);
    if(FAILED(hr)){std::cerr<<"OS ActivateProfile: "<<std::hex<<hr<<"\n";return 11;}
    hr=profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD,&active);
    bool correct=SUCCEEDED(hr)&&IsEqualGUID(active.clsid,clsid)&&IsEqualGUID(active.guidProfile,profile);
    ITfKeystrokeMgr* keystrokes=nullptr;
    bool shortcuts=SUCCEEDED(manager->QueryInterface(IID_ITfKeystrokeMgr,reinterpret_cast<void**>(&keystrokes)));
    if(keystrokes) {
      for(UINT slot=0;slot<5;++slot) {
        GUID command={0x7f26d4b0+slot,0x317c,0x47ed,{0xb9,0x56,0x18,0xcf,0x44,0x90,0xac,0x10}};
        TF_PRESERVEDKEY key{'1'+slot,TF_MOD_ALT};BOOL registered=FALSE;
        shortcuts=SUCCEEDED(keystrokes->IsPreservedKey(command,&key,&registered))&&registered&&shortcuts;
      }
      keystrokes->Release();
    }
    if(!shortcuts)std::cerr<<"Candidate shortcut registration failed\n";
    correct=correct&&shortcuts;
    if(restore)profiles->ActivateProfile(previous.dwProfileType,previous.langid,previous.clsid,previous.guidProfile,previous.hkl,TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE|TF_IPPMF_FORPROCESS);
    profiles->Release();manager->Deactivate();manager->Release();if(!correct)return 12;
    std::cout<<"OS-managed TSF profile activation / 5 candidate shortcuts passed ("<<sizeof(void*)*8<<" bit)\n";
  } else std::cout<<"TSF DLL load / COM factory / key-sink interface passed ("<<sizeof(void*)*8<<" bit); system activation not requested\n";
  FreeLibrary(module);CoUninitialize();return 0;
}
