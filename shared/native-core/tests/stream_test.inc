// Assistant mode keeps two candidates unless the request asks for more slots (emoticon requests).
{
  auto invoke=[](const J& args) {auto r=J::parse(orangecell::invoke(J{{"op","stream"},{"args",args}}.dump()));if(r.contains("error"))throw std::runtime_error(r.dump());return r.at("ok");};
  auto hex=[](const std::string& v) {std::string h;for(unsigned char c:v){h+="0123456789abcdef"[c>>4];h+="0123456789abcdef"[c&15];}return h;};
  const std::string endpoint="https://openrouter.ai/api/v1/chat/completions";
  const std::string body=std::string("data: ")+J{{"choices",J::array({J{{"index",0},{"delta",{{"content","[\"a\",\"b\",\"c\",\"d\",\"e\"]"}}}}})}}.dump()+"\r\n\r\n";
  auto five=invoke({{"endpoint",endpoint},{"assistantEnabled",true},{"slots",5},{"chunkHex",hex(body)}});
  five=invoke({{"endpoint",endpoint},{"assistantEnabled",true},{"slots",5},{"state",five["state"]},{"finish",true}});
  if(five["result"]["candidates"].size()!=5)throw std::runtime_error("emoticon request must keep five candidates");
  auto two=invoke({{"endpoint",endpoint},{"assistantEnabled",true},{"chunkHex",hex(body)}});
  two=invoke({{"endpoint",endpoint},{"assistantEnabled",true},{"state",two["state"]},{"finish",true}});
  if(two["result"]["candidates"].size()!=2)throw std::runtime_error("assistant mode keeps correction and assistant only");
}
// All split points include UTF-8 bytes, SSE CRLF, JSON escapes and role order.
{
  auto invoke=[](const J& args) {auto r=J::parse(orangecell::invoke(J{{"op","stream"},{"args",args}}.dump()));if(r.contains("error"))throw std::runtime_error(r.dump());return r.at("ok");};
  auto hex=[](const std::string& v) {std::string h;for(unsigned char c:v){h+="0123456789abcdef"[c>>4];h+="0123456789abcdef"[c&15];}return h;};
  auto event=[](const J& e){return "data: "+e.dump()+"\r\n\r\n";};
  for(const auto& endpoint: {"https://api.openai.com/v1/responses","https://openrouter.ai/api/v1/chat/completions","https://generativelanguage.googleapis.com/v1beta/interactions"}) {
    bool gemini=std::string(endpoint).find("google")!=std::string::npos, openai=std::string(endpoint).find("api.openai")!=std::string::npos;
    auto delta=[&](const std::string& text) {
      return event(gemini?J{{"event_type","step.delta"},{"index",1},{"delta",{{"type","text"},{"text",text}}}}:
        openai?J{{"type","response.output_text.delta"},{"delta",text}}:
        J{{"choices",J::array({J{{"index",0},{"delta",{{"content",text}}}}})}});
    };
    std::string begin=": heartbeat\r\n\r\n";
    if(gemini) {
      begin+=event({{"event_type","step.start"},{"index",0},{"step",{{"type","thought"}}}});
      begin+=event({{"event_type","step.delta"},{"index",0},{"delta",{{"type","text"},{"text","secret"}}}});
      begin+=event({{"event_type","step.start"},{"index",1},
                    {"step",{{"type","model_output"},{"content",{{{"type","text"},{"text","["}}}}}}});
    } else if(openai)begin+=event({{"type","response.reasoning_summary_text.delta"},{"delta","secret"}});
    else begin+=event({{"choices",J::array({J{{"delta",{{"reasoning","secret"}}}}})}});
    auto first=begin+delta(gemini ? u8"\"你好🍜\"" : u8"[\"你好🍜\"");
    auto second=delta(",\"say \\\"hi\\\" \\ud83d\\ude00\"]");
    auto end=gemini?event({{"event_type","interaction.completed"},{"interaction",{{"status","completed"},{"usage",{{"total_input_tokens",12},{"total_output_tokens",8}}}}}}):
      openai?event({{"type","response.completed"},{"response",{{"usage",{{"input_tokens",12},{"output_tokens",8}}}}}}):
      event({{"choices",J::array()},{"usage",{{"prompt_tokens",12},{"completion_tokens",8}}}})+"data: [DONE]\n\n";
    for(size_t split=0;split<=first.size();++split) {
      J args={{"endpoint",endpoint},{"assistantEnabled",true},{"chunkHex",hex(first.substr(0,split))}};
      auto r=invoke(args);args["state"]=r["state"];args["chunkHex"]=hex(first.substr(split));r=invoke(args);
      if(r["result"]["candidates"]!=J::array({u8"你好🍜"})||r["result"]["streaming"]!=true)throw std::runtime_error("first not early");
      args["state"]=r["state"];args["chunkHex"]=hex(second+end);r=invoke(args);
      if(r["result"]["candidates"]!=J::array({u8"你好🍜",u8"say \"hi\" 😀"}) || r["result"]["streaming"]!=false || r["result"]["usage"]["input"]!=12)throw std::runtime_error("stream roles or usage");
      ++count;
    }
    // Complete correction survives 12 different truncated assistant tails.
    for(const std::string& tail:{"",",",",\"",",\"word",",\"\\",",\"\\u",",\"\\u4",",\"\\u4f",",\"\\uD83D",",\"\\uD83D\\u",",\"x\\\"",",\"word \\"}) {
      auto r=invoke({{"endpoint",endpoint},{"assistantEnabled",true},{"chunkHex",hex(first+delta(tail))}});
      r=invoke({{"endpoint",endpoint},{"assistantEnabled",true},{"state",r["state"]},{"finish",true}});
      if(r["result"]["candidates"]!=J::array({u8"你好🍜"}) || r["result"]["streaming"]!=false)throw std::runtime_error("truncation lost correction");++count;
    }
    auto r=invoke({{"endpoint",endpoint},{"assistantEnabled",true},{"chunkHex",hex(first+event({{"error",{{"message","secret"}}}}))}});
    if(r["result"]["candidates"]!=J::array({u8"你好🍜"}) || r["result"]["streamError"]!="provider")throw std::runtime_error("provider error lost correction");++count;
    if (gemini) {
      auto noOutput = J::parse(orangecell::invoke(J{{"op","stream"},{"args",{
          {"endpoint",endpoint},{"chunkHex",hex(event({{"event_type","interaction.completed"},
              {"interaction",{{"status","incomplete"}}}}))}}}}.dump()));
      if (noOutput.value("error", "") != "truncated")
        throw std::runtime_error("Gemini token exhaustion reported as invalid format");
      ++count;
    }
  }
}
