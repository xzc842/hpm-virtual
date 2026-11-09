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

# 虚拟设备脚本基类。
#
# 设备包里的 debug/virtual.gd 以如下方式继承：
#   extends "res://sdk/virtual_device.gd"
#
# 主程序负责：加载模型、把包脚本实例挂到设备节点下、在调试会话开始时
# 把 /outputs/stream 里属于该设备的 values 转发给 _on_values()。
# 脚本只操作 3D 节点和调用 send()/invoke()，不要自己发起 HTTP 请求。
class_name VirtualDevice
extends Node

## 设备实例名，对应 project.json 里 devices 的 key。
var device_name := ""
## 显示名，来自 device.json 或调试服务。
var device_title := ""
## 设备包名 / 版本。
var package_name := ""
var package_version := ""
## 该设备在 virtual.glb 里的模型根节点。
var model: Node3D = null
## virtual.json 里该实例的 props。
var props: Dictionary = {}
## 调试会话是否正在运行。
var active := false
## 最近一次收到的输出通道值。
var values: Dictionary = {}
## 整个 virtual.glb 场景的根节点（只读访问）。
var scene_root: Node3D = null
## SimView（可读取设备节点、添加标尺等）。
var sim_view: Node = null

var _bridge: Node = null
var _interactions: Dictionary = {}
var _interaction_order: Array[String] = []

# ---------------------------------------------------------------- 供脚本使用

## 写输入设备通道（POST /devices/input）。
func send(channel: String, value: Variant) -> void:
	if _bridge != null:
		_bridge.send_input(device_name, channel, value)

## 触发按钮/动作通道。
func invoke(channel: String) -> void:
	if _bridge != null:
		_bridge.invoke_input(device_name, channel)

## 读取最近一次输出值。
func get_value(channel: String, default_value: Variant = null) -> Variant:
	return values.get(channel, default_value)

## 取模型根节点下的节点。path 为空时返回模型根节点。
func get_model_node(path: String = "") -> Node:
	if model == null:
		return null
	if path.is_empty():
		return model
	var node := model.get_node_or_null(path)
	if node != null:
		return node
	return model.find_child(path.get_file(), true, false)

# ---------------------------------------------------------------- 场景 / 交互 / 标尺

## 注册一个可点击交互。设备在“选择”模式下悬停会高亮，左键触发。
func register_interaction(id: String, callback: Callable, hint: String = "") -> void:
	if not callback.is_valid():
		log_warn("register_interaction 收到无效 Callable：%s" % id)
		return
	var key := id if not id.is_empty() else "default"
	_interactions[key] = {"callback": callback, "hint": hint}
	if not _interaction_order.has(key):
		_interaction_order.append(key)

func unregister_interaction(id: String) -> void:
	var key := id if not id.is_empty() else "default"
	_interactions.erase(key)
	_interaction_order.erase(key)

func clear_interactions() -> void:
	_interactions.clear()
	_interaction_order.clear()

func has_interaction() -> bool:
	return not _interactions.is_empty()

func get_interaction_hint() -> String:
	var hints := PackedStringArray()
	for key: String in _interaction_order:
		if not _interactions.has(key):
			continue
		var hint := String(_interactions[key].get("hint", ""))
		if not hint.is_empty():
			hints.append(hint)
	if hints.is_empty():
		return "点击交互"
	return " / ".join(hints)

## 触发交互；id 为空时触发第一个注册的交互。
func trigger_interaction(id: String = "") -> bool:
	var key := id
	if key.is_empty():
		if _interaction_order.is_empty():
			return false
		key = _interaction_order[0]
	if not _interactions.has(key):
		return false
	var callback: Callable = _interactions[key]["callback"]
	if not callback.is_valid():
		return false
	callback.call()
	return true

## 读取整个虚拟场景（根节点）。
func get_scene_root() -> Node3D:
	return scene_root

func get_scene_node(path: String) -> Node:
	if scene_root == null:
		return null
	return scene_root.get_node_or_null(path)

## 在世界坐标画一条标尺；返回标尺 id（失败为 -1）。
func draw_ruler(from_point: Vector3, to_point: Vector3, label_text: String = "") -> int:
	if sim_view != null and sim_view.has_method("add_ruler"):
		return int(sim_view.add_ruler(from_point, to_point, label_text))
	return -1

func clear_rulers() -> void:
	if sim_view != null and sim_view.has_method("clear_rulers"):
		sim_view.clear_rulers()

func log_info(message: String) -> void:
	print("[virtual:", device_name, "] ", message)

func log_warn(message: String) -> void:
	push_warning("[virtual:%s] %s" % [device_name, message])

func log_error(message: String) -> void:
	push_error("[virtual:%s] %s" % [device_name, message])

# ---------------------------------------------------------------- 生命周期

## 绑定完成时调用，ctx 包含 name/title/package/version/node_path/props/device。
func _on_bind(_ctx: Dictionary) -> void:
	pass

## 调试会话开始（长连接建立前）。
func _on_session_start() -> void:
	pass

## 收到该设备的输出通道值（服务端只在值变化时推送）。
func _on_values(_new_values: Dictionary) -> void:
	pass

## 调试会话结束。
func _on_session_stop() -> void:
	pass

## 每帧调用；需要模拟动画时覆写它。
func _on_tick(_delta: float) -> void:
	pass

## 节点释放前调用。
func _on_unbind() -> void:
	pass

# ---------------------------------------------------------------- 主程序内部

func _host_bind(bridge: Node, ctx: Dictionary) -> void:
	_bridge = bridge
	device_name = String(ctx.get("name", device_name))
	device_title = String(ctx.get("title", device_title))
	package_name = String(ctx.get("package", package_name))
	package_version = String(ctx.get("version", package_version))
	model = ctx.get("model", model)
	props = ctx.get("props", {})
	scene_root = ctx.get("scene_root", scene_root)
	sim_view = ctx.get("sim", sim_view)
	set_process(true)
	_on_bind(ctx)

func _host_session_start() -> void:
	active = true
	_on_session_start()

func _host_values(new_values: Dictionary) -> void:
	values = new_values.duplicate(true)
	_on_values(values)

func _host_session_stop() -> void:
	active = false
	values.clear()
	_on_session_stop()

func _host_unbind() -> void:
	_on_unbind()
	clear_interactions()

func _process(delta: float) -> void:
	if model != null:
		_on_tick(delta)
