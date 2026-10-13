import json
import threading
import time
import difflib
from http.server import BaseHTTPRequestHandler, HTTPServer

_server = None
_thread = None
_lock = threading.Lock()
_cache = []  # list of {"prompt": str, "response": str}


def _find_cached(prompt):
    if not _cache:
        return None
    prompts = [c["prompt"] for c in _cache]
    matches = difflib.get_close_matches(prompt, prompts, n=1, cutoff=0.6)
    if matches:
        for c in _cache:
            if c["prompt"] == matches[0]:
                return c["response"]
    return None


class _Handler(BaseHTTPRequestHandler):
    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b"{}"
            data = json.loads(raw or b"{}")
        except Exception:
            self._send_json(400, {"error": "invalid json"})
            return

        if self.path == "/v1/chat/completions":
            messages = data.get("messages", [])
            prompt = messages[-1]["content"] if messages else ""
            cached = _find_cached(prompt)
            if cached is None:
                # A cache miss is not an AI answer. Returning 404 lets the Dart
                # gateway continue to configured cloud providers instead of
                # incorrectly stopping at a generic offline message.
                self._send_json(404, {"error": "cache_miss"})
                return
            self._send_json(200, {
                "choices": [{"message": {"role": "assistant", "content": cached}}]
            })
            return

        if self.path == "/v1/cache/store":
            prompt = data.get("prompt", "")
            response = data.get("response", "")
            if prompt and response:
                with _lock:
                    _cache.append({"prompt": prompt, "response": response})
                    if len(_cache) > 500:
                        del _cache[0]
            self._send_json(200, {"stored": True})
            return

        self._send_json(404, {"error": "not found"})

    def log_message(self, format, *args):
        pass  # silence default stderr logging


def start_server():
    global _server, _thread
    with _lock:
        if _server is not None:
            return
        _server = HTTPServer(("127.0.0.1", 8000), _Handler)
        _thread = threading.Thread(target=_server.serve_forever, daemon=True)
        _thread.start()


def stop_server():
    global _server, _thread
    with _lock:
        if _server is not None:
            _server.shutdown()
            _server.server_close()
            _server = None
            _thread = None


def is_running():
    return _server is not None
