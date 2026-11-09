#!/usr/bin/env python3
"""Minimal hpm-gui debug service mock for hpm-virtual end-to-end checks."""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROJECT = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 18081
STREAM_LIFE = float(sys.argv[3]) if len(sys.argv) > 3 else 6.0

DEVICES = [{
    "name": "led",
    "device": "led",
    "driver": "gpio",
    "config": {"pin": "P1_1"},
    "present": True,
    "online": True,
    "role": "output",
    "title": "演示 LED",
    "channels": [],
    "values": {"power": False},
    "source": "project",
}]

INPUTS = []


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("mock: " + fmt % args + "\n")

    def _json(self, payload, code=200):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/debugger"):
            self._json({
                "ok": True, "active": True, "pid": 1, "project": PROJECT,
                "protocol": "hpm-debug/2",
                "features": ["device.list", "device.snapshot"],
                "status": {"status": "running", "pc": 1, "halted": False},
                "device_count": 1,
            })
        elif self.path.startswith("/devices"):
            self._json({"ok": True, "project": PROJECT, "active": True,
                        "count": len(DEVICES), "devices": DEVICES})
        elif self.path.startswith("/outputs/stream"):
            self._stream()
        else:
            self._json({"ok": False, "error": "not found"}, 404)

    def _chunk(self, text):
        data = text.encode()
        self.wfile.write(("%x\r\n" % len(data)).encode() + data + b"\r\n")
        self.wfile.flush()

    def _stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        self._chunk("retry: 1000\n\n")
        self._chunk(
            'event: snapshot\n'
            'data: {"type":"snapshot","active":true,"devices":'
            '[{"device":"led","values":{"power":false}}]}\n\n'
        )
        time.sleep(0.6)
        self._chunk(
            'id: 1\nevent: device\n'
            'data: {"cursor":1,"type":"device","device":"led",'
            '"values":{"power":true}}\n\n'
        )
        deadline = time.time() + STREAM_LIFE
        while time.time() < deadline:
            time.sleep(0.2)
            self._chunk(": ping\n\n")
        self.wfile.write(b"0\r\n\r\n")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        payload = self.rfile.read(length)
        INPUTS.append(payload.decode())
        sys.stderr.write("mock: input %s\n" % payload.decode())
        self._json({"ok": True})


if __name__ == "__main__":
    print("mock listening on %d" % PORT, flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
