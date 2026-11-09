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

# 生成两个示例工程的虚拟场景（以及 project2 的自定义包模型）。
# 只读取已安装的 gpio / pwm 设备包，不写 ~/.hpm。
extends SceneTree

const GltfEmbed := preload("res://tools/gltf_embed.gd")

const PROJECT1 := "res://examples/project1"
const PROJECT2 := "res://examples/project2"
const PACK_DIR := "res://examples/project2/virtual/packages/clickable-led-1.0.0"

const LED2_RENAMES := {
	"LedBody": "Body",
	"LedBarrel": "Barrel2",
	"LedDome": "Dome2",
	"LedBase": "Base2",
	"LedAnode": "Anode2",
	"LedCathode": "Cathode2",
}

func _init() -> void:
	var gpio_dir := _find_package("gpio-")
	var pwm_dir := _find_package("pwm-stc90c51")
	if gpio_dir.is_empty() or pwm_dir.is_empty():
		push_error("找不到已安装的 gpio / pwm 设备包")
		quit(1)
		return

	var led_model := gpio_dir.path_join("device.gltf")
	var servo_model := pwm_dir.path_join("device.gltf")
	var ok := true
	ok = _export(_build_world(led_model, servo_model), PROJECT1.path_join("virtual/virtual.glb")) and ok
	ok = _export(_build_world(led_model, servo_model), PROJECT2.path_join("virtual/virtual.glb")) and ok
	ok = _export(_build_led2(led_model), PACK_DIR.path_join("model.gltf")) and ok
	quit(0 if ok else 1)

func _find_package(prefix: String) -> String:
	var root := OS.get_environment("HPM_PACKAGES_DIR")
	if root.is_empty():
		root = OS.get_environment("HOME").path_join(".hpm/packages")
	var dir := DirAccess.open(root)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and entry.begins_with(prefix):
			dir.list_dir_end()
			return root.path_join(entry).path_join("debug")
		entry = dir.get_next()
	dir.list_dir_end()
	return ""

func _build_world(led_model: String, servo_model: String) -> Node3D:
	var root := Node3D.new()
	root.name = "VirtualScene"

	var environment := Node3D.new()
	environment.name = "Environment"
	root.add_child(environment)

	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(3.5, 0.1, 3.5)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.05, 0.0)
	floor.material_override = ModelLoader.make_material(Color(0.16, 0.18, 0.22))
	environment.add_child(floor)

	var devices := Node3D.new()
	devices.name = "Devices"
	root.add_child(devices)

	var led1 := _load_scene(led_model)
	led1.name = "led1"
	led1.position = Vector3(-0.35, 0.06, 0.12)
	devices.add_child(led1)

	var led2 := _build_led2(led_model)
	led2.name = "led2"
	led2.position = Vector3(-0.15, 0.06, -0.16)
	devices.add_child(led2)

	var servo := _load_scene(servo_model)
	servo.name = "servo"
	servo.position = Vector3(0.25, 0.0, 0.0)
	devices.add_child(servo)
	return root

func _build_led2(model: String) -> Node3D:
	var root := _load_scene(model)
	root.name = "led2"
	for node in root.find_children("*", "", true, false):
		var old_name := String(node.name)
		if LED2_RENAMES.has(old_name):
			node.name = LED2_RENAMES[old_name]
	return root

func _load_scene(path: String) -> Node3D:
	var scene := ModelLoader.load_scene(path)
	if scene == null:
		push_error("加载失败：%s" % path)
		return Node3D.new()
	return scene

func _export(root: Node3D, path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var dir_err := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if dir_err != OK:
		push_error("创建目录失败：%s" % absolute.get_base_dir())
		root.free()
		return false
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var append_err := doc.append_from_scene(root, state)
	if append_err != OK:
		push_error("append_from_scene 失败：%s" % error_string(append_err))
		root.free()
		return false
	var write_err := doc.write_to_filesystem(state, absolute)
	root.free()
	if write_err == OK and absolute.ends_with(".gltf"):
		GltfEmbed.embed(absolute)
	if write_err != OK:
		push_error("写出失败 %s：%s" % [absolute, error_string(write_err)])
		return false
	print("wrote ", absolute)
	return true
