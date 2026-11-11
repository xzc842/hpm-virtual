#!/usr/bin/env python3
# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

"""Minimal hpm-gui debug service mock for hpm-virtual end-to-end checks.

Usage:
  python3 tools/mock_debug_service.py <project-dir> [port] [stream-seconds]

Reads <project-dir>/project.json and only emits devices that exist there.
The LED toggles every 0.5s so the blink demo can be tested without hpm-gui.
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROJECT = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 18081
STREAM_LIFE = float(sys.argv[3]) if len(sys.argv) > 3 else 6.0


def build_devices():
    templates = {
        "led": {
            "driver": "gpio",
            "config": {"pin": "P1_0"},
            "title": "LED",
            "values": {"power": False},
        },
        "stepper_fl": {"driver": "stepper", "config": {}, "title": "左前轮", "values": {"angle": 0.0, "direction": 1}},
    "stepper_fr": {"driver": "stepper", "config": {}, "title": "右前轮", "values": {"angle": 0.0, "direction": 1}},
    "stepper_rl": {"driver": "stepper", "config": {}, "title": "左后轮", "values": {"angle": 0.0, "direction": 1}},
    "stepper_rr": {"driver": "stepper", "config": {}, "title": "右后轮", "values": {"angle": 0.0, "direction": 1}},
    "sonar": {
        "driver": "ultrasonic",
        "config": {"effective_distance": "30", "max_distance": "400"},
        "title": "超声波测距",
        "values": {"target_distance": 100.0, "distance": 100.0, "in_range": False,
                   "effective_distance": 30.0},
    },
    "servo": {
            "driver": "pwm",
            "config": {"pin": "P1_1"},
            "title": "Servo",
            "values": {"angle": 90.0, "duty_pct": 7.5},
        },
    }
    names = ["led"]
    project_json = os.path.join(PROJECT, "project.json")
    if os.path.isfile(project_json):
        try:
            data = json.loads(open(project_json, encoding="utf-8").read())
            names = list((data.get("devices") or {}).keys()) or names
        except (OSError, ValueError):
            pass
    devices = []
    for name in names:
        if name.startswith("led"):
            template = dict(templates["led"])
            template["title"] = name.upper()
        else:
            template = templates.get(name, {
                "driver": "",
                "config": {},
                "title": name,
                "values": {},
            })
        devices.append({
            "name": name,
            "device": name,
            "driver": template["driver"],
            "config": template["config"],
            "present": True,
            "online": True,
            "role": "output",
            "title": template["title"],
            "channels": [],
            "values": dict(template["values"]),
            "source": "project",
        })
    return devices


DEVICES = build_devices()
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
                "device_count": len(DEVICES),
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

    def _event(self, cursor, name, values):
        payload = {
            "cursor": cursor,
            "type": "device",
            "device": name,
            "values": values,
        }
        self._chunk(
            f"id: {cursor}\nevent: device\n"
            f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
        )

    def _stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        self._chunk("retry: 1000\n\n")

        states = {item["name"]: dict(item["values"]) for item in DEVICES}
        snapshot = {
            "type": "snapshot",
            "active": True,
            "devices": [{"device": name, "values": values}
                        for name, values in states.items()],
        }
        self._chunk(f"event: snapshot\ndata: {json.dumps(snapshot)}\n\n")

        cursor = 0
        led_names = [name for name in states if name.startswith("led")]
        # 有超声波时由距离输入控制 LED，不再自动闪烁。
        led_blink_names = list(led_names) if "sonar" not in states else []
        time.sleep(0.6)
        if "sonar" in states:
            states["sonar"].update({"target_distance": 100.0})
            cursor += 1
            self._event(cursor, "sonar", dict(states["sonar"]))

        for name in led_blink_names:
            states[name]["power"] = True
            cursor += 1
            self._event(cursor, name, dict(states[name]))
        if "servo" in states:
            states["servo"].update({"angle": 90.0, "duty_pct": 7.5})
            cursor += 1
            self._event(cursor, "servo", dict(states["servo"]))

        deadline = time.time() + STREAM_LIFE
        next_blink = time.time() + 0.5
        next_servo = time.time() + 1.5
        next_sonar = time.time() + 0.6
        next_stepper = time.time() + 0.2
        sonar_step = 0
        input_cursor = len(INPUTS)
        next_ping = time.time() + 0.5
        angles = [0.0, 90.0, 180.0]
        angle_index = 0
        while time.time() < deadline:
            time.sleep(0.1)
            now = time.time()
            if led_blink_names and now >= next_blink:
                for name in led_blink_names:
                    states[name]["power"] = not states[name]["power"]
                    cursor += 1
                    self._event(cursor, name, dict(states[name]))
                next_blink = now + 0.5
            if "servo" in states and now >= next_servo:
                angle = angles[angle_index % len(angles)]
                angle_index += 1
                duty = 5.0 + angle / 180.0 * 5.0
                states["servo"].update({"angle": angle, "duty_pct": duty})
                cursor += 1
                self._event(cursor, "servo", dict(states["servo"]))
                next_servo = now + 1.5
            if all(n in states for n in ("stepper_fl", "stepper_fr", "stepper_rl", "stepper_rr")) and now >= next_stepper:
                for n in ("stepper_fl", "stepper_fr", "stepper_rl", "stepper_rr"):
                    states[n]["angle"] = float(states[n].get("angle", 0.0)) + 2.0
                    cursor += 1
                    self._event(cursor, n, dict(states[n]))
                next_stepper = now + 0.2
            if "sonar" in states and now >= next_sonar:
                sonar_step = (sonar_step + 1) % 10
                if sonar_step < 2:
                    states["sonar"].update({"target_distance": 100.0})
                else:
                    cm = max(25.0 - (sonar_step - 2) * 4.0, 1.0)
                    states["sonar"].update({"target_distance": cm})
                cursor += 1
                self._event(cursor, "sonar", dict(states["sonar"]))
                next_sonar = now + 0.6
            if "led" in states and "sonar" in states:
                for raw in INPUTS[input_cursor:]:
                    try:
                        payload = json.loads(raw)
                    except ValueError:
                        continue
                    if payload.get("device") == "sonar" and payload.get("channel") == "distance":
                        distance = float(payload.get("value", 400.0))
                        on = distance < 30.0
                        if states["led"].get("power") != on:
                            states["led"]["power"] = on
                            sys.stderr.write("mock: led %s distance %.1f\n" % ("on" if on else "off", distance))
                            sys.stderr.flush()
                            cursor += 1
                            self._event(cursor, "led", dict(states["led"]))
                input_cursor = len(INPUTS)
            if now >= next_ping:
                self._chunk(": ping\n\n")
                next_ping = now + 0.5
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
