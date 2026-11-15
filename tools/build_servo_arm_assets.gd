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

# 生成 servo-arm 场景：舵机+长杆、右侧超声波、LED、地板。
#   godot --headless --path . --script res://tools/build_servo_arm_assets.gd
extends SceneTree

const SCENE := "res://examples/servo-arm/virtual/virtual.glb"

var _packages_dir := ""

func _init() -> void:
	_packages_dir = OS.get_environment("HOME").path_join(".hpm/packages")
	var servo := _load_device("pwm-stc90c51-1.0.0")
	var sonar := _load_device("ultrasonic-*-1.0.0")
	var led := _load_device("gpio-*-1.0.0")
	if servo == null or sonar == null or led == null:
		quit(1)
		return

	var root := Node3D.new()
	root.name = "VirtualScene"
	var devices := Node3D.new()
	devices.name = "Devices"
	root.add_child(devices)

	servo.name = "servo"
	servo.position = Vector3(0.0, 0.0, 0.0)
	devices.add_child(servo)
	var horn := servo.find_child("ServoHorn", true, false) as Node3D
	if horn == null:
		push_error("舵机模型缺少 ServoHorn")
		quit(1)
		return
	var rod := MeshInstance3D.new()
	rod.name = "Rod"
	var rod_mesh := BoxMesh.new()
	rod_mesh.size = Vector3(0.04, 0.04, 1.0)
	rod.mesh = rod_mesh
	rod.position = Vector3(0.0, 0.02, 0.5)
	rod.material_override = _material(Color(0.95, 0.55, 0.12))
	horn.add_child(rod)

	sonar.name = "sonar"
	sonar.position = Vector3(1.12, 0.31, 0.0)
	sonar.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	devices.add_child(sonar)

	led.name = "led"
	led.position = Vector3(0.72, 0.34, 0.55)
	devices.add_child(led)

	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(4.0, 0.02, 3.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.4, -0.01, 0.4)
	floor.material_override = _material(Color(0.30, 0.33, 0.38))
	root.add_child(floor)

	var absolute := ProjectSettings.globalize_path(SCENE)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	root.free()
	if err != OK:
		push_error("append_from_scene 失败: %s" % error_string(err))
		quit(1)
		return
	var write_err := doc.write_to_filesystem(state, absolute)
	if write_err != OK:
		push_error("写出失败: %s" % error_string(write_err))
		quit(1)
		return
	print("wrote ", absolute)
	quit(0)

func _load_device(dir_name: String) -> Node3D:
	var path := _packages_dir.path_join(dir_name).path_join("debug/device.gltf")
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
