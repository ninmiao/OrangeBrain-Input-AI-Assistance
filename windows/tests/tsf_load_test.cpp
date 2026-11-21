#define UNICODE
#define _UNICODE
#include <windows.h>
#include <msctf.h>
#include <tlhelp32.h>
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
  CLSID clsid={0x7a61ac12,0xaf2d,0x4810,{0x89,0x5e,0x09,0xdb,0x95,0xc0,0xd3,0xb2}};
  GUID profile={0xc6be1eb4,0x0700,0x4ace,{0xb9,0x86,0xd1,0x49,0xc5,0x38,0x5e,0xcb}};
  IClassFactory* creator=nullptr;ITfTextInputProcessorEx* service=nullptr;
  if(!factory){std::cerr<<"GetProcAddress(DllGetClassObject): "<<GetLastError()<<"\n";return 5;}
  hr=factory(clsid,IID_IClassFactory,reinterpret_cast<void**>(&creator));
  if(FAILED(hr)){std::cerr<<"DllGetClassObject: "<<std::hex<<hr<<std::dec<<"\n";return 5;}
  // List the OrangeCell modules this process loaded. Through the ARM64X loader an ARM64
  // process gets the ARM64 module and an x64 process the x64 module.
  if(HANDLE snapshot=CreateToolhelp32Snapshot(TH32CS_SNAPMODULE,0);snapshot!=INVALID_HANDLE_VALUE) {
    MODULEENTRY32W entry{sizeof(entry)};
    for(BOOL more=Module32FirstW(snapshot,&entry);more;more=Module32NextW(snapshot,&entry))
      if(_wcsnicmp(entry.szModule,L"OrangeCellTSF",9)==0||_wcsnicmp(entry.szModule,L"weasel",6)==0)
        std::wcout<<L"Loaded module: "<<entry.szExePath<<L"\n";
    CloseHandle(snapshot);
  }
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
