# 仿真视图：加载 virtual.glb、按物体生成摩擦、绑定设备脚本、分发调试输出。
class_name SimView
extends Node3D

signal binding_report(report: Dictionary)

const DEVICE_DEFAULT_FRICTION := 0.8
const ENV_DEFAULT_FRICTION := 0.8

var project_dir := ""

var _resolver: PackageResolver
var _scene_root: Node3D
var _device_scripts: Dictionary = {}
var _device_nodes: Dictionary = {}
var _report: Dictionary = {
	"scene_loaded": false,
	"placeholder": false,
	"bound": [],
	"overrides": [],
	"errors": [],
	"missing_nodes": [],
	"physics_bodies": 0,
}
var _camera: Camera3D
var _bridge_connected := false

func setup(info: Dictionary) -> void:
	project_dir = String(info.get("root", ""))
	_resolver = PackageResolver.new(project_dir)
	_build_environment()
	var virtual: Dictionary = info.get("virtual", {})
	var scene_path := String(info.get("virtual_dir", "")).path_join(String(virtual.get("scene", "virtual.glb")))
	if bool(info.get("has_virtual", false)) and FileAccess.file_exists(scene_path):
		_scene_root = ModelLoader.load_scene(scene_path)
		if _scene_root != null:
			_report["scene_loaded"] = true
	if _scene_root == null:
		_scene_root = _build_placeholder()
		_report["placeholder"] = true
	add_child(_scene_root)

	_apply_environment_physics(virtual)
	_bind_devices(virtual)
	_frame_camera()
	_connect_bridge()
	binding_report.emit(_report)
	_sync_session_state()

func get_report() -> Dictionary:
	return _report

func get_device_scripts() -> Dictionary:
	return _device_scripts

# ---------------------------------------------------------------- 场景与环境

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.86)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

	_camera = Camera3D.new()
	_camera.position = Vector3(2.4, 2.0, 2.4)
	_camera.current = true
	add_child(_camera)

func _build_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "PlaceholderWorld"
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 0.2, 6.0)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0.0, -0.1, 0.0)
	floor_mesh.material_override = ModelLoader.make_material(Color(0.22, 0.24, 0.28))
	root.add_child(floor_mesh)
	return root

func _apply_environment_physics(virtual: Dictionary) -> void:
	var default_physics: Dictionary = virtual.get("physics", {})
	var overrides: Array = virtual.get("objects", [])
	var device_nodes: Array = []
	for instance: Variant in virtual.get("devices", []):
		if typeof(instance) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = instance
		var node := _find_device_node(String(entry.get("node", "")), String(entry.get("name", "")))
		if node != null:
			device_nodes.append(node)
	_report["physics_bodies"] += PhysicsBuilder.apply(
		_scene_root, default_physics, overrides, ENV_DEFAULT_FRICTION, device_nodes
	)

# ---------------------------------------------------------------- 设备绑定

func _bind_devices(virtual: Dictionary) -> void:
	var instances: Array = virtual.get("devices", [])
	if instances.is_empty():
		# 没有 virtual.json 时，按 project.json 的设备名自动找同名节点。
		var project_devices: Dictionary = App.project_json.get("devices", {})
		for device_name: String in project_devices:
			instances.append({"name": device_name, "node": device_name})
			if project_devices[device_name] is Dictionary:
				_report["errors"].append("设备 %s 未在 virtual.json 登记，使用同名节点兜底" % device_name)

	for instance: Variant in instances:
		if typeof(instance) != TYPE_DICTIONARY:
			continue
		_bind_device(instance)

