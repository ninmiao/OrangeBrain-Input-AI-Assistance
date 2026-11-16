// SPDX-License-Identifier: GPL-3.0-or-later
// Isolated feasibility probe; see docs/research/wanxiang-assessment.md.
#define NOMINMAX
#include <windows.h>
#include <psapi.h>
#include <rime_api.h>
#include <chrono>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>

using Clock = std::chrono::steady_clock;
double ms(Clock::time_point t) { return std::chrono::duration<double,std::milli>(Clock::now()-t).count(); }
std::string clean(const char* p) {std::string s=p?p:"";for(char& c:s)if(c=='\t'||c=='\n'||c=='\r')c=' ';return s;}
std::vector<std::string> candidates(RimeApi* api,RimeSessionId session,std::string* pre=nullptr) {
  RIME_STRUCT(RimeContext,c);std::vector<std::string> result;
  if(api->get_context(session,&c)) {
    if(pre)*pre=clean(c.composition.preedit);
    for(int i=0;i<c.menu.num_candidates;++i)result.push_back(clean(c.menu.candidates[i].text));
    api->free_context(&c);
  } return result;
}
int main(int argc,char** argv) {
 if(argc<5)return 2;
 const std::string root=argv[1], dll=argv[2], schema=argv[3], mode=argv[4];
 HMODULE module=LoadLibraryA(dll.c_str());if(!module){std::cerr<<"Load DLL failed: "<<GetLastError();return 3;}
 auto api=((RimeApi*(*)())GetProcAddress(module,"rime_get_api"))();
 const std::string data=root+"/data", user=root+"/user",logs=root+"/logs";
 const char* modules[]={"default","deployer","lua","octagram",nullptr};
 RIME_STRUCT(RimeTraits,t);t.shared_data_dir=data.c_str();t.user_data_dir=user.c_str();
 t.app_name="rime.zephyr-wanxiang-study";t.distribution_name="Zephyr study";
 t.modules=modules;t.min_log_level=0;t.log_dir=logs.c_str();
 api->setup(&t);api->initialize(&t);
 std::cout<<"version="<<api->get_version()<<" grammar_module="<<(api->find_module("grammar")!=nullptr)<<" lua_module="<<(api->find_module("lua")!=nullptr)<<std::endl;
 if(mode=="deploy") {
   api->deployer_initialize(&t);
   api->deploy_config_file("default.yaml","config_version");
   auto start=Clock::now();bool ok=api->deploy_schema((data+"/"+schema+".schema.yaml").c_str());
   std::cout<<"deployed="<<ok<<" ms="<<ms(start)<<std::endl;api->finalize();return ok?0:4;
 }
 auto start=Clock::now();auto session=api->create_session();
 if(!session||!api->select_schema(session,schema.c_str())){std::cerr<<"Select schema failed";api->finalize();return 5;}
 std::cout<<"session_ready_ms="<<ms(start)<<std::endl;
 api->set_option(session,"ascii_mode",false);
 std::ifstream in(root+"/cases.tsv");std::ofstream out(root+"/"+schema+"-results.tsv");std::string line;
 std::vector<double> all;
 while(std::getline(in,line)) {
   auto first=line.find('\t'),second=line.find('\t',first+1);auto raw=line.substr(first+1,second-first-1);
   api->clear_composition(session);std::vector<double> times;std::vector<std::string> words;
   for(size_t n=1;n<=raw.size();++n) {
     // Existing regression data includes literal Chinese: never split UTF-8 codepoints.
     if(n<raw.size() && (static_cast<unsigned char>(raw[n])&0xc0)==0x80)continue;
     start=Clock::now();api->set_input(session,raw.substr(0,n).c_str());words=candidates(api,session);double elapsed=ms(start);times.push_back(elapsed);all.push_back(elapsed);
   }
   out<<line<<'\t'<<times.back()<<'\t'<<*std::max_element(times.begin(),times.end());for(auto& w:words)out<<'\t'<<w;out<<'\n';out.flush();
 }
 // Reproduce Zephyr's native selection API and subsequent refresh with identical raw input.
 api->clear_composition(session);const char* raw="xianzaishurufahouxuanyouwenti";api->set_input(session,raw);
 auto before=candidates(api,session);auto found=std::find(before.begin(),before.end(),"现在");
 bool partial=false,committed=false;std::string pre;
 if(found!=before.end()) {
   partial=api->select_candidate(session,size_t(found-before.begin()));
   RIME_STRUCT(RimeCommit,c);committed=api->get_commit(session,&c);if(committed)api->free_commit(&c);
   api->set_input(session,raw);auto after=candidates(api,session,&pre);
   out<<"PARTIAL\t"<<partial<<'\t'<<committed<<'\t'<<clean(api->get_input(session))<<'\t'<<pre;for(auto& w:after)out<<'\t'<<w;out<<'\n';
 }else out<<"PARTIAL\tNOT_FOUND\n";
 api->clear_composition(session);api->set_option(session,"traditionalization",true);api->set_input(session,"ruanjian");auto trad=candidates(api,session);out<<"TRADITIONAL";for(auto& w:trad)out<<'\t'<<w;out<<'\n';
 std::sort(all.begin(),all.end());PROCESS_MEMORY_COUNTERS memory{};GetProcessMemoryInfo(GetCurrentProcess(),&memory,sizeof(memory));
 std::cout<<"keystrokes="<<all.size()<<" p50_ms="<<all[all.size()/2]<<" p95_ms="<<all[all.size()*95/100]<<" max_ms="<<all.back()<<" working_mib="<<memory.WorkingSetSize/1048576.0<<" peak_mib="<<memory.PeakWorkingSetSize/1048576.0<<" partial="<<partial<<" premature_commit="<<committed<<std::endl;
 std::ofstream perf(root+"/"+schema+"-performance.json");
 perf<<"{\"prefix_states\":"<<all.size()<<",\"p50_ms\":"<<all[all.size()/2]<<",\"p95_ms\":"<<all[all.size()*95/100]<<",\"max_ms\":"<<all.back()<<",\"working_mib\":"<<memory.WorkingSetSize/1048576.0<<",\"peak_mib\":"<<memory.PeakWorkingSetSize/1048576.0<<"}\n";
 api->destroy_session(session);api->finalize();return 0;
}
