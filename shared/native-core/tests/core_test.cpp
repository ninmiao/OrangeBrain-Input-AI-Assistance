#include "core.h"

#include <fstream>
#include <iostream>
#include <nlohmann/json.hpp>
#include <stdexcept>
using J = nlohmann::ordered_json;
int main() {
  try {
    int count = 0;
#include "stream_test.inc"
    {
      auto call = [](const char* op, const J& args) {
        return J::parse(orangecell::invoke(J{{"op", op}, {"args", args}}.dump())).at("ok");
      };
      const std::string endpoint = "https://generativelanguage.googleapis.com/v1beta/interactions";
      auto row = [](const char* id, bool thinking) {
        return J{{"name", id}, {"thinking", thinking},
                 {"supportedGenerationMethods", {"generateContent"}}};
      };
      auto models = call("modelsReasoning", {{"gemini", true},
          {"models", {row("models/gemini-4-hydrogen", false),
                      row("models/gemini-3.8-flash", true),
                      row("models/gemini-unknown", true)}}});
      J catalog = {{"version", "models-gemini"}, {"models", models}};
      auto definition = [&](const char* id) {
        return call("modelDefinition", {{"endpoint", endpoint}, {"model", id},
                                        {"catalog", catalog}});
      };
      if (definition("gemini-4-hydrogen").at("parameters").size() != 1 ||
          definition("gemini-3.8-flash").at("parameters").at(1).at("choices").size() != 3 ||
          !definition("gemini-unknown").is_null())
        throw std::runtime_error("Gemini discovery reasoning mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\"", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"未完成", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\u4", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\uD83D", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\uD83D\\u", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"x\\\"", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"hello\\nworld\"", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["hello\nworld"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"he\\\"llo\", \"wor", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["he\"llo"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"🍜\",\"面", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["🍜"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\", \"hello\", ", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好", "hello"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\n ", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 3619");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"半句话", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 3818");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"\\u4f", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4019");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"🍜", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4216");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"hello\",oops", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4424");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "思考：[\"你好\"]", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4629");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "```json\n[\"你好\"]\n```", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4845");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\"] trailing", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 5056");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"<think>secret</think>\"]", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 5277");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"hello\"]", "truncated": false}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好", "hello"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(orangecell::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\"", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 5747");
      ++count;
    }
    {
      J response = J::parse(R"CASE({"status":"completed","error":null,"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"[\"hello\"]"}]}]})CASE");
      auto invokeEnvelope = [&](const J& body) {
        return J::parse(orangecell::invoke(J{{"op","envelope"},{"args",{{"endpoint","https://api.openai.com/v1/responses"},{"envelope",body}}}}.dump()));
      };
      auto ok = invokeEnvelope(response);
      if (!ok.contains("ok") || ok["ok"]["candidates"] != J::array({"hello"}))
        throw std::runtime_error("null provider error rejected successful Responses output");
      ++count;
      response["error"] = {{"code",429},{"message","test provider failure"}};
      if (invokeEnvelope(response).value("error","") != "provider")
        throw std::runtime_error("real provider error was ignored");
      ++count;
      response["error"] = nullptr; response["status"] = "failed";
      if (invokeEnvelope(response).value("error","") != "provider")
        throw std::runtime_error("failed response status was ignored");
      ++count;
    }
    {
      auto call=[](const char* op,J args){return J::parse(orangecell::invoke(J{{"op",op},{"args",args}}.dump()));};
      for(bool zh:{true,false}) for(bool traditional:{true,false}) {
        auto r=call("prompt",{{"assistantEnabled",true},{"chinese",zh},{"traditional",traditional}});
        auto s=r.at("ok").get<std::string>();
        if(s.find("No requests for more info; Give your best result directly.")==s.npos || s.find("Return only JSON [\"correction\",\"assistant\"]")==s.npos)
          throw std::runtime_error("approved assistant prompt missing");
        if(s.find(zh?(traditional?"Traditional Chinese":"Simplified Chinese"):"Both candidates use English only.")==s.npos)
          throw std::runtime_error("assistant language contract");
        ++count;
      }
      auto dual=call("decode",{{"text","[\"hello\",\"hello\"]"},{"assistantEnabled",true}});
      if(dual.at("ok").at("candidates")!=J::array({"hello","hello"}))throw std::runtime_error("duplicate roles lost");
      ++count;
      for(auto s:{"[\"hello\",", "[\"hello\",\"par", "[\"hello\",\"partial\\u4"}) {
        auto r=call("decode",{{"text",s},{"truncated",true},{"assistantEnabled",true}});
        if(r.at("ok").at("candidates")!=J::array({"hello"}))throw std::runtime_error("first role lost on truncation");
        ++count;
      }
      auto invalid=call("decode",{{"text","I think the answer is [\"hello\",\"hi\"]"},{"assistantEnabled",true}});
      if(!invalid.contains("error"))throw std::runtime_error("reasoning leaked into candidate");
      ++count;
      auto fenced=call("decode",{{"text","```json\n[\"hello\",\"hi\"]\n```"},{"assistantEnabled",true}});
      if(fenced.at("ok").at("candidates")!=J::array({"hello","hi"}))throw std::runtime_error("whole JSON fence not recovered");
      ++count;
      for(auto s:{"Explanation\n```json\n[\"hello\",\"hi\"]\n```", "```json\n[\"hello\",\"hi\"]\n```\nExplanation", "```json\n[\"hello\",\"hi\"]"}) {
        if(!call("decode",{{"text",s},{"assistantEnabled",true}}).contains("error"))throw std::runtime_error("prose or partial fence accepted");
        ++count;
      }
    }
    std::cout << count << " native truncation/format/envelope cases passed\n";
    return 0;
  } catch (const std::exception& e) {
    std::cerr << e.what();
    return 1;
  }
}
