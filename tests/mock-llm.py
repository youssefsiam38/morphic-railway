"""A stand-in OpenAI-compatible model for the local tests: answers every chat completion with one fixed
sentence, streamed or not, so a whole chat can be exercised without a real provider or key."""
import json
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ANSWER = "Mock model answer: the bundle works."


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
        if not req.get("stream"):
            return self._json(200, {
                "id": "cmpl-mock", "object": "chat.completion", "created": created, "model": req.get("model"),
                "choices": [{"index": 0, "message": {"role": "assistant", "content": ANSWER}, "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 1, "completion_tokens": 7, "total_tokens": 8},
            })
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def send(obj):
            self.wfile.write(b"data: " + json.dumps(obj).encode() + b"\n\n")
            self.wfile.flush()

        base = {"id": "chatcmpl-mock", "object": "chat.completion.chunk", "created": created, "model": req.get("model")}
        send({**base, "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": None}]})
        for word in ANSWER.split(" "):
            send({**base, "choices": [{"index": 0, "delta": {"content": word + " "}, "finish_reason": None}]})
        send({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
              "usage": {"prompt_tokens": 1, "completion_tokens": 7, "total_tokens": 8}})
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


class Server(ThreadingHTTPServer):
    address_family = socket.AF_INET6  # dual-stack on Linux, like the other listeners


Server(("::", 8000), Handler).serve_forever()
