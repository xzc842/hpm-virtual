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

# 真实设备包（gpio / pwm）+ project1 场景测试。
#   godot --headless --path . --script res://tests/real_packages_test.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _init() -> void:
	var resolver := PackageResolver.new("")
	var gpio_pkg := resolver.find("gpio", "", "stc90c51")
	var pwm_pkg := resolver.find("pwm", "", "stc90c51")
	if gpio_pkg.is_empty() or pwm_pkg.is_empty():
		print("SKIP: 未安装 gpio / pwm 设备包")
		quit(0)
		return

	print("[Packages] ", gpio_pkg.get("dir_name", ""), " / ", pwm_pkg.get("dir_name", ""))
	var project := {"mcu": "stc90c51"}
	var led1_instance := {
		"name": "led1", "node": "Devices/led1", "package": "gpio",
		"version": "1.0.0", "props": {"color": "red"},
	}
	var led2_instance := {
		"name": "led2", "node": "Devices/led2", "package": "gpio",
		"version": "1.0.0", "props": {"color": "green"},
		"objects": [
			{"node": "Body", "physics": {"friction": 0.35, "mass": 0.12, "bounce": 0.2}},
			{"node": "Base2", "physics": {"friction": 0.65}},
			{"node": "Anode2", "physics": {"friction": 0.75}},
			{"node": "Cathode2", "physics": {"friction": 0.75}},
		],
	}
	var servo_instance := {
		"name": "servo", "node": "Devices/servo", "package": "pwm",
		"version": "1.0.0", "props": {"speed_deg_per_s": 240},
	}
	var led1_resolved := resolver.resolve_device(led1_instance, project)
	var led2_resolved := resolver.resolve_device(led2_instance, project)
	var servo_resolved := resolver.resolve_device(servo_instance, project)
	_check(bool(led1_resolved.get("ok", false)), "解析 gpio 包")
	_check(bool(led2_resolved.get("ok", false)), "解析第二个 gpio 设备")
	_check(bool(servo_resolved.get("ok", false)), "解析 pwm 包")

	var scene := ModelLoader.load_scene(
		ProjectSettings.globalize_path("res://examples/project1/virtual/virtual.glb")
	)
	_check(scene != null, "加载 project1/virtual.glb")
	if scene == null:
		_finish()
		return
	var led1_node := scene.get_node_or_null("Devices/led1") as Node3D
	var led2_node := scene.get_node_or_null("Devices/led2") as Node3D
	var servo_node := scene.get_node_or_null("Devices/servo") as Node3D
	_check(led1_node != null and led1_node.get_node_or_null("LedBody") != null, "LED1 节点")
	_check(led2_node != null and led2_node.get_node_or_null("Body") != null, "LED2 重命名节点")
	_check(servo_node != null and servo_node.get_node_or_null("ServoHorn") != null, "舵机节点")

	var led1_json: Dictionary = led1_resolved.get("device_json", {})
	var led2_json: Dictionary = led2_resolved.get("device_json", {})
	var servo_json: Dictionary = servo_resolved.get("device_json", {})
	var bodies := 0
	bodies += PhysicsBuilder.apply(scene, {}, [], 0.8,
		[led1_node, led2_node, servo_node])
	bodies += PhysicsBuilder.apply(led1_node, led1_json.get("physics", {}),
		led1_json.get("objects", []), 0.8)
	var merged := PhysicsBuilder.merge_overrides(led2_json, led2_instance)
	bodies += PhysicsBuilder.apply(led2_node, merged["physics"], merged["objects"], 0.8)
	bodies += PhysicsBuilder.apply(servo_node, servo_json.get("physics", {}),
		servo_json.get("objects", []), 0.8)
	_check(bodies == 19, "19 个网格生成碰撞体（地板 + 5 + 5 + 8）")

	var base2 := led2_node.get_node_or_null("Base2/HPMPhysics_Base2") as StaticBody3D
	if base2 != null:
		_check(is_equal_approx(base2.physics_material_override.friction, 0.65), "LED2 实例摩擦")
	var body2 := led2_node.get_node_or_null("Body/Barrel2/HPMPhysics_Barrel2") as StaticBody3D
	if body2 != null:
		_check(is_equal_approx(PhysicsBuilder.get_mass(body2), 0.12), "LED2 实例质量")
		_check(is_equal_approx(float(body2.get_meta("hpm_mass", 0.0)), 0.12), "质量元数据")

	# LED1 脚本
	var led1_script := _instantiate(led1_resolved)
	_check(led1_script != null, "加载 LED1 脚本")
	if led1_script != null:
		led1_script.model = led1_node
		led1_script._host_bind(null, {
			"name": "led1", "title": "LED 1", "package": "gpio",
			"props": led1_instance["props"], "model": led1_node,
		})
		led1_script._host_session_start()
		led1_script._host_values({"power": true})
		var barrel := led1_node.get_node_or_null("LedBody/LedBarrel") as MeshInstance3D
		_check(barrel != null and barrel.material_override != null, "LED1 材质")
		if barrel != null and barrel.material_override != null:
			_check(barrel.material_override.emission_energy_multiplier > 0.0, "LED1 点亮")

	# LED2 脚本（节点名是 Body / Barrel2，脚本走 fallback）
	var led2_script := _instantiate(led2_resolved)
	_check(led2_script != null, "加载 LED2 脚本")
	if led2_script != null:
		led2_script.model = led2_node
		led2_script._host_bind(null, {
			"name": "led2", "title": "LED 2", "package": "gpio",
			"props": led2_instance["props"], "model": led2_node,
		})
		led2_script._host_session_start()
		led2_script._host_values({"power": true})
		var barrel2 := led2_node.get_node_or_null("Body/Barrel2") as MeshInstance3D
		_check(barrel2 != null and barrel2.material_override != null, "LED2 材质")
		if barrel2 != null and barrel2.material_override != null:
			_check(barrel2.material_override.albedo_color.g > barrel2.material_override.albedo_color.r, "LED2 绿色")

	# 舵机脚本
	var servo_script := _instantiate(servo_resolved)
	_check(servo_script != null, "加载舵机脚本")
	if servo_script != null:
		servo_script.model = servo_node
		servo_script._host_bind(null, {
			"name": "servo", "title": "舵机", "package": "pwm",
			"props": servo_instance["props"], "model": servo_node,
		})
		servo_script._host_session_start()
		servo_script._host_values({"angle": 150.0, "duty_pct": 9.17})
		servo_script._on_tick(1.0)
		var horn := servo_node.get_node("ServoHorn") as Node3D
		_check(is_equal_approx(horn.rotation_degrees.y, 60.0), "舵机 150° -> 摆臂 +60°")

	if led1_script != null:
		led1_script._host_unbind()
		led1_script.free()
	if led2_script != null:
		led2_script._host_unbind()
		led2_script.free()
	if servo_script != null:
		servo_script._host_unbind()
		servo_script.free()
	scene.free()
	_finish()

func _instantiate(resolved: Dictionary) -> VirtualDevice:
	var cached := ScriptHost.cache_script(
		String(resolved.get("package_path", "")), String(resolved.get("script_path", ""))
	)
	var script := ScriptHost.load_script(cached)
	if script == null:
		return null
	return script.new() as VirtualDevice

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)

func _finish() -> void:
	print("REAL PACKAGES: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
