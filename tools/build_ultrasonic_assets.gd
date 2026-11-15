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

# 生成超声波设备的 device.gltf 和 examples/ultrasonic/virtual/virtual.glb。
#   godot --headless --path . --script res://tools/build_ultrasonic_assets.gd
extends SceneTree

const GltfEmbed := preload("res://tools/gltf_embed.gd")
var PACKAGE_DEBUG := OS.get_environment("HOME").path_join(".hpm/packages/ultrasonic-*-1.0.0/debug")
const SCENE_DIR := "res://examples/ultrasonic/virtual"

func _init() -> void:
	var ok := true
	ok = _export(_build_sensor(), PACKAGE_DEBUG.path_join("device.gltf")) and ok
	ok = _export(_build_scene(), SCENE_DIR.path_join("virtual.glb")) and ok
	quit(0 if ok else 1)

func _build_sensor() -> Node3D:
	var root := Node3D.new()
	root.name = "sonar"

	var body := _box("Body", Vector3(0.20, 0.08, 0.06), Vector3(0.0, 0.04, 0.0),
		Color(0.12, 0.32, 0.72))
	root.add_child(body)

	var left := _cylinder("LeftEye", 0.03, 0.018, Vector3(-0.055, 0.04, 0.038),
		Color(0.72, 0.76, 0.82))
	root.add_child(left)
	var right := _cylinder("RightEye", 0.03, 0.018, Vector3(0.055, 0.04, 0.038),
		Color(0.72, 0.76, 0.82))
	root.add_child(right)

	var mount := _box("Mount", Vector3(0.22, 0.015, 0.09), Vector3(0.0, 0.0075, 0.0),
		Color(0.10, 0.12, 0.16))
	root.add_child(mount)

	var pins := _box("Pins", Vector3(0.12, 0.012, 0.025), Vector3(0.0, 0.02, -0.04),
		Color(0.85, 0.65, 0.15))
	root.add_child(pins)
	return root

func _build_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "VirtualScene"

	var devices := Node3D.new()
	devices.name = "Devices"
	root.add_child(devices)
	var sensor := _build_sensor()
	sensor.position = Vector3(0.0, 0.0, 0.0)
	devices.add_child(sensor)

	var target := _box("Target", Vector3(0.18, 0.24, 0.06), Vector3(0.0, 0.20, 2.5),
		Color(0.95, 0.45, 0.12))
	root.add_child(target)

	var floor_mesh := _box("Floor", Vector3(6.0, 0.02, 6.0), Vector3(0.0, -0.01, 1.5),
		Color(0.30, 0.33, 0.38))
	root.add_child(floor_mesh)
	return root

func _box(node_name: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = position
	node.material_override = _material(color)
	return node

func _cylinder(node_name: String, radius: float, height: float, position: Vector3,
		color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = position
	node.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	node.material_override = _material(color)
	return node

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.15
	material.roughness = 0.55
	return material

func _export(root: Node3D, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	root.free()
	if err != OK:
		push_error("append_from_scene 失败: %s" % error_string(err))
		return false
	var absolute := ProjectSettings.globalize_path(path)
	var write_err := doc.write_to_filesystem(state, absolute)
	if write_err == OK and absolute.ends_with(".gltf"):
		GltfEmbed.embed(absolute)
	if write_err != OK:
		push_error("写出失败 %s: %s" % [path, error_string(write_err)])
		return false
	print("wrote ", absolute)
	return true
