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

# 超声波闭环：target_distance -> 3D 射线测量 -> send("distance") -> 标尺。
extends SceneTree

const DeviceConfigScript := preload("res://core/device_config.gd")

class FakeBridge extends Node:
	var sent: Array = []
	func send_input(device: String, channel: String, value: Variant) -> void:
		sent.append({"device": device, "channel": channel, "value": value})
	func invoke_input(_device: String, _channel: String) -> void:
		pass

var _failures := 0
var _checks := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var resolver := PackageResolver.new("")
	var resolved := resolver.resolve_device({
		"name": "sonar", "package": "ultrasonic", "version": "1.0.0",
	}, {"mcu": "stc90c51"})
	if not bool(resolved.get("ok", false)):
		print("SKIP: 未安装 ultrasonic 包")
		quit(0)
		return
	_check(String(resolved.get("script_path", "")).ends_with("ultrasonic-*-1.0.0/debug/virtual.gd"), "解析 ultrasonic 脚本")

	var scene := ModelLoader.load_scene(
		ProjectSettings.globalize_path("res://examples/ultrasonic/virtual/virtual.glb")
	)
	_check(scene != null, "加载超声波场景")
	if scene == null:
		_finish()
		return
	get_root().add_child(scene)
	await process_frame

	var model := scene.get_node_or_null("Devices/sonar") as Node3D
	var target := scene.get_node_or_null("Target") as Node3D
	_check(model != null and target != null, "传感器与目标节点")
	if model == null or target == null:
		_finish()
		return

	PhysicsBuilder.apply(scene, {"friction": 0.8, "mass": 1.0}, [], 0.8, [model])
	await physics_frame

	var ruler := RulerTool.new()
	get_root().add_child(ruler)
	var config := DeviceConfigScript.resolve(
		resolved.get("device_json", {}), resolved.get("manifest", {}),
		{"config": {"effective_distance": "30"}}, {}
	)
	_check(is_equal_approx(float(config.get("effective_distance", 0.0)), 30.0), "读取有效距离配置")

	var script := ScriptHost.load_script(ScriptHost.cache_script(
		String(resolved.get("package_path", "")), String(resolved.get("script_path", ""))
	))
	var device: VirtualDevice = script.new() if script != null else null
	_check(device != null, "加载超声波脚本")
	if device != null:
		var bridge := FakeBridge.new()
		get_root().add_child(bridge)
		model.add_child(device)
		device._host_bind(bridge, {
			"name": "sonar", "package": "ultrasonic", "model": model,
			"scene_root": scene, "sim": ruler, "config": config,
		})
		device._host_values({"target_distance": 25.0})
		for i in range(4):
			await physics_frame
			await process_frame
		_check(target.visible, "目标移动到输入距离")
		var sent_distance := _sent_distance(bridge)
		_check(sent_distance > 0.0 and sent_distance < 30.0, "3D 测量值回写模拟器")
		_check(ruler.get_ruler_count() == 1, "实测进入有效距离后画标尺")

		device._host_values({"target_distance": 100.0})
		for i in range(4):
			await physics_frame
			await process_frame
		_check(ruler.get_ruler_count() == 0, "实测离开有效距离后清除标尺")
		device._host_unbind()
		device.queue_free()
		bridge.queue_free()
	ruler.clear_rulers()
	ruler.queue_free()
	scene.free()
	_finish()

func _sent_distance(bridge: FakeBridge) -> float:
	for item in bridge.sent:
		if String(item.get("channel", "")) == "distance":
			return float(item.get("value", 0.0))
	return 0.0

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)

func _finish() -> void:
	print("ULTRASONIC SCENE: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
