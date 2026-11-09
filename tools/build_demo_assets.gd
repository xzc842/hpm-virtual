# 生成演示用 GLB/glTF 资产（不依赖 Blender）。
# 用法：
#   Godot_v4.7 --headless --path . --script res://tools/build_demo_assets.gd
extends SceneTree

const PROJECT_DIR := "res://examples/demo-project"

func _init() -> void:
	var virtual_scene := _build_virtual_scene()
	var ok := _export(virtual_scene, PROJECT_DIR.path_join("virtual/virtual.glb"))
	print("virtual.glb: ", "ok" if ok else "failed")

	var device_scene := _build_led_device()
	var ok_device := _export(
		device_scene,
		PROJECT_DIR.path_join("packages/led-demo-1.0.0/debug/device.gltf")
	)
	print("device.gltf: ", "ok" if ok_device else "failed")

	quit(0 if ok and ok_device else 1)

func _build_virtual_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "VirtualScene"

	var environment := Node3D.new()
	environment.name = "Environment"
	root.add_child(environment)

	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(6.0, 0.2, 6.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.1, 0.0)
	floor.material_override = _material(Color(0.17, 0.19, 0.23), 0.9)
	environment.add_child(floor)

	var devices := Node3D.new()
	devices.name = "Devices"
	root.add_child(devices)

	var led := _build_led_device()
	led.name = "led"
	led.position = Vector3(0.0, 0.0, 0.0)
	devices.add_child(led)
	return root

func _build_led_device() -> Node3D:
	var led := Node3D.new()
	led.name = "led"

	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.3, 0.2, 0.2)
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.1, 0.0)
	body.material_override = _material(Color(0.28, 0.30, 0.34), 0.55)
	led.add_child(body)

	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.045
	lamp_mesh.height = 0.09
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(0.12, 0.2, 0.0)
	lamp.material_override = _material(Color(0.12, 0.13, 0.15), 0.25)
	led.add_child(lamp)

	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.06
	base_mesh.bottom_radius = 0.06
	base_mesh.height = 0.02
	base.mesh = base_mesh
	base.position = Vector3(0.0, 0.01, 0.0)
	base.material_override = _material(Color(0.38, 0.24, 0.12), 0.8)
	led.add_child(base)
	return led

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _export(root: Node3D, path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var dir := absolute.get_base_dir()
	var mkdir_err := DirAccess.make_dir_recursive_absolute(dir)
	if mkdir_err != OK:
		push_error("创建目录失败：%s" % dir)
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
	if write_err != OK:
		push_error("写出失败 %s：%s" % [absolute, error_string(write_err)])
		return false
	print("wrote ", absolute)
	return true
