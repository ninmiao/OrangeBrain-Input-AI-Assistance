#include "core.h"

#include <fstream>
#include <iostream>
#include <nlohmann/json.hpp>
#include <stdexcept>
using J = nlohmann::ordered_json;
int main() {
  try {
    int count = 0;
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\"", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"未完成", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\u4", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\uD83D", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"\\uD83D\\u", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"x\\\"", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"hello\\nworld\"", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["hello\nworld"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"he\\\"llo\", \"wor", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["he\"llo"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"🍜\",\"面", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["🍜"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\", \"hello\", ", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好", "hello"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\n ", "truncated": true}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 3619");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"半句话", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 3818");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"\\u4f", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4019");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"🍜", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4216");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"hello\",oops", "truncated": true}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4424");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "思考：[\"你好\"]", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4629");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "```json\n[\"你好\"]\n```", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 4845");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\"] trailing", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 5056");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"<think>secret</think>\"]", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 5277");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\",\"hello\"]", "truncated": false}})CASE"));
      if (!r.contains("ok") ||
          r["ok"]["candidates"] != J::parse(R"CASE(["你好", "hello"])CASE"))
        throw std::runtime_error("candidate mismatch");
      ++count;
    }
    {
      auto r = J::parse(zephyr::invoke(
          R"CASE({"op": "decode", "args": {"text": "[\"你好\"", "truncated": false}})CASE"));
      if (!r.contains("error"))
        throw std::runtime_error("accepted invalid 5747");
      ++count;
    }
    {
      J response = J::parse(R"CASE({"status":"completed","error":null,"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"[\"hello\"]"}]}]})CASE");
      auto invokeEnvelope = [&](const J& body) {
        return J::parse(zephyr::invoke(J{{"op","envelope"},{"args",{{"endpoint","https://api.openai.com/v1/responses"},{"envelope",body}}}}.dump()));
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
    std::cout << count << " native truncation/format/envelope cases passed\n";
    return 0;
  } catch (const std::exception& e) {
    std::cerr << e.what();
    return 1;
  }
}
