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

# 生成步进轮模型与四轮小车场景。
extends SceneTree

const GltfEmbed := preload("res://tools/gltf_embed.gd")
const SCENE := "res://examples/stepper-car/virtual/virtual.glb"
const WHEEL_GLTF := "res://packages/stepper-*-1.0.0/debug/device.gltf"

func _init() -> void:
	var wheel := _build_wheel()
	if not _export(wheel, WHEEL_GLTF):
		quit(1)
		return
	var scene := _build_scene()
	if not _export(scene, SCENE):
		quit(1)
		return
	quit(0)

func _build_wheel() -> Node3D:
	var root := Node3D.new()
	root.name = "wheel"

	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = 0.04
	tire.mesh = cyl
	tire.rotation_degrees = Vector3(0, 0, 90)
	tire.material_override = _material(Color(0.08, 0.09, 0.11))
	root.add_child(tire)

	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.035
	hub_mesh.bottom_radius = 0.035
	hub_mesh.height = 0.042
	hub.mesh = hub_mesh
	hub.rotation_degrees = Vector3(0, 0, 90)
	hub.material_override = _material(Color(0.7, 0.72, 0.75))
	root.add_child(hub)
	return root

func _build_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "VirtualScene"
	var car := Node3D.new()
	car.name = "Car"
	root.add_child(car)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.10, 0.46)
	body.mesh = box
	body.position = Vector3(0, 0.13, 0)
	body.material_override = _material(Color(0.1, 0.35, 0.8))
	car.add_child(body)

	var positions := {
		"stepper_fl": Vector3(-0.17, 0.08, 0.20),
		"stepper_fr": Vector3(0.17, 0.08, 0.20),
		"stepper_rl": Vector3(-0.17, 0.08, -0.20),
		"stepper_rr": Vector3(0.17, 0.08, -0.20),
	}
	for name: String in positions:
		var wheel := _load_wheel()
		if wheel == null:
			return root
		wheel.name = name
		wheel.position = positions[name]
		car.add_child(wheel)

	var sonar := _load_device("ultrasonic-*-1.0.0")
	if sonar != null:
		sonar.name = "sonar"
		sonar.position = Vector3(0, 0.20, 0.34)
		car.add_child(sonar)

	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(1.2, 0.6, 0.06)
	wall.mesh = wall_mesh
	wall.position = Vector3(0, 0.30, 1.25)
	wall.material_override = _material(Color(0.75, 0.65, 0.5))
	root.add_child(wall)

	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(4.0, 0.02, 5.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.01, 0.6)
	floor.material_override = _material(Color(0.28, 0.31, 0.35))
	root.add_child(floor)
	return root

func _load_wheel() -> Node3D:
	return ModelLoader.load_scene(ProjectSettings.globalize_path(WHEEL_GLTF))

func _load_device(dir_name: String) -> Node3D:
	var path := OS.get_environment("HOME").path_join(".hpm/packages").path_join(dir_name).path_join("debug/device.gltf")
	if not FileAccess.file_exists(path):
		push_error("找不到设备模型: " + path)
		return null
	return ModelLoader.load_scene(path)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.1
	material.roughness = 0.6
	return material

func _export(root: Node3D, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_scene(root, state) != OK:
		root.free()
		return false
	var absolute := ProjectSettings.globalize_path(path)
	var err := doc.write_to_filesystem(state, absolute)
	root.free()
	if err != OK:
		push_error("写出失败: " + path)
		return false
	if absolute.ends_with(".gltf"):
		GltfEmbed.embed(absolute)
	print("wrote ", absolute)
	return true
