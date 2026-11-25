#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A local stand-in for the three AI services, for the CI runs (no real network, no real key).

It listens on 127.0.0.1 only and answers the three wire formats of the app with server-sent events:

    POST /openai/v1/responses                    OpenAI Responses
    POST /openrouter/api/v1/chat/completions     OpenRouter / Chat Completions
    POST /gemini/v1beta/interactions             Gemini Interactions

The answer depends on the request: an emoticon request (the fixed emoji prompt) gets five emoticons, an
assistant request gets a correction and an answer, a plain request only the correction. The assistant answer of
the sentence 我要吃火锅 is slow on purpose (the second candidate comes seconds after the first), so a test can
press another key while it is still streaming.

Every request is written to a JSON lines log (`--log`): what was asked, whether the key was right, whether the
client went away before the answer was complete. `GET /__stats` returns the counts, `POST /__reset` clears them.
Nothing here is secret: the key it accepts is a made-up one.
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EMOTICONS = ["(≧▽≦)", "(｡•̀ᴗ-)", "٩(◕‿◕｡)۶", "(^_^)", "😋"]

# input -> (correction, assistant)
ANSWERS = {
    "woyaochihuogou": ("我要吃火锅", "好啊，一起去吃火锅吧"),
    "我要吃火锅": ("我要吃火锅。", "好啊，一起去吃吧"),
    "Tomorow we have a meetng": ("Tomorrow we have a meeting.", "Sounds good, see you there."),
}

FAST_MS = 150


class State:
    lock = threading.Lock()
    counter = 0
    log_path = None
    key = ""
    slow_ms = 2200
    stats = {"requests": 0, "unauthorized": 0, "aborted": 0, "complete": 0}

    @classmethod
    def write(cls, record):
        record["time"] = round(time.time(), 3)
        line = json.dumps(record, ensure_ascii=False)
        with cls.lock:
            if cls.log_path:
                with open(cls.log_path, "a", encoding="utf8") as handle:
                    handle.write(line + "\n")

    @classmethod
    def next_id(cls):
        with cls.lock:
            cls.counter += 1
            cls.stats["requests"] += 1
            return cls.counter

    @classmethod
    def bump(cls, name):
        with cls.lock:
            cls.stats[name] += 1


def parse_request(path, body):
    """(wire format, system prompt, input text) of a request body."""
    data = json.loads(body.decode("utf8"))
    if path.startswith("/gemini"):
        return "gemini", data.get("system_instruction", ""), data.get("input", "")
    if path.startswith("/openai"):
        return "openai", data.get("instructions", ""), data.get("input", "")
    messages = data.get("messages", [])
    system = messages[0]["content"] if messages else ""
    user = messages[1]["content"] if len(messages) > 1 else ""
    return "openrouter", system, user


def decide(system, user):
    """(kind, candidates, input) for a request."""
    try:
        wire = json.loads(user)
        text = wire.get("i", "")
    except Exception:
        text = user
    if "emoticons" in system:
        return "emoji", EMOTICONS, text
    correction, assistant = ANSWERS.get(text, (text, "（模拟）" + text))
    if '"correction","assistant"' in system:
        return "assistant", [correction, assistant], text
    return "correction", [correction], text


def pieces(candidates):
    """The text of the answer in the pieces a model would stream it in: a JSON array, one string at a time."""
    out = []
    for index, candidate in enumerate(candidates):
        quoted = json.dumps(candidate, ensure_ascii=False)
        out.append(("[" if index == 0 else ",") + quoted)
    out[-1] += "]"
    return out


def event(obj):
    return ("data: " + json.dumps(obj, ensure_ascii=False) + "\r\n\r\n").encode("utf8")


def start_events(fmt):
    head = [b": mock heartbeat\r\n\r\n"]
    if fmt == "gemini":
        head.append(event({"event_type": "step.start", "index": 1, "step": {"type": "model_output", "content": [{"type": "text", "text": ""}]}}))
    return head


def delta_event(fmt, text):
    if fmt == "gemini":
        return event({"event_type": "step.delta", "index": 1, "delta": {"type": "text", "text": text}})
    if fmt == "openai":
        return event({"type": "response.output_text.delta", "delta": text})
    return event({"choices": [{"index": 0, "delta": {"content": text}}]})


def end_events(fmt):
    if fmt == "gemini":
        return [event({"event_type": "interaction.completed", "interaction": {"status": "completed", "usage": {"total_input_tokens": 12, "total_output_tokens": 8}}})]
    if fmt == "openai":
        return [event({"type": "response.completed", "response": {"usage": {"input_tokens": 12, "output_tokens": 8}}})]
    return [event({"choices": [], "usage": {"prompt_tokens": 12, "completion_tokens": 8}}), b"data: [DONE]\n\n"]


class Handler(BaseHTTPRequestHandler):
    server_version = "OrangeCellMock/1"
    # The body ends when the connection closes: simple, and what URLSession reads as a stream.
    protocol_version = "HTTP/1.0"

    def log_message(self, fmt, *args):  # no access log on stderr
        pass

    def do_GET(self):
        if self.path == "/__stats":
            body = json.dumps(State.stats).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        if self.path == "/__reset":
            with State.lock:
                for name in State.stats:
                    State.stats[name] = 0
            self.send_response(204)
            self.end_headers()
            return
        ident = State.next_id()
        auth = self.headers.get("Authorization", "") or self.headers.get("x-goog-api-key", "")
        expected = State.key
        authorized = auth in (expected, "Bearer " + expected)
        try:
            fmt, system, user = parse_request(self.path, body)
            kind, candidates, text = decide(system, user)
        except Exception as error:  # a malformed request is a test failure, say so in the log
            State.write({"event": "bad-request", "id": ident, "path": self.path, "error": str(error)})
            self.send_error(400)
            return
        State.write({"event": "request", "id": ident, "path": self.path, "format": fmt, "kind": kind, "input": text,
                     "authorized": authorized, "bodyHasKey": expected.encode() in body, "bytes": len(body)})
        if not authorized:
            State.bump("unauthorized")
            payload = b'{"error":{"message":"bad key"}}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        slow = kind == "assistant" and text == "我要吃火锅"
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            for chunk in start_events(fmt):
                self.wfile.write(chunk)
            self.wfile.flush()
            parts = pieces(candidates)
            for index, part in enumerate(parts):
                time.sleep(((State.slow_ms if slow and index > 0 else FAST_MS)) / 1000)
                self.wfile.write(delta_event(fmt, part))
                self.wfile.flush()
            time.sleep(FAST_MS / 1000)
            for chunk in end_events(fmt):
                self.wfile.write(chunk)
            self.wfile.flush()
            State.bump("complete")
            State.write({"event": "complete", "id": ident, "kind": kind})
        except (BrokenPipeError, ConnectionResetError):
            State.bump("aborted")
            State.write({"event": "aborted", "id": ident, "kind": kind, "input": text})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--log", default="")
    parser.add_argument("--key", default="sk-mock-orangecell-test")
    parser.add_argument("--slow-ms", type=int, default=2200)
    parser.add_argument("--ready-file", default="")
    args = parser.parse_args()
    State.log_path = args.log or None
    State.key = args.key
    State.slow_ms = args.slow_ms
    if State.log_path:
        open(State.log_path, "w").close()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    if args.ready_file:
        with open(args.ready_file, "w") as handle:
            handle.write(str(args.port))
    print("mock AI server on 127.0.0.1:%d" % args.port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
