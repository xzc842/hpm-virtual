# 生成 gpio(LED) / pwm(舵机) 的 device.gltf 与真实设备演示工程。
# 用法：
#   Godot_v4.7 --headless --path . --script res://tools/build_device_assets.gd
extends SceneTree

const DEMO_DIR := "res://examples/real-project"
const BLINK_DIR := "res://examples/blink"

func _init() -> void:
	var gpio_dir := _find_package_debug_dir("gpio-")
	var pwm_dir := _find_package_debug_dir("pwm-stc90c51")
	if gpio_dir.is_empty() or pwm_dir.is_empty():
		push_error("找不到已安装的 gpio / pwm 设备包，请检查 ~/.hpm/packages")
		quit(1)
		return

	var ok := true
	ok = _export(_build_led(), gpio_dir.path_join("device.gltf")) and ok
	ok = _export(_build_servo(), pwm_dir.path_join("device.gltf")) and ok

	var world := _build_world()
	ok = _export(world, DEMO_DIR.path_join("virtual/virtual.glb")) and ok
	ok = _export(_build_blink_world(), BLINK_DIR.path_join("virtual/virtual.glb")) and ok
	quit(0 if ok else 1)

func _find_package_debug_dir(prefix: String) -> String:
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

func _build_world() -> Node3D:
	var root := Node3D.new()
	root.name = "VirtualScene"

	var environment := Node3D.new()
	environment.name = "Environment"
	root.add_child(environment)

	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(4.0, 0.1, 4.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.05, 0.0)
	floor.material_override = _material(Color(0.16, 0.18, 0.22), 0.9)
	environment.add_child(floor)

	var devices := Node3D.new()
	devices.name = "Devices"
	root.add_child(devices)

	var led := _build_led()
	led.position = Vector3(-0.35, 0.06, 0.12)
	devices.add_child(led)

	var servo := _build_servo()
	servo.position = Vector3(0.2, 0.0, 0.0)
	devices.add_child(servo)
	return root

func _build_blink_world() -> Node3D:
	var root := Node3D.new()
	root.name = "VirtualScene"

	var environment := Node3D.new()
	environment.name = "Environment"
	root.add_child(environment)

	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(3.0, 0.1, 3.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.05, 0.0)
	floor.material_override = _material(Color(0.16, 0.18, 0.22), 0.9)
	environment.add_child(floor)

	var devices := Node3D.new()
	devices.name = "Devices"
	root.add_child(devices)

	var led := _build_led()
	led.position = Vector3(0.0, 0.06, 0.0)
	devices.add_child(led)
	return root

# ---------------------------------------------------------------- LED

func _build_led() -> Node3D:
	var led := Node3D.new()
	led.name = "led"

	var base := _mesh_node("LedBase", _cylinder(0.05, 0.05, 0.015, 16), Color(0.18, 0.19, 0.21), 0.6)
	base.position = Vector3(0.0, 0.0075, 0.0)
	led.add_child(base)

	var body := Node3D.new()
	body.name = "LedBody"
	body.position = Vector3(0.0, 0.015, 0.0)
	led.add_child(body)

	var barrel := _mesh_node("LedBarrel", _cylinder(0.04, 0.04, 0.07, 20), Color(0.65, 0.06, 0.06), 0.25)
	barrel.position = Vector3(0.0, 0.035, 0.0)
	body.add_child(barrel)

	var dome := _mesh_node("LedDome", _sphere(0.04, 24), Color(0.75, 0.08, 0.08), 0.2)
	dome.position = Vector3(0.0, 0.07, 0.0)
	dome.scale = Vector3(1.0, 0.65, 1.0)
	body.add_child(dome)

	var anode := _mesh_node("LedAnode", _cylinder(0.004, 0.004, 0.06, 8), Color(0.7, 0.7, 0.75), 0.3)
	anode.position = Vector3(-0.018, -0.03, 0.0)
	led.add_child(anode)

	var cathode := _mesh_node("LedCathode", _cylinder(0.004, 0.004, 0.05, 8), Color(0.7, 0.7, 0.75), 0.3)
	cathode.position = Vector3(0.018, -0.025, 0.0)
	led.add_child(cathode)
	return led

# ---------------------------------------------------------------- 舵机

func _build_servo() -> Node3D:
	var servo := Node3D.new()
	servo.name = "servo"

	var body := _mesh_node("ServoBody", _box(Vector3(0.22, 0.26, 0.11)), Color(0.07, 0.22, 0.72), 0.5)
	body.position = Vector3(0.0, 0.13, 0.0)
	servo.add_child(body)

	var mount_left := _mesh_node("ServoMountLeft", _box(Vector3(0.08, 0.025, 0.10)),
		Color(0.07, 0.22, 0.72), 0.5)
	mount_left.position = Vector3(-0.15, 0.045, 0.0)
	servo.add_child(mount_left)

	var mount_right := _mesh_node("ServoMountRight", _box(Vector3(0.08, 0.025, 0.10)),
		Color(0.07, 0.22, 0.72), 0.5)
	mount_right.position = Vector3(0.15, 0.045, 0.0)
	servo.add_child(mount_right)

	var top := _mesh_node("ServoTop", _box(Vector3(0.12, 0.035, 0.09)),
		Color(0.88, 0.89, 0.86), 0.4)
	top.position = Vector3(0.0, 0.2775, 0.0)
	servo.add_child(top)

	var shaft := _mesh_node("ServoShaft", _cylinder(0.012, 0.012, 0.025, 12),
		Color(0.65, 0.66, 0.7), 0.25)
	shaft.position = Vector3(0.0, 0.3075, 0.0)
	servo.add_child(shaft)

	var horn := Node3D.new()
	horn.name = "ServoHorn"
	horn.position = Vector3(0.0, 0.322, 0.0)
	servo.add_child(horn)

	var hub := _mesh_node("ServoHub", _cylinder(0.022, 0.022, 0.012, 16),
		Color(0.9, 0.9, 0.88), 0.4)
	hub.position = Vector3(0.0, 0.004, 0.0)
	horn.add_child(hub)

	var arm := _mesh_node("ServoArm", _box(Vector3(0.11, 0.012, 0.018)),
		Color(0.9, 0.9, 0.88), 0.4)
	arm.position = Vector3(0.055, 0.004, 0.0)
	horn.add_child(arm)

	var cable := _mesh_node("ServoCable", _box(Vector3(0.022, 0.005, 0.14)),
		Color(0.22, 0.1, 0.08), 0.7)
	cable.position = Vector3(0.0, 0.008, -0.115)
	servo.add_child(cable)
	return servo

# ---------------------------------------------------------------- 原语

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _cylinder(top_radius: float, bottom_radius: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh

func _sphere(radius: float, segments: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(segments / 2, 6)
	return mesh

func _mesh_node(name: String, mesh: Mesh, color: Color, roughness: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = _material(color, roughness)
	return node

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

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
	if write_err != OK:
		push_error("写出失败 %s：%s" % [absolute, error_string(write_err)])
		return false
	print("wrote ", absolute)
	return true
