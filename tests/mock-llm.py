"""A stand-in OpenAI-compatible model for the tests, so a whole chat can be exercised without a real
provider or key.

When a request offers Morphic's `search` tool and no tool result has come back yet, it asks for an
advanced search; that makes Morphic's search tool call SearXNG through the app's own advanced-search
route, with the Valkey cache. Every other request is answered with one fixed sentence that reports how
many results the search returned, streamed or not."""
import json
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SEARCH_ARGS = {"query": "railway app hosting", "type": "optimized", "search_depth": "advanced", "max_results": 10}


def answer_for(req):
    results = None
    for msg in req.get("messages", []):
        if msg.get("role") == "tool":
            content = msg.get("content")
            try:
                data = json.loads(content) if isinstance(content, str) else content
                found = data.get("results") if isinstance(data, dict) else None
                results = len(found) if isinstance(found, list) else "unknown"
            except (ValueError, TypeError, AttributeError):
                results = "unreadable"
    if results is None:
        return "Mock model answer: the bundle works."
    return f"Mock model answer: the bundle works; search tool returned {results} results."


def wants_search(req):
    offered = any((t.get("function") or {}).get("name") == "search" for t in req.get("tools") or [])
    answered = any(m.get("role") == "tool" for m in req.get("messages", []))
    return offered and not answered


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            return self._json(200, {"object": "list", "data": [{"id": "mock-model", "object": "model"}]})
        self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        req = json.loads(self.rfile.read(length) or b"{}")
        if self.headers.get("Authorization") != "Bearer mock-llm-key":
            return self._json(401, {"error": {"message": "bad key"}})
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self._json(404, {"error": "not found"})
        created = int(time.time())
        usage = {"prompt_tokens": 1, "completion_tokens": 7, "total_tokens": 8}
        search = wants_search(req)
        text = answer_for(req)
        if not req.get("stream"):
            return self._json(200, {
                "id": "cmpl-mock", "object": "chat.completion", "created": created, "model": req.get("model"),
                "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}],
                "usage": usage,
            })
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def send(obj):
            self.wfile.write(b"data: " + json.dumps(obj).encode() + b"\n\n")
            self.wfile.flush()

        base = {"id": "chatcmpl-mock", "object": "chat.completion.chunk", "created": created, "model": req.get("model")}
        if search:
            send({**base, "choices": [{"index": 0, "delta": {"role": "assistant", "tool_calls": [{
                "index": 0, "id": "call_mock_search", "type": "function",
                "function": {"name": "search", "arguments": json.dumps(SEARCH_ARGS)}}]}, "finish_reason": None}]})
            send({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}], "usage": usage})
        else:
            send({**base, "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": None}]})
            for word in text.split(" "):
                send({**base, "choices": [{"index": 0, "delta": {"content": word + " "}, "finish_reason": None}]})
            send({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}], "usage": usage})
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


class Server(ThreadingHTTPServer):
    address_family = socket.AF_INET6  # dual-stack on Linux, like the other listeners


Server(("::", 8000), Handler).serve_forever()
