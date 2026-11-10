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

# 舵机杆扫过右侧超声波：左侧无遮挡，180° 右端遮挡并绘制标尺。
extends SceneTree

const DeviceConfigScript := preload("res://core/device_config.gd")

class FakeBridge extends Node:
	var sent: Array = []
	func send_input(_device: String, channel: String, value: Variant) -> void:
		sent.append({"channel": channel, "value": value})
	func invoke_input(_device: String, _channel: String) -> void:
		pass

var _failures := 0
var _checks := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var resolver := PackageResolver.new(ProjectSettings.globalize_path("res://examples/servo-arm"))
	var resolved := resolver.resolve_device({
		"name": "sonar", "package": "ultrasonic", "version": "1.0.0",
	}, {"mcu": "stc90c51"})
	if not bool(resolved.get("ok", false)):
		print("SKIP: 未安装 ultrasonic 包")
		quit(0)
		return
	var scene := ModelLoader.load_scene(
		ProjectSettings.globalize_path("res://examples/servo-arm/virtual/virtual.glb")
	)
	_check(scene != null, "加载 servo-arm 场景")
	if scene == null:
		_finish()
		return
	get_root().add_child(scene)
	await process_frame

	var servo := scene.get_node_or_null("Devices/servo") as Node3D
	var sonar := scene.get_node_or_null("Devices/sonar") as Node3D
	var horn := scene.get_node_or_null("Devices/servo/ServoHorn") as Node3D
	_check(servo != null and sonar != null and horn != null, "舵机/摆杆/超声波节点")
	if servo == null or sonar == null or horn == null:
		_finish()
		return
	PhysicsBuilder.apply(scene, {"friction": 0.8, "mass": 1.0}, [], 0.8, [sonar])
	await physics_frame

	var ruler := RulerTool.new()
	get_root().add_child(ruler)
	var config := DeviceConfigScript.resolve(
		resolved.get("device_json", {}), resolved.get("manifest", {}),
		{"config": {"effective_distance": "10", "auto_measure": "true"}}, {}
	)
	_check(config.get("auto_measure") == true, "自动测量配置")

	var script := ScriptHost.load_script(ScriptHost.cache_script(
		String(resolved.get("package_path", "")), String(resolved.get("script_path", ""))
	))
	var device: VirtualDevice = script.new() if script != null else null
	_check(device != null, "加载超声脚本")
	if device != null:
		var bridge := FakeBridge.new()
		get_root().add_child(bridge)
		sonar.add_child(device)
		device._host_bind(bridge, {
			"name": "sonar", "package": "ultrasonic", "model": sonar,
			"scene_root": scene, "sim": ruler, "config": config,
		})



		horn.rotation_degrees.y = -90.0
		await physics_frame
		device._on_tick(0.2)
		await process_frame
		_check(_sent_distance(bridge) >= 30.0, "左侧无遮挡，距离为最大值")
		_check(ruler.get_ruler_count() == 0, "左侧不画标尺")

		horn.rotation_degrees.y = 90.0
		await physics_frame
		device._on_tick(0.2)
		for i in range(2):
			await physics_frame
			await process_frame
		_check(_sent_distance(bridge) < 30.0, "右端遮挡，测得近距离")
		_check(ruler.get_ruler_count() == 1, "遮挡后绘制标尺")
		device._host_unbind()
		device.queue_free()
		bridge.queue_free()
	ruler.clear_rulers()
	ruler.queue_free()
	scene.free()
	_finish()

func _sent_distance(bridge: FakeBridge) -> float:
	var result := 0.0
	for item in bridge.sent:
		if String(item.get("channel", "")) == "distance":
			result = float(item.get("value", 0.0))
	return result

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)

func _finish() -> void:
	print("SERVO ARM: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
