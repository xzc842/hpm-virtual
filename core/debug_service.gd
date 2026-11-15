# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# hpm-gui 本地调试服务客户端（Autoload: Bridge）。
#
# 职责：
#   - 轮询 GET /debugger 检测调试会话开始/结束；
#   - 会话开始后建立 GET /outputs/stream 的 SSE 长连接（断线自动重连）；
#   - 把每个设备的输出值通过 device_values 信号分发给对应虚拟设备脚本；
#   - 提供 POST /devices/input 的写入口（send_input / invoke_input）。
extends Node

signal state_changed(state: String)
signal session_changed(active: bool)
signal devices_changed(devices: Array)
signal device_values(device_name: String, values: Dictionary)
signal values_reset()
signal stream_changed(connected: bool, message: String)
signal input_failed(payload: Dictionary, message: String)

const PROBE_INTERVAL := 1.5
const STREAM_PATH := "/outputs/stream"
const DEFAULT_URL := "http://127.0.0.1:17321"

var _base_url := DEFAULT_URL
var _host := "127.0.0.1"
var _port := 17321
var _project_dir := ""

var _state := "offline"
var _active := false
var _service_ok := false
var _devices: Array = []
var _device_values_cache: Dictionary = {}

var _probe_timer := 0.0
var _probe_busy := false
var _probe_request: HTTPRequest

var _devices_busy := false
var _devices_request: HTTPRequest

var _input_busy := false
var _input_queue: Array = []
var _input_current: Dictionary = {}
var _input_request: HTTPRequest

var _sse: HTTPClient = null
var _sse_phase := 0  # 1=connecting, 2=requesting, 3=body
var _sse_wait := 0.0
var _sse_since_data := 0.0
var _sse_connected := false
var _sse_reconnect_timer := 0.0
var _parser: SseParser

func _ready() -> void:
	_resolve_base_url()
	_parser = SseParser.new()
	_parser.event_received.connect(_on_sse_event)
	_create_requests()
	set_process(true)
	_probe()

func _process(delta: float) -> void:
	_probe_timer += delta
	if _probe_timer >= PROBE_INTERVAL and not _probe_busy:
		_probe_timer = 0.0
		_probe()

	if _sse == null and _active and _sse_reconnect_timer > 0.0:
		_sse_reconnect_timer -= delta
		if _sse_reconnect_timer <= 0.0:
			_open_stream()

	if _sse != null:
		_poll_stream(delta)

	_pump_input()

# ---------------------------------------------------------------- 对外接口

func is_active() -> bool:
	return _active

func get_service_state() -> String:
	return _state

func get_base_url() -> String:
	return _base_url

func get_devices() -> Array:
	return _devices

func get_cached_values(device_name: String) -> Dictionary:
	return _device_values_cache.get(device_name, {})

func set_project_dir(dir: String) -> void:
	_project_dir = dir

## 仅用于测试/自定义部署。
func set_service_url(url: String) -> void:
	_apply_url(url)
	_state = "offline"

func send_input(device_name: String, channel: String, value: Variant) -> void:
	_queue_input({"device": device_name, "channel": channel, "value": value})

func invoke_input(device_name: String, channel: String) -> void:
	_queue_input({"device": device_name, "channel": channel, "action": "invoke"})

## 设置多个通道。
func send_values(device_name: String, values: Dictionary) -> void:
	_queue_input({"device": device_name, "values": values})

# ---------------------------------------------------------------- 调试会话探测

func _create_requests() -> void:
	_probe_request = HTTPRequest.new()
	_probe_request.timeout = 1.0
	add_child(_probe_request)
	_probe_request.request_completed.connect(_on_probe_done)

	_devices_request = HTTPRequest.new()
	_devices_request.timeout = 3.0
	add_child(_devices_request)
	_devices_request.request_completed.connect(_on_devices_done)

	_input_request = HTTPRequest.new()
	_input_request.timeout = 3.0
	add_child(_input_request)
	_input_request.request_completed.connect(_on_input_done)

func _probe() -> void:
	if _probe_busy:
		return
	_probe_busy = true
	var err := _probe_request.request(_base_url + "/debugger")
	if err != OK:
		_probe_busy = false
		_service_ok = false
		_set_service_state("offline")

