// Shared bounded SSE decoder. Raw pending bytes are hex encoded across JNI calls
// so a network chunk may end inside a UTF-8 codepoint without corrupting state.
std::string streamHex(const std::string& s) {
  static const char* digits = "0123456789abcdef";
  std::string out;
  for (unsigned char c : s) { out += digits[c >> 4]; out += digits[c & 15]; }
  return out;
}
std::string streamBytes(const std::string& s) {
  check(s.size() % 2 == 0 && s.size() <= 2097152, "response");
  auto digit = [](char c) { return c >= '0' && c <= '9' ? c-'0' : c >= 'a' && c <= 'f' ? c-'a'+10 : -1; };
  std::string out;
  for (size_t i=0;i<s.size();i+=2) {
    int a=digit(s[i]), b=digit(s[i+1]); check(a>=0 && b>=0,"response");
    out += char((a<<4)|b);
  }
  return out;
}
J streamDecode(const J& a) {
  J s=a.value("state", J::object());
  auto endpoint=a.value("endpoint",std::string());
  bool finish=a.value("finish",false), roles=a.value("assistantEnabled",false);
  auto chunk=streamBytes(a.value("chunkHex",std::string()));
  int total=s.value("total",0)+int(chunk.size());
  check(total <= 1048576,"response"); s["total"]=total;
  std::string pending=streamBytes(s.value("pending",std::string()))+chunk;
  std::string text=s.value("text",std::string()), data=s.value("data",std::string());
  bool done=s.value("done",false), cut=s.value("cut",false);
  std::string error=s.value("error",std::string());
  auto event=[&] {
    if(data.empty() || done) { data.clear(); return; }
    if(trim(data)=="[DONE]") { done=true; data.clear(); return; }
    J e;
    try {e=parseBounded(data);}catch(...) {data.clear();error="response";done=true;return;}
    data.clear();
    if(e.contains("error") && !e["error"].is_null()) {error="provider";done=true;return;}
    auto type=e.value("type",e.value("event_type",std::string()));
    if(type=="error" || type=="response.failed") {error="provider";done=true;return;}
    if(api(endpoint)=="gemini") {
      auto index=std::to_string(e.value("index",-1));
      if(type=="step.start") {
        const auto& step = e.at("step");
        auto kind = step.value("type", std::string());
        s["steps"][index] = kind;
        if (kind == "model_output") {
          for (const auto& block : step.value("content", J::array()))
            if (block.value("type", std::string()) == "text")
              text += block.value("text", std::string());
        }
      }
      if(type=="step.delta" && s.value("steps",J::object()).value(index,std::string())=="model_output") {
        auto d=e.at("delta");
        if(d.value("type",std::string())=="text") text+=d.value("text",std::string());
      }
      if(type=="interaction.completed") {
        auto i=e.at("interaction"); s["usage"]=i.value("usage",J::object());
        cut=i.value("status",std::string())=="incomplete"; done=true;
      }
    } else if(responses(endpoint)) {
      if(type=="response.output_text.delta") text+=e.at("delta").get<std::string>();
      if(type=="response.completed" || type=="response.incomplete") {
        s["usage"]=e.at("response").value("usage",J::object());
        cut=type=="response.incomplete";done=true;
      }
    } else {
      if(e.contains("usage") && e["usage"].is_object()) s["usage"]=e["usage"];
      for(auto& c:e.value("choices",J::array())) {
        if(c.value("index",0)!=0) continue;
        auto d=c.value("delta",J::object());
        if(d.contains("content") && d["content"].is_string()) text+=d["content"].get<std::string>();
        auto f=c.contains("finish_reason") && c["finish_reason"].is_string() ? c["finish_reason"].get<std::string>() : "";
        if(f=="length") cut=true;
        if(f=="error" || f=="content_filter") {error="provider";done=true;}
      }
    }
    check(text.size()<=32768,"response");
  };
  // Compatible gateways may ignore stream=true and return a normal envelope.
  auto first=pending.find_first_not_of(" \r\n\t");
  if(!s.contains("mode") && first!=pending.npos) s["mode"]=pending[first]=='{' ? "json" : "sse";
  J result=s.value("result",J());
  if(s.value("mode",std::string())=="json") {
    check(pending.size()<=65536,"response");
    if(finish) { result=envelope({{"endpoint",endpoint},{"body",pending},{"assistantEnabled",roles}});done=true;pending.clear(); }
  } else {
    size_t p;
    while((p=pending.find('\n'))!=pending.npos) {
      auto line=pending.substr(0,p); pending.erase(0,p+1);
      if(!line.empty() && line.back()=='\r') line.pop_back();
      if(line.empty()) event();
      else if(starts(line,"data:")) { auto v=line.substr(5);if(starts(v," "))v.erase(0,1); if(!data.empty()) data+='\n';data+=v; }
      check(data.size()<=262144,"response");
    }
    check(pending.size()<=262144,"response");
    if(finish && !data.empty()) event();
    auto partial=trim(text);
    if(roles && starts(partial,"```")) {
      auto n=partial.find('\n');
      if(n!=partial.npos && (partial.substr(0,n)=="```json" || partial.substr(0,n)=="```" || partial.substr(0,n)=="```json\r" || partial.substr(0,n)=="```\r")) {
        partial=trim(partial.substr(n+1));
        auto fence=partial.rfind("\n`");
        if(fence!=partial.npos && partial.find_first_not_of('`',fence+1)==partial.npos)
          partial=trim(partial.substr(0,fence));
      }
    }
    try { result=decode((finish||done)&&!cut&&error.empty()?text:partial,!(finish||done)||cut||!error.empty(),roles); }
    catch(const Failure&) {
      if((finish||done) && error.empty()) error=cut ? "truncated" : "response";
    }
    if(finish && !done) { cut=true;if(error.empty())error="truncated"; }
    if(result.is_object() && (finish||done) && s.contains("usage")) {
      // Reuse the existing usage normalization, independently of wire protocol.
      J e={{"usage",s["usage"]}};
      auto safe=result["candidates"].dump();
      if(api(endpoint)=="gemini") e["steps"]=J::array({J{{"type","model_output"},{"content",J::array({J{{"type","text"},{"text",safe}}})}}});
      else if(responses(endpoint)) e["output"]=J::array({J{{"type","message"},{"content",J::array({J{{"type","output_text"},{"text",safe}}})}}});
      else e["choices"]=J::array({J{{"message",{{"content",safe}}}}});
      result["usage"]=envelope({{"endpoint",endpoint},{"envelope",e},{"assistantEnabled",roles}})["usage"];
    }
  }
  if(result.is_object()) {
    auto& candidates = result.at("candidates");
    const size_t slots = roles ? 2 : 1;
    if (candidates.size() > slots) candidates.erase(candidates.begin() + slots, candidates.end());
    result["streaming"]=!finish&&!done;
    if(!error.empty() || ((done||finish) && cut)) {
      result["streamError"]=error.empty() ? "truncated" : error;
      result["recovered"]=true;
    }
  } else if(finish||done) throw Failure(error.empty()?"response":error.c_str());
  s["pending"]=streamHex(pending);s["text"]=text;s["data"]=data;s["done"]=done;
  s["cut"]=cut;s["error"]=error;s["result"]=result;
  return {{"state",s},{"result",result},{"done",done}};
}
