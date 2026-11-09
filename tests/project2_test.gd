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

# project2 自定义虚拟包运行时测试：led2 使用 clickable-led。
#   godot --headless --path . --script res://tests/project2_test.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _init() -> void:
	var project_dir := ProjectSettings.globalize_path("res://examples/project2")
	var resolver := PackageResolver.new(project_dir)
	var resolved := resolver.resolve_device({
		"name": "led2", "package": "gpio", "version": "1.0.0",
		"override": {"name": "clickable-led", "version": "1.0.0"},
	}, {"mcu": "stc90c51"})
	_check(bool(resolved.get("ok", false)), "解析 clickable-led")
	_check(String(resolved.get("script_path", "")).ends_with("clickable-led-1.0.0/virtual.gd"), "使用覆盖脚本")
	_check(String(resolved.get("device_json", {}).get("display_name", "")) == "可点击 LED", "使用覆盖 device.json")

	var scene := ModelLoader.load_scene(project_dir.path_join("virtual/virtual.glb"))
	var led2 := scene.get_node_or_null("Devices/led2") as Node3D
	_check(led2 != null, "找到 led2 节点")
	if led2 == null:
		_finish()
		return

	var cached := ScriptHost.cache_script(
		String(resolved.get("package_path", "")), String(resolved.get("script_path", ""))
	)
	var script := ScriptHost.load_script(cached)
	_check(script != null, "加载覆盖脚本")
	if script == null:
		_finish()
		return
	var device: VirtualDevice = script.new()
	device.model = led2
	device._host_bind(null, {
		"name": "led2", "title": "可点击 LED", "package": "gpio",
		"props": {"color": "green"}, "model": led2, "scene_root": scene,
	})
	_check(device.has_interaction(), "注册了点击交互")
	_check(device.get_interaction_hint() == "点击切换颜色", "交互提示")
	device._host_values({"power": true})
	_check(device.trigger_interaction("color"), "触发颜色切换")
	var barrel := led2.get_node_or_null("Body/Barrel2") as MeshInstance3D
	_check(barrel != null and barrel.material_override != null, "LED2 材质")
	if barrel != null and barrel.material_override != null:
		_check(barrel.material_override.albedo_color.b > barrel.material_override.albedo_color.r, "点击后变蓝")

	device._host_unbind()
	device.free()
	scene.free()
	_finish()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)

func _finish() -> void:
	print("PROJECT2: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