func _on_probe_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_probe_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_service_ok = false
		_set_service_state("offline")
		if _active:
			_deactivate()
		return
	var data := _parse_json(body)
	if data.is_empty():
		_service_ok = false
		_set_service_state("offline")
		if _active:
			_deactivate()
		return
	_service_ok = true
	var active := bool(data.get("active", false))
	var project := String(data.get("project", ""))
	var same_project := not _project_dir.is_empty() and (project.is_empty() or _same_path(project, _project_dir))

	if not active:
		_set_service_state("idle")
		if _active:
			_deactivate()
		return

	if _project_dir.is_empty():
		_set_service_state("idle")
		if _active:
			_deactivate()
		return

	if not same_project:
		_set_service_state("other_project")
		if _active:
			_deactivate()
		return

	_set_service_state("running")
	if not _active:
		_activate()

func _activate() -> void:
	if _active:
		return
	_active = true
	session_changed.emit(true)
	_fetch_devices()
	_sse_reconnect_timer = 0.0
	_open_stream()

func _deactivate() -> void:
	if not _active:
		return
	_active = false
	_stop_stream()
	_input_queue.clear()
	_devices = []
	_device_values_cache.clear()
	devices_changed.emit([])
	values_reset.emit()
	session_changed.emit(false)
	_set_service_state("idle" if _service_ok else "offline")

# ---------------------------------------------------------------- SSE 输出流

func _open_stream() -> void:
	if _sse != null:
		return
	_sse = HTTPClient.new()
	_sse.set_read_chunk_size(65536)
	var err := _sse.connect_to_host(_host, _port)
	if err != OK:
		_sse = null
		_schedule_reconnect()
		return
	_sse_phase = 1
	_sse_wait = 0.0
	_sse_since_data = 0.0
	_parser.reset()

func _poll_stream(delta: float) -> void:
	_sse_wait += delta
	_sse_since_data += delta
	var status := _sse.get_status()

	match status:
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			_sse.poll()
			if _sse_wait > 5.0:
				_fail_stream("连接输出流超时")
		HTTPClient.STATUS_CONNECTED:
			if _sse_phase == 1:
				var err := _sse.request(
					HTTPClient.METHOD_GET,
					STREAM_PATH,
					PackedStringArray(["Accept: text/event-stream", "Cache-Control: no-cache"])
				)
				if err != OK:
					_fail_stream("请求输出流失败")
					return
				_sse_phase = 2
			elif _sse_phase >= 3:
				_fail_stream("输出流已结束")
				return
			_sse.poll()
		HTTPClient.STATUS_REQUESTING:
			_sse.poll()
			if _sse_wait > 5.0:
				_fail_stream("等待输出流响应超时")
		HTTPClient.STATUS_BODY:
			if _sse_phase != 3:
				_sse_phase = 3
				if not _sse_connected:
					_sse_connected = true
					stream_changed.emit(true, "")
			var chunk := _sse.read_response_body_chunk()
			if chunk.size() > 0:
				_sse_wait = 0.0
				_sse_since_data = 0.0
				_parser.feed(chunk)
			elif _sse_since_data > 35.0:
				_fail_stream("输出流长时间无数据")
				return
			_sse.poll()
		HTTPClient.STATUS_DISCONNECTED:
			if _sse_phase >= 3 or _sse_connected:
				_fail_stream("输出流已断开")
			else:
				_fail_stream("无法建立输出流")
		_:
			_fail_stream("输出流连接错误")

func _fail_stream(message: String) -> void:
	var was_connected := _sse_connected
	_stop_stream()
	if was_connected:
		stream_changed.emit(false, message)
	if _active:
		_schedule_reconnect()

func _schedule_reconnect() -> void:
	if _sse_reconnect_timer <= 0.0:
		_sse_reconnect_timer = 1.0

func _stop_stream() -> void:
	if _sse != null:
		_sse.close()
		_sse = null
	_sse_phase = 0
	_sse_connected = false
	_sse_reconnect_timer = 0.0