func _bind_device(instance: Dictionary) -> void:
	var device_name := String(instance.get("name", ""))
	var node := _find_device_node(String(instance.get("node", "")), device_name)
	if node == null:
		_report["missing_nodes"].append(device_name)
		_report["errors"].append("virtual.glb 中找不到设备 %s 的节点：%s" % [
			device_name, instance.get("node", device_name)
		])
		return

	var resolved := _resolver.resolve_device(instance, App.project_json)
	if not bool(resolved.get("ok", false)):
		_report["errors"].append("设备 %s：%s" % [device_name, resolved.get("error", "包解析失败")])
		PhysicsBuilder.apply(node, {"friction": DEVICE_DEFAULT_FRICTION}, [], DEVICE_DEFAULT_FRICTION)
		return

	var device_json: Dictionary = resolved.get("device_json", {})
	var merged := _merge_physics(device_json, instance)
	_report["physics_bodies"] += PhysicsBuilder.apply(
		node, merged["physics"], merged["objects"], DEVICE_DEFAULT_FRICTION
	)
	if not String(resolved.get("override_error", "")).is_empty():
		_report["errors"].append("设备 %s：%s" % [device_name, resolved.get("override_error")])
	elif not (resolved.get("override", {}) as Dictionary).is_empty():
		_report["overrides"].append(device_name)

	_device_nodes[device_name] = node

	var script_path := String(resolved.get("script_path", ""))
	if not FileAccess.file_exists(script_path):
		_report["errors"].append("设备 %s 缺少外部脚本：%s" % [device_name, script_path])
		return
	var cached := ScriptHost.cache_script(String(resolved.get("package_path", "")), script_path)
	var gd := ScriptHost.load_script(cached)
	if gd == null:
		_report["errors"].append("设备 %s 脚本加载失败：%s" % [device_name, script_path])
		return

	var instance_node: Node = gd.new()
	if not instance_node is VirtualDevice:
		_report["errors"].append("设备 %s 的脚本没有继承 res://sdk/virtual_device.gd" % device_name)
		return
	instance_node.name = "HPMVirtualScript"
	node.add_child(instance_node)

	var title := String(device_json.get("display_name", device_name))
	var ctx := {
		"name": device_name,
		"title": title,
		"package": String(resolved.get("package", "")),
		"version": String(resolved.get("version", "")),
		"node_path": String(instance.get("node", "")),
		"props": instance.get("props", {}),
		"device": App.project_json.get("devices", {}).get(device_name, {}),
		"model": node,
	}
	(instance_node as VirtualDevice)._host_bind(Bridge, ctx)
	_device_scripts[device_name] = instance_node
	_report["bound"].append(device_name)

## 实例级 physics/objects 覆盖 device.json 的默认值；实例规则优先。
func _merge_physics(device_json: Dictionary, instance: Dictionary) -> Dictionary:
	return PhysicsBuilder.merge_overrides(device_json, instance)

func _find_device_node(path: String, device_name: String) -> Node3D:
	var node: Node = null
	if not path.is_empty():
		node = _scene_root.get_node_or_null(path)
	if node == null and not device_name.is_empty():
		node = _scene_root.find_child(device_name, true, false)
	return node as Node3D

# ---------------------------------------------------------------- 调试分发

func _connect_bridge() -> void:
	if _bridge_connected:
		return
	_bridge_connected = true
	Bridge.session_changed.connect(_on_session_changed)
	Bridge.device_values.connect(_on_device_values)
	Bridge.devices_changed.connect(_on_devices_changed)

func _sync_session_state() -> void:
	_on_session_changed(Bridge.is_active())

func _on_session_changed(active: bool) -> void:
	for script: VirtualDevice in _device_scripts.values():
		if active:
			script._host_session_start()
		else:
			script._host_session_stop()

func _on_device_values(device_name: String, values: Dictionary) -> void:
	var script: VirtualDevice = _device_scripts.get(device_name, null)
	if script != null:
		script._host_values(values)

func _on_devices_changed(devices: Array) -> void:
	# 用调试服务的 title 补全显示名。
	for item: Variant in devices:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var name := String(entry.get("name", entry.get("device", "")))
		var script: VirtualDevice = _device_scripts.get(name, null)
		if script != null and entry.has("title"):
			script.device_title = String(entry.get("title"))

# ---------------------------------------------------------------- 相机

func _frame_camera() -> void:
	var box := AABB()
	var first := true
	if not _device_nodes.is_empty():
		for node: Node3D in _device_nodes.values():
			var device_box := _compute_aabb(node)
			if not device_box.has_volume():
				continue
			if first:
				box = device_box
				first = false
			else:
				box = box.merge(device_box)
	if first:
		box = _compute_aabb(_scene_root)
	if not box.has_volume():
		return
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.22)
	var direction := Vector3(0.85, 1.0, 0.85).normalized()
	_camera.global_position = center + direction * radius * 4.0
	_camera.look_at(center, Vector3.UP)

func _compute_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var mesh_box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			box = mesh_box
			first = false
		else:
			box = box.merge(mesh_box)
	return box

func _exit_tree() -> void:
	for script: VirtualDevice in _device_scripts.values():
		script._host_unbind()
