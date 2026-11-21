// SPDX-License-Identifier: GPL-3.0-or-later
// Headless, per-user data deployment. No COM registration and no administrator rights.
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <rime_api.h>
#include <rime_levers_api.h>
#include <string>
#include <vector>
#include <algorithm>
#include <filesystem>

static std::string utf8(const wchar_t* s) {
  int n=WideCharToMultiByte(CP_UTF8,0,s,-1,nullptr,0,nullptr,nullptr);
  std::string out(n,0);WideCharToMultiByte(CP_UTF8,0,s,-1,out.data(),n,nullptr,nullptr);out.pop_back();return out;
}
int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int) {
  int argc=0;wchar_t** argv=CommandLineToArgvW(GetCommandLineW(),&argc);
  if(argc!=5){LocalFree(argv);return 2;}
  std::wstring dll=argv[1];std::string shared=utf8(argv[2]),user=utf8(argv[3]),schema=utf8(argv[4]);LocalFree(argv);
  if(schema!="orangecell_wanxiang" && schema!="rime_ai_simp")return 3;
  HANDLE mutex=CreateMutexW(nullptr,TRUE,L"WeaselDeployerMutex");
  if(!mutex || GetLastError()==ERROR_ALREADY_EXISTS){if(mutex)CloseHandle(mutex);return 4;}
  HMODULE library=LoadLibraryExW(dll.c_str(),nullptr,LOAD_WITH_ALTERED_SEARCH_PATH);
  if(!library)return 5;
  auto entry=reinterpret_cast<RimeApi*(*)()>(GetProcAddress(library,"rime_get_api"));if(!entry)return 6;
  auto api=entry();int result=0;
  const char* modules[]={"default","deployer","lua","octagram",nullptr};
  RIME_STRUCT(RimeTraits,t);t.shared_data_dir=shared.c_str();t.user_data_dir=user.c_str();
  const std::string staging=user+"/build", logs=user+"/.orangecell-wanxiang";
  std::filesystem::create_directories(std::filesystem::u8path(staging));
  std::filesystem::create_directories(std::filesystem::u8path(logs));
  t.prebuilt_data_dir=shared.c_str();t.staging_dir=staging.c_str();
  t.app_name="rime.orangecell-data";t.distribution_name="OrangeCell";t.modules=modules;t.min_log_level=2;t.log_dir=logs.c_str();
  api->setup(&t);api->initialize(&t);api->deployer_initialize(&t);
  auto module=api->find_module("levers");
  if(!module)result=7;
  if(!result) {
    auto levers=reinterpret_cast<RimeLeversApi*>(module->get_api());
    auto switcher=levers->switcher_settings_init();auto settings=reinterpret_cast<RimeCustomSettings*>(switcher);
    levers->load_settings(settings);
    RimeSchemaList list{};std::vector<std::string> selected{schema};
    if(levers->get_selected_schema_list(switcher,&list)) {
      for(size_t i=0;i<list.size;i++) {
        if(!list.list[i].schema_id || selected.front()==list.list[i].schema_id)continue;
        const std::string id=list.list[i].schema_id;
        // Rollback before first installation may remove our unpublished schema.
        if(id=="orangecell_wanxiang" && !std::filesystem::exists(std::filesystem::u8path(user+"/"+id+".schema.yaml")))continue;
        selected.push_back(id);
      }
      levers->schema_list_destroy(&list);
    }
    if(std::find(selected.begin(),selected.end(),"rime_ai_simp")==selected.end())selected.emplace_back("rime_ai_simp");
    std::vector<const char*> ids;for(auto& item:selected)ids.push_back(item.c_str());
    if(!levers->select_schemas(switcher,ids.data(),int(ids.size())) ||
       (levers->settings_is_modified(settings) && !levers->save_settings(settings)))result=8;
    levers->custom_settings_destroy(settings);
  }
  if(!result && !api->deploy())result=9;
  if(!result) {
    const auto local=user+"/"+schema+".schema.yaml";
    const auto source=std::filesystem::exists(std::filesystem::u8path(local))?local:shared+"/"+schema+".schema.yaml";
    if(!api->deploy_schema(source.c_str()))result=13;
  }
  if(!result) {
    // SwitcherSettings may cache the pre-deployment configuration. Reload after compiling.
    api->finalize();api->initialize(&t);
    // Require the requested dictionary to produce a real candidate, not just a schema ID.
    auto session=api->create_session();
    if(!session || !api->select_schema(session,schema.c_str()))result=10;
    else {
      api->set_option(session,"ascii_mode",false);
      for(char c:std::string("nihao"))api->process_key(session,c,0);
      RIME_STRUCT(RimeContext,c);
      if(!api->get_context(session,&c))result=11;
      else {if(c.menu.num_candidates==0)result=12;api->free_context(&c);}
      api->clear_composition(session);
    }
    if(session)api->destroy_session(session);
  }
  api->finalize();FreeLibrary(library);ReleaseMutex(mutex);CloseHandle(mutex);return result;
}