func _on_sse_event(event_name: String, data: String, _event_id: String) -> void:
	if data.strip_edges().is_empty():
		return
	var obj := _parse_json(data.to_utf8_buffer())
	if obj.is_empty():
		return
	if bool(obj.get("heartbeat", false)):
		return
	var type := String(obj.get("type", event_name))
	match type:
		"snapshot":
			var list: Variant = obj.get("devices", [])
			if typeof(list) == TYPE_ARRAY:
				for item: Variant in list:
					if typeof(item) == TYPE_DICTIONARY:
						var entry: Dictionary = item
						var name := String(entry.get("device", entry.get("name", "")))
						var values: Variant = entry.get("values", entry.get("state", {}))
						if not name.is_empty() and typeof(values) == TYPE_DICTIONARY:
							_emit_values(name, values)
			if obj.has("active") and not bool(obj.get("active")):
				_deactivate()
		"device", "state", "device.updated", "event":
			var name := String(obj.get("device", obj.get("name", "")))
			var values: Variant = obj.get("values", {})
			if typeof(values) != TYPE_DICTIONARY or (values as Dictionary).is_empty():
				var ui: Variant = obj.get("ui", {})
				if typeof(ui) == TYPE_DICTIONARY:
					values = (ui as Dictionary).get("state", {})
			if not name.is_empty() and typeof(values) == TYPE_DICTIONARY:
				_emit_values(name, values)
		"reset":
			_device_values_cache.clear()
			values_reset.emit()
		_:
			pass

func _emit_values(device_name: String, values: Dictionary) -> void:
	_device_values_cache[device_name] = values.duplicate(true)
	device_values.emit(device_name, values)

# ---------------------------------------------------------------- 设备清单与输入

func _fetch_devices() -> void:
	if _devices_busy:
		return
	_devices_busy = true
	var err := _devices_request.request(_base_url + "/devices")
	if err != OK:
		_devices_busy = false

func _on_devices_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_devices_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var data := _parse_json(body)
	var list: Variant = data.get("devices", [])
	if typeof(list) == TYPE_ARRAY:
		_devices = list
		devices_changed.emit(_devices)

func _queue_input(payload: Dictionary) -> void:
	if not _active:
		push_warning("调试会话未运行，忽略输入：%s/%s" % [payload.get("device", ""), payload.get("channel", "")])
		return
	_input_queue.append(payload)
	_pump_input()

func _pump_input() -> void:
	if _input_busy or _input_queue.is_empty():
		return
	_input_busy = true
	var payload: Dictionary = _input_queue.pop_front()
	_input_current = payload
	var err := _input_request.request(
		_base_url + "/devices/input",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		_input_busy = false
		input_failed.emit(payload, "请求发送失败")

func _on_input_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_input_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var payload := _input_current
		_input_current = {}
		input_failed.emit(payload, "HTTP %d: %s" % [response_code, body.get_string_from_utf8()])
	else:
		_input_current = {}
	_pump_input()

# ---------------------------------------------------------------- 工具

func _schedule_state(state: String, force: bool = false) -> void:
	if _state == state and not force:
		return
	_state = state
	state_changed.emit(state)

func _set_service_state(state: String) -> void:
	_schedule_state(state)

func _resolve_base_url() -> void:
	var url := OS.get_environment("HPM_GUI_SERVICE_URL").strip_edges()
	if url.is_empty():
		var config_dir := OS.get_environment("XDG_CONFIG_HOME")
		if config_dir.is_empty():
			config_dir = OS.get_environment("HOME").path_join(".config")
		var service_file := config_dir.path_join("hpm-gui/service.json")
		if FileAccess.file_exists(service_file):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(service_file))
			if typeof(data) == TYPE_DICTIONARY:
				url = String(data.get("url", ""))
	if url.is_empty():
		url = DEFAULT_URL
	_apply_url(url)

func _apply_url(url: String) -> void:
	url = url.strip_edges()
	if url.begins_with("https://"):
		push_warning("暂不支持 https 调试服务地址，改用默认地址")
		url = DEFAULT_URL
	url = url.trim_prefix("http://")
	url = url.trim_suffix("/")
	var slash := url.find("/")
	if slash >= 0:
		url = url.substr(0, slash)
	var colon := url.rfind(":")
	if colon > 0:
		_host = url.substr(0, colon)
		_port = int(url.substr(colon + 1))
	else:
		_host = url
		_port = 80
	_base_url = "http://%s:%d" % [_host, _port]

func _parse_json(body: PackedByteArray) -> Dictionary:
	if body.is_empty():
		return {}
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _same_path(a: String, b: String) -> bool:
	return a.simplify_path().trim_suffix("/") == b.simplify_path().trim_suffix("/")
