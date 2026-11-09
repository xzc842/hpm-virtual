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

# 最小 SSE 解析器（text/event-stream），把字节流拆成事件。
class_name SseParser
extends RefCounted

signal event_received(event_name: String, data: String, event_id: String)

var last_event_id := ""
var retry_ms := 0

var _buffer := ""
var _event := ""
var _data := PackedStringArray()

func reset() -> void:
	_buffer = ""
	_event = ""
	_data.clear()

func feed(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	_buffer += bytes.get_string_from_utf8()
	while true:
		var idx := _buffer.find("\n")
		if idx < 0:
			break
		var line := _buffer.substr(0, idx)
		_buffer = _buffer.substr(idx + 1)
		if line.ends_with("\r"):
			line = line.substr(0, line.length() - 1)
		_line(line)

func _line(line: String) -> void:
	if line.is_empty():
		if not _data.is_empty() or not _event.is_empty():
			var name := _event if not _event.is_empty() else "message"
			event_received.emit(name, "\n".join(_data), last_event_id)
		_event = ""
		_data.clear()
		return
	if line.begins_with(":"):
		return
	var pos := line.find(":")
	var field := line if pos < 0 else line.substr(0, pos)
	var value := "" if pos < 0 else line.substr(pos + 1)
	if value.begins_with(" "):
		value = value.substr(1)
	match field:
		"event":
			_event = value
		"data":
			_data.append(value)
		"id":
			last_event_id = value
		"retry":
			retry_ms = int(value)
